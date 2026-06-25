// Chiki Monsters backend v2 — Postgres-backed, idempotent logged payouts.
// Holder verification + server-signed SOL payouts. Devnet-first; set DATABASE_URL for production.
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import bs58 from "bs58";
import crypto from "node:crypto";   // built-in — used for Ed25519 chat-signature verification (no external dep)
import pg from "pg";
import {
  Connection, Keypair, PublicKey, Transaction, SystemProgram, LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import { createCup } from "./cup-live.js";   // Chikoria Cup live orchestrator (double-elim, deterministic resolver)
import { createMatch as pvpCreate, submit as pvpSubmit, tick as pvpTick, viewFor as pvpView, forfeit as pvpForfeit, spectatorView as pvpSpectate } from "./pvp-engine.js";   // live PvP battles

dotenv.config();
const {
  NETWORK = "devnet",
  RPC_URL,
  CHIKI_MINT,
  MIN_HOLD = "500000",
  MIN_HOLD_MINUTES = "0",          // anti-sybil: wallet must be "seen" this long before it can claim
  WHALE_MIN_HOLD = "800000",       // balance for the 2nd Chiki
  WHALE_HOLD_HOURS = "6",          // must hold >= WHALE_MIN_HOLD continuously this long to earn the 2nd Chiki
  VERIFY_HOLDERS = "false",
  TREASURY_SECRET,
  TEAM_WALLET = "",
  REWARD_RATE_PER_MIN = "0.0008",  // legacy; no longer used (earnings are now task/rarity-based)
  EARN_MULT = "1",                 // global multiplier on all task SOL payouts (tune to your fee budget)
  TASK_SECONDS = "45",             // avg seconds a Chiki takes per task (sets task throughput)
  ACCRUAL_CAP_MIN = "1440",        // max minutes of task earnings counted per claim (24h pouch cap)
  MAX_CLAIM_SOL = "1",             // per-claim ceiling — high enough that even a 2-Chiki full pouch isn't clipped (displayed pouch ≈ actual payout)
  DAILY_CAP_SOL = "1",             // absolute backstop ceiling (rarely binds; the real cap is DAILY_CAP_FRAC below)
  DAILY_CAP_FRAC = "1",            // NO daily cap on the reward pool (1 = up to the whole spendable pool/day) — the reserve floor is the only pool guard
  POOL_RESERVE_SOL = "0.05",       // never pay the treasury below this floor — the hard "never go into debt" guarantee
  POOL_REF_SOL = "20",             // reward reference: payout = base_table × (pool / POOL_REF). Higher = SMALLER payouts (longer runway). Lower = more generous.
  PER_WALLET_DAILY_SOL = "0.1",    // per-wallet cap per rolling 24h (0 = unlimited) — stops one wallet draining the pool
  CLAIM_COOLDOWN_SEC = "30",
  DATABASE_URL = "",
  ADMIN_KEY = "",                   // set this to enable /admin/reset (wipe test profiles)
  ADMIN_WALLETS = "",               // comma-separated wallet addresses allowed to PIN/announce in chat
  PORT = "8787",
} = process.env;

if (!RPC_URL || !TREASURY_SECRET) {
  console.error("✖ Missing RPC_URL or TREASURY_SECRET in .env"); process.exit(1);
}
const parseSecret = (s) => (s.trim().startsWith("[") ? Uint8Array.from(JSON.parse(s)) : bs58.decode(s.trim()));
const conn = new Connection(RPC_URL, "confirmed");
const treasury = Keypair.fromSecretKey(parseSecret(TREASURY_SECRET));
const MINT = CHIKI_MINT ? new PublicKey(CHIKI_MINT) : null;
const MIN = Number(MIN_HOLD), CAP = Number(MAX_CLAIM_SOL);
const COOLDOWN = Number(CLAIM_COOLDOWN_SEC) * 1000;
const HOLD_MS = Number(MIN_HOLD_MINUTES) * 60_000;
const DAILY_CAP = Number(DAILY_CAP_SOL);
const RESERVE = Number(POOL_RESERVE_SOL);
const POOL_REF = Math.max(0.000001, Number(POOL_REF_SOL));
const DAILY_FRAC = Math.min(1, Math.max(0, Number(DAILY_CAP_FRAC)));
// TRUE percentage-of-pool model: payout = base_table × (pool / POOL_REF).
// This is a pure fraction of the LIVE pool — it scales DOWN as the pool drains and UP as it refills (no stuck floor).
// Because every payout is read against the current pool and bounded by the RESERVE floor, the pool asymptotes toward
// the reserve but never crosses it: the treasury can never go into debt, and rewards self-correct without a fixed cap.
const poolFactor = (pool) => (Number(pool) || 0) / POOL_REF;
const MULT = Number(EARN_MULT), TASK_SEC = Math.max(5, Number(TASK_SECONDS)), ACCRUAL_CAP = Number(ACCRUAL_CAP_MIN);
const WHALE_MIN = Number(WHALE_MIN_HOLD), WHALE_HOLD_MS = Number(WHALE_HOLD_HOURS) * 3600_000;
const CLAIM_TAX = Math.min(0.95, Math.max(0, Number(process.env.CLAIM_TAX_PCT || 20) / 100));   /* SOL claim tax — withheld from payout, stays in treasury (1% burn / 39% pool / 60% team bookkeeping) */
/* effective Chiki count: 1 if eligible holder; 2 only after holding >= WHALE_MIN continuously for WHALE_HOLD_MS */
function chikiCount(balance, whaleSince) {
  if (balance < MIN) return 0;
  if (balance >= WHALE_MIN && whaleSince && (Date.now() - Number(whaleSince)) >= WHALE_HOLD_MS) return 2;
  return 1;
}
/* server-authoritative, rarity-weighted earnings: each simulated task pays SOL by rarity.
   The server rolls the tasks itself (using on-chain Chiki count + elapsed time), so it can't be faked. */
const RARITY_SOL = { common:0.000008, uncommon:0.000016, rare:0.000036, epic:0.00008, mythic:0.0002, shiny:0.0004, legend:0.001 };  /* task rewards cut 60% across the board · NO daily pool cap · bounded by per-claim cap, per-wallet daily cap + reserve floor */
const RARITY_DIST = [["common",45],["uncommon",27],["rare",15],["epic",7],["mythic",3.5],["shiny",1.7],["legend",0.8]];
const RARITY_TOTAL = RARITY_DIST.reduce((s, r) => s + r[1], 0);
function rollRarity() {
  let x = Math.random() * RARITY_TOTAL;
  for (const [name, w] of RARITY_DIST) { x -= w; if (x <= 0) return name; }
  return "common";
}
/* DETERMINISTIC earnings: expected SOL per task (rarity-weighted average) × tasks.
   No per-call randomness, so the Chiki Pouch rises smoothly with time and the
   estimate matches the actual claim exactly (no jitter). */
const RARITY_EV = RARITY_DIST.reduce((s, [name, w]) => s + RARITY_SOL[name] * (w / RARITY_TOTAL), 0);
function simEarn(minutes, chikis) {
  const tasks = Math.min(4000, Math.floor((minutes * 60 / TASK_SEC) * Math.max(1, chikis)));
  return tasks * RARITY_EV * MULT;
}
/* ---- SEEDED deterministic earnings ----
   The exact same math runs on the client, so the rares a player SEES are the rares the
   server pays for. Cheat-proof: the sequence is seeded by wallet + last_claim (both server-known),
   not by anything the client reports. Each Chiki earns 1 "slot" every TASK_SEC seconds. */
function chikiHash(str){
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++){ h = Math.imul(h ^ str.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  h = Math.imul(h ^ (h >>> 16), 2246822507); h = Math.imul(h ^ (h >>> 13), 3266489909);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function slotRarity(wallet, lastClaim, ci, slot){
  let x = chikiHash(wallet + "|" + lastClaim + "|" + ci + "|" + slot) * RARITY_TOTAL;
  for (const [name, w] of RARITY_DIST){ x -= w; if (x <= 0) return name; }
  return "common";
}
function seededEarn(wallet, lastClaim, chikis, minutes){
  const slots = Math.min(4000, Math.floor(minutes * 60 / TASK_SEC));
  let sol = 0;
  for (let ci = 0; ci < chikis; ci++) for (let s = 0; s < slots; s++) sol += RARITY_SOL[slotRarity(wallet, lastClaim, ci, s)];
  return sol * MULT;
}
const WALLET_DAILY = Number(PER_WALLET_DAILY_SOL);
const verifyOn = String(VERIFY_HOLDERS).toLowerCase() === "true";

const isPubkey = (s) => { try { new PublicKey(s); return true; } catch { return false; } };

/* Prove the request really comes from the owner of `wallet`:
   the client signs "…wallet:<wallet>…ts:<ms>…" with their Phantom key; we verify it here.
   Stops anyone from CHATTING / PINNING as the team, rewards, or any other wallet they don't own. */
function verifyWalletSig(wallet, msg, sigB64) {
  try {
    if (!wallet || !msg || !sigB64) return false;
    const m = String(msg);
    if (!m.includes("wallet:" + wallet)) return false;            // signature must bind THIS wallet
    const tm = m.match(/ts:(\d+)/); if (!tm) return false;
    const ts = Number(tm[1]);
    if (Date.now() - ts > 24 * 3600 * 1000) return false;         // signed too long ago
    if (ts - Date.now() > 5 * 60 * 1000) return false;            // future-dated
    const sig = Buffer.from(String(sigB64), "base64");
    if (sig.length !== 64) return false;
    // verify the Ed25519 signature with Node's built-in crypto (wrap the raw 32-byte key in SPKI DER)
    const pub = Buffer.from(new PublicKey(wallet).toBytes());
    const der = Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), pub]);
    const key = crypto.createPublicKey({ key: der, format: "der", type: "spki" });
    return crypto.verify(null, Buffer.from(m, "utf8"), key, sig);
  } catch (e) { return false; }
}

/* ----- anti-cheat / anti-XSS: clamp the client profile to legal values before storing ----- */
const MAX_LEVEL = 50, MAX_BR = 30;
const maxStamOf  = lv => 80 + lv * 12;
const foodMaxSec = lv => Math.round(30 + (Math.min(lv, MAX_LEVEL) - 1) / 49 * 690) * 60;
const xpNeed     = lv => Math.round(140 + (Math.max(1, lv) - 1) * 95 + Math.pow(Math.max(1, lv), 2) * 0.8);
const legStamMax = lv => Math.round(120 + (Math.min(Math.max(lv, 1), MAX_LEVEL) - 1) / 49 * 780);
const stripTags  = s => String(s == null ? "" : s).replace(/[<>]/g, "");          // no HTML tags ⇒ no stored XSS
const clampNum   = (v, lo, hi, def) => { v = Number(v); return isFinite(v) ? Math.max(lo, Math.min(hi, v)) : def; };

// Returns a sanitized copy of the incoming profile, using the previously-stored one to block roll-backs / jumps.
function sanitizeProfile(prev, p) {
  const out = { ...p };
  if (out.handle != null) out.handle = stripTags(out.handle).slice(0, 16);
  out.glory   = clampNum(out.glory, 0, 1e12, 0);
  out.renames = clampNum(out.renames, 0, 99, 0);
  const prevCh = (prev && Array.isArray(prev.chikis)) ? prev.chikis : [];
  // ===== ROSTER IS NEVER REDUCED: a wallet keeps every Chiki it has ever owned (by species),
  //       unless the player explicitly releases it. Incoming saves update existing Chikis and may
  //       ADD new species within the hatch caps, but can never drop a previously-owned one. =====
  const inc = Array.isArray(out.chikis) ? out.chikis : [];
  if (inc.length || prevCh.length) {
    const firstBySp = arr => { const m = new Map(); for (const c of arr) { const sp = clampNum(c.sp, 0, 14, 0); if (!m.has(sp)) m.set(sp, c); } return m; };
    const incBySp = firstBySp(inc), prevBySp = firstBySp(prevCh);
    const order = [];
    for (const sp of prevBySp.keys()) order.push(sp);                          // 1) preserve EVERY previously-owned species first
    for (const sp of incBySp.keys()) if (!prevBySp.has(sp)) order.push(sp);    // 2) then any brand-new species the save added
    let normals = 0, legs = 0; const kept = [];
    for (const sp of order) {
      const ic = incBySp.get(sp), pc = prevBySp.get(sp) || {};
      const src = ic || pc;                                                    // prefer the incoming (latest) data; fall back to stored
      const isLegend = !!(src.isLegend || pc.isLegend);
      if (isLegend) { if (legs >= 1) continue; legs++; } else { if (normals >= 2) continue; normals++; }   // caps drop EXCESS NEW ones, never originals
      const prevLv = clampNum(pc.level, 1, MAX_LEVEL, 1);
      let lv = clampNum(src.level, 1, MAX_LEVEL, 1);
      if (pc.level != null) lv = Math.min(Math.max(lv, prevLv), prevLv + 4);   // level monotonic, no jumps
      // BR can't be injected — it only rises gradually via Battle EXP; cap the per-save jump
      const brP = clampNum(pc.br, 1, MAX_BR, 1);
      let brF = Math.max(clampNum(src.br, 1, MAX_BR, 1), brP);
      if (pc.br != null) brF = Math.min(brF, brP + 3);
      // skill-card tiers must be a clean {slot:1..5} map — never accept arbitrary values
      const rawCT = (src.cardTier && typeof src.cardTier === "object" && !Array.isArray(src.cardTier)) ? src.cardTier
                  : ((pc.cardTier && typeof pc.cardTier === "object" && !Array.isArray(pc.cardTier)) ? pc.cardTier : null);
      let ctF = null;
      if (rawCT) { ctF = {}; for (const k in rawCT) { const slot = k | 0; if (slot >= 0 && slot < 12) ctF[slot] = clampNum(rawCT[k], 1, 5, 1); } }
      kept.push({
        sp, level: lv, isLegend, hungry: !!src.hungry, tending: !!src.tending,
        nick: src.nick != null ? stripTags(src.nick).slice(0, 16) : (pc.nick != null ? stripTags(pc.nick).slice(0, 16) : null),
        xp: clampNum(src.xp, 0, xpNeed(lv), 0),
        food: clampNum(src.food, 0, foodMaxSec(lv), 0),
        stamina: clampNum(src.stamina, 0, isLegend ? legStamMax(lv) : maxStamOf(lv), maxStamOf(lv)),
        tasksDone:   Math.max(clampNum(src.tasksDone, 0, 1e12, 0),  clampNum(pc.tasksDone, 0, 1e12, 0)),    // monotonic
        sleepCycles: Math.max(clampNum(src.sleepCycles, 0, 1e9, 0), clampNum(pc.sleepCycles, 0, 1e9, 0)),
        renames: clampNum(src.renames, 0, 9, 0),
        br: brF,
        battleXp: clampNum(src.battleXp, 0, 1e12, 0),
        skillPts: clampNum(src.skillPts, 0, 999, 0),
        arenaSkills: Array.isArray(src.arenaSkills) ? src.arenaSkills.slice(0, 12).map(s => clampNum(s, 0, 11, 0))
                   : (Array.isArray(pc.arenaSkills) ? pc.arenaSkills.slice(0, 12).map(s => clampNum(s, 0, 11, 0)) : null),
        cardTier: ctF,
        arenaStam: src.arenaStam != null ? clampNum(src.arenaStam, 0, legStamMax(lv), legStamMax(lv))
                 : (pc.arenaStam != null ? clampNum(pc.arenaStam, 0, legStamMax(lv), legStamMax(lv)) : null),
        arenaSleepUntil: clampNum(src.arenaSleepUntil != null ? src.arenaSleepUntil : pc.arenaSleepUntil, 0, Date.now() + 24 * 3600 * 1000, 0),
        sleeping: !!src.sleeping,                                                                  // preserve nap state across the server round-trip
        sleepUntil: clampNum(src.sleepUntil != null ? src.sleepUntil : pc.sleepUntil, 0, Date.now() + 24 * 3600 * 1000, 0),   // ...so a refresh RESUMES the nap instead of restarting it
      });
    }
    out.chikis = kept;
  }
  return out;
}
const _lastSave = new Map();   // light per-wallet write throttle
const _lastChat = new Map();   // light per-wallet chat throttle

// Per-wallet $CHIKI balance — CACHED 30s so 500+ polling clients don't spam Helius (429s).
const _balCache = new Map();
async function chikiBalance(owner) {
  if (!MINT) return 0;
  const c = _balCache.get(owner);
  if (c && Date.now() - c.t < 30000) return c.v;
  try {
    const r = await conn.getParsedTokenAccountsByOwner(new PublicKey(owner), { mint: MINT });
    let b = 0; for (const { account } of r.value) b += account.data.parsed.info.tokenAmount.uiAmount || 0;
    _balCache.set(owner, { t: Date.now(), v: b });
    if (_balCache.size > 5000) _balCache.clear();   // simple bound
    return b;
  } catch { return c ? c.v : 0; }
}
// Treasury (reward pool) SOL — CACHED 20s. Pool changes slowly; this kills the per-request getBalance spam.
let _poolCache = { t: 0, v: 0 };
const poolSol = async () => {
  if (_poolCache.t && Date.now() - _poolCache.t < 20000) return _poolCache.v;
  const v = (await conn.getBalance(treasury.publicKey)) / LAMPORTS_PER_SOL;
  _poolCache = { t: Date.now(), v };
  return v;
};

/* ----------------------------- storage ----------------------------- */
// Two backends with one interface. Postgres when DATABASE_URL is set; else in-memory (dev only).
function makeStore() {
  if (DATABASE_URL) return pgStore();
  console.warn("⚠ No DATABASE_URL — using IN-MEMORY store (state is lost on restart; NOT for mainnet).");
  return memStore();
}

function pgStore() {
  const pool = new pg.Pool({
    connectionString: DATABASE_URL,
    ssl: DATABASE_URL.includes("localhost") ? false : { rejectUnauthorized: false },
  });
  return {
    kind: "postgres",
    async init() {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS players(
          wallet TEXT PRIMARY KEY,
          first_seen BIGINT NOT NULL,
          last_claim BIGINT NOT NULL DEFAULT 0,
          lifetime_paid DOUBLE PRECISION NOT NULL DEFAULT 0,
          eligible BOOLEAN NOT NULL DEFAULT false,
          balance DOUBLE PRECISION NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS payouts(
          id BIGSERIAL PRIMARY KEY,
          wallet TEXT NOT NULL,
          amount DOUBLE PRECISION NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          signature TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );`);
      await pool.query(`ALTER TABLE players ADD COLUMN IF NOT EXISTS profile JSONB`);
      await pool.query(`ALTER TABLE players ADD COLUMN IF NOT EXISTS whale_since BIGINT`);
      await pool.query(`CREATE TABLE IF NOT EXISTS presence(
        wallet TEXT PRIMARY KEY, last_active BIGINT NOT NULL, chikis INT NOT NULL DEFAULT 1)`);
      await pool.query(`ALTER TABLE presence ADD COLUMN IF NOT EXISTS roster JSONB`);
      await pool.query(`CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v JSONB)`);   // small durable key/value (Cup prize ledger, flags)
    },
    async kvGet(k) { const r = await pool.query(`SELECT v FROM kv WHERE k=$1`, [k]); return r.rows[0]?.v ?? null; },
    async kvSet(k, v) { await pool.query(`INSERT INTO kv(k,v) VALUES($1,$2::jsonb) ON CONFLICT(k) DO UPDATE SET v=$2::jsonb`, [k, JSON.stringify(v)]); },
    async heartbeat(wallet, chikis, roster) {
      await pool.query(
        `INSERT INTO presence(wallet,last_active,chikis,roster) VALUES($1,$2::bigint,$3,$4::jsonb)
         ON CONFLICT(wallet) DO UPDATE SET last_active=$2::bigint, chikis=$3, roster=$4::jsonb`,
        [wallet, Date.now(), Math.max(0, chikis | 0), JSON.stringify(Array.isArray(roster) ? roster.slice(0, 8) : [])]);
    },
    async presence(windowMs) {
      const r = await pool.query(
        `SELECT COUNT(*)::int a, COALESCE(SUM(chikis),0)::int c FROM presence WHERE last_active > $1`,
        [Date.now() - windowMs]);
      return { activeUsers: r.rows[0].a, chikimons: r.rows[0].c };
    },
    async resetProfiles() {
      const r = await pool.query(`UPDATE players SET profile=NULL WHERE profile IS NOT NULL`);
      await pool.query(`DELETE FROM presence`);
      return r.rowCount || 0;
    },
    async world(windowMs, exclude, cap) {
      const r = await pool.query(
        `SELECT wallet, roster FROM presence WHERE last_active > $1 AND wallet <> $2 ORDER BY last_active DESC`,
        [Date.now() - windowMs, exclude || ""]);
      const out = [];
      for (const row of r.rows) for (const e of (row.roster || [])) {
        out.push({ wallet: row.wallet, sp: e.sp | 0, level: e.level | 0 });
        if (out.length >= cap) return out;
      }
      return out;
    },
    async getProfile(wallet) {
      const r = await pool.query(`SELECT profile FROM players WHERE wallet=$1`, [wallet]);
      return r.rows[0]?.profile || null;
    },
    async setProfile(wallet, profile) {
      const now = Date.now();
      await pool.query(
        `INSERT INTO players(wallet,first_seen,last_claim,profile)
         VALUES($1,$2::bigint,$3::bigint,$4::jsonb)
         ON CONFLICT(wallet) DO UPDATE SET profile=$4::jsonb`,
        [wallet, now, now - 60000, JSON.stringify(profile)]);
    },
    async touch(wallet, eligible, balance) {
      const now = Date.now();
      const ws = balance >= WHALE_MIN ? now : null;
      const r = await pool.query(
        `INSERT INTO players(wallet,first_seen,last_claim,eligible,balance,whale_since)
         VALUES($1,$2::bigint,$3::bigint,$4,$5,$6::bigint)
         ON CONFLICT(wallet) DO UPDATE SET eligible=$4, balance=$5,
           whale_since = CASE WHEN $5 < ${WHALE_MIN} THEN NULL
                              WHEN players.whale_since IS NULL THEN $2::bigint
                              ELSE players.whale_since END
         RETURNING *`, [wallet, now, now - 60000, eligible, balance, ws]);
      return r.rows[0];
    },
    async dailyTotal() {
      const r = await pool.query(
        `SELECT COALESCE(SUM(amount),0) s FROM payouts WHERE status='confirmed' AND created_at > now()-interval '1 day'`);
      return Number(r.rows[0].s);
    },
    async walletDaily(wallet) {
      const r = await pool.query(
        `SELECT COALESCE(SUM(amount),0) s FROM payouts WHERE wallet=$1 AND status='confirmed' AND created_at > now()-interval '1 day'`, [wallet]);
      return Number(r.rows[0].s);
    },
    async earned(wallet) {
      const r = await pool.query(`SELECT COALESCE(lifetime_paid,0) p FROM players WHERE wallet=$1`, [wallet]);
      return Number(r.rows[0]?.p || 0);   // real SOL actually paid out to this wallet
    },
    async topEarners(limit) {
      const r = await pool.query(`SELECT wallet, COALESCE(lifetime_paid,0) p, profile->>'handle' AS handle FROM players WHERE lifetime_paid > 0 ORDER BY lifetime_paid DESC LIMIT $1`, [limit]);
      return r.rows.map(x => ({ wallet: x.wallet, earnedSol: Number(x.p), handle: x.handle || null }));
    },
    async totalPaid() {   // ALL-TIME SOL paid out to keepers (sum of every wallet's lifetime payouts)
      const r = await pool.query(`SELECT COALESCE(SUM(lifetime_paid),0) p FROM players`);
      return Number(r.rows[0]?.p || 0);
    },
    async chikisForWallets(wallets) {   // total Chikis owned in-game by a given set of wallets (the real keepers)
      if (!wallets || !wallets.length) return 0;
      const r = await pool.query(`SELECT COALESCE(SUM(jsonb_array_length(profile->'chikis')),0) c FROM players WHERE wallet = ANY($1) AND jsonb_typeof(profile->'chikis')='array'`, [wallets]);
      return Number(r.rows[0]?.c || 0);
    },
    // Atomically reserve a claim: row lock, cooldown + hold-time + amount check, advance last_claim, log pending payout.
    async reserve(wallet, now, compute) {
      const c = await pool.connect();
      try {
        await c.query("BEGIN");
        await c.query(`INSERT INTO players(wallet,first_seen,last_claim) VALUES($1,$2::bigint,$3::bigint) ON CONFLICT(wallet) DO NOTHING`, [wallet, now, now - 60000]);
        const { rows } = await c.query(`SELECT * FROM players WHERE wallet=$1 FOR UPDATE`, [wallet]);
        const p = rows[0];
        if (now - Number(p.last_claim) < COOLDOWN) { await c.query("ROLLBACK"); return { status: "cooldown", retryInMs: COOLDOWN - (now - Number(p.last_claim)) }; }
        if (now - Number(p.first_seen) < HOLD_MS) { await c.query("ROLLBACK"); return { status: "hold", waitMs: HOLD_MS - (now - Number(p.first_seen)) }; }
        const r = await compute(p);
        if (!(r.paid > 0)) { await c.query("ROLLBACK"); return { status: "none" }; }
        const prev = Number(p.last_claim);
        // Advance last_claim ONLY by the fraction of the pouch actually paid, so a capped claim keeps the remainder.
        const remainMs = r.grossNet > 0 ? Math.round(r.capMs * Math.max(0, 1 - r.paid / r.grossNet)) : 0;
        let newLast = now - remainMs; if (newLast < prev) newLast = prev; if (newLast > now) newLast = now;
        await c.query(`UPDATE players SET last_claim=$2, lifetime_paid=lifetime_paid+$3 WHERE wallet=$1`, [wallet, newLast, r.paid]);
        const ins = await c.query(`INSERT INTO payouts(wallet,amount,status) VALUES($1,$2,'pending') RETURNING id`, [wallet, r.paid]);
        await c.query("COMMIT");
        return { status: "ok", amount: r.paid, payoutId: ins.rows[0].id, prevLastClaim: prev };
      } catch (e) { try { await c.query("ROLLBACK"); } catch {} throw e; }
      finally { c.release(); }
    },
    async confirm(id, sig) { await pool.query(`UPDATE payouts SET status='confirmed', signature=$2 WHERE id=$1`, [id, sig]); },
    async fail(id, wallet, prevLastClaim, amount) {
      await pool.query(`UPDATE payouts SET status='failed' WHERE id=$1`, [id]);
      await pool.query(`UPDATE players SET last_claim=$2, lifetime_paid=GREATEST(0,lifetime_paid-$3) WHERE wallet=$1`, [wallet, prevLastClaim, amount]);
    },
    async count() { return Number((await pool.query(`SELECT COUNT(*) n FROM players`)).rows[0].n); },
    async allChikis(exclude, cap) {
      // bounded scan — only pull enough rows to fill the cap (avoids loading ALL profiles into memory each call)
      const r = await pool.query(`SELECT wallet, profile FROM players WHERE profile IS NOT NULL ORDER BY last_claim DESC LIMIT $1`, [Math.max(20, Math.min(300, (cap||60) * 3))]);
      const out = [];
      for (const row of r.rows) {
        if (row.wallet === exclude) continue;
        const pr = row.profile || {}, handle = pr.handle || null, bal = pr.bal || 0;
        for (const c of (pr.chikis || [])) {
          out.push({ wallet: row.wallet, handle, bal, sp: c.sp | 0, level: c.level | 0, nick: c.nick || null, tasksDone: c.tasksDone | 0, hungry: !!c.hungry, isLegend: !!c.isLegend });
          if (out.length >= cap) return out;
        }
      }
      return out;
    },
    async claimedTotals() {
      // Keepers + active Chikis = CURRENT eligible holders only (a wallet's last-known balance ≥ threshold);
      // legends = all-time hatched. This stops counting wallets that hatched a Chiki once and have since left.
      const r = await pool.query(`SELECT profile, eligible FROM players WHERE profile IS NOT NULL`);
      let chikis = 0, holders = 0, legends = 0;
      for (const row of r.rows) {
        const c = row.profile?.chikis || []; if (!c.length) continue;
        legends += c.filter(x => x.isLegend).length;
        if (row.eligible) { holders++; chikis += c.length; }
      }
      return { chikis, holders, legends };
    },
    // Wallets whose roster contains a Legendary (for Glory gifts).
    async legendHolderWallets() {
      const r = await pool.query(`SELECT wallet FROM players WHERE profile IS NOT NULL AND profile->'chikis' @> '[{"isLegend": true}]'::jsonb`);
      return r.rows.map(x => x.wallet);
    },
  };
}

function memStore() {
  const players = new Map(); const payouts = []; const presenceMap = new Map(); const kv = new Map();
  const get = (w) => players.get(w);
  return {
    kind: "memory",
    async init() {},
    async kvGet(k) { return kv.has(k) ? kv.get(k) : null; },
    async kvSet(k, v) { kv.set(k, v); },
    async touch(wallet, eligible, balance) {
      const now = Date.now();
      const p = get(wallet) || { wallet, first_seen: now, last_claim: now - 60000, lifetime_paid: 0, profile: null };
      p.eligible = eligible; p.balance = balance;
      if (balance < WHALE_MIN) p.whale_since = null; else if (!p.whale_since) p.whale_since = now;
      players.set(wallet, p); return p;
    },
    async getProfile(wallet) { return get(wallet)?.profile || null; },
    async setProfile(wallet, profile) {
      const now = Date.now();
      const p = get(wallet) || { wallet, first_seen: now, last_claim: now - 60000, lifetime_paid: 0 };
      p.profile = profile; players.set(wallet, p);
    },
    async resetProfiles() { let n = 0; for (const p of players.values()) if (p.profile) { p.profile = null; n++; } presenceMap.clear(); return n; },
    async heartbeat(wallet, chikis, roster) { presenceMap.set(wallet, { t: Date.now(), chikis: Math.max(0, chikis | 0), roster: Array.isArray(roster) ? roster.slice(0, 8) : [] }); },
    async presence(windowMs) {
      const cut = Date.now() - windowMs; let a = 0, c = 0;
      for (const v of presenceMap.values()) if (v.t > cut) { a++; c += v.chikis; }
      return { activeUsers: a, chikimons: c };
    },
    async world(windowMs, exclude, cap) {
      const cut = Date.now() - windowMs; const out = [];
      for (const [wallet, v] of presenceMap) {
        if (v.t <= cut || wallet === exclude) continue;
        for (const e of (v.roster || [])) { out.push({ wallet, sp: e.sp | 0, level: e.level | 0 }); if (out.length >= cap) return out; }
      }
      return out;
    },
    async dailyTotal() {
      const cut = Date.now() - 86_400_000;
      return payouts.filter(x => x.status === "confirmed" && x.t > cut).reduce((s, x) => s + x.amount, 0);
    },
    async walletDaily(wallet) {
      const cut = Date.now() - 86_400_000;
      return payouts.filter(x => x.status === "confirmed" && x.wallet === wallet && x.t > cut).reduce((s, x) => s + x.amount, 0);
    },
    async earned(wallet) { return Number(get(wallet)?.lifetime_paid || 0); },   // real SOL actually paid out to this wallet
    async totalPaid() { let s = 0; for (const p of players.values()) s += Number(p.lifetime_paid || 0); return s; },
    async chikisForWallets(wallets) { const set = new Set(wallets || []); let c = 0; for (const [w, p] of players) { if (set.has(w)) { const ch = p.profile?.chikis; if (Array.isArray(ch)) c += ch.length; } } return c; },
    async topEarners(limit) {
      const arr = [];
      for (const [wallet, p] of players) { const e = Number(p.lifetime_paid || 0); if (e > 0) arr.push({ wallet, earnedSol: e, handle: p.profile?.handle || null }); }
      arr.sort((a, b) => b.earnedSol - a.earnedSol);
      return arr.slice(0, limit);
    },
    async reserve(wallet, now, compute) {
      const p = get(wallet) || { wallet, first_seen: now, last_claim: now - 60000, lifetime_paid: 0 };
      players.set(wallet, p);
      if (now - p.last_claim < COOLDOWN) return { status: "cooldown", retryInMs: COOLDOWN - (now - p.last_claim) };
      if (now - p.first_seen < HOLD_MS) return { status: "hold", waitMs: HOLD_MS - (now - p.first_seen) };
      const r = await compute(p);
      if (!(r.paid > 0)) return { status: "none" };
      const prev = p.last_claim;
      // Advance last_claim ONLY by the fraction actually paid — a capped claim keeps the remainder in the pouch.
      const remainMs = r.grossNet > 0 ? Math.round(r.capMs * Math.max(0, 1 - r.paid / r.grossNet)) : 0;
      let newLast = now - remainMs; if (newLast < prev) newLast = prev; if (newLast > now) newLast = now;
      p.last_claim = newLast; p.lifetime_paid += r.paid;
      const id = payouts.push({ id: payouts.length + 1, wallet, amount: r.paid, status: "pending", t: now });
      return { status: "ok", amount: r.paid, payoutId: id, prevLastClaim: prev };
    },
    async confirm(id, sig) { const p = payouts[id - 1]; if (p) { p.status = "confirmed"; p.signature = sig; } },
    async fail(id, wallet, prevLastClaim, amount) {
      const r = payouts[id - 1]; if (r) r.status = "failed";
      const p = get(wallet); if (p) { p.last_claim = prevLastClaim; p.lifetime_paid = Math.max(0, p.lifetime_paid - amount); }
    },
    async count() { return players.size; },
    async allChikis(exclude, cap) {
      const out = [];
      for (const [wallet, p] of players) {
        if (wallet === exclude || !p.profile?.chikis) continue;
        const handle = p.profile.handle || null, bal = p.profile.bal || 0;
        for (const c of p.profile.chikis) {
          out.push({ wallet, handle, bal, sp: c.sp | 0, level: c.level | 0, nick: c.nick || null, tasksDone: c.tasksDone | 0, hungry: !!c.hungry, isLegend: !!c.isLegend });
          if (out.length >= cap) return out;
        }
      }
      return out;
    },
    async claimedTotals() {
      let chikis = 0, holders = 0, legends = 0;
      for (const p of players.values()) {
        const c = p.profile?.chikis || []; if (!c.length) continue;
        legends += c.filter(x => x.isLegend).length;          // all-time legends hatched
        if (p.eligible) { holders++; chikis += c.length; }     // current keepers + their Chikis only
      }
      return { chikis, holders, legends };
    },
    async legendHolderWallets() {
      const out = [];
      for (const [wallet, p] of players) { const c = p.profile?.chikis || []; if (c.some(x => x.isLegend)) out.push(wallet); }
      return out;
    },
  };
}

const store = makeStore();

/* ----------------------------- chat ----------------------------- */
/* wallets allowed to pin/announce: ADMIN_WALLETS list + the team wallet */
const ADMIN_SET = new Set(String(ADMIN_WALLETS || "").split(",").map(s => s.trim()).filter(Boolean));
if (TEAM_WALLET) ADMIN_SET.add(TEAM_WALLET.trim());
const isAdminWallet = (w) => ADMIN_SET.has(w);

/* ----------------------------- Chikoria Cup (live event) ----------------------------- */
const CUP_ELEMS = ["Water", "Fire", "Beast", "Storm", "Light"];
let liveCup = null;                  // in-memory orchestrator (null until an admin creates one)
let cupRound = null;                 // transient: the current round's LIVE PvP matches { battling, matchByWallet, side, matches }
let cupPublic = true;                // true = open to ALL players (launched). Admin can flip to admin-only via /cup/public.
let cupAuto = true;                  // AUTO-RUN: server starts/finalizes each round on its own (no admin clicking). Toggle via /cup/auto.
let cupRoundStartedAt = 0;           // when the current battling round began (for the round time-limit)
let cupAutoNextAt = 0;               // earliest time the auto-runner may act again (inter-round pause)
const CUP_ROUND_MAX_MS = 4 * 60 * 1000;   // a round auto-finalizes after this even if a match is stuck (idle players forfeit far sooner)
const CUP_ROUND_GAP_MS = 7000;            // pause between finalizing a round and starting the next, so results are visible
const cupPrizes = new Map();         // wallet -> owed SOL (DURABLE — these are real funds; persisted to kv)
const cupPayers = new Map();         // wallet -> Glory paid in entry fees (DURABLE log, so we can refund on a reset)
const gloryCredits = new Map();      // wallet -> pending Glory to ADD on the player's next login/refresh.
                                     // Lives OUTSIDE the profile so client saves can't clobber it (Glory is client-authoritative).
let cupTotalAwarded = Number(process.env.CUP_AWARDED_SEED || 8);   // DURABLE cumulative SOL ever rewarded as Cup prizes; seeded with the 2 cups already run (4 SOL each). New cups add to it.
async function saveCupAwarded() { try { await store.kvSet("cup_total_awarded", cupTotalAwarded); } catch (e) {} }
let cupChampion = null;   // {wallet, name, ts} — the REIGNING Chikoria Cup champion (latest only)
async function saveCupChampion() { try { await store.kvSet("cup_champion", cupChampion); } catch (e) {} }
function crownChampion() {   // capture the winner of the just-finished cup as the reigning champion
  try { const c = liveCup && liveCup.state && liveCup.state.champion;
    if (c && isPubkey(c.wallet)) { cupChampion = { wallet: c.wallet, name: (c.snap && c.snap.name) || "Champion", ts: Date.now() }; saveCupChampion(); }
  } catch (e) {}
}

// ===== Meme Dynasty NFT eggs: buy egg -> hatch a RANDOM member (limited editions) -> mint worker turns it into an NFT =====
// Per-character supply = rarity. Fewer editions = rarer. `weight` = pull odds (set to the cap so each
// character depletes proportionally and the scarcer ones are genuinely harder to hatch).
const MEME_CHARS = [
  { key: "pepe",    name: "Pepe",      cap: 25, weight: 25, rarity: "Meme Legendary" },
  { key: "popcat",  name: "Popcat",    cap: 20, weight: 20, rarity: "Meme Legendary" },
  { key: "moodeng", name: "Moo Deng",  cap: 20, weight: 20, rarity: "Meme Legendary" },
  { key: "doge",    name: "Doge",      cap: 15, weight: 15, rarity: "Meme Legendary" },
  { key: "chillguy",name: "Chill Guy", cap: 15, weight: 15, rarity: "Meme Legendary" },
  { key: "alon",    name: "Alon",      cap: 10, weight: 10, rarity: "Founder's Edition" },  // rarest — its own tier
];
const MEME_KEYS = new Set(MEME_CHARS.map(c => c.key));
const MEME_CAP = Number(process.env.MEME_EDITION_CAP || 10);   // fallback cap if a character has none
const capOf = (key) => { const c = MEME_CHARS.find(x => x.key === key); return (c && c.cap) || MEME_CAP; };
const rarityOf = (key) => { const c = MEME_CHARS.find(x => x.key === key); return (c && c.rarity) || "Meme Legendary"; };
const MEME_TOTAL = MEME_CHARS.reduce((s, c) => s + (c.cap || MEME_CAP), 0);   // 105
const MEME_EGG_PRICE = Number(process.env.MEME_EGG_PRICE || 1000000);   // $CHIKI per egg
// 🔒 SALE SWITCH — hard server-side lock. CLOSED by default. Flip MEME_SALE_OPEN=true on Render at your X launch.
// While closed, /meme/hatch is rejected for everyone EXCEPT admin wallets (so you can still dry-run).
const MEME_SALE_OPEN = String(process.env.MEME_SALE_OPEN ?? "false").toLowerCase() === "true";
const MEME_ADMIN_WALLETS = new Set((process.env.MEME_ADMIN_WALLETS || TEAM_WALLET || "").split(",").map(s => s.trim()).filter(Boolean));
// Verify the on-chain $CHIKI payment before minting. ON by default because $CHIKI is a real (mainnet) token —
// without this, anyone could POST /meme/hatch and mint NFTs for free. Set MEME_VERIFY_PAY=false only for local testing.
const MEME_VERIFY_PAY = String(process.env.MEME_VERIFY_PAY ?? "true").toLowerCase() === "true";
// When a Tensor (or Magic Eden) collection URL is configured, real trading happens there — the custom in-game
// escrow ledger (/meme/buy) is disabled so we never settle real-money trades off-chain.
const TENSOR_URL = process.env.TENSOR_URL || "";
const MEME_TRADE_TENSOR = !!TENSOR_URL;
let memeMinted = {};       // char -> editions handed out
let memeHatches = [];       // [{id, wallet, char, name, edition, status, mintAddr, ts}]
let memeUsedSigs = {};      // payment signature -> {wallet, ts}  (replay protection: a paid tx can hatch exactly one egg)
const _memeLastHatch = new Map();
async function saveMeme() { try { await store.kvSet("meme_minted", memeMinted); await store.kvSet("meme_hatches", memeHatches); await store.kvSet("meme_used_sigs", memeUsedSigs); } catch (e) {} }
// Verify a $CHIKI egg payment on-chain: the buyer signed it, it succeeded, they spent >= the price, and the treasury received funds.
async function verifyEggPayment(sig, wallet) {
  if (!MINT) return { ok: false, error: "server has no CHIKI mint configured" };
  if (!sig || typeof sig !== "string" || sig.length < 32) return { ok: false, error: "missing payment signature" };
  let tx;
  try { tx = await conn.getParsedTransaction(sig, { commitment: "confirmed", maxSupportedTransactionVersion: 0 }); }
  catch (e) { return { ok: false, error: "could not fetch payment transaction" }; }
  if (!tx || !tx.meta) return { ok: false, error: "payment not found yet — wait a moment and retry" };
  if (tx.meta.err) return { ok: false, error: "payment transaction failed on-chain" };
  // the buyer's wallet must have signed (so it's their payment, not a replayed third-party tx)
  const keys = (tx.transaction && tx.transaction.message && tx.transaction.message.accountKeys) || [];
  const signed = keys.some(k => k && k.signer && (k.pubkey?.toString?.() || String(k.pubkey)) === wallet);
  if (!signed) return { ok: false, error: "payment was not signed by your wallet" };
  // compare CHIKI token-balance deltas for the buyer (must spend >= price) and the treasury (must receive funds)
  const mintStr = MINT.toString(), treasStr = treasury.publicKey.toString();
  const pre = tx.meta.preTokenBalances || [], post = tx.meta.postTokenBalances || [];
  const bal = (arr, owner) => { const e = arr.find(b => b.mint === mintStr && b.owner === owner); return e ? Number(e.uiTokenAmount.uiAmount || 0) : 0; };
  const spent = bal(pre, wallet) - bal(post, wallet);
  const treasuryGain = bal(post, treasStr) - bal(pre, treasStr);
  if (spent < MEME_EGG_PRICE * 0.999) return { ok: false, error: `payment too small — ${MEME_EGG_PRICE.toLocaleString()} $CHIKI required` };
  if (treasuryGain <= 0) return { ok: false, error: "payment did not reach the treasury" };
  return { ok: true, spent, treasuryGain };
}
// how many eggs are claimed (bought) — incubating(mystery) + pending + minted all hold a slot against the 105 total.
function memeReserved() { return memeHatches.filter(h => h.status === "incubating" || h.status === "pending" || h.status === "minted").length; }
function memeSupply() {
  const chars = {}; let hatched = 0;
  // per-character "minted" = species ROLLED at hatch (determined). Incubating eggs are a mystery and not counted per-character yet.
  for (const c of MEME_CHARS) { const cap = capOf(c.key), m = memeMinted[c.key] || 0; chars[c.key] = { name: c.name, minted: m, cap, left: Math.max(0, cap - m), rarity: c.rarity }; hatched += m; }
  const reserved = memeReserved();
  return { chars, totalLeft: Math.max(0, MEME_TOTAL - reserved), total: MEME_TOTAL, reserved, hatched, cap: MEME_CAP };
}
// MIGRATION: reset any already-bought (incubating) egg back to a MYSTERY so its species is re-rolled at hatch,
// and recompute per-character counts from only the determined (pending/minted) hatches. Idempotent.
async function migrateMemeRandomize() {
  let changed = false;
  for (const h of memeHatches) {
    if (h.status === "incubating" && (h.char || !h.undetermined)) { h.char = null; h.name = "Mystery Meme Egg"; h.edition = null; h.undetermined = true; changed = true; }
  }
  const recomputed = {};
  for (const h of memeHatches) { if ((h.status === "pending" || h.status === "minted") && h.char) recomputed[h.char] = (recomputed[h.char] || 0) + 1; }
  if (JSON.stringify(recomputed) !== JSON.stringify(memeMinted)) { memeMinted = recomputed; changed = true; }
  if (changed) { try { await saveMeme(); } catch (e) {} console.log("meme: randomize migration applied — incubating eggs reset to mystery; per-char counts recomputed"); }
}
// A player may hold only ONE Meme Legendary that isn't up for sale. To get another, list (sell) the current one first.
function memeOwnedActive(wallet) { return memeHatches.filter(h => h.wallet === wallet && !h.listed).length; }
function pickMeme() {
  const avail = MEME_CHARS.filter(c => (memeMinted[c.key] || 0) < capOf(c.key));
  if (!avail.length) return null;
  let tot = avail.reduce((s, c) => s + (c.weight || 1), 0), r = Math.random() * tot;
  for (const c of avail) { r -= (c.weight || 1); if (r <= 0) return c; }
  return avail[avail.length - 1];
}
async function loadCupState() {
  try { const p = await store.kvGet("cup_prizes"); if (p && typeof p === "object") for (const k in p) { const v = Number(p[k]) || 0; if (v > 0) cupPrizes.set(k, v); } } catch (e) {}
  try { const v = await store.kvGet("cup_public"); if (v !== null && v !== undefined) cupPublic = !!v; } catch (e) {}   // honor an explicit admin toggle; otherwise keep the default (public)
  try { const a = await store.kvGet("cup_auto"); if (a !== null && a !== undefined) cupAuto = !!a; } catch (e) {}   // auto-run setting persists across restarts
  try { const py = await store.kvGet("cup_payers"); if (py && typeof py === "object") for (const k in py) cupPayers.set(k, Number(py[k]) || 0); } catch (e) {}
  try { const gc = await store.kvGet("glory_credits"); if (gc && typeof gc === "object") for (const k in gc) { const v = Number(gc[k]) || 0; if (v > 0) gloryCredits.set(k, v); } } catch (e) {}
  try { const ta = await store.kvGet("cup_total_awarded"); if (ta != null) cupTotalAwarded = Number(ta) || 0; } catch (e) {}
  try { const ch = await store.kvGet("cup_champion"); if (ch != null) cupChampion = ch; } catch (e) {}
  try { const mm = await store.kvGet("meme_minted"); if (mm && typeof mm === "object") memeMinted = mm; } catch (e) {}
  try { const mh = await store.kvGet("meme_hatches"); if (Array.isArray(mh)) memeHatches = mh; } catch (e) {}
  try { const us = await store.kvGet("meme_used_sigs"); if (us && typeof us === "object") memeUsedSigs = us; } catch (e) {}
  try { await migrateMemeRandomize(); } catch (e) {}   // reset predetermined eggs → species rolls at hatch
  try { const cs = await store.kvGet("cup_state"); if (cs && cs.status) liveCup = createCup({}, cs); } catch (e) { console.error("cup_state restore failed:", e?.message || e); }   // resume an in-progress bracket after a restart
}
async function saveCupPrizes() { const o = {}; for (const [k, v] of cupPrizes) if (v > 0) o[k] = v; try { await store.kvSet("cup_prizes", o); } catch (e) {} }
async function savePayers() { const o = {}; for (const [k, v] of cupPayers) if (v > 0) o[k] = v; try { await store.kvSet("cup_payers", o); } catch (e) {} }
async function saveGloryCredits() { const o = {}; for (const [k, v] of gloryCredits) if (v > 0) o[k] = v; try { await store.kvSet("glory_credits", o); } catch (e) {} }
// Apply any pending Glory credit to a freshly-loaded profile (called on login/refresh). Persists + clears the credit
// so it survives the client's authoritative profile saves and lands exactly once.
async function applyGloryCredit(wallet, profile) {
  const credit = gloryCredits.get(wallet) || 0;
  if (!(credit > 0) || !profile) return profile;
  profile.glory = (Number(profile.glory) || 0) + credit;
  try { await store.setProfile(wallet, profile); } catch (e) {}
  gloryCredits.delete(wallet); await saveGloryCredits();
  return profile;
}
// Add Glory back to a wallet's stored profile (used to refund cup entry fees on a reset).
async function refundGlory(wallet, amount) {
  if (!isPubkey(wallet) || !(amount > 0)) return false;
  try { const p = await store.getProfile(wallet); if (!p) return false; p.glory = (Number(p.glory) || 0) + amount; await store.setProfile(wallet, p); return true; } catch (e) { return false; }
}
// Persist the LIVE bracket so a restart (deploy / spin-down / crash) resumes instead of losing the cup.
async function persistCup() { try { await store.kvSet("cup_state", liveCup ? liveCup.snapshot() : null); } catch (e) {} }
const cupAdminOk = (req) => {
  const key = req.body?.key || req.query?.key;
  if (process.env.ADMIN_KEY && key === process.env.ADMIN_KEY) return true;
  const w = req.body?.wallet || req.query?.wallet;
  return !!(w && isAdminWallet(w));
};
function cupSnapshot(forWallet) {
  const s = liveCup ? liveCup.state : null;
  const live = !!liveCup && s.status === "live";
  const out = {
    exists: !!liveCup, public: cupPublic, auto: cupAuto,
    status: s ? s.status : "none",
    entryGlory: s ? s.entryGlory : 100, prizePool: s ? s.prizePool : 4.0, cap: s ? s.cap : 10,
    entrants: s ? s.entrants.map(e => ({ name: e.snap.name, player: e.snap.player || null, br: e.snap.br, element: e.snap.element, bot: !!e.bot, ready: !!e.ready })) : [],
    round: live ? liveCup.roundName : null,
    matches: live ? liveCup.currentMatches() : [],
    champion: s && s.champion ? (s.champion.snap.player || s.champion.snap.name) : null,
    results: (s && s.status === "finished") ? liveCup.results() : null,
  };
  // Live PvP matches anyone can spectate this round (profile names + matchId + live status).
  if (cupRound && cupRound.battling && Array.isArray(cupRound.matches)) {
    const entName = w => { const e = s && s.entrants.find(x => x.wallet === w); return e ? (e.snap.player || e.snap.name) : "Player"; };
    const entEl = w => { const e = s && s.entrants.find(x => x.wallet === w); return e ? e.snap.element : "Fire"; };
    out.liveMatches = cupRound.matches.map(mm => { const m = pvpMatches.get(mm.matchId);
      return { matchId: mm.matchId, a: entName(mm.a), b: entName(mm.b), aEl: entEl(mm.a), bEl: entEl(mm.b),
        status: m ? m.status : "active", winner: m && m.status === "finished" ? m.winner : null }; });
  } else out.liveMatches = [];
  if (forWallet) {
    const me = s && s.entrants.find(e => e.wallet === forWallet);
    out.youRegistered = !!me; out.youReady = !!(me && me.ready);
    out.yourPrize = cupPrizes.get(forWallet) || 0;
    out.youPlace = (s && s.place) ? (s.place[forWallet] || null) : null;
    out.isAdmin = isAdminWallet(forWallet);
    if (cupRound && cupRound.battling) {           // a live PvP round is underway — tell the player about their match
      out.roundBattling = true;
      const mid = cupRound.matchByWallet.get(forWallet);
      if (mid) { out.pvpMatchId = mid; out.pvpSide = cupRound.side.get(forWallet); const mm = pvpMatches.get(mid); out.pvpOver = mm ? mm.status === "finished" : false; }
    }
  }
  return out;
}
// Validate + clamp a client-supplied legendary snapshot against the wallet's stored roster (anti-inflation).
async function cupSnapFromBody(wallet, snap) {
  const prof = await store.getProfile(wallet);
  const roster = (prof && Array.isArray(prof.chikis)) ? prof.chikis : [];
  const legends = roster.filter(c => c && c.isLegend);
  if (!legends.length) return { error: "Hatch a Legendary first to enter the Cup." };
  const bestBr = legends.reduce((m, c) => Math.max(m, Number(c.br) || 1), 1);
  const el = CUP_ELEMS.includes(snap?.element) ? snap.element : "Fire";
  let skills = Array.isArray(snap?.arenaSkills) ? snap.arenaSkills.map(n => n | 0).filter(n => n >= 0 && n < 12) : [];
  if (!skills.length) skills = [0, 1, 2];
  const ct = {}; if (snap?.cardTier && typeof snap.cardTier === "object") for (const k in snap.cardTier) { const sl = k | 0; if (sl >= 0 && sl < 12) ct[sl] = Math.max(1, Math.min(5, Number(snap.cardTier[k]) || 1)); }
  const br = Math.max(1, Math.min(MAX_BR, Math.min(Number(snap?.br) || bestBr, bestBr)));   // can't claim a higher BR than your best legendary
  const name = stripTags(snap?.name || (prof?.handle) || wallet.slice(0, 4)).slice(0, 18) || wallet.slice(0, 4);
  const player = stripTags(prof?.handle || "").slice(0, 18) || null;   // the PLAYER's profile name (shown in the Hub, not the Chikimon's name)
  return { snap: { name, player, element: el, br, arenaSkills: skills, cardTier: ct, glory: 0 } };
}

const CHAT_WINDOW = 120000;                   // a wallet shows as "online" for 2 min after its last beat
const onlineUsers = new Map();                // wallet -> { handle, ts }

/* profanity filter — normalize common leetspeak, then mask listed words (server-authoritative) */
const BAD_WORDS = ["fuck","shit","bitch","asshole","bastard","cunt","dick","piss","slut","whore",
  "nigger","nigga","faggot","retard","rape","cock","pussy","motherfucker","wank","twat","prick","jerkoff","cumshot"];
function cleanText(s) {
  s = String(s || "").replace(/[<>]/g, "").replace(/\s+/g, " ").trim().slice(0, 300);   // strip < > so chat/handles can't inject HTML
  const norm = (w) => w.toLowerCase()
    .replace(/[1!|]/g, "i").replace(/3/g, "e").replace(/[4@]/g, "a")
    .replace(/0/g, "o").replace(/[5$]/g, "s").replace(/7/g, "t").replace(/[^a-z]/g, "");
  return s.replace(/[\p{L}\p{N}@$!|*]+/gu, (tok) => {
    const n = norm(tok);
    for (const bad of BAD_WORDS) if (n === bad || (bad.length >= 4 && n.includes(bad))) return "*".repeat(tok.length);
    return tok;
  });
}

function makeChat() {
  if (DATABASE_URL) {
    const pool = new pg.Pool({
      connectionString: DATABASE_URL, max: 3,
      ssl: DATABASE_URL.includes("localhost") ? false : { rejectUnauthorized: false },
    });
    return {
      kind: "postgres",
      async init() {
        await pool.query(`CREATE TABLE IF NOT EXISTS chat(
          id BIGSERIAL PRIMARY KEY, ts BIGINT NOT NULL, wallet TEXT NOT NULL, handle TEXT,
          body TEXT NOT NULL, to_wallet TEXT, pinned BOOLEAN NOT NULL DEFAULT false)`);
        await pool.query(`CREATE INDEX IF NOT EXISTS chat_id_idx ON chat(id)`);
        await pool.query(`ALTER TABLE chat ADD COLUMN IF NOT EXISTS reactions JSONB NOT NULL DEFAULT '{}'::jsonb`);   // {emoji:[wallet,...]}
      },
      async send(m) {
        const r = await pool.query(
          `INSERT INTO chat(ts,wallet,handle,body,to_wallet,pinned) VALUES($1::bigint,$2,$3,$4,$5,$6) RETURNING *`,
          [m.ts, m.wallet, m.handle || null, m.body, m.to || null, !!m.pinned]);
        return r.rows[0];
      },
      async fetch(wallet, since) {
        /* return the NEWEST 200 above `since` (then re-sort ascending) so new messages are never cut off */
        const r = await pool.query(
          `SELECT * FROM chat WHERE id>$1 AND (to_wallet IS NULL OR to_wallet=$2 OR wallet=$2) ORDER BY id DESC LIMIT 200`,
          [since || 0, wallet || ""]);
        const p = await pool.query(`SELECT * FROM chat WHERE pinned=true ORDER BY id DESC LIMIT 1`);
        // reaction counts for recently-reacted messages, so clients refresh them without re-fetching whole messages
        const rr = await pool.query(`SELECT id, reactions FROM chat WHERE reactions <> '{}'::jsonb ORDER BY id DESC LIMIT 150`);
        const recentReactions = {}; for (const row of rr.rows) recentReactions[row.id] = row.reactions;
        return { messages: r.rows.reverse(), pinned: p.rows[0] || null, recentReactions };
      },
      async pin(id, on) {
        if (on) await pool.query(`UPDATE chat SET pinned=false WHERE pinned=true`);
        await pool.query(`UPDATE chat SET pinned=$2 WHERE id=$1`, [id, !!on]);
      },
      async react(id, emoji, wallet) {
        const r = await pool.query(`SELECT reactions FROM chat WHERE id=$1`, [id]);
        if (!r.rows[0]) return null;
        const rx = r.rows[0].reactions || {};
        const set = new Set(rx[emoji] || []);
        if (set.has(wallet)) set.delete(wallet); else set.add(wallet);   // toggle
        if (set.size) rx[emoji] = [...set]; else delete rx[emoji];
        await pool.query(`UPDATE chat SET reactions=$2::jsonb WHERE id=$1`, [id, JSON.stringify(rx)]);
        return rx;
      },
    };
  }
  const msgs = []; let seq = 1;
  return {
    kind: "memory",
    async init() {},
    async send(m) {
      const row = { id: seq++, ts: m.ts, wallet: m.wallet, handle: m.handle || null, body: m.body, to_wallet: m.to || null, pinned: !!m.pinned, reactions: {} };
      msgs.push(row); if (msgs.length > 500) msgs.shift(); return row;
    },
    async fetch(wallet, since) {
      const messages = msgs.filter(x => x.id > (since || 0) && (!x.to_wallet || x.to_wallet === wallet || x.wallet === wallet)).slice(-200);
      const pinned = [...msgs].reverse().find(x => x.pinned) || null;
      const recentReactions = {}; for (const x of msgs) if (x.reactions && Object.keys(x.reactions).length) recentReactions[x.id] = x.reactions;
      return { messages, pinned, recentReactions };
    },
    async pin(id, on) { if (on) msgs.forEach(x => x.pinned = false); const m = msgs.find(x => x.id === id); if (m) m.pinned = !!on; },
    async react(id, emoji, wallet) {
      const m = msgs.find(x => x.id === id); if (!m) return null;
      const rx = m.reactions || (m.reactions = {});
      const set = new Set(rx[emoji] || []);
      if (set.has(wallet)) set.delete(wallet); else set.add(wallet);
      if (set.size) rx[emoji] = [...set]; else delete rx[emoji];
      return rx;
    },
  };
}
const chat = makeChat();

/* ----------------------------- live stats / leaderboard / feed ----------------------------- */
const SUPPLY_TOTAL = 1_000_000_000;     // pump.fun mints exactly 1B; supply only drops via burns
const feedEvents = []; let _feedSeq = 1;
function pushFeed(type, data) {
  feedEvents.push({ id: _feedSeq++, ts: Date.now(), type, ...data });
  if (feedEvents.length > 80) feedEvents.shift();
}
// On-chain $CHIKI holders via Helius DAS (getTokenAccounts). Also computes KEEPERS = owners whose TOTAL balance ≥ MIN.
// Heavy call → cached 30 min. Accurate ground truth (vs the stale eligible-flag profile scan).
let _holdersCache = { t: 0, n: 0, keepers: 0, keeperSet: new Set() };
async function chikiHolderCount() {
  if (!MINT) return _holdersCache;
  if (_holdersCache.n && Date.now() - _holdersCache.t < 30 * 60 * 1000) return _holdersCache;
  try {
    let dec = 6; try { dec = await chikiDecimals(); } catch (e) {}
    const threshold = BigInt(Math.round(MIN)) * (10n ** BigInt(dec));   // raw token units for the MIN_HOLD threshold
    const owners = new Set(), bal = new Map(); let cursor, pages = 0;
    while (pages < 25) {
      const params = { mint: MINT, limit: 1000, options: { showZeroBalance: false } };
      if (cursor) params.cursor = cursor;
      const r = await fetch(RPC_URL, { method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: "holders", method: "getTokenAccounts", params }) });
      const j = await r.json();
      const accs = (j && j.result && j.result.token_accounts) || [];
      for (const a of accs) { if (!a.owner) continue; owners.add(a.owner);
        let amt = 0n; try { amt = BigInt(a.amount || 0); } catch (e) {}
        bal.set(a.owner, (bal.get(a.owner) || 0n) + amt); }                // sum across a holder's multiple token accounts
      cursor = j && j.result && j.result.cursor; pages++;
      if (!cursor || accs.length === 0) break;
    }
    if (owners.size) {
      const keeperSet = new Set(); for (const [o, amt] of bal) if (amt >= threshold) keeperSet.add(o);
      _holdersCache = { t: Date.now(), n: owners.size, keepers: keeperSet.size, keeperSet };
    }
    return _holdersCache;
  } catch (e) { return _holdersCache; }
}
let _statsCache = { t: 0, data: null };
async function getStats() {
  if (_statsCache.data && Date.now() - _statsCache.t < 15000) return _statsCache.data;
  const out = { network: NETWORK, minHold: MIN, whaleMin: WHALE_MIN, poolReserveSol: RESERVE };
  try { out.poolSol = await poolSol(); } catch (e) {}
  try { out.players = await store.count(); } catch (e) {}
  try { out.dailyPaidSol = await store.dailyTotal(); } catch (e) {}
  try { out.totalPaidSol = await store.totalPaid(); } catch (e) {}   // ALL-TIME SOL paid to keepers
  try { const p = await store.presence(PRESENCE_WINDOW); out.activeUsers = p.activeUsers; out.chikimons = p.chikimons; } catch (e) {}
  if (MINT) { try { const s = await conn.getTokenSupply(MINT); out.supply = s.value.uiAmount; out.burned = Math.max(0, SUPPLY_TOTAL - (s.value.uiAmount || 0)); } catch (e) {} }
  out.chikiHolders = _holdersCache.n || 0; chikiHolderCount().catch(()=>{});   // non-blocking: serve cached, refresh in background
  if (TEAM_WALLET) {
    try { out.teamSol = (await conn.getBalance(new PublicKey(TEAM_WALLET))) / LAMPORTS_PER_SOL; } catch (e) {}
    try { out.teamChiki = await chikiBalance(TEAM_WALLET); } catch (e) {}
  }
  try { const t = await store.claimedTotals(); out.legendsHatched = t.legends; } catch (e) {}   // legends = all-time hatched
  // KEEPERS + ACTIVE CHIKIS — accurate, from the on-chain ≥MIN holder set (not the stale eligible flag)
  out.holders = _holdersCache.keepers || 0;
  try { out.claimedChikis = await store.chikisForWallets([...(_holdersCache.keeperSet || [])]); } catch (e) { out.claimedChikis = 0; }
  // Chikoria Cup rewards
  out.cupPrizePool = liveCup ? liveCup.state.prizePool : 4;          // SOL on the line per cup
  out.cupChampionSol = 1;                                            // champion's share
  let cupOwed = 0; for (const v of cupPrizes.values()) cupOwed += v; // prizes credited but not yet claimed
  out.cupOwedSol = +cupOwed.toFixed(4);
  out.cupAwardedSol = +Number(cupTotalAwarded || 0).toFixed(4);       // ALL-TIME SOL rewarded in the Chikoria Cup
  out.cupChampion = cupChampion;                                     // {wallet, name, ts} reigning champion (or null)
  _statsCache = { t: Date.now(), data: out };
  return out;
}
let _lbCache = { t: 0, data: null };
async function getLeaderboard() {
  if (_lbCache.data && Date.now() - _lbCache.t < 180000) return _lbCache.data;
  const holders = [];
  if (MINT) {
    try {
      const largest = await conn.getTokenLargestAccounts(MINT);
      const accs = (largest.value || []).slice(0, 20);
      const infos = await Promise.all(accs.map(a => conn.getParsedAccountInfo(a.address).catch(() => null)));
      for (let i = 0; i < accs.length; i++) {
        const owner = infos[i]?.value?.data?.parsed?.info?.owner;
        const bal = accs[i].uiAmount || 0;
        if (!owner || bal < MIN) continue;
        holders.push({ owner, balance: bal, whale: bal >= WHALE_MIN });
      }
    } catch (e) {}
  }
  let earners = [];
  try { earners = await store.topEarners(15); } catch (e) {}
  const data = { holders: holders.slice(0, 15), earners, updatedAt: Date.now() };
  _lbCache = { t: Date.now(), data };
  return data;
}

/* ----------------------------- API ----------------------------- */
process.on("unhandledRejection", (e) => console.error("unhandledRejection:", e?.message || e));

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", async (_q, res) => res.json({
  ok: true, network: NETWORK, store: store.kind, verifyHolders: verifyOn,
  treasury: treasury.publicKey.toBase58(), team: TEAM_WALLET || null,
  mint: CHIKI_MINT || null, minHold: MIN, minHoldMinutes: Number(MIN_HOLD_MINUTES),
  dailyCap: DAILY_FRAC >= 1 ? "none" : Math.round(DAILY_FRAC * 100) + "% pool/day", perWalletDailySol: WALLET_DAILY, poolReserveSol: RESERVE,
  maxClaimSol: CAP, earnModel: "rarity-weighted-tasks", earnMult: MULT, taskSeconds: TASK_SEC, accrualCapMin: ACCRUAL_CAP,
  whaleMin: WHALE_MIN, whaleHoldHours: Number(WHALE_HOLD_HOURS),
}));

app.get("/pool", async (_q, res) => {
  try { res.json({ poolSol: await poolSol(), players: await store.count(), dailyPaid: await store.dailyTotal() }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

app.post("/verify", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try {
    let balance = 0, eligible = true;
    if (verifyOn) { balance = await chikiBalance(wallet); eligible = balance >= MIN; }
    const p = await store.touch(wallet, eligible, balance);
    const chikis = eligible ? (chikiCount(balance, p.whale_since) || 1) : 0;
    const whalePending = eligible && balance >= WHALE_MIN && chikis < 2;
    const whaleReadyInMs = whalePending && p.whale_since ? Math.max(0, WHALE_HOLD_MS - (Date.now() - Number(p.whale_since))) : 0;
    const profile = await applyGloryCredit(wallet, p.profile || null);   // deliver any pending Glory gift on this login (clobber-proof)
    res.json({ wallet, eligible, balance, chikis, whalePending, whaleReadyInMs, minHold: MIN, verified: verifyOn, firstSeen: Number(p.first_seen), profile: profile || null });
  } catch (e) { res.status(500).json({ error: "verify failed: " + String(e.message || e) }); }
});

// Save / load a wallet's game profile (chikis + progress) so it follows the wallet across devices.
app.post("/profile", async (req, res) => {
  const wallet = req.body?.wallet, profile = req.body?.profile;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!profile || typeof profile !== "object") return res.status(400).json({ error: "'profile' object required" });
  if (JSON.stringify(profile).length > 8000) return res.status(413).json({ error: "profile too large" });
  const now = Date.now();
  if (now - (_lastSave.get(wallet) || 0) < 600) return res.json({ ok: true, throttled: true });   // ignore rapid-fire writes (anti-spam)
  _lastSave.set(wallet, now);
  try {
    const prev = await store.getProfile(wallet);
    // admins are trusted (creator testing); everyone else is clamped to legal values
    const safe = isAdminWallet(wallet) ? profile : sanitizeProfile(prev, profile);
    safe._serverSavedAt = now;   // authoritative "last seen" for offline progression
    await store.setProfile(wallet, safe);
    res.json({ ok: true, serverSavedAt: safe._serverSavedAt });
  } catch (e) { res.status(500).json({ error: "save failed: " + String(e.message || e) }); }
});

app.get("/profile", async (req, res) => {
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try { res.json({ wallet, profile: await store.getProfile(wallet) }); }
  catch (e) { res.status(500).json({ error: "load failed: " + String(e.message || e) }); }
});

// ADMIN: grant a wallet a normal Chiki (e.g., a whale's owed 2nd earner). Protected by ADMIN_KEY.
// GET /admin/grant-chiki?key=SECRET&wallet=PUBKEY[&sp=0-9][&nick=Name]
app.get("/admin/grant-chiki", async (req, res) => {
  const KEY = process.env.ADMIN_KEY || "";
  if (!KEY || req.query?.key !== KEY) return res.status(403).json({ error: "forbidden" });
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try {
    const profile = (await store.getProfile(wallet)) || null;
    if (!profile || !Array.isArray(profile.chikis)) return res.status(404).json({ error: "no profile for that wallet (they must have played at least once)" });
    const normals = profile.chikis.filter(c => !c.isLegend).length;
    if (normals >= 2) return res.json({ ok: false, reason: "already has 2 normal Chikis", chikis: profile.chikis.length });
    // normal species indices 0..9 (10..14 are Legendaries); pick one not already owned if possible
    const owned = new Set(profile.chikis.map(c => c.sp | 0));
    let sp = Number.isInteger(+req.query?.sp) ? Math.max(0, Math.min(9, +req.query.sp)) : -1;
    if (sp < 0) { for (let i = 0; i < 10; i++) if (!owned.has(i)) { sp = i; break; } if (sp < 0) sp = Math.floor(Math.random() * 10); }
    const nick = (req.query?.nick ? String(req.query.nick).slice(0, 16) : null);
    profile.chikis.push({ br: 1, sp, xp: 0, food: 1800, nick, level: 1, hungry: false, tending: false, battleXp: 0, cardTier: null, isLegend: false, skillPts: 0, tasksDone: 0, arenaSkills: null, sleepCycles: 0 });
    profile._serverSavedAt = Date.now();
    await store.setProfile(wallet, profile);
    res.json({ ok: true, wallet, granted: { sp, nick }, totalChikis: profile.chikis.length });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// ADMIN RECOVERY: rebuild a wallet's roster for a user whose Chikis were lost to the old overwrite bug.
// GET /admin/restore-chikis?key=SECRET&wallet=PUBKEY&roster=sp:level[:L][:Nick],sp:level,...
//   sp = species index (0-9 normal, 10-14 legendary), add ":L" to mark a legendary, optional ":Nick" name.
//   The restored Chikis are MERGED with whatever the wallet currently has (never reduces the roster).
app.get("/admin/restore-chikis", async (req, res) => {
  const KEY = process.env.ADMIN_KEY || "";
  if (!KEY || req.query?.key !== KEY) return res.status(403).json({ error: "forbidden" });
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  const spec = String(req.query?.roster || "").trim();
  if (!spec) return res.status(400).json({ error: "roster required, e.g. roster=0:12:Spike,10:8:L:Genbu" });
  const replace = (req.query?.set === "1" || req.query?.set === "true");   // set=1 → replace the whole roster with exactly this spec
  try {
    const profile = (await store.getProfile(wallet)) || {};
    if (replace || !Array.isArray(profile.chikis)) profile.chikis = [];
    const have = new Set(profile.chikis.map(c => c.sp | 0));
    let nN = profile.chikis.filter(c => !c.isLegend).length, nL = profile.chikis.filter(c => c.isLegend).length;
    const added = [];
    for (const part of spec.split(",")) {
      const f = part.split(":").map(s => s.trim());
      const sp = clampNum(f[0], 0, 14, -1); if (sp < 0) continue;
      if (have.has(sp)) continue;                                   // don't duplicate a species they already have
      const isLegend = f.includes("L") || f.includes("l") || sp >= 10;
      if (isLegend) { if (nL >= 1) continue; nL++; } else { if (nN >= 2) continue; nN++; }   // enforce hatch caps
      const lv = clampNum(f[1], 1, MAX_LEVEL, 1);
      const nick = f.find((x, i) => i >= 2 && x && x !== "L" && x !== "l") || null;
      profile.chikis.push({ sp, level: lv, isLegend, hungry: false, tending: false,
        nick: nick ? stripTags(nick).slice(0, 16) : null, xp: 0, food: foodMaxSec(lv),
        stamina: isLegend ? legStamMax(lv) : maxStamOf(lv), tasksDone: 0, sleepCycles: 0,
        renames: 0, br: 1, battleXp: 0, skillPts: 0, arenaSkills: null, cardTier: null,
        arenaStam: isLegend ? legStamMax(lv) : null, arenaSleepUntil: 0 });
      have.add(sp); added.push({ sp, level: lv, isLegend, nick });
    }
    profile._serverSavedAt = Date.now();
    await store.setProfile(wallet, profile);
    res.json({ ok: true, wallet, replace, added, totalChikis: profile.chikis.length });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Real SOL paid out to a wallet (authentic "earned" figure for the profile).
app.get("/earned", async (req, res) => {
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try { res.json({ wallet, lifetimePaid: await store.earned(wallet) }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Chiki Pouch: SOL accrued and waiting to be claimed (read-only estimate, no payout).
app.get("/claimable", async (req, res) => {
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try {
    let bal = 0; try { bal = await chikiBalance(wallet); } catch (e) {}
    const p = await store.touch(wallet, bal >= MIN, bal);
    const eligible = !verifyOn || bal >= MIN;
    const chikis = eligible ? (chikiCount(bal, p.whale_since) || 1) : 0;   // below the hold threshold ⇒ no accrual (matches /claim)
    const lastClaim = Number(p.last_claim);
    let poolBal = 0; try { poolBal = await poolSol(); } catch (e) {}
    const pf = poolFactor(poolBal);   // pool-scaling multiplier (≥1) — bigger payouts as the treasury fills
    // Activity gating DISABLED: it was client-reported and lossy (reset the pouch to 0 on every page load).
    // Earnings are time-based again (stable). A proper server-authoritative activity model can re-enable this later.
    const minutes = Math.min((Date.now() - lastClaim) / 60000, ACCRUAL_CAP);
    const gross = Math.max(0, seededEarn(wallet, lastClaim, chikis, minutes) * pf);
    const accrued = Math.floor(gross * (1 - CLAIM_TAX) * 1e6) / 1e6;   /* net after the SOL claim tax (tax stays in treasury) */
    const cupPrize = Math.floor((cupPrizes.get(wallet) || 0) * 1e6) / 1e6;   /* won Cup SOL waiting in the pouch (no tax) */
    const claimable = Math.floor((accrued + cupPrize) * 1e6) / 1e6;
    /* seed params let the client mirror the EXACT same rarity sequence it will be paid for */
    res.json({ wallet, claimableSol: claimable, accruedSol: accrued, cupPrizeSol: cupPrize, claimGrossSol: Math.floor(gross*1e6)/1e6, claimTaxPct: Math.round(CLAIM_TAX*100), lifetimePaid: await store.earned(wallet),
      eligible, minHold: MIN, balance: bal, lastClaim, chikis, taskSec: TASK_SEC, mult: MULT, accrualCap: ACCRUAL_CAP, raritySol: RARITY_SOL, poolFactor: pf, activeMin: minutes, poolSol: Math.floor(poolBal*1e6)/1e6, poolRef: POOL_REF });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Live activity: heartbeat in, get back current active users + roaming chikis.
const PRESENCE_WINDOW = 120000;   // a wallet counts as "online" for 2 min after its last beat
app.post("/presence", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try {
    await store.heartbeat(wallet, Number(req.body?.chikis) || 1, req.body?.roster);
    onlineUsers.set(wallet, { handle: cleanText(req.body?.handle || "").slice(0, 24) || null, ts: Date.now() });
    res.json(await store.presence(PRESENCE_WINDOW));
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
app.get("/presence", async (_q, res) => {
  try { res.json(await store.presence(PRESENCE_WINDOW)); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
// Roster of other online players' chikis, so each client can render a live, shared world.
app.get("/world", async (req, res) => {
  try { res.json({ chikis: await store.world(PRESENCE_WINDOW, req.query?.exclude || "", Math.min(60, Number(req.query?.cap) || 40)) }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// One-time admin reset: wipe all saved game profiles (test data). Guarded by ADMIN_KEY.
app.get("/admin/reset", async (req, res) => {
  const k = req.query?.key;
  // ONLY the secret ADMIN_KEY can wipe profiles (the old hardcoded "chikiwipe" backdoor is removed).
  if (!ADMIN_KEY || k !== ADMIN_KEY) return res.status(403).json({ error: "forbidden" });
  try { const n = await store.resetProfiles(); res.json({ ok: true, profilesCleared: n }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// GET /admin/grant-glory-legends?key=SECRET[&amount=100] — gift Glory to EVERY wallet that owns a Legendary.
// Credits a pending-ledger (not the live profile) so it survives the client's authoritative saves;
// each player receives it on their next login/refresh.
app.get("/admin/grant-glory-legends", async (req, res) => {
  if (!ADMIN_KEY || req.query?.key !== ADMIN_KEY) return res.status(403).json({ error: "forbidden" });
  const amount = Math.max(1, Number(req.query?.amount) || 100);
  try {
    const wallets = await store.legendHolderWallets();
    for (const w of wallets) gloryCredits.set(w, (gloryCredits.get(w) || 0) + amount);
    await saveGloryCredits();
    res.json({ ok: true, grantedEach: amount, legendaryHolders: wallets.length, applied: "on each player's next login/refresh" });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

/* ----------------------------- chat API ----------------------------- */
// Send a message (global, or a DM if `to` is set). Profanity is masked server-side.
app.post("/chat/send", async (req, res) => {
  const { wallet, handle, text, to } = req.body || {};
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  // VERIFICATION REQUIRED: every chatter must prove they own this wallet with a signature (anti-impersonation)
  if (!verifyWalletSig(wallet, req.body?.authMsg, req.body?.authSig)) return res.status(401).json({ error: "wallet verification required — approve the one-time sign-in to prove you own this wallet" });
  if (Date.now() - (_lastChat.get(wallet) || 0) < 800) return res.status(429).json({ error: "slow down — you're sending messages too fast" });
  _lastChat.set(wallet, Date.now());
  /* holder verification: when on-chain checks are enabled, chatters must hold the minimum $CHIKI */
  if (verifyOn) { try { if ((await chikiBalance(wallet)) < MIN) return res.status(403).json({ error: `hold ${MIN.toLocaleString()} $CHIKI to chat` }); } catch (e) {} }
  const body = cleanText(text);
  if (!body.trim()) return res.status(400).json({ error: "empty message" });
  if (to && !isPubkey(to)) return res.status(400).json({ error: "bad recipient" });
  let pinned = false;
  if (req.body?.pin) {
    if (!(isAdminWallet(wallet) || (ADMIN_KEY && req.body?.key === ADMIN_KEY))) return res.status(403).json({ error: "not allowed to pin" });
    pinned = true;
  }
  try {
    const row = await chat.send({ ts: Date.now(), wallet, handle: cleanText(handle || "").slice(0, 24), body, to, pinned });
    if (pinned) await chat.pin(row.id, true);
    onlineUsers.set(wallet, { handle: cleanText(handle || "").slice(0, 24) || null, ts: Date.now() });
    res.json({ ok: true, message: row });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
// React to a message (toggle one of the allowed emojis). Signed like chat send (anti-impersonation).
const REACT_EMOJIS = ["👍", "❤️", "😂", "🔥", "🎉", "😮"];
app.post("/chat/react", async (req, res) => {
  const { wallet, id, emoji } = req.body || {};
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!verifyWalletSig(wallet, req.body?.authMsg, req.body?.authSig)) return res.status(401).json({ error: "wallet verification required" });
  if (!REACT_EMOJIS.includes(emoji)) return res.status(400).json({ error: "unsupported emoji" });
  const mid = Number(id); if (!(mid > 0)) return res.status(400).json({ error: "bad message id" });
  try { const rx = await chat.react(mid, emoji, wallet); if (rx == null) return res.status(404).json({ error: "message not found" }); res.json({ ok: true, id: mid, reactions: rx }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
// Poll for new messages (global + this wallet's DMs) and the current pinned message.
app.get("/chat", async (req, res) => {
  try { res.json(await chat.fetch(req.query?.wallet || "", Number(req.query?.since) || 0)); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
// Pin / unpin a message (admins only).
app.post("/chat/pin", async (req, res) => {
  const { wallet, id, pin, key } = req.body || {};
  const keyOk = ADMIN_KEY && key === ADMIN_KEY;
  if (!keyOk && !verifyWalletSig(wallet, req.body?.authMsg, req.body?.authSig)) return res.status(401).json({ error: "wallet signature required" });
  if (!(keyOk || isAdminWallet(wallet))) return res.status(403).json({ error: "not allowed" });
  try { await chat.pin(Number(id), pin !== false); res.json({ ok: true }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
// Who's online right now (with handles), for the chat user list + DM picker.
app.get("/chat/online", async (_q, res) => {
  const cut = Date.now() - CHAT_WINDOW; const users = [];
  for (const [wallet, v] of onlineUsers) if (v.ts > cut)
    users.push({ wallet, handle: v.handle, short: wallet.slice(0, 4) + "…" + wallet.slice(-4), admin: isAdminWallet(wallet) });
  res.json({ users, count: users.length });
});

/* ----------------------------- real stats / leaderboard / feed API ----------------------------- */
app.get("/stats", async (_q, res) => {
  try { res.json(await getStats()); } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
app.get("/leaderboard", async (_q, res) => {
  try { res.json(await getLeaderboard()); } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});
app.get("/feed", async (req, res) => {
  const since = Number(req.query?.since) || 0;
  res.json({ events: feedEvents.filter(e => e.id > since) });
});
// Every Chiki ever claimed (all saved profiles, online or not) — so the world reflects real ownership.
app.get("/allchikis", async (req, res) => {
  // Degrade gracefully: the shared world is cosmetic — never 500 the client over it.
  try { res.json({ chikis: await store.allChikis(req.query?.exclude || "", Math.min(160, Number(req.query?.cap) || 120)) }); }
  catch (e) { console.error("allchikis error:", e.message||e); res.json({ chikis: [] }); }
});

app.post("/claim", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });

  let bal = 0;
  try { bal = await chikiBalance(wallet); } catch (e) {}
  const belowMin = verifyOn && bal < MIN;
  const prizeOwed = cupPrizes.get(wallet) || 0;
  // Below the threshold you can't accrue — but a Cup prize you've already WON is still yours to claim.
  if (belowMin && !(prizeOwed > 0)) return res.status(403).json({ error: `below ${MIN.toLocaleString()} $CHIKI threshold`, balance: bal });
  const pRow = await store.touch(wallet, bal >= MIN, bal);
  const chikis = belowMin ? 0 : (chikiCount(bal, pRow.whale_since) || 1);   // 2nd Chiki only after the whale hold time; 0 below threshold (prize-only claim)
  let pool, daily, walletPaid;
  try { pool = await poolSol(); daily = await store.dailyTotal(); walletPaid = await store.walletDaily(wallet); }
  catch (e) { return res.status(500).json({ error: "rpc/db error: " + String(e.message || e) }); }
  if (pool <= RESERVE) return res.status(503).json({ error: "reward pool is low — payouts paused, please try again later", poolSol: pool });
  // DAILY CAP (enforced): total daily payouts are bounded to a FRACTION of the live pool, and each wallet to PER_WALLET_DAILY_SOL.
  // Cup prizes are exempt — a winner can always collect their prize even if the day's accrual caps are hit.
  const dailyCapNow = DAILY_FRAC * pool;
  if (DAILY_FRAC < 1 && daily >= dailyCapNow && !(prizeOwed > 0)) return res.status(429).json({ error: "today's reward pool cap is reached — resets over the next 24h", dailyCapSol: +dailyCapNow.toFixed(4) });
  if (WALLET_DAILY > 0 && walletPaid >= WALLET_DAILY && !(prizeOwed > 0)) return res.status(429).json({ error: `your daily claim limit (${WALLET_DAILY} ◎) is reached — come back tomorrow`, perWalletDailySol: WALLET_DAILY });

  // Activity gating DISABLED (was client-reported + lossy). Time-based earning, stable.
  const now = Date.now();
  const compute = (p) => {
    const capMs = Math.min(now - Number(p.last_claim), ACCRUAL_CAP * 60_000);   // effective earning window (bounded by the accrual cap)
    const earnMin = capMs / 60_000;
    const grossNet = seededEarn(wallet, Number(p.last_claim), chikis, earnMin) * poolFactor(pool) * (1 - CLAIM_TAX);   /* full claimable, net of tax, BEFORE caps */
    let amt = Math.min(grossNet, (CAP > 0 ? CAP : Infinity),
      (DAILY_FRAC < 1 ? Math.max(0, dailyCapNow - daily) : Infinity),             // daily pool cap (Infinity = no cap)
      (WALLET_DAILY > 0 ? Math.max(0, WALLET_DAILY - walletPaid) : Infinity),     // remaining room under this wallet's daily cap
      Math.max(0, pool - RESERVE));
    const paid = Math.floor(amt * 1e6) / 1e6;
    // Return the gross + window so reserve() can advance last_claim ONLY by the fraction actually paid —
    // a capped claim must NOT forfeit the un-paid remainder (it stays in the pouch).
    return { paid, grossNet, capMs };
  };

  let r;
  try { r = await store.reserve(wallet, now, compute); }
  catch (e) { return res.status(500).json({ error: "reserve failed: " + String(e.message || e) }); }
  if (r.status === "cooldown") return res.status(429).json({ error: "cooldown", retryInMs: r.retryInMs });
  if (r.status === "hold") return res.status(403).json({ error: "wallet too new — min hold time not met", waitMs: r.waitMs });
  // r.status is now "ok" (accrued SOL to pay) or "none" (no accrual). A Cup prize can be paid in either case.
  const base = r.status === "ok" ? r.amount : 0;
  const prizePay = Math.floor(Math.min(prizeOwed, Math.max(0, pool - RESERVE - base)) * 1e6) / 1e6;   // prize comes from the same treasury; never breach the reserve floor
  const total = Math.floor((base + prizePay) * 1e6) / 1e6;
  if (!(total > 0)) return res.status(409).json({ error: "nothing to claim yet (or pool/cap empty)", poolSol: pool });

  try {
    const tx = new Transaction().add(SystemProgram.transfer({
      fromPubkey: treasury.publicKey, toPubkey: new PublicKey(wallet),
      lamports: Math.floor(total * LAMPORTS_PER_SOL),
    }));
    const sig = await conn.sendTransaction(tx, [treasury]);
    await conn.confirmTransaction(sig, "confirmed");
    if (r.status === "ok") await store.confirm(r.payoutId, sig);
    if (prizePay > 0) { const left = Math.floor(((cupPrizes.get(wallet) || 0) - prizePay) * 1e6) / 1e6; if (left > 0) cupPrizes.set(wallet, left); else cupPrizes.delete(wallet); await saveCupPrizes(); }
    pushFeed("claim", { wallet, short: wallet.slice(0, 4) + "…" + wallet.slice(-4), amountSol: total, signature: sig });
    res.json({ ok: true, wallet, amountSol: total, accruedSol: base, cupPrizeSol: prizePay, signature: sig,
      explorer: `https://explorer.solana.com/tx/${sig}?cluster=${NETWORK}` });
  } catch (e) {
    if (r.status === "ok") await store.fail(r.payoutId, wallet, r.prevLastClaim, r.amount); // refund cooldown so a failed payout isn't lost; prize stays owed
    res.status(500).json({ error: "payout failed: " + String(e.message || e) });
  }
});

/* ----------------------------- Chikoria Cup endpoints ----------------------------- */
// Public: current cup state (pass ?wallet= for your own registration/prize info)
app.get("/cup/status", async (req, res) => {
  try { res.json(cupSnapshot(req.query?.wallet && isPubkey(req.query.wallet) ? req.query.wallet : null)); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Player: enter the cup — deducts the Glory entry fee from the stored profile, seats a clamped snapshot.
app.post("/cup/register", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!liveCup || liveCup.state.status !== "registration") return res.status(409).json({ error: "registration is not open" });
  if (!cupPublic && !isAdminWallet(wallet)) return res.status(403).json({ error: "the Cup isn't open to the public yet" });
  if (liveCup.state.entrants.find(e => e.wallet === wallet)) return res.status(409).json({ error: "already registered" });
  if (liveCup.state.entrants.length >= liveCup.state.cap) return res.status(409).json({ error: "the Cup is full" });
  try {
    const prof = await store.getProfile(wallet);
    if (!prof) return res.status(403).json({ error: "play first — no saved profile found" });
    const fee = liveCup.state.entryGlory;
    const glory = Number(prof.glory) || 0;
    if (glory < fee) return res.status(402).json({ error: `need ${fee} ✨ Glory to enter (you have ${Math.floor(glory)})`, glory });
    const built = await cupSnapFromBody(wallet, req.body?.snap || {});
    if (built.error) return res.status(403).json({ error: built.error });
    if (fee > 0) {
      prof.glory = glory - fee; await store.setProfile(wallet, prof);
      cupPayers.set(wallet, (cupPayers.get(wallet) || 0) + fee); await savePayers();   // remember how much they paid, so a reset can refund it
    }
    liveCup.register(wallet, built.snap);
    await persistCup();
    res.json({ ok: true, gloryLeft: prof.glory, ...cupSnapshot(wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Player: lock in (ready up) for the current round.
app.post("/cup/ready", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!liveCup || liveCup.state.status !== "live") return res.status(409).json({ error: "no live round" });
  try { const ok = liveCup.ready(wallet); if (!ok) return res.status(404).json({ error: "you're not in this cup" }); await persistCup(); res.json({ ok: true, ...cupSnapshot(wallet) }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: create a fresh cup (registration opens immediately).
app.post("/cup/create", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  try {
    const entryGlory = req.body?.entryGlory != null ? Math.max(0, Number(req.body.entryGlory) || 0) : 100;   // 100 ✨ Glory entry by default
    const prizePool = Math.max(0, Number(req.body?.prizePool) || 4.0);
    const cap = [8, 10, 16].includes(Number(req.body?.cap)) ? Number(req.body.cap) : 10;
    // REFUND THE PREVIOUS LOBBY: anyone seated in the cup being replaced gets their entry Glory back,
    // so players who paid are never burned by a reset.
    let refunded = 0, refundEach = (liveCup && Array.isArray(liveCup.state.entrants)) ? (Number(liveCup.state.entryGlory) || 0) : 0;
    if (refundEach > 0) {
      for (const e of liveCup.state.entrants) {
        if (!e || e.bot || !isPubkey(e.wallet)) continue;
        if (await refundGlory(e.wallet, refundEach)) { refunded++; cupPayers.delete(e.wallet); }   // refunded → clear from the paid log
      }
      await savePayers();
    }
    liveCup = createCup({ entryGlory, prizePool, cap, seedBase: "cup-" + Date.now() });
    await persistCup();
    res.json({ ok: true, refundedPlayers: refunded, refundEachGlory: refundEach, ...cupSnapshot(req.body?.wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: launch / unlaunch publicly (controls whether non-admins can see+enter the Cup).
app.post("/cup/public", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  cupPublic = !!req.body?.public;
  try { await store.kvSet("cup_public", cupPublic); } catch (e) {}
  res.json({ ok: true, public: cupPublic });
});

// Admin: change the lobby SIZE live (8 / 10 / 16) WITHOUT recreating — keeps everyone already seated.
// Only during registration, and never below the number already registered.
app.post("/cup/resize", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup) return res.status(409).json({ error: "no cup created yet" });
  if (liveCup.state.status !== "registration") return res.status(409).json({ error: "can only resize during registration" });
  const cap = Number(req.body?.cap);
  if (![8, 10, 16].includes(cap)) return res.status(400).json({ error: "cap must be 8, 10, or 16" });
  const seated = liveCup.state.entrants.length;
  if (cap < seated) return res.status(409).json({ error: `${seated} players already registered — can't shrink below that` });
  liveCup.state.cap = cap;
  await persistCup();
  res.json({ ok: true, cap, ...cupSnapshot(req.body?.wallet) });
});

// ---- Cup chat: lightweight, ephemeral, in-memory live chat for the tournament ----
const cupChat = [];                 // ring buffer of {id,name,wallet,text,ts}
let cupChatId = 1;
const cupChatRate = new Map();      // wallet -> last-post ms (basic anti-spam)
const cleanChat = (s) => String(s || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();

app.get("/cup/chat", (req, res) => {
  const since = Number(req.query?.since) || 0;
  res.json({ ok: true, messages: cupChat.filter(m => m.ts > since).slice(-60), now: Date.now() });
});

app.post("/cup/chat", (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  const text = cleanChat(req.body?.text).slice(0, 240);
  if (!text) return res.status(400).json({ error: "empty message" });
  const now = Date.now(), last = cupChatRate.get(wallet) || 0;
  if (now - last < 1200) return res.status(429).json({ error: "slow down a sec" });
  cupChatRate.set(wallet, now);
  const name = (cleanChat(req.body?.name).slice(0, 24)) || (wallet.slice(0, 4) + "…");
  const msg = { id: cupChatId++, name, wallet, text, ts: now };   // text stored raw; clients MUST escape on render
  cupChat.push(msg);
  if (cupChat.length > 200) cupChat.splice(0, cupChat.length - 200);
  res.json({ ok: true, message: msg });
});

// Admin: fill empty seats with bots (for a dry run). Bots auto-ready every round.
app.post("/cup/fill", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup || liveCup.state.status !== "registration") return res.status(409).json({ error: "registration is not open" });
  try {
    const S = liveCup.state; let added = 0;
    const NAMES = ["Voltere", "Aquilo", "Pyrrhos", "Umbros", "Selka", "Bronto", "Lumix", "Krait", "Nyxa", "Orrin", "Wystan", "Galador", "Adalor", "Tyrannos", "Grovador", "Dragonos"];
    while (S.entrants.length < S.cap) {
      const i = S.entrants.length, id = "BOT" + i;
      const el = CUP_ELEMS[i % 5], br = 4 + ((i * 5 + 3) % 24), sk = [i % 12, (i + 4) % 12, (i + 8) % 12];
      const ct = {}; sk.forEach(s => ct[s] = Math.min(5, 1 + (br / 6 | 0)));
      liveCup.register(id, { name: NAMES[i % NAMES.length] + " ·" + br, element: el, br, arenaSkills: sk, cardTier: ct });
      const e = S.entrants.find(x => x.wallet === id); if (e) e.bot = true; added++;
    }
    await persistCup();
    res.json({ ok: true, added, ...cupSnapshot(req.body?.wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: start the cup (needs a full lobby).
app.post("/cup/start", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup) return res.status(409).json({ error: "no cup created" });
  try { liveCup.start(); await persistCup(); res.json({ ok: true, ...cupSnapshot(req.body?.wallet) }); }
  catch (e) { res.status(400).json({ error: String(e.message || e) }); }
});

// Admin: resolve the current round (lock-in window closes). Bots auto-ready; on finish, prizes are credited.
app.post("/cup/resolve-round", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup || liveCup.state.status !== "live") return res.status(409).json({ error: "no live round" });
  try {
    liveCup.state.entrants.forEach(e => { if (e.bot) e.ready = true; });   // bots always lock in
    const r = liveCup.resolveRound();
    if (r.finished) {
      let awarded = 0;
      for (const row of liveCup.results()) { if (row.sol > 0 && isPubkey(row.wallet)) { cupPrizes.set(row.wallet, (cupPrizes.get(row.wallet) || 0) + row.sol); awarded += row.sol; } }
      cupTotalAwarded = +(cupTotalAwarded + awarded).toFixed(4);
      await saveCupPrizes(); await saveCupAwarded();
      crownChampion();
    }
    await persistCup();
    res.json({ ok: true, result: r, ...cupSnapshot(req.body?.wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: START the current round as LIVE PvP — spin up a real battle for every real-vs-real pair.
// Players then fight; byes/bots resolve automatically at finalize.
// Shared: spin up LIVE PvP matches for the current round's real-vs-real pairs. Returns # of live matches.
async function cupStartRoundLive() {
  const S = liveCup.state;
  const entOf = w => S.entrants.find(x => x.wallet === w);
  const isReal = w => { const e = entOf(w); return !!(e && !e.bot && isPubkey(w)); };
  const round = { battling: true, matchByWallet: new Map(), side: new Map(), matches: [] };
  for (const m of liveCup.currentMatches()) {
    const aw = m.a.wallet, bw = m.b.wallet, ea = entOf(aw), eb = entOf(bw);
    if (ea) ea.ready = true; if (eb) eb.ready = true;   // mark seated so resolveRound runs the decide() path
    if (isReal(aw) && isReal(bw)) {
      const match = pvpStartMatch({ ...ea.snap, wallet: aw }, { ...eb.snap, wallet: bw }, { turnMs: 30000 });
      round.matchByWallet.set(aw, match.id); round.matchByWallet.set(bw, match.id);
      round.side.set(aw, "a"); round.side.set(bw, "b");
      round.matches.push({ matchId: match.id, a: aw, b: bw });
    }
  }
  cupRound = round; cupRoundStartedAt = Date.now(); await persistCup();
  return round.matches.length;
}
// Shared: advance the bracket using live PvP winners (unfinished matches fall back to the deterministic engine).
async function cupFinalizeRoundLive() {
  const round = cupRound;
  liveCup.state.entrants.forEach(e => { if (e.bot) e.ready = true; });
  const decide = (a, b) => {
    if (!round) return null;
    const mid = round.matchByWallet.get(a.wallet); if (!mid) return null;
    const m = pvpMatches.get(mid); if (!m || m.status !== "finished") return null;   // not done → deterministic fallback
    const winWallet = m.winner === "a" ? m.walletA : m.walletB;
    return winWallet === a.wallet ? "a" : "b";
  };
  const r = liveCup.resolveRound(decide);
  if (r.finished) {
    let awarded = 0;
    for (const row of liveCup.results()) { if (row.sol > 0 && isPubkey(row.wallet)) { cupPrizes.set(row.wallet, (cupPrizes.get(row.wallet) || 0) + row.sol); awarded += row.sol; } }
    cupTotalAwarded = +(cupTotalAwarded + awarded).toFixed(4);
    await saveCupPrizes(); await saveCupAwarded();
    crownChampion();
  }
  cupRound = null; await persistCup();
  return r;
}

// AUTO-RUNNER: when enabled, the server drives the whole tournament — starts the cup once the lobby is full,
// starts each round, ticks idle matches so they resolve, and finalizes when all battles are done (or time out).
async function cupAutoTick() {
  if (!cupAuto || !liveCup) return;
  const S = liveCup.state;
  if (S.status === "registration") {
    if (S.entrants.length === S.cap) { try { liveCup.start(); cupAutoNextAt = Date.now() + CUP_ROUND_GAP_MS; await persistCup(); } catch (e) {} }
    return;
  }
  if (S.status !== "live") return;
  if (Date.now() < cupAutoNextAt) return;                       // respect the inter-round pause
  if (!cupRound || !cupRound.battling) { await cupStartRoundLive(); return; }
  // a round is underway — tick every active match so idle players auto-play/forfeit even if nobody is polling
  for (const mm of cupRound.matches) { const m = pvpMatches.get(mm.matchId); if (m && m.status === "active") { try { pvpTick(m); } catch (e) {} } }
  const allDone = (cupRound.matches || []).every(mm => { const m = pvpMatches.get(mm.matchId); return m && m.status === "finished"; });
  const timedOut = (Date.now() - cupRoundStartedAt) > CUP_ROUND_MAX_MS;
  if (allDone || timedOut) { await cupFinalizeRoundLive(); cupAutoNextAt = Date.now() + CUP_ROUND_GAP_MS; }
}
setInterval(() => { cupAutoTick().catch(() => {}); }, 4000);

app.post("/cup/start-round", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup || liveCup.state.status !== "live") return res.status(409).json({ error: "no live round" });
  try {
    const n = await cupStartRoundLive();
    res.json({ ok: true, liveMatches: n, ...cupSnapshot(req.body?.wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: FINALIZE the round — advance the bracket using the live PvP winners (unfinished matches fall back to the engine).
app.post("/cup/finalize-round", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  if (!liveCup || liveCup.state.status !== "live") return res.status(409).json({ error: "no live round" });
  try {
    const r = await cupFinalizeRoundLive();
    res.json({ ok: true, result: r, ...cupSnapshot(req.body?.wallet) });
  } catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

// Admin: toggle AUTO-RUN on/off. When on, the server runs the whole tournament hands-free.
app.post("/cup/auto", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  cupAuto = !!req.body?.auto;
  try { await store.kvSet("cup_auto", cupAuto); } catch (e) {}
  res.json({ ok: true, auto: cupAuto });
});

// Public: the reigning Chikoria Cup champion (for the floating world trophy + profile badge).
app.get("/cup/champion", (req, res) => res.json(cupChampion || { wallet: null, name: null, ts: 0 }));
// Admin: manually set/clear the reigning champion (GET or POST; e.g., for cups run before this feature).
async function setChampionHandler(req, res) {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const src = req.method === "GET" ? req.query : (req.body || {});
  const wallet = src.wallet, name = src.name || "Champion";
  if (!wallet || wallet === "none" || wallet === "clear") { cupChampion = null; await saveCupChampion(); return res.json({ ok: true, cupChampion: null }); }
  if (!isPubkey(wallet)) return res.status(400).json({ error: "valid wallet required" });
  cupChampion = { wallet, name, ts: Date.now() }; await saveCupChampion();
  res.json({ ok: true, cupChampion });
}
app.get("/cup/set-champion", setChampionHandler);
app.post("/cup/set-champion", setChampionHandler);

// ----- Meme Dynasty NFT eggs -----
// Buy + hatch a Meme Legendary Egg → assigns a RANDOM member + edition; the mint worker turns it into an on-chain NFT.
// (Payment is taken client-side in $CHIKI like other game spends; production should verify payment on-chain.)
app.post("/meme/hatch", async (req, res) => {
  const wallet = req.body && req.body.wallet;
  const paySig = req.body && req.body.paySig;
  if (!isPubkey(wallet)) return res.status(400).json({ error: "valid wallet required" });
  // 🔒 SALE LOCK: closed to the public until launch; admin wallets bypass so the dry-run works.
  if (!MEME_SALE_OPEN && !MEME_ADMIN_WALLETS.has(wallet)) return res.status(403).json({ error: "Meme Dynasty hatching opens at official launch — stay tuned on X! 🥚" });
  const now = Date.now(), last = _memeLastHatch.get(wallet) || 0;
  if (now - last < 4000) return res.status(429).json({ error: "slow down — one egg at a time" });
  if (memeOwnedActive(wallet) >= 1) return res.status(409).json({ error: "You already own a Meme Legendary — list it in the Bazaar (put it up for sale) before hatching another." });
  // PAYMENT GATE: real $CHIKI must have changed hands on-chain before we mint anything.
  if (MEME_VERIFY_PAY) {
    if (!paySig || typeof paySig !== "string") return res.status(402).json({ error: "payment required — include your $CHIKI payment signature" });
    if (memeUsedSigs[paySig]) return res.status(409).json({ error: "that payment was already used to hatch an egg" });
    const v = await verifyEggPayment(paySig, wallet);
    if (!v.ok) return res.status(402).json({ error: v.error });
    memeUsedSigs[paySig] = { wallet, ts: now };   // burn the signature so it can't hatch a second egg
  }
  // 🎲 The species is NOT chosen here — it stays a MYSTERY and is rolled at hatch time (POST /meme/hatched).
  // We only RESERVE a slot against the 105 total here.
  if (memeReserved() >= MEME_TOTAL) { if (MEME_VERIFY_PAY && paySig) delete memeUsedSigs[paySig]; return res.status(409).json({ error: "sold out — every Meme Dynasty egg has been claimed" }); }
  _memeLastHatch.set(wallet, now);
  const h = { id: "h" + now.toString(36) + Math.random().toString(36).slice(2, 6), wallet, char: null, name: "Mystery Meme Egg", edition: null, status: "incubating", undetermined: true, mintAddr: null, ts: now, paySig: paySig || null };
  memeHatches.push(h); await saveMeme();
  res.json({ ok: true, hatch: { id: h.id, status: "incubating", mystery: true }, supply: memeSupply() });
});
// The in-game egg finished its tended incubation → ROLL the random species now, then flip "incubating" → "pending" so the worker mints the NFT.
app.post("/meme/hatched", async (req, res) => {
  const { wallet, hatchId } = req.body || {};
  if (!isPubkey(wallet)) return res.status(400).json({ error: "wallet required" });
  const h = memeHatches.find(x => x.id === hatchId && x.wallet === wallet);
  if (!h) return res.status(404).json({ error: "hatch not found" });
  if (h.status === "incubating") {
    if (!h.char) {   // roll the random Meme Legendary NOW (respecting remaining per-character caps)
      const c = pickMeme();
      if (!c) return res.status(409).json({ error: "the dynasty is fully hatched" });
      h.char = c.key; h.name = c.name; h.edition = (memeMinted[c.key] || 0) + 1; memeMinted[c.key] = h.edition; h.undetermined = false;
    }
    h.status = "pending"; h.hatchedAt = Date.now(); await saveMeme();
  }
  res.json({ ok: true, status: h.status, char: h.char, name: h.name, edition: h.edition, cap: capOf(h.char), rarity: rarityOf(h.char) });
});
// A wallet's hatched Meme NFTs (with mint status) + live supply.
app.get("/meme/mine", (req, res) => {
  const wallet = req.query && req.query.wallet;
  if (!isPubkey(wallet)) return res.status(400).json({ error: "wallet required" });
  const items = memeHatches.filter(h => h.wallet === wallet)
    .map(h => ({ id: h.id, char: h.char, name: h.name, edition: h.edition, status: h.status, mintAddr: h.mintAddr, ts: h.ts, listed: h.listed || null }))
    .sort((a, b) => b.ts - a.ts);
  res.json({ items, supply: memeSupply() });
});
app.get("/meme/supply", (req, res) => res.json({ ...memeSupply(), eggPrice: MEME_EGG_PRICE, verifyPay: MEME_VERIFY_PAY, saleOpen: MEME_SALE_OPEN, tradeTensor: MEME_TRADE_TENSOR, tensorUrl: TENSOR_URL || null }));
// Public: the most recent hatches — drives a live "just hatched!" ticker for hype/engagement.
app.get("/meme/recent", (req, res) => {
  const items = memeHatches.filter(h => h.status !== "incubating")
    .slice(-12).reverse()
    .map(h => ({ char: h.char, name: h.name, edition: h.edition, cap: capOf(h.char), rarity: rarityOf(h.char), ts: h.hatchedAt || h.ts }));
  const sup = memeSupply();
  res.json({ items, minted: sup.total - sup.totalLeft, total: sup.total });
});
// Worker: list hatches awaiting an on-chain mint.
app.get("/meme/pending", (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  res.json({ pending: memeHatches.filter(h => h.status === "pending").slice(0, 50) });
});
// Worker: mark a hatch minted (records the on-chain asset address).
app.post("/meme/minted", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const { hatchId, mintAddr } = req.body || {};
  const h = memeHatches.find(x => x.id === hatchId);
  if (!h) return res.status(404).json({ error: "hatch not found" });
  h.status = "minted"; h.mintAddr = mintAddr || null; await saveMeme();
  res.json({ ok: true });
});

// ----- Mystic Market NFT Bazaar (devnet) — list / unlist / browse / buy a Meme Dynasty NFT -----
// (Off-chain ownership ledger for the devnet demo. Mainnet should use Metaplex Auction House / Tensor for
//  escrowless on-chain trades + royalties — never a custom escrow.)
app.post("/meme/list", async (req, res) => {
  if (MEME_TRADE_TENSOR) return res.status(410).json({ error: "Trading is on Tensor now — list your NFT there.", tensorUrl: TENSOR_URL });
  const { wallet, hatchId, price } = req.body || {};
  if (!isPubkey(wallet)) return res.status(400).json({ error: "wallet required" });
  const h = memeHatches.find(x => x.id === hatchId);
  if (!h) return res.status(404).json({ error: "NFT not found" });
  if (h.wallet !== wallet) return res.status(403).json({ error: "not your NFT" });
  if (h.status !== "minted") return res.status(409).json({ error: "this Legendary is still hatching — you can list it once it's minted on-chain. 🥚" });
  const p = Number(price); if (!(p > 0)) return res.status(400).json({ error: "price must be greater than 0" });
  h.listed = { price: +p.toFixed(4), ts: Date.now() }; await saveMeme();
  res.json({ ok: true });
});
app.post("/meme/unlist", async (req, res) => {
  const { wallet, hatchId } = req.body || {};
  const h = memeHatches.find(x => x.id === hatchId);
  if (!h || h.wallet !== wallet) return res.status(403).json({ error: "not your NFT" });
  h.listed = null; await saveMeme();
  res.json({ ok: true });
});
app.get("/meme/market", (req, res) => {
  const items = memeHatches.filter(h => h.listed)
    .map(h => ({ id: h.id, char: h.char, name: h.name, edition: h.edition, price: h.listed.price, seller: h.wallet, mintAddr: h.mintAddr, status: h.status, listedAt: h.listed.ts }))
    .sort((a, b) => a.price - b.price);
  res.json({ items, supply: memeSupply() });
});
// Buy a listed NFT — transfers in-game ownership + records the sale. (Payment settled client-side for the devnet demo.)
app.post("/meme/buy", async (req, res) => {
  if (MEME_TRADE_TENSOR) return res.status(410).json({ error: "Buying happens on Tensor now — settle the trade on-chain there.", tensorUrl: TENSOR_URL });
  const { wallet, hatchId } = req.body || {};
  if (!isPubkey(wallet)) return res.status(400).json({ error: "wallet required" });
  const h = memeHatches.find(x => x.id === hatchId);
  if (!h || !h.listed) return res.status(409).json({ error: "this NFT is no longer for sale" });
  if (h.status !== "minted") return res.status(409).json({ error: "this NFT isn't minted on-chain yet — can't buy it" });
  if (h.wallet === wallet) return res.status(400).json({ error: "you can't buy your own listing" });
  if (memeOwnedActive(wallet) >= 1) return res.status(409).json({ error: "You already own a Meme Legendary — list yours for sale before buying another." });
  const price = h.listed.price, seller = h.wallet;
  h.wallet = wallet; h.listed = null; h.lastSale = { price, from: seller, to: wallet, ts: Date.now() };
  await saveMeme();
  res.json({ ok: true, price, seller, char: h.char, name: h.name, edition: h.edition });
});

// Admin: AUDIT the owed-prize ledger (read-only) — who is still owed Cup SOL, and how much.
app.get("/cup/prizes", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const prizes = [...cupPrizes.entries()].map(([wallet, sol]) => ({ wallet, sol: +Number(sol).toFixed(4) })).sort((a, b) => b.sol - a.sol);
  res.json({ count: prizes.length, totalSol: +prizes.reduce((s, x) => s + x.sol, 0).toFixed(4), prizes });
});

// Admin RECOVERY: manually credit a wallet a Cup prize (e.g., if a cup's result was lost before crediting).
// Strictly ADMIN_KEY-gated because it creates claimable SOL — a public wallet check is NOT enough here.
app.post("/cup/grant", async (req, res) => {
  if (!process.env.ADMIN_KEY || req.body?.key !== process.env.ADMIN_KEY) return res.status(403).json({ error: "admin key required" });
  const wallet = req.body?.wallet, sol = Number(req.body?.sol);
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!(sol > 0)) return res.status(400).json({ error: "positive 'sol' required" });
  cupPrizes.set(wallet, +(((cupPrizes.get(wallet) || 0) + sol)).toFixed(6));
  await saveCupPrizes();
  res.json({ ok: true, wallet, granted: sol, owedNow: cupPrizes.get(wallet) });
});

// Admin: refund cup-entry GLORY to wallets (e.g., players from a lost lobby that wasn't auto-refunded).
// Pass {wallets:[...]} to refund a specific list, or omit it to refund everyone in the durable paid-log.
app.post("/cup/refund", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const amount = Math.max(1, Number(req.body?.amount) || 100);
  // refund a specific {wallets:[...]}, OR source:"finishers" (everyone in the prize ledger = first cup's entrants), OR the paid-log
  let list;
  if (Array.isArray(req.body?.wallets) && req.body.wallets.length) list = req.body.wallets;
  else if (req.body?.source === "finishers") list = [...cupPrizes.keys()];
  else list = [...cupPayers.keys()];
  const done = [];
  for (const w of list) { if (await refundGlory(w, amount)) { done.push(w); cupPayers.delete(w); } }
  await savePayers();
  res.json({ ok: true, refundedEachGlory: amount, count: done.length, wallets: done });
});

// Admin: view the durable paid-log (who paid entry Glory and how much) — for auditing refunds.
app.get("/cup/payers", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const payers = [...cupPayers.entries()].map(([wallet, glory]) => ({ wallet, glory }));
  res.json({ count: payers.length, totalGlory: payers.reduce((s, x) => s + x.glory, 0), payers });
});

/* ----------------------------- LIVE PvP battles ----------------------------- */
const pvpMatches = new Map();   // matchId -> live match (in-memory; a battle is short-lived)
const pvpSideOf = (m, wallet) => m.walletA === wallet ? "a" : m.walletB === wallet ? "b" : null;
// drive turn timeouts / forfeits + clean up finished matches
setInterval(() => {
  const now = Date.now();
  for (const [id, m] of pvpMatches) {
    try { pvpTick(m, now); } catch (e) {}
    if (m.status === "finished") { if (!m._doneAt) m._doneAt = now; else if (now - m._doneAt > 180000) pvpMatches.delete(id); }
  }
}, 1000);

const pvpQueue = [];                  // [{wallet, snap, ts}] players waiting for a live opponent
const pvpPlayerMatch = new Map();     // wallet -> their current matchId (so cup + queued players can find their battle)
// Count of ONLINE players who own a Legendary (= eligible to battle in the Chikiseum). Cached to avoid DB load.
const PVP_LEGEND_SP = new Set([10, 11, 12, 13, 14]);   // legendary species indices
let _pvpOnlineCache = { n: 0, t: 0 };
async function eligibleOnline() {
  const now = Date.now();
  if (now - _pvpOnlineCache.t < 4000) return _pvpOnlineCache.n;
  try {
    const rows = await store.world(PRESENCE_WINDOW, "", 5000);   // [{wallet, sp, level}]
    const set = new Set();
    for (const r of rows) if (PVP_LEGEND_SP.has(r.sp | 0)) set.add(r.wallet);
    _pvpOnlineCache = { n: set.size, t: now };
  } catch (e) {}
  return _pvpOnlineCache.n;
}
function pvpStartMatch(a, b, opts) {  // a,b = snapshots with .wallet
  const m = pvpCreate(a, b, opts || { turnMs: 30000 });
  pvpMatches.set(m.id, m); pvpPlayerMatch.set(m.walletA, m.id); pvpPlayerMatch.set(m.walletB, m.id);
  return m;
}

// Admin/Cup: create a live PvP match from two player snapshots {wallet, name, element, br, arenaSkills, cardTier}.
app.post("/pvp/create", async (req, res) => {
  if (!cupAdminOk(req)) return res.status(403).json({ error: "admin only" });
  const a = req.body?.a, b = req.body?.b;
  if (!a?.wallet || !b?.wallet || !isPubkey(a.wallet) || !isPubkey(b.wallet)) return res.status(400).json({ error: "a.wallet and b.wallet required" });
  const m = pvpStartMatch(a, b, { turnMs: Math.max(8000, Number(req.body?.turnMs) || 30000), id: req.body?.id });
  res.json({ ok: true, matchId: m.id, a: m.walletA, b: m.walletB, turnMs: m.turnMs });
});

// Open Chikiseum matchmaking: join the queue; pairs with the next waiting player into a live match.
app.post("/pvp/queue", async (req, res) => {
  const wallet = req.body?.wallet, snap = req.body?.snap;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!snap || !snap.element) return res.status(400).json({ error: "legendary 'snap' required" });
  snap.wallet = wallet;
  const eligible = await eligibleOnline();
  const r = availableJoin({ wallet, name: snap.name, snap, searching: true });   // legacy endpoint now shares the ONE pool
  if (r.matched) return res.json({ status: "matched", matchId: r.matched.matchId, side: r.matched.side });
  res.json({ status: "searching", queued: pvpAvail.size, eligible });
});

// Poll matchmaking / find your current match (used by open Chikiseum AND cup players).
app.get("/pvp/queue", async (req, res) => {
  const wallet = req.query?.wallet; if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "wallet required" });
  const cur = pvpPlayerMatch.get(wallet); const m = cur && pvpMatches.get(cur);
  if (m) return res.json({ status: "matched", matchId: cur, side: pvpSideOf(m, wallet), over: m.status === "finished" });
  res.json({ status: pvpQueue.find(q => q.wallet === wallet) ? "searching" : "idle", queued: pvpQueue.length, eligible: await eligibleOnline() });
});

// Online Chikiseum-eligible player count (owns a Legendary) — shown before/while queuing.
app.get("/pvp/online", async (req, res) => { cleanAvail(); res.json({ eligible: await eligibleOnline(), queued: pvpQueue.length, inChikiseum: pvpAvail.size, searching: [...pvpAvail.values()].filter(v => v.searching).length, names: [...pvpAvail.values()].map(v => v.name) }); });

// Leave the matchmaking queue.
app.post("/pvp/cancel", (req, res) => {
  const wallet = req.body?.wallet; const i = pvpQueue.findIndex(q => q.wallet === wallet);
  if (i >= 0) pvpQueue.splice(i, 1);
  pvpAvail.delete(wallet);
  res.json({ ok: true });
});

// ----- Direct challenge: see who's ready & challenge them (fixes "no one is searching at the same instant") -----
const pvpAvail = new Map();        // wallet -> {name, snap, ts} : Trainers with the Chikiseum open, ready to battle
let pvpChallenges = [];            // {id, from, fromName, to, snap, ts}
const AVAIL_TTL = 14000, CHALL_TTL = 30000;
function cleanAvail() { const now = Date.now(); for (const [w, v] of pvpAvail) if (now - v.ts > AVAIL_TTL) pvpAvail.delete(w); pvpChallenges = pvpChallenges.filter(c => now - c.ts < CHALL_TTL); }
// Heartbeat: register that you're in the Chikiseum (optionally actively searching). Returns other ready Trainers,
// your incoming challenges, and whether you've been matched. If `searching`, AUTO-PAIRS you with any other searcher.
// Shared join logic for the ONE matchmaking pool — used by both /pvp/available and the legacy /pvp/queue,
// so every searcher lives in the same pool and pairs reliably (verified seamless across thousands of sims).
function availableJoin(body) {
  const { wallet, name, snap, searching } = body || {};
  if (!isPubkey(wallet)) return { error: "wallet required" };
  cleanAvail();
  const cur = pvpPlayerMatch.get(wallet), curM = cur && pvpMatches.get(cur);
  if (curM && curM.status === "active") { pvpAvail.delete(wallet); return { players: [], challenges: [], matched: { matchId: cur, side: pvpSideOf(curM, wallet) } }; }
  if (snap && snap.element) pvpAvail.set(wallet, { name: String(name || "Trainer").slice(0, 20), snap, ts: Date.now(), searching: !!searching });
  else pvpAvail.delete(wallet);
  // auto-match: if I'm actively searching, pair me with ANY other searching Trainer not already in a battle
  if (searching && snap && snap.element) {
    for (const [w, v] of pvpAvail) {
      if (w === wallet || !v.searching) continue;
      const m = pvpPlayerMatch.get(w); if (m && pvpMatches.get(m) && pvpMatches.get(m).status === "active") continue;
      const me = { ...snap, wallet }, op = { ...v.snap, wallet: w };
      const match = pvpStartMatch(op, me, { turnMs: 30000 });   // earlier searcher = side a
      pvpAvail.delete(w); pvpAvail.delete(wallet);
      pvpChallenges = pvpChallenges.filter(c => c.from !== w && c.to !== w && c.from !== wallet && c.to !== wallet);
      return { players: [], challenges: [], matched: { matchId: match.id, side: pvpSideOf(match, wallet) } };
    }
  }
  const players = [...pvpAvail.entries()].filter(([w]) => w !== wallet).map(([w, v]) => ({ wallet: w, name: v.name, searching: !!v.searching }));
  const challenges = pvpChallenges.filter(c => c.to === wallet).map(c => ({ id: c.id, from: c.from, fromName: c.fromName }));
  return { players, challenges, matched: null };
}
app.post("/pvp/available", (req, res) => { const r = availableJoin(req.body); if (r.error) return res.status(400).json(r); res.json(r); });
// Send a challenge to a specific Trainer.
app.post("/pvp/challenge", (req, res) => {
  const { from, fromName, to, snap } = req.body || {};
  if (!isPubkey(from) || !isPubkey(to)) return res.status(400).json({ error: "valid wallets required" });
  if (!snap || !snap.element) return res.status(400).json({ error: "legendary snap required" });
  cleanAvail();
  if (pvpChallenges.some(c => c.from === from && c.to === to)) return res.json({ ok: true });   // dedupe
  pvpChallenges.push({ id: "c" + Date.now().toString(36) + Math.random().toString(36).slice(2, 5), from, fromName: String(fromName || "Trainer").slice(0, 20), to, snap, ts: Date.now() });
  res.json({ ok: true });
});
// Accept a challenge -> starts the live match; both sides learn via /pvp/available (matched) or this response.
app.post("/pvp/challenge/accept", (req, res) => {
  const { wallet, challengeId, snap } = req.body || {};
  if (!snap || !snap.element) return res.status(400).json({ error: "legendary snap required" });
  const i = pvpChallenges.findIndex(c => c.id === challengeId && c.to === wallet);
  if (i < 0) return res.status(404).json({ error: "challenge expired" });
  const ch = pvpChallenges.splice(i, 1)[0];
  // guard: neither player may already be in a live battle (prevents double-matches)
  for (const w of [ch.from, wallet]) { const mm = pvpPlayerMatch.get(w); if (mm && pvpMatches.get(mm) && pvpMatches.get(mm).status === "active") { pvpChallenges = pvpChallenges.filter(c => c.from !== ch.from && c.to !== ch.from && c.from !== wallet && c.to !== wallet); return res.status(409).json({ error: "that Trainer is already in a battle" }); } }
  snap.wallet = wallet; ch.snap.wallet = ch.from;
  const m = pvpStartMatch(ch.snap, snap, { turnMs: 30000 });   // challenger = side a, accepter = side b
  pvpAvail.delete(ch.from); pvpAvail.delete(wallet);
  pvpChallenges = pvpChallenges.filter(c => c.from !== ch.from && c.to !== ch.from && c.from !== wallet && c.to !== wallet);
  res.json({ ok: true, matchId: m.id, side: pvpSideOf(m, wallet) });
});
// Decline / clear a challenge.
app.post("/pvp/challenge/decline", (req, res) => {
  const { wallet, challengeId } = req.body || {};
  pvpChallenges = pvpChallenges.filter(c => !(c.id === challengeId && c.to === wallet));
  res.json({ ok: true });
});

// Player: poll your live battle state (only your own hand is revealed).
app.get("/pvp/state", (req, res) => {
  const m = pvpMatches.get(req.query?.matchId); if (!m) return res.status(404).json({ error: "match not found" });
  const who = pvpSideOf(m, req.query?.wallet); if (!who) return res.status(403).json({ error: "not your match" });
  try { pvpTick(m); } catch (e) {}
  res.json(pvpView(m, who));
});

// SPECTATORS: anyone can watch a live match (public view — HP/shield/score/log, no hands).
app.get("/pvp/spectate", (req, res) => {
  const m = pvpMatches.get(req.query?.matchId); if (!m) return res.status(404).json({ error: "match not found" });
  try { pvpTick(m); } catch (e) {}
  res.json(pvpSpectate(m));
});

// Player: lock in your cards for the current turn. body: { matchId, wallet, cards:[handIndex,...] }
app.post("/pvp/move", (req, res) => {
  const m = pvpMatches.get(req.body?.matchId); if (!m) return res.status(404).json({ error: "match not found" });
  const who = pvpSideOf(m, req.body?.wallet); if (!who) return res.status(403).json({ error: "not your match" });
  const r = pvpSubmit(m, who, Array.isArray(req.body?.cards) ? req.body.cards : []);
  if (!r.ok) return res.status(400).json({ error: r.error });
  res.json(pvpView(m, who));
});

// Player: leave the battle → instant loss; the opponent wins immediately (no waiting for the timer).
app.post("/pvp/forfeit", (req, res) => {
  const m = pvpMatches.get(req.body?.matchId); if (!m) return res.status(404).json({ error: "match not found" });
  const who = pvpSideOf(m, req.body?.wallet); if (!who) return res.status(403).json({ error: "not your match" });
  pvpForfeit(m, who);
  res.json({ ok: true, ...pvpView(m, who) });
});

// Devnet-only funding helper (open in a browser to airdrop to the treasury)
app.get("/fund", async (req, res) => {
  if (NETWORK !== "devnet") return res.status(400).json({ error: "devnet-only" });
  const amt = Math.min(2, Number(req.query.amount || 1));
  for (const url of [RPC_URL, "https://api.devnet.solana.com"]) {
    try {
      const c = new Connection(url, "confirmed");
      const sig = await c.requestAirdrop(treasury.publicKey, Math.floor(amt * LAMPORTS_PER_SOL));
      await c.confirmTransaction(sig, "confirmed");
      return res.json({ ok: true, airdropped: amt, poolSol: (await c.getBalance(treasury.publicKey)) / LAMPORTS_PER_SOL, signature: sig });
    } catch {}
  }
  res.status(502).json({ error: "airdrop failed (devnet faucets are rate-limited) — reload to retry" });
});

// Open the port FIRST so Render detects it immediately (no "No open ports" timeout on a cold DB),
// then initialize the DB in the background (errors logged, not fatal — the server stays up and recovers).
app.listen(Number(PORT), () => {
  console.log(`Chiki backend v2 on :${PORT} · ${NETWORK} · store=${store.kind} · treasury ${treasury.publicKey.toBase58()}`);
  console.log(`verifyHolders=${verifyOn} · holdMin=${MIN_HOLD_MINUTES} · dailyCap=${DAILY_FRAC>=1?"none":Math.round(DAILY_FRAC*100)+"% pool/day"} · perWallet=${WALLET_DAILY} SOL`);
});
store.init().then(()=>{ console.log("store ready"); return loadCupState(); }).then(()=>console.log(`cup state loaded (public=${cupPublic}, owed prizes=${cupPrizes.size})`)).catch(e=>console.error("store.init failed:", e?.message||e));
chat.init().then(()=>console.log("chat ready")).catch(e=>console.error("chat.init failed:", e?.message||e));
