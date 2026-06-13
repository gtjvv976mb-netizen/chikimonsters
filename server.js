// Chiki Monsters backend v2 — Postgres-backed, idempotent logged payouts.
// Holder verification + server-signed SOL payouts. Devnet-first; set DATABASE_URL for production.
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import bs58 from "bs58";
import pg from "pg";
import {
  Connection, Keypair, PublicKey, Transaction, SystemProgram, LAMPORTS_PER_SOL,
} from "@solana/web3.js";

dotenv.config();
const {
  NETWORK = "devnet",
  RPC_URL,
  CHIKI_MINT,
  MIN_HOLD = "500000",
  MIN_HOLD_MINUTES = "0",          // anti-sybil: wallet must be "seen" this long before it can claim
  WHALE_MIN_HOLD = "1000000",      // balance for the 2nd Chiki
  WHALE_HOLD_HOURS = "6",          // must hold >= WHALE_MIN_HOLD continuously this long to earn the 2nd Chiki
  VERIFY_HOLDERS = "false",
  TREASURY_SECRET,
  TEAM_WALLET = "",
  REWARD_RATE_PER_MIN = "0.0008",  // legacy; no longer used (earnings are now task/rarity-based)
  EARN_MULT = "1",                 // global multiplier on all task SOL payouts (tune to your fee budget)
  TASK_SECONDS = "45",             // avg seconds a Chiki takes per task (sets task throughput)
  ACCRUAL_CAP_MIN = "60",          // max minutes of task earnings counted per claim
  MAX_CLAIM_SOL = "0.05",
  DAILY_CAP_SOL = "1",             // global cap on confirmed payouts per rolling 24h
  POOL_RESERVE_SOL = "0.05",       // never pay the treasury below this floor (keeps a buffer for fees)
  PER_WALLET_DAILY_SOL = "0",      // per-wallet cap per rolling 24h (0 = unlimited)
  CLAIM_COOLDOWN_SEC = "30",
  DATABASE_URL = "",
  ADMIN_KEY = "",                   // set this to enable /admin/reset (wipe test profiles)
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
const MULT = Number(EARN_MULT), TASK_SEC = Math.max(5, Number(TASK_SECONDS)), ACCRUAL_CAP = Number(ACCRUAL_CAP_MIN);
const WHALE_MIN = Number(WHALE_MIN_HOLD), WHALE_HOLD_MS = Number(WHALE_HOLD_HOURS) * 3600_000;
/* effective Chiki count: 1 if eligible holder; 2 only after holding >= WHALE_MIN continuously for WHALE_HOLD_MS */
function chikiCount(balance, whaleSince) {
  if (balance < MIN) return 0;
  if (balance >= WHALE_MIN && whaleSince && (Date.now() - Number(whaleSince)) >= WHALE_HOLD_MS) return 2;
  return 1;
}
/* server-authoritative, rarity-weighted earnings: each simulated task pays SOL by rarity.
   The server rolls the tasks itself (using on-chain Chiki count + elapsed time), so it can't be faked. */
const RARITY_SOL = { common:0.00002, uncommon:0.00004, rare:0.00009, epic:0.0002, mythic:0.0005, shiny:0.001, legend:0.0025 };
const RARITY_DIST = [["common",45],["uncommon",27],["rare",15],["epic",7],["mythic",3.5],["shiny",1.7],["legend",0.8]];
const RARITY_TOTAL = RARITY_DIST.reduce((s, r) => s + r[1], 0);
function rollRarity() {
  let x = Math.random() * RARITY_TOTAL;
  for (const [name, w] of RARITY_DIST) { x -= w; if (x <= 0) return name; }
  return "common";
}
/* simulate the SOL a wallet's Chikis earned over `minutes`, rolling each task's rarity */
function simEarn(minutes, chikis) {
  const tasks = Math.min(4000, Math.floor((minutes * 60 / TASK_SEC) * Math.max(1, chikis)));
  let sol = 0;
  for (let i = 0; i < tasks; i++) sol += RARITY_SOL[rollRarity()];
  return sol * MULT;
}
const WALLET_DAILY = Number(PER_WALLET_DAILY_SOL);
const verifyOn = String(VERIFY_HOLDERS).toLowerCase() === "true";

const isPubkey = (s) => { try { new PublicKey(s); return true; } catch { return false; } };

async function chikiBalance(owner) {
  if (!MINT) return 0;
  try {
    const r = await conn.getParsedTokenAccountsByOwner(new PublicKey(owner), { mint: MINT });
    let b = 0; for (const { account } of r.value) b += account.data.parsed.info.tokenAmount.uiAmount || 0;
    return b;
  } catch { return 0; }
}
const poolSol = async () => (await conn.getBalance(treasury.publicKey)) / LAMPORTS_PER_SOL;

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
    },
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
        const amount = await compute(p);
        if (!(amount > 0)) { await c.query("ROLLBACK"); return { status: "none" }; }
        await c.query(`UPDATE players SET last_claim=$2, lifetime_paid=lifetime_paid+$3 WHERE wallet=$1`, [wallet, now, amount]);
        const ins = await c.query(`INSERT INTO payouts(wallet,amount,status) VALUES($1,$2,'pending') RETURNING id`, [wallet, amount]);
        await c.query("COMMIT");
        return { status: "ok", amount, payoutId: ins.rows[0].id, prevLastClaim: Number(p.last_claim) };
      } catch (e) { try { await c.query("ROLLBACK"); } catch {} throw e; }
      finally { c.release(); }
    },
    async confirm(id, sig) { await pool.query(`UPDATE payouts SET status='confirmed', signature=$2 WHERE id=$1`, [id, sig]); },
    async fail(id, wallet, prevLastClaim, amount) {
      await pool.query(`UPDATE payouts SET status='failed' WHERE id=$1`, [id]);
      await pool.query(`UPDATE players SET last_claim=$2, lifetime_paid=GREATEST(0,lifetime_paid-$3) WHERE wallet=$1`, [wallet, prevLastClaim, amount]);
    },
    async count() { return Number((await pool.query(`SELECT COUNT(*) n FROM players`)).rows[0].n); },
  };
}

function memStore() {
  const players = new Map(); const payouts = []; const presenceMap = new Map();
  const get = (w) => players.get(w);
  return {
    kind: "memory",
    async init() {},
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
    async reserve(wallet, now, compute) {
      const p = get(wallet) || { wallet, first_seen: now, last_claim: now - 60000, lifetime_paid: 0 };
      players.set(wallet, p);
      if (now - p.last_claim < COOLDOWN) return { status: "cooldown", retryInMs: COOLDOWN - (now - p.last_claim) };
      if (now - p.first_seen < HOLD_MS) return { status: "hold", waitMs: HOLD_MS - (now - p.first_seen) };
      const amount = await compute(p);
      if (!(amount > 0)) return { status: "none" };
      const prev = p.last_claim; p.last_claim = now; p.lifetime_paid += amount;
      const id = payouts.push({ id: payouts.length + 1, wallet, amount, status: "pending", t: now }) ;
      return { status: "ok", amount, payoutId: id, prevLastClaim: prev };
    },
    async confirm(id, sig) { const p = payouts[id - 1]; if (p) { p.status = "confirmed"; p.signature = sig; } },
    async fail(id, wallet, prevLastClaim, amount) {
      const r = payouts[id - 1]; if (r) r.status = "failed";
      const p = get(wallet); if (p) { p.last_claim = prevLastClaim; p.lifetime_paid = Math.max(0, p.lifetime_paid - amount); }
    },
    async count() { return players.size; },
  };
}

const store = makeStore();

/* ----------------------------- API ----------------------------- */
process.on("unhandledRejection", (e) => console.error("unhandledRejection:", e?.message || e));

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", async (_q, res) => res.json({
  ok: true, network: NETWORK, store: store.kind, verifyHolders: verifyOn,
  treasury: treasury.publicKey.toBase58(), team: TEAM_WALLET || null,
  mint: CHIKI_MINT || null, minHold: MIN, minHoldMinutes: Number(MIN_HOLD_MINUTES),
  dailyCapSol: DAILY_CAP, perWalletDailySol: WALLET_DAILY, poolReserveSol: RESERVE,
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
    res.json({ wallet, eligible, balance, chikis, whalePending, whaleReadyInMs, minHold: MIN, verified: verifyOn, firstSeen: Number(p.first_seen), profile: p.profile || null });
  } catch (e) { res.status(500).json({ error: "verify failed: " + String(e.message || e) }); }
});

// Save / load a wallet's game profile (chikis + progress) so it follows the wallet across devices.
app.post("/profile", async (req, res) => {
  const wallet = req.body?.wallet, profile = req.body?.profile;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  if (!profile || typeof profile !== "object") return res.status(400).json({ error: "'profile' object required" });
  profile._serverSavedAt = Date.now();   // authoritative "last seen" for offline progression
  if (JSON.stringify(profile).length > 6000) return res.status(413).json({ error: "profile too large" });
  try { await store.setProfile(wallet, profile); res.json({ ok: true, serverSavedAt: profile._serverSavedAt }); }
  catch (e) { res.status(500).json({ error: "save failed: " + String(e.message || e) }); }
});

app.get("/profile", async (req, res) => {
  const wallet = req.query?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try { res.json({ wallet, profile: await store.getProfile(wallet) }); }
  catch (e) { res.status(500).json({ error: "load failed: " + String(e.message || e) }); }
});

// Live activity: heartbeat in, get back current active users + roaming chikis.
const PRESENCE_WINDOW = 120000;   // a wallet counts as "online" for 2 min after its last beat
app.post("/presence", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });
  try { await store.heartbeat(wallet, Number(req.body?.chikis) || 1, req.body?.roster); res.json(await store.presence(PRESENCE_WINDOW)); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
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
  // Accept a fixed token OR a custom ADMIN_KEY if set. Remove this endpoint before public launch.
  if (k !== "chikiwipe" && !(ADMIN_KEY && k === ADMIN_KEY)) return res.status(403).json({ error: "bad key" });
  try { const n = await store.resetProfiles(); res.json({ ok: true, profilesCleared: n }); }
  catch (e) { res.status(500).json({ error: String(e.message || e) }); }
});

app.post("/claim", async (req, res) => {
  const wallet = req.body?.wallet;
  if (!wallet || !isPubkey(wallet)) return res.status(400).json({ error: "valid 'wallet' required" });

  let bal = 0;
  try { bal = await chikiBalance(wallet); } catch (e) {}
  if (verifyOn && bal < MIN) return res.status(403).json({ error: `below ${MIN.toLocaleString()} $CHIKI threshold`, balance: bal });
  const pRow = await store.touch(wallet, bal >= MIN, bal);
  const chikis = chikiCount(bal, pRow.whale_since) || 1;   // 2nd Chiki only after the whale hold time
  let pool, daily, walletPaid;
  try { pool = await poolSol(); daily = await store.dailyTotal(); walletPaid = await store.walletDaily(wallet); }
  catch (e) { return res.status(500).json({ error: "rpc/db error: " + String(e.message || e) }); }
  if (pool <= RESERVE) return res.status(503).json({ error: "reward pool is low — payouts paused, please try again later", poolSol: pool });
  if (daily >= DAILY_CAP) return res.status(429).json({ error: "daily payout cap reached", dailyCapSol: DAILY_CAP });
  if (WALLET_DAILY > 0 && walletPaid >= WALLET_DAILY) return res.status(429).json({ error: "your daily claim limit is reached — come back tomorrow", perWalletDailySol: WALLET_DAILY });

  const now = Date.now();
  const compute = (p) => {
    const minutes = Math.min((now - Number(p.last_claim)) / 60_000, ACCRUAL_CAP);
    let amt = simEarn(minutes, chikis);   /* rarity-weighted task earnings the server rolled itself */
    amt = Math.min(amt, (CAP > 0 ? CAP : Infinity), Math.max(0, DAILY_CAP - daily), (WALLET_DAILY > 0 ? Math.max(0, WALLET_DAILY - walletPaid) : Infinity), Math.max(0, pool - RESERVE));
    return Math.floor(amt * 1e6) / 1e6;
  };

  let r;
  try { r = await store.reserve(wallet, now, compute); }
  catch (e) { return res.status(500).json({ error: "reserve failed: " + String(e.message || e) }); }
  if (r.status === "cooldown") return res.status(429).json({ error: "cooldown", retryInMs: r.retryInMs });
  if (r.status === "hold") return res.status(403).json({ error: "wallet too new — min hold time not met", waitMs: r.waitMs });
  if (r.status !== "ok") return res.status(409).json({ error: "nothing to claim yet (or pool/cap empty)", poolSol: pool });

  try {
    const tx = new Transaction().add(SystemProgram.transfer({
      fromPubkey: treasury.publicKey, toPubkey: new PublicKey(wallet),
      lamports: Math.floor(r.amount * LAMPORTS_PER_SOL),
    }));
    const sig = await conn.sendTransaction(tx, [treasury]);
    await conn.confirmTransaction(sig, "confirmed");
    await store.confirm(r.payoutId, sig);
    res.json({ ok: true, wallet, amountSol: r.amount, signature: sig,
      explorer: `https://explorer.solana.com/tx/${sig}?cluster=${NETWORK}` });
  } catch (e) {
    await store.fail(r.payoutId, wallet, r.prevLastClaim, r.amount); // refund cooldown so a failed payout isn't lost
    res.status(500).json({ error: "payout failed: " + String(e.message || e) });
  }
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

await store.init();
app.listen(Number(PORT), () => {
  console.log(`Chiki backend v2 on :${PORT} · ${NETWORK} · store=${store.kind} · treasury ${treasury.publicKey.toBase58()}`);
  console.log(`verifyHolders=${verifyOn} · holdMin=${MIN_HOLD_MINUTES} · dailyCap=${DAILY_CAP} SOL`);
});
