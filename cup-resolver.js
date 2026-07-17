// Chikoria Cup — server-authoritative, DETERMINISTIC battle resolver (Phase 0).
// Ports the client lock-in battle engine (play.html) so the SERVER decides match winners.
// Same seed + same two snapshots => identical result every time. No client trust.
//
// A "snapshot" = { name, element, br, arenaSkills:[slot...], cardTier:{slot:tier} }
//   element ∈ Water|Fire|Beast|Storm|Light ; slots 0..11 ; tier 1..5
//
// resolveBattle(a, b, seed) -> { winner:'a'|'b', rounds, log:[...], aHp, bHp, reason }

/* ---------- constants (mirror of play.html) ---------- */
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
// Tunable balance knobs. Cup standard (tuned so element is an EDGE not a coinflip, BR/tier decides,
// and matches last ~15-20 rounds). Solo play.html still uses 1.5/0.7/hp120 unless synced later.
const DEFAULTS = { strong:1.10, weak:0.92, hpBase:240, hpPerBr:12, dmgScale:0.7 };
let CFG = { ...DEFAULTS };
const elemMult = (a,b) => ELEM_NEXT[a]===b ? CFG.strong : ELEM_NEXT[b]===a ? CFG.weak : 1;
const tier = (snap,slot) => Math.min(5, Math.max(1, (snap.cardTier && snap.cardTier[slot]) || 1));
const statsFor = br => ({ hp:CFG.hpBase+br*CFG.hpPerBr, spd:42+br*2, skill:30+br*2, mor:30+br*2 });
const cardDmgN = (slot,t) => {
  const k = ARCHK[slot];
  return k==="strike"?TVAL.strike[t]:k==="blast"?TVAL.blast[t]:k==="quick"?TVAL.quick[t]
       :k==="drain"?TVAL.drainDmg[t]:k==="nova"?TVAL.novaDmg[t]:k==="rend"?TVAL.rendDmg[t]
       :k==="jolt"?TVAL.joltDmg[t]:k==="wither"?TVAL.witherDmg[t]:0;
};

/* ---------- seeded PRNG (deterministic) ---------- */
function hashStr(s){ let h=1779033703^s.length; for(let i=0;i<s.length;i++){h=Math.imul(h^s.charCodeAt(i),3432918353);h=(h<<13)|(h>>>19);} return (h>>>0); }
function mulberry32(a){ return function(){ a|=0; a=a+0x6D2B79F5|0; let t=Math.imul(a^a>>>15,1|a); t=t+Math.imul(t^t>>>7,61|t)^t; return ((t^t>>>14)>>>0)/4294967296; }; }

/* ---------- side setup ---------- */
function makeSide(snap, rng, key){
  const br = Math.max(1, snap.br||1);
  const st = statsFor(br);
  const owned = (snap.arenaSkills && snap.arenaSkills.length) ? snap.arenaSkills.slice() : [0,1,2];
  const deck = []; for(let i=0;i<12;i++) deck.push(owned[i%owned.length]);
  for(let i=deck.length-1;i>0;i--){ const j=Math.floor(rng()*(i+1)); [deck[i],deck[j]]=[deck[j],deck[i]]; }
  return { key, snap, st, hp:st.hp, maxhp:st.hp, shield:0, energy:0, buff:1, _turnBuff:1, _reflect:0,
           draw:deck, hand:[], disc:[], ls:0, started:false, playedThisTurn:0, queue:[], _joltNext:0, _weaken:0 };
}
function drawTo(s, n, rng){
  while(s.hand.length<n){
    if(s.draw.length===0){ if(s.disc.length===0) break; s.draw=s.disc.slice(); s.disc=[];
      for(let i=s.draw.length-1;i>0;i--){const j=Math.floor(rng()*(i+1));[s.draw[i],s.draw[j]]=[s.draw[j],s.draw[i]];} }
    s.hand.push(s.draw.pop());
  }
}

/* ---------- combat ---------- */
function applyHP(def, dmg, rng){
  if(def.ls>0){ def.ls--; if(def.ls<=0) def.hp=-1; return; }
  def.hp -= dmg;
  if(def.hp<=0){ if(rng()<def.st.mor/255 || def.st.mor>=120){ def.ls=1+Math.floor(def.st.mor/60); def.hp=1; } }
}
function dealDamage(att, def, raw, pierceFrac, rng){
  pierceFrac = pierceFrac||0;
  let dmg = raw*CFG.dmgScale*att.buff; att.buff=1;
  dmg *= (att._turnBuff||1);
  dmg *= elemMult(att.snap.element, def.snap.element);
  if(att._weaken){ dmg*=(1-att._weaken); att._weaken=0; }
  if(att.playedThisTurn>1) dmg += Math.round(att.st.skill*0.4*(att.playedThisTurn-1));
  const crit = rng()<Math.min(.5, att.st.mor/240); if(crit) dmg*=2;
  dmg = Math.round(dmg);
  const direct = Math.round(dmg*pierceFrac), viaShield = dmg-direct;
  if(def.shield>0 && viaShield>0){
    if(def._reflect) applyHP(att, def._reflect, rng);
    if(viaShield>=def.shield){ const over=Math.round((viaShield-def.shield)*1.15); def.shield=0; applyHP(def, direct+over, rng); }
    else { def.shield-=viaShield; applyHP(def, direct, rng); }
  } else applyHP(def, dmg, rng);
  return crit;
}
function applyCard(side, foe, slot, rng){
  const t = tier(side.snap, slot), k = ARCHK[slot];
  side.energy -= CARD_COST[slot]; side.playedThisTurn++;
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
/* AI plan (same policy as the client rival) — also the default for an absent/forfeited player */
function plan(me, rng){
  me.queue=[]; const used=new Set(); let budget=me.energy;
  const take = pred => { for(let i=0;i<me.hand.length;i++){ if(used.has(i))continue; const s=me.hand[i];
    if(pred(s) && CARD_COST[s]<=budget && me.queue.length<3){ used.add(i); me.queue.push(i); budget-=CARD_COST[s]; if(s===4)budget+=1; return true; } } return false; };
  if(me.hp/me.maxhp<.4){ if(!take(s=>s===3)) take(s=>s===11); }
  if(me.hand.some(s=>s===4) && me.hand.some(s=>s===6||s===1)) take(s=>s===4);
  while(me.queue.length<3){ let bi=-1,bd=-1;
    for(let i=0;i<me.hand.length;i++){ if(used.has(i))continue; const s=me.hand[i];
      if(ATK.has(ARCHK[s]) && CARD_COST[s]<=budget && cardDmgN(s,tier(me.snap,s))>bd){ bd=cardDmgN(s,tier(me.snap,s)); bi=i; } }
    if(bi<0)break; used.add(bi); me.queue.push(bi); budget-=CARD_COST[me.hand[bi]];
  }
}

/* ---------- full match ---------- */
function resolveBattle(a, b, seed, cfg){
  CFG = { ...DEFAULTS, ...(cfg||{}) };
  const rng = mulberry32(hashStr(String(seed)+"|"+(a.name||"a")+"|"+(b.name||"b")));
  const A = makeSide(a, rng, "a"), Bs = makeSide(b, rng, "b");
  const sides = { a:A, b:Bs };
  const log = [];
  let first = (rng()<0.5) ? "a" : "b";
  const MAX_ROUNDS = 60;
  let round = 0, over = false, winner = null, reason = "";
  const dead = s => s.hp<=0 && s.ls<=0;

  while(!over && round<MAX_ROUNDS){
    round++;
    for(const w of ["a","b"]){ const s=sides[w];
      s.disc=s.disc.concat(s.hand); s.hand=[]; s.shield=0; s._reflect=0; s._turnBuff=1;
      s.energy=Math.min(10, s.started?s.energy+1:3);
      if(s._joltNext){ s.energy=Math.max(0,s.energy-s._joltNext); s._joltNext=0; }
      s.started=true; s.buff=1; s.playedThisTurn=0; s.queue=[];
      drawTo(s,6,rng); plan(s,rng);
    }
    const second = first==="a"?"b":"a";
    const lists = { a:A.queue.map(i=>A.hand[i]), b:Bs.queue.map(i=>Bs.hand[i]) };
    const seq=[], mx=Math.max(lists.a.length, lists.b.length);
    for(let i=0;i<mx;i++){ if(lists[first][i]!=null)seq.push([first,lists[first][i]]); if(lists[second][i]!=null)seq.push([second,lists[second][i]]); }
    // move played cards to discard
    A.queue.slice().sort((x,y)=>y-x).forEach(i=>{A.disc.push(A.hand[i]);A.hand.splice(i,1);});
    Bs.queue.slice().sort((x,y)=>y-x).forEach(i=>{Bs.disc.push(Bs.hand[i]);Bs.hand.splice(i,1);});
    A.queue=[]; Bs.queue=[];
    for(const [who,slot] of seq){
      const att=sides[who], def=sides[who==="a"?"b":"a"];
      const crit = applyCard(att, def, slot, rng);
      log.push({ round, who, slot, card:ARCHK[slot], crit:!!crit, aHp:Math.round(A.hp), bHp:Math.round(Bs.hp) });
      if(dead(Bs)){ over=true; winner="a"; reason="ko"; break; }
      if(dead(A)){ over=true; winner="b"; reason="ko"; break; }
    }
    first = second;
  }
  if(!over){ // round cap -> higher HP% wins; tie -> seeded coin
    const fa=A.hp/A.maxhp, fb=Bs.hp/Bs.maxhp;
    winner = fa>fb ? "a" : fb>fa ? "b" : (rng()<0.5?"a":"b");
    reason = "time";
  }
  return { winner, rounds:round, reason, aHp:Math.max(0,Math.round(A.hp)), bHp:Math.max(0,Math.round(Bs.hp)), log };
}

export { resolveBattle, statsFor, elemMult };

/* ---------- self-test (run: node cup-resolver.js) ---------- */
if (import.meta.url === `file://${process.argv[1]}`) {
  const A = { name:"Dragonos", element:"Fire", br:14, arenaSkills:[0,1,6], cardTier:{0:5,1:5,6:5} };
  const B = { name:"Galador",  element:"Water", br:14, arenaSkills:[3,5,7], cardTier:{3:5,5:5,7:5} };
  const r1 = resolveBattle(A,B,"match-1");
  const r2 = resolveBattle(A,B,"match-1");
  const r3 = resolveBattle(A,B,"match-2");
  console.log("seed match-1:", r1.winner, `(rounds ${r1.rounds}, ${r1.reason}, hp ${r1.aHp}/${r1.bHp})`);
  console.log("determinism (same seed => same result):", r1.winner===r2.winner && r1.rounds===r2.rounds ? "PASS ✅" : "FAIL ❌");
  console.log("different seed can differ:", "match-2 ->", r3.winner, `(rounds ${r3.rounds})`);
  // win-rate sanity over many seeds (Water beats Fire ×1.5, so Galador should edge it)
  let aw=0,N=2000; for(let i=0;i<N;i++){ if(resolveBattle(A,B,"s"+i).winner==="a")aw++; }
  console.log(`win split over ${N} seeds: Dragonos(Fire) ${(aw/N*100).toFixed(1)}% vs Galador(Water) ${(100-aw/N*100).toFixed(1)}%  (Water should lead)`);
}
