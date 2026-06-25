// Chikoria Cup — LIVE PvP battle engine (server-authoritative, polling-based).
// Same combat model as cup-resolver.js, but each TURN the two players choose & lock in their own cards.
// The server holds the decks/hands (clients can't fake cards), resolves a turn once both submit
// (or a turn deadline passes → the absent side is auto-played; repeated misses = forfeit).
//
//   createMatch(aSnap, bSnap, opts) -> match
//   submit(match, who, indices)     -> { ok, error }   // who ∈ 'a'|'b'; indices into that side's hand, in play order
//   tick(match, now)                -> resolves on deadline / both-ready; returns true if state changed
//   viewFor(match, who)             -> client-safe view (only your own hand)
//
// A "snapshot" = { name, element, br, arenaSkills:[slot...], cardTier:{slot:tier} }

const TVAL = {
  strike:[0,18,20,22,24,26], blast:[0,30,33,36,39,42], quick:[0,12,14,16,18,20],
  guardReflect:[0,6,7,8,9,10], guardShield:[0,30,34,38,42,46],
  charge:[0,1.7,1.8,1.9,2.0,2.2], drainDmg:[0,14,16,18,20,22], drainHeal:[0,0.60,0.64,0.68,0.72,0.76],
  novaDmg:[0,40,44,48,52,56], novaRecoil:[0,8,7,6,5,4],
  rendDmg:[0,16,18,20,22,24], joltDmg:[0,10,11,12,13,14],
  rally:[0,1.25,1.30,1.35,1.40,1.50],
  witherDmg:[0,8,9,10,11,12], witherAmt:[0,0.30,0.33,0.36,0.39,0.45],
  bulwarkShield:[0,45,50,55,60,65], bulwarkReflect:[0,10,11,12,13,14]
};
const ARCHK = ["strike","blast","quick","guard","charge","drain","nova","rend","jolt","rally","wither","bulwark"];
const CARD_COST = [1,2,1,1,0,1,2,1,1,1,1,2];
const ATK = new Set(["strike","blast","quick","drain","nova","rend","jolt","wither"]);
const ELEM_NEXT = { Water:"Fire", Fire:"Beast", Beast:"Storm", Storm:"Light", Light:"Water" };
const CFG = { strong:1.10, weak:0.92, hpBase:240, hpPerBr:12, dmgScale:0.7 };
const TURN_MS_DEFAULT = 30000;     // seconds to lock in each turn
const MAX_TURNS = 60, FORFEIT_MISSES = 3;
const BEST_OF_DEFAULT = 3;         // a PvP match is best-of-3 games (first to 2 wins)
const INTERMISSION_MS = 4000;      // pause between games so both clients see the result

const elemMult = (a,b) => ELEM_NEXT[a]===b ? CFG.strong : ELEM_NEXT[b]===a ? CFG.weak : 1;
const tier = (snap,slot) => Math.min(5, Math.max(1, (snap.cardTier && snap.cardTier[slot]) || 1));
const statsFor = br => ({ hp:CFG.hpBase+br*CFG.hpPerBr, spd:42+br*2, skill:30+br*2, mor:30+br*2 });
const cardDmgN = (slot,t) => { const k=ARCHK[slot];
  return k==="strike"?TVAL.strike[t]:k==="blast"?TVAL.blast[t]:k==="quick"?TVAL.quick[t]
       :k==="drain"?TVAL.drainDmg[t]:k==="nova"?TVAL.novaDmg[t]:k==="rend"?TVAL.rendDmg[t]
       :k==="jolt"?TVAL.joltDmg[t]:k==="wither"?TVAL.witherDmg[t]:0; };
function hashStr(s){ let h=1779033703^s.length; for(let i=0;i<s.length;i++){h=Math.imul(h^s.charCodeAt(i),3432918353);h=(h<<13)|(h>>>19);} return (h>>>0); }
function mulberry32(a){ return function(){ a|=0; a=a+0x6D2B79F5|0; let t=Math.imul(a^a>>>15,1|a); t=t+Math.imul(t^t>>>7,61|t)^t; return ((t^t>>>14)>>>0)/4294967296; }; }

function makeSide(snap, key, rng){
  const br = Math.max(1, snap.br||1), st = statsFor(br);
  const owned = (snap.arenaSkills && snap.arenaSkills.length) ? snap.arenaSkills.slice() : [0,1,2];
  const deck=[]; for(let i=0;i<12;i++) deck.push(owned[i%owned.length]);
  for(let i=deck.length-1;i>0;i--){ const j=Math.floor(rng()*(i+1)); [deck[i],deck[j]]=[deck[j],deck[i]]; }
  return { key, snap, st, hp:st.hp, maxhp:st.hp, shield:0, energy:0, buff:1, _turnBuff:1, _reflect:0,
           draw:deck, hand:[], disc:[], ls:0, started:false, playedThisTurn:0, queue:[], _joltNext:0, _weaken:0,
           submitted:false, misses:0, lastSeen:Date.now() };
}
function drawTo(s, n, rng){
  while(s.hand.length<n){
    if(s.draw.length===0){ if(s.disc.length===0) break; s.draw=s.disc.slice(); s.disc=[];
      for(let i=s.draw.length-1;i>0;i--){const j=Math.floor(rng()*(i+1));[s.draw[i],s.draw[j]]=[s.draw[j],s.draw[i]];} }
    s.hand.push(s.draw.pop());
  }
}
function applyHP(def, dmg, rng){ if(def.ls>0){ def.ls--; if(def.ls<=0)def.hp=-1; return; }
  def.hp-=dmg; if(def.hp<=0){ if(rng()<def.st.mor/255||def.st.mor>=120){ def.ls=1+Math.floor(def.st.mor/60); def.hp=1; } } }
function dealDamage(att, def, raw, pierceFrac, rng){ pierceFrac=pierceFrac||0;
  let dmg=raw*CFG.dmgScale*att.buff; att.buff=1; dmg*=(att._turnBuff||1); dmg*=elemMult(att.snap.element, def.snap.element);
  if(att._weaken){ dmg*=(1-att._weaken); att._weaken=0; }
  if(att.playedThisTurn>1) dmg+=Math.round(att.st.skill*0.4*(att.playedThisTurn-1));
  const crit=rng()<Math.min(.5, att.st.mor/240); if(crit)dmg*=2; dmg=Math.round(dmg);
  const direct=Math.round(dmg*pierceFrac), viaShield=dmg-direct;
  if(def.shield>0 && viaShield>0){ if(def._reflect)applyHP(att, def._reflect, rng);
    if(viaShield>=def.shield){ const over=Math.round((viaShield-def.shield)*1.15); def.shield=0; applyHP(def, direct+over, rng); }
    else { def.shield-=viaShield; applyHP(def, direct, rng); } }
  else applyHP(def, dmg, rng);
  return crit;
}
function applyCard(side, foe, slot, rng){
  const t=tier(side.snap, slot), k=ARCHK[slot]; side.energy-=CARD_COST[slot]; side.playedThisTurn++;
  if(k==="guard"){ side.shield+=TVAL.guardShield[t]; side._reflect=Math.max(side._reflect||0,TVAL.guardReflect[t]); }
  else if(k==="bulwark"){ side.shield+=TVAL.bulwarkShield[t]; side._reflect=Math.max(side._reflect||0,TVAL.bulwarkReflect[t]); }
  else if(k==="charge"){ side.energy+=1; side.buff=Math.max(side.buff,TVAL.charge[t]); }
  else if(k==="rally"){ side._turnBuff=Math.max(side._turnBuff||1,TVAL.rally[t]); }
  else if(k==="drain"){ dealDamage(side,foe,TVAL.drainDmg[t],0,rng); side.hp=Math.min(side.maxhp, side.hp+Math.round(TVAL.drainDmg[t]*TVAL.drainHeal[t])); }
  else if(k==="nova"){ dealDamage(side,foe,TVAL.novaDmg[t],0,rng); side.hp-=TVAL.novaRecoil[t]; }
  else if(k==="quick"){ dealDamage(side,foe,TVAL.quick[t],1,rng); }
  else if(k==="rend"){ dealDamage(side,foe,TVAL.rendDmg[t],0.5,rng); }
  else if(k==="jolt"){ dealDamage(side,foe,TVAL.joltDmg[t],0,rng); foe._joltNext=(foe._joltNext||0)+1; }
  else if(k==="wither"){ dealDamage(side,foe,TVAL.witherDmg[t],0,rng); foe._weaken=Math.max(foe._weaken||0,TVAL.witherAmt[t]); }
  else dealDamage(side,foe,(k==="strike"?TVAL.strike[t]:TVAL.blast[t]),0,rng);
}
// AI plan (used to auto-play an absent side on a turn timeout)
function plan(me){
  const q=[]; const used=new Set(); let budget=me.energy;
  const take = pred => { for(let i=0;i<me.hand.length;i++){ if(used.has(i))continue; const s=me.hand[i];
    if(pred(s)&&CARD_COST[s]<=budget&&q.length<3){ used.add(i); q.push(i); budget-=CARD_COST[s]; if(s===4)budget+=1; return true; } } return false; };
  if(me.hp/me.maxhp<.4){ if(!take(s=>s===3)) take(s=>s===11); }
  if(me.hand.some(s=>s===4)&&me.hand.some(s=>s===6||s===1)) take(s=>s===4);
  while(q.length<3){ let bi=-1,bd=-1;
    for(let i=0;i<me.hand.length;i++){ if(used.has(i))continue; const s=me.hand[i];
      if(ATK.has(ARCHK[s])&&CARD_COST[s]<=budget&&cardDmgN(s,tier(me.snap,s))>bd){ bd=cardDmgN(s,tier(me.snap,s)); bi=i; } } if(bi<0)break;
    used.add(bi); q.push(bi); budget-=CARD_COST[me.hand[bi]]; }
  return q;
}

const dead = s => s.hp<=0 && s.ls<=0;

function startTurn(m){
  const now = Date.now();
  for(const w of ["a","b"]){ const s=m.sides[w];
    s.disc=s.disc.concat(s.hand); s.hand=[]; s.shield=0; s._reflect=0; s._turnBuff=1;
    s.energy=Math.min(10, s.started?s.energy+1:3);
    if(s._joltNext){ s.energy=Math.max(0,s.energy-s._joltNext); s._joltNext=0; }
    s.started=true; s.buff=1; s.playedThisTurn=0; s.queue=[]; s.submitted=false;
    drawTo(s,6,m.rng);
  }
  m.turn++; m.deadline = now + m.turnMs; m.lastTurn=null;
}

function validateQueue(side, indices){
  if(!Array.isArray(indices)) return "no cards submitted";
  if(indices.length>3) return "max 3 cards per turn";
  const used=new Set(); let budget=side.energy;
  for(const i of indices){
    if(!Number.isInteger(i)||i<0||i>=side.hand.length) return "invalid card index";
    if(used.has(i)) return "duplicate card";
    const slot=side.hand[i], cost=CARD_COST[slot];
    if(cost>budget) return "not enough energy";
    used.add(i); budget-=cost; if(slot===4)budget+=1;   // charge refunds 1
  }
  return null;
}

function resolveTurn(m){
  const A=m.sides.a, B=m.sides.b, log=[];
  const lists = { a:A.queue.map(i=>A.hand[i]), b:B.queue.map(i=>B.hand[i]) };
  const first=m.first, second=first==="a"?"b":"a";
  const seq=[], mx=Math.max(lists.a.length, lists.b.length);
  for(let i=0;i<mx;i++){ if(lists[first][i]!=null)seq.push([first,lists[first][i]]); if(lists[second][i]!=null)seq.push([second,lists[second][i]]); }
  // move played cards to discard
  A.queue.slice().sort((x,y)=>y-x).forEach(i=>{A.disc.push(A.hand[i]);A.hand.splice(i,1);});
  B.queue.slice().sort((x,y)=>y-x).forEach(i=>{B.disc.push(B.hand[i]);B.hand.splice(i,1);});
  A.queue=[]; B.queue=[];
  for(const [who,slot] of seq){
    const att=m.sides[who], def=m.sides[who==="a"?"b":"a"];
    const crit=applyCard(att, def, slot, m.rng);
    log.push({ who, slot, card:ARCHK[slot], crit:!!crit, aHp:Math.round(A.hp), bHp:Math.round(B.hp) });
    if(dead(B)){ return endGame(m, "a", "ko", log); }
    if(dead(A)){ return endGame(m, "b", "ko", log); }
  }
  m.first = second;
  m.lastTurn = { turn:m.turn, first, seq:log };
  if(m.turn>=MAX_TURNS){ const fa=A.hp/A.maxhp, fb=B.hp/B.maxhp; return endGame(m, fa>=fb?"a":"b", "time", log); }
  startTurn(m);
  return m.lastTurn;
}

// One GAME ended (KO or time). Tally the score; finish the MATCH at winsNeeded, else go to intermission.
function endGame(m, gameWinner, reason, log){
  m.score[gameWinner] = (m.score[gameWinner]||0) + 1;
  const matchOver = m.score[gameWinner] >= m.winsNeeded;
  const lt = { turn:m.turn, first:m.first, seq:log||[], final:true, gameOver:true,
               gameWinner, gameReason:reason, game:m.game, score:{a:m.score.a,b:m.score.b}, matchOver };
  m.lastTurn = lt;
  if(matchOver){ m.status="finished"; m.winner=gameWinner; m.reason=reason; }
  else { m.between=true; m.betweenUntil=Date.now()+INTERMISSION_MS;
         m.gameResult={ winner:gameWinner, game:m.game, score:{a:m.score.a,b:m.score.b} }; }
  return lt;
}
// Reset both sides for the next game in the series.
function startNextGame(m){
  m.sides = { a:makeSide(m.aSnap,"a",m.rng), b:makeSide(m.bSnap,"b",m.rng) };
  m.turn=0; m.first = m.rng()<0.5?"a":"b"; m.deadline=0; m.lastTurn=null;
  m.game++; m.between=false; m.gameResult=null;
  startTurn(m);
}
// Whole MATCH ends immediately (used for forfeits / disconnects).
function finishMatch(m, winner, reason, log){
  if(m.score[winner]<m.winsNeeded) m.score[winner]=m.winsNeeded;   // reflect the awarded series win
  m.status="finished"; m.winner=winner; m.reason=reason; m.between=false;
  m.lastTurn = { turn:m.turn, first:m.first, seq:log||[], final:true, gameOver:true, matchOver:true,
                 gameWinner:winner, gameReason:reason, game:m.game, score:{a:m.score.a,b:m.score.b} };
  return m.lastTurn;
}

function createMatch(aSnap, bSnap, opts={}){
  const seed = opts.seed || ("pvp-"+Date.now());
  const rng = mulberry32(hashStr(String(seed)));
  const m = {
    id: opts.id || ("m"+Math.random().toString(36).slice(2,9)),
    seed, status:"active", turnMs: opts.turnMs || TURN_MS_DEFAULT,
    walletA: aSnap.wallet||null, walletB: bSnap.wallet||null,
    rng, aSnap, bSnap, sides:{ a:makeSide(aSnap,"a",rng), b:makeSide(bSnap,"b",rng) },
    turn:0, first: rng()<0.5?"a":"b", deadline:0, winner:null, reason:"", lastTurn:null,
    bestOf: opts.bestOf||BEST_OF_DEFAULT, winsNeeded: Math.ceil((opts.bestOf||BEST_OF_DEFAULT)/2),
    score:{a:0,b:0}, game:1, between:false, betweenUntil:0, gameResult:null,
  };
  startTurn(m);
  return m;
}

function submit(m, who, indices){
  if(m.status!=="active") return { ok:false, error:"match is over" };
  if(m.between) return { ok:false, error:"next game is starting…" };
  const s=m.sides[who]; if(!s) return { ok:false, error:"not in this match" };
  s.lastSeen=Date.now();
  if(s.submitted) return { ok:false, error:"already locked in this turn" };
  const err=validateQueue(s, indices); if(err) return { ok:false, error:err };
  s.queue = indices.slice(); s.submitted=true; s.misses=0;
  if(m.sides.a.submitted && m.sides.b.submitted) resolveTurn(m);   // both locked in → resolve now
  return { ok:true };
}

// Call periodically. On a turn deadline, auto-play any side that hasn't locked in; forfeit after repeated misses.
function tick(m, now=Date.now()){
  if(m.status!=="active") return false;
  if(m.between){ if(now>=m.betweenUntil){ startNextGame(m); return true; } return false; }   // between games → start the next when the break ends
  if(now < m.deadline) return false;
  let changed=false;
  for(const w of ["a","b"]){ const s=m.sides[w];
    if(!s.submitted){ s.misses=(s.misses||0)+1; s.queue=plan(s); s.submitted=true; changed=true; }   // timed out → AI plays this turn
  }
  // a side that has missed too many turns in a row has disconnected → forfeit the whole match
  const fa=m.sides.a.misses>=FORFEIT_MISSES, fb=m.sides.b.misses>=FORFEIT_MISSES;
  if(fa||fb){ finishMatch(m, fa&&!fb?"b":fb&&!fa?"a":(m.sides.a.hp>=m.sides.b.hp?"a":"b"), "forfeit", []); return true; }
  if(changed) resolveTurn(m);
  return true;
}

function sideView(s, isYou){
  const base = { name:s.snap.name, handle:s.snap.handle||null, element:s.snap.element, br:s.snap.br, hp:Math.max(0,Math.round(s.hp)), maxhp:s.maxhp, shield:Math.round(s.shield), submitted:s.submitted };
  if(isYou){ base.energy=s.energy;
    base.hand = s.hand.map((slot,i)=>({ i, slot, type:ARCHK[slot], cost:CARD_COST[slot], tier:tier(s.snap,slot) })); }
  return base;
}
// A player explicitly leaves → instant loss, opponent wins.
function forfeit(m, who){
  if(!m || m.status!=="active") return false;
  finishMatch(m, who==="a"?"b":"a", "forfeit", []);
  return true;
}
function viewFor(m, who){
  const me=who==="a"?m.sides.a:m.sides.b, foe=who==="a"?m.sides.b:m.sides.a;
  if(me) me.lastSeen=Date.now();
  return {
    matchId:m.id, turn:m.turn, status:m.status, turnMs:m.turnMs,
    deadlineInMs: Math.max(0, m.deadline-Date.now()),
    youSubmitted: !!me?.submitted, foeSubmitted: !!foe?.submitted,
    you: sideView(me, true), foe: sideView(foe, false),
    lastTurn: m.lastTurn,
    over: m.status==="finished",
    result: m.status==="finished" ? (m.winner===who ? "win" : "loss") : null,
    reason: m.reason || null,
    // best-of series state
    bestOf: m.bestOf, game: m.game,
    score: { you: who==="a"?m.score.a:m.score.b, foe: who==="a"?m.score.b:m.score.a },
    between: !!m.between,
    breakInMs: m.between ? Math.max(0, m.betweenUntil-Date.now()) : 0,
    gameResult: m.between && m.gameResult ? { youWonGame: m.gameResult.winner===who, game:m.gameResult.game } : null,
  };
}

// Public, no-secrets view for SPECTATORS — both sides' HP/shield/score and the shared turn log, no hands.
function spectatorView(m){
  const pub = s => ({ name: s.snap.name, player: s.snap.player || s.snap.handle || null, element: s.snap.element, br: s.snap.br,
    hp: Math.max(0, Math.round(s.hp)), maxhp: s.maxhp, shield: Math.round(s.shield), submitted: !!s.submitted });
  return {
    matchId:m.id, turn:m.turn, status:m.status, turnMs:m.turnMs,
    deadlineInMs: Math.max(0, m.deadline-Date.now()),
    a: pub(m.sides.a), b: pub(m.sides.b), walletA:m.walletA, walletB:m.walletB,
    lastTurn: m.lastTurn, over: m.status==="finished",
    winner: m.status==="finished" ? m.winner : null, reason: m.reason || null,
    bestOf:m.bestOf, game:m.game, score:{ a:m.score.a, b:m.score.b },
    between: !!m.between, breakInMs: m.between ? Math.max(0, m.betweenUntil-Date.now()) : 0,
  };
}

export { createMatch, submit, tick, viewFor, forfeit, spectatorView, ARCHK, CARD_COST };

/* ---------- self-test (node pvp-engine.js) ---------- */
if (import.meta.url === `file://${process.argv[1]}`) {
  const A={ wallet:"WA", name:"Dragonos", element:"Fire", br:14, arenaSkills:[0,1,6,3,5], cardTier:{0:4,1:3,6:4,3:2,5:2} };
  const B={ wallet:"WB", name:"Galador", element:"Water", br:14, arenaSkills:[3,5,7,0,2], cardTier:{3:3,5:3,7:4,0:2,2:2} };
  // helper: pick a valid greedy queue from a view's hand (≤3, within energy)
  const pick = v => { const used=new Set(); let budget=v.you.energy; const q=[];
    const hand=v.you.hand.slice().sort((x,y)=>y.cost-x.cost);
    for(const c of hand){ if(q.length>=3)break; if(c.cost<=budget&&!used.has(c.i)){ used.add(c.i); q.push(c.i); budget-=c.cost; if(c.slot===4)budget+=1; } } return q; };

  // 1) full best-of-3 match where BOTH players submit every turn
  let m=createMatch(A,B,{seed:"t1"}); let turns=0;
  while(m.status==="active" && turns<400){
    if(m.between){ tick(m, m.betweenUntil); }                 // advance the inter-game break
    else { submit(m,"a",pick(viewFor(m,"a"))); submit(m,"b",pick(viewFor(m,"b"))); }
    turns++;
  }
  console.log("best-of-3 match:", m.status, "winner", m.winner, "score", JSON.stringify(m.score), "games", m.game,
    "| PASS", (m.status==="finished" && (m.score.a===2||m.score.b===2))?"✅":"❌");
  // anti-cheat: can't submit a card you don't have / can't afford
  let m2=createMatch(A,B,{seed:"t2"}); const r=submit(m2,"a",[0,1,2,3]); console.log("4-card reject:", r.error?"PASS ✅":"FAIL ❌", "("+r.error+")");
  const big=submit(m2,"a",[99]); console.log("bad-index reject:", big.error?"PASS ✅":"FAIL ❌");
  // deadline auto-play: B never submits → tick auto-plays B; match still completes
  let m3=createMatch(A,B,{seed:"t3",turnMs:1}); let t3=0;
  while(m3.status==="active" && t3<600){ if(!m3.between)submit(m3,"a",pick(viewFor(m3,"a"))); tick(m3, (m3.between?m3.betweenUntil:Date.now())+10); t3++; }
  console.log("deadline auto-play completes:", m3.status==="finished"?"PASS ✅":"FAIL ❌", "(winner "+m3.winner+", reason "+m3.reason+", score "+JSON.stringify(m3.score)+")");
  // forfeit: neither side acts for 3 turns → forfeit
  let m4=createMatch(A,B,{seed:"t4",turnMs:1}); for(let i=0;i<5 && m4.status==="active";i++) tick(m4, Date.now()+10);
  console.log("idle forfeit:", m4.status==="finished"&&m4.reason==="forfeit"?"PASS ✅":"FAIL ❌");
  // client view hides the foe's hand
  const v=viewFor(createMatch(A,B,{seed:"t5"}),"a");
  console.log("foe hand hidden:", v.foe.hand===undefined && Array.isArray(v.you.hand)?"PASS ✅":"FAIL ❌");
}
