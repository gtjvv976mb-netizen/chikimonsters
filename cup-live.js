// Chikoria Cup — Phase 1 LIVE orchestrator.
// Runs the 16-player double-elimination as a live, round-by-round event:
//   registration → lobby fills to 16 → 11 rounds, each with a lock-in/ready window →
//   matches auto-resolve via the deterministic resolver → advance/drop → champion → payouts.
// "Lock-in" = the player readied up AND is present this round. No lock-in / disconnect = forfeit.

import { resolveBattle } from "./cup-resolver.js";

const SEED16 = [1,16,8,9,5,12,4,13,3,14,6,11,7,10,2,15];
function payout(place, cap){
  // Each table totals exactly 4.00 SOL with a 1.00 SOL champion. The 16-slot bracket pads with byes,
  // so the REAL finishing-place sets are: 8p {1,2,3,4,5,5,7,7} · 10p {…,9,9} · 16p {…,9×4,13×4}.
  cap = cap || 10;
  if(cap <= 8){                                   // 8 players
    if(place===1) return 1.00; if(place===2) return 0.85; if(place===3) return 0.60; if(place===4) return 0.45;
    if(place<=6) return 0.30; return 0.25;        // 5–6 · 7–8
  }
  if(cap >= 16){                                  // 16 players
    if(place===1) return 1.00; if(place===2) return 0.60; if(place===3) return 0.42; if(place===4) return 0.32;
    if(place<=6) return 0.24; if(place<=8) return 0.18; if(place<=12) return 0.13; return 0.075;
  }
  // 10 players (default)
  if(place===1) return 1.00; if(place===2) return 0.70; if(place===3) return 0.50; if(place===4) return 0.40;
  if(place<=6) return 0.28; if(place<=8) return 0.24; return 0.18;
}
// Play order for a 16 double-elim (interleaved so eliminated players don't wait long).
const SCHEDULE = ["WB1","LB1","WB2","LB2","WB3","LB3","WF","LB4","LB5","LF","GF"];

// Bracket slots that hold ARRAYS of entrant objects, and SINGLE entrant objects — used by snapshot/hydrate.
const ARR_SLOTS = ["slot","wb1w","wb1l","wb2w","wb2l","wb3w","wb3l","lb1","lb2","lb3","lb4"];
const ONE_SLOTS = ["wf","wfl","lb5","lbc","champion"];

// Rebuild S from a JSON snapshot, restoring object IDENTITY (bracket arrays point at the SAME entrant objects
// as `entrants`/`byes`), so flags like `ready` set on an entrant are seen everywhere it appears.
function hydrate(snap){
  const S = {
    status:snap.status, entryGlory:snap.entryGlory, prizePool:snap.prizePool, seedBase:snap.seedBase, cap:snap.cap,
    entrants:(snap.entrants||[]).map(e=>({...e})), byes:(snap.byes||[]).map(e=>({...e})),
    roundIdx:snap.roundIdx, mid:snap.mid||0, log:snap.log||[], place:snap.place||{},
    slot:[], wb1w:[],wb1l:[],wb2w:[],wb2l:[],wb3w:[],wb3l:[], wf:null,wfl:null,
    lb1:[],lb2:[],lb3:[],lb4:[], lb5:null, lbc:null, champion:null,
  };
  const map=new Map(); [...S.entrants,...S.byes].forEach(e=>map.set(e.wallet,e));
  const deref=a=>(a||[]).map(w=> w!=null ? map.get(w) : undefined);
  for(const k of ARR_SLOTS) S[k]=deref(snap[k]);
  for(const k of ONE_SLOTS) S[k]= snap[k]!=null ? map.get(snap[k]) : null;
  return S;
}

function createCup(opts={}, snap=null){
  const S = snap ? hydrate(snap) : {
    status:"registration",                 // registration | live | finished
    entryGlory: opts.entryGlory ?? 100,
    prizePool: opts.prizePool ?? 4.0,
    seedBase: opts.seedBase || ("cup-"+Date.now()),
    cap: [8,10,16].includes(opts.cap) ? opts.cap : 10, entrants: [], byes: [],   // 8/10/16 real players; bracket padded to 16 with byes
    roundIdx: -1, mid: 0, log: [], place: {},
    // working slots (hold entrant objects)
    slot:[], wb1w:[],wb1l:[],wb2w:[],wb2l:[],wb3w:[],wb3l:[], wf:null,wfl:null,
    lb1:[],lb2:[],lb3:[],lb4:[], lb5:null, lbc:null, champion:null,
  };

  const api = {
    state: S,
    get roundName(){ return S.roundIdx>=0 ? SCHEDULE[S.roundIdx] : null; },

    // JSON-safe snapshot for durable storage. Bracket slots are stored as wallet refs; hydrate() restores identity.
    snapshot(){
      const refs = a => (a||[]).map(e=> e ? e.wallet : null);
      const out = { status:S.status, entryGlory:S.entryGlory, prizePool:S.prizePool, seedBase:S.seedBase, cap:S.cap,
        roundIdx:S.roundIdx, mid:S.mid, log:S.log, place:S.place, entrants:S.entrants, byes:S.byes||[] };
      for(const k of ARR_SLOTS) out[k]=refs(S[k]);
      for(const k of ONE_SLOTS) out[k]= S[k] ? S[k].wallet : null;
      return out;
    },

    register(wallet, snap){
      if(S.status!=="registration") throw new Error("registration closed");
      if(S.entrants.find(e=>e.wallet===wallet)) throw new Error("already registered");
      if(S.entrants.length>=S.cap) throw new Error("cup full");
      S.entrants.push({ wallet, snap:{...snap, name: snap.name||wallet.slice(0,4)}, ready:false });
      return { entrants:S.entrants.length, cap:S.cap };
    },
    ready(wallet){ const e=S.entrants.find(x=>x.wallet===wallet); if(e) e.ready=true; return !!e; },

    start(){
      if(S.entrants.length!==S.cap) throw new Error(`need ${S.cap} entrants (have ${S.entrants.length})`);
      const seeded = S.entrants.slice().sort((a,b)=>(b.snap.br||1)-(a.snap.br||1));
      // Pad to a full 16-slot bracket with auto-forfeit BYES so a non-power-of-2 field still runs a clean double-elim.
      // Byes take the bottom seeds, lose to any real player, and are excluded from placements/prizes.
      S.byes = [];
      for(let i=seeded.length;i<16;i++){ const b={ wallet:"__BYE"+i, snap:{name:"(bye)",br:0,element:"Light",arenaSkills:[0,1,2],cardTier:{}}, ready:true, bye:true }; seeded.push(b); S.byes.push(b); }
      S.slot = SEED16.map(s=>seeded[s-1]);
      S.status="live"; S.roundIdx=0;
      return this.currentMatches();
    },

    // the matches players must ready up for THIS round (pairs of {wallet,name})
    currentMatches(){
      return this._pairs().map(([a,b])=>({ a:{wallet:a.wallet,name:a.snap.name,player:a.snap.player||null,br:a.snap.br,element:a.snap.element},
                                           b:{wallet:b.wallet,name:b.snap.name,player:b.snap.player||null,br:b.snap.br,element:b.snap.element} }));
    },

    // resolve the current round (call when the lock-in window closes), advance the bracket.
    // decide(a,b) → "a"|"b" (or the entrant) supplies a LIVE PvP result; return null to fall back to the deterministic engine.
    resolveRound(decide){
      if(S.status!=="live") throw new Error("cup not live");
      const rname=SCHEDULE[S.roundIdx];
      const pairs=this._pairs(), winners=[], losers=[], forfeits=[];
      for(const [a,b] of pairs){
        let w,l,ff=null;
        if(a.bye && b.bye){ w=a; l=b; }                       // bye vs bye — advance one (still a bye), no battle
        else if(a.bye){ w=b; l=a; }                           // a real player auto-advances over a bye
        else if(b.bye){ w=a; l=b; }
        else if(a.ready && b.ready){
          const dw = decide ? decide(a,b) : null;             // live PvP winner, if any
          if(dw==="a"||dw===a){ w=a; l=b; }
          else if(dw==="b"||dw===b){ w=b; l=a; }
          else { const r=resolveBattle(a.snap,b.snap,S.seedBase+"|"+SCHEDULE[S.roundIdx]+"|"+(S.mid++)); w=r.winner==="a"?a:b; l=r.winner==="a"?b:a; }
        }
        else if(a.ready){ w=a; l=b; ff=b.wallet; }            // forfeit
        else if(b.ready){ w=b; l=a; ff=a.wallet; }
        else { w=(a.snap.br||1)>=(b.snap.br||1)?a:b; l=w===a?b:a; ff="both"; }  // double no-show
        winners.push(w); losers.push(l); if(ff)forfeits.push({match:a.snap.name+" vs "+b.snap.name, ff});
        S.log.push({round:SCHEDULE[S.roundIdx], winner:w.snap.name, loser:l.snap.name, forfeit:ff});
      }
      this._consume(winners, losers);
      S.entrants.forEach(e=>e.ready=false);                    // must re-ready next round
      const done = S.roundIdx>=SCHEDULE.length-1;
      if(done){ S.status="finished"; }
      else { S.roundIdx++; }
      return { round:rname, winners:winners.map(w=>w.snap.name), forfeits,
               finished:done, champion: done? S.champion.snap.name : null,
               next: done? null : SCHEDULE[S.roundIdx] };
    },

    finished(){ return S.status==="finished"; },
    // final placements + SOL payouts (call after finished)
    results(){
      return S.entrants.map(e=>{ const pl=S.place[e.wallet]; const sol=payout(pl, S.cap); return {wallet:e.wallet, name:e.snap.name, place:pl, sol:+sol.toFixed(4)}; })
                       .sort((a,b)=>a.place-b.place);
    },

    // ---- internals: which matches this round, and how results flow ----
    _pairs(){
      const r=SCHEDULE[S.roundIdx], P=[];
      const pair=(arr)=>{ for(let i=0;i<arr.length;i+=2)P.push([arr[i],arr[i+1]]); };
      if(r==="WB1") pair(S.slot);
      else if(r==="LB1") pair(S.wb1l);
      else if(r==="WB2") pair(S.wb1w);
      else if(r==="LB2"){ for(let i=0;i<4;i++)P.push([S.lb1[i],S.wb2l[i]]); }
      else if(r==="WB3") pair(S.wb2w);
      else if(r==="LB3") pair(S.lb2);
      else if(r==="WF") P.push([S.wb3w[0],S.wb3w[1]]);
      else if(r==="LB4"){ for(let i=0;i<2;i++)P.push([S.lb3[i],S.wb3l[i]]); }
      else if(r==="LB5") P.push([S.lb4[0],S.lb4[1]]);
      else if(r==="LF") P.push([S.lb5,S.wfl]);
      else if(r==="GF") P.push([S.wf,S.lbc]);
      return P;
    },
    _consume(W,L){
      const r=SCHEDULE[S.roundIdx], setPlace=(arr,pl)=>arr.forEach(e=>S.place[e.wallet]=pl);
      if(r==="WB1"){ S.wb1w=W; S.wb1l=L; }
      else if(r==="LB1"){ S.lb1=W; setPlace(L,13); }
      else if(r==="WB2"){ S.wb2w=W; S.wb2l=L; }
      else if(r==="LB2"){ S.lb2=W; setPlace(L,9); }
      else if(r==="WB3"){ S.wb3w=W; S.wb3l=L; }
      else if(r==="LB3"){ S.lb3=W; setPlace(L,7); }
      else if(r==="WF"){ S.wf=W[0]; S.wfl=L[0]; }
      else if(r==="LB4"){ S.lb4=W; setPlace(L,5); }
      else if(r==="LB5"){ S.lb5=W[0]; S.place[L[0].wallet]=4; }
      else if(r==="LF"){ S.lbc=W[0]; S.place[L[0].wallet]=3; }
      else if(r==="GF"){ S.champion=W[0]; S.place[L[0].wallet]=2; S.place[W[0].wallet]=1; }
    },
  };
  return api;
}

export { createCup, payout, SCHEDULE };

/* ---------- self-test: run a full LIVE cup ---------- */
if (import.meta.url === `file://${process.argv[1]}`) {
  const ELEMS=["Water","Fire","Beast","Storm","Light"];
  const N=10;
  const mk=()=>{ const cup=createCup({seedBase:"live-1"});
    for(let i=0;i<N;i++){ const br=4+((i*5+3)%24), el=ELEMS[i%5], sk=[i%12,(i+4)%12,(i+8)%12], ct={}; sk.forEach(s=>ct[s]=Math.min(5,1+(br/6|0)));
      cup.register("W"+i, {name:`L${String(i+1).padStart(2,"0")}(${el[0]}·${br})`, element:el, br, arenaSkills:sk, cardTier:ct}); }
    return cup; };

  // everyone readies every round
  const cup=mk(); cup.start();
  let rounds=0;
  while(!cup.finished()){ cup.state.entrants.forEach(e=>e.ready=true); const r=cup.resolveRound(); rounds++;
    console.log(`R${rounds} ${r.round}: ${r.winners.length} advance${r.finished?` · 🏆 ${r.champion}`:` → next ${r.next}`}`); }
  console.log("rounds:", rounds, "(expect 11)");
  const res=cup.results();
  const everyone = res.length===N && res.every(x=>x.place>=1 && x.sol>0);
  const total=res.reduce((s,x)=>s+x.sol,0);
  console.log("real players:", res.length, "(expect "+N+")");
  console.log("places:", res.map(x=>x.place).join(","));
  console.log("everyone placed+paid:", everyone?"PASS ✅":"FAIL ❌", "· total SOL", total.toFixed(3), "(expect 4.000)");

  // forfeit test: a real player in a real-vs-real match no-shows round 1 → must be forfeited
  const cup2=mk(); cup2.start();
  const m=cup2.currentMatches().find(x=>x.a.br>0 && x.b.br>0);   // a match with no bye
  cup2.state.entrants.forEach(e=>{ if(e.wallet!==m.a.wallet) e.ready=true; });  // everyone ready EXCEPT player a of that match
  const r1=cup2.resolveRound();
  console.log("forfeit handled (no-show loses):", r1.forfeits.length>0?"PASS ✅":"FAIL ❌", JSON.stringify(r1.forfeits[0]));
}
