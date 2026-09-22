/* The app-account flow, end to end, through the REAL policy layer and the REAL server.
 *
 *   node godot-patch/verify/app-account.e2e.mjs
 *
 * The two suites beside this one test chiki-ios.js in a VM sandbox and index.html by parsing it.
 * Neither can answer the question that actually matters here: does a person who downloads this app,
 * owns no wallet and has never heard of Solana end up playing — and does the account they make stay
 * unable to sell until they connect a wallet?
 *
 * So this boots server.js for real, serves realm/ for real with the isolation headers Cloudflare
 * applies, loads the page in Chromium with the shell's injection, and drives window.CHIK_LINK the
 * way the Swift shell drives it. Both halves are the real thing; only the browser is a stand-in for
 * the WKWebView.
 *
 * The backend is proxied onto the page's own origin, which is not a convenience — chiki-ios.js
 * refuses every host that is not location.host or a named Chikoria backend, and a test that
 * disabled that guard would be testing a policy layer nobody ships.
 */
import { spawn } from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import nacl from '/home/user/backend/node_modules/tweetnacl/nacl-fast.js';
import bs58 from '/home/user/backend/node_modules/bs58/src/esm/index.js';
import pw from '/opt/node22/lib/node_modules/playwright/index.js';

const REALM = '/home/user/chikimonsters/realm';
const { chromium } = pw;

let failures = 0;
const check = (ok, label) => {
	if (ok) { console.log('  ok    ' + label); } else { failures++; console.log('  FAIL  ' + label); }
};

const freePort = async () => {
	const s = net.createServer();
	await new Promise((ok, no) => { s.once('error', no); s.listen(0, '127.0.0.1', ok); });
	const p = s.address().port;
	await new Promise((ok) => s.close(ok));
	return p;
};

const API_PATHS = /^\/(verify|account|link|profile|market|nft|claim|quest|world|health|config|assets|meme|cup|chat)(\/|$)/;

const apiPort = await freePort();
const webPort = await freePort();
const BASE = `http://127.0.0.1:${webPort}`;

// ---- the backend ---------------------------------------------------------------------------
const treasury = nacl.sign.keyPair();
const backend = spawn(process.execPath, ['server.js'], {
	cwd: '/home/user/backend',
	env: {
		...process.env,
		PORT: String(apiPort),
		RPC_URL: 'http://127.0.0.1:59999',
		TREASURY_SECRET: JSON.stringify(Array.from(treasury.secretKey)),
		// The gate is ARMED, or there is no gate here for an app player to be let past. No RPC is
		// reached: chikiBalance returns 0 immediately with CHIKI_MINT unset, so every wallet in
		// this run holds nothing — which is the player the change exists for.
		VERIFY_HOLDERS: 'true',
		MIN_HOLD: '500000',
		CHIKI_MINT: '',
		NETWORK: 'devnet',
		CHIKISEUM_LIVE_ENABLED: '0',
		DATABASE_URL: '',
		RENDER: '',
	},
	stdio: ['ignore', 'pipe', 'pipe'],
});
backend.stdout.on('data', () => {});
backend.stderr.on('data', () => {});
const cleanup = () => { try { backend.kill('SIGKILL'); } catch (e) {} };
process.on('exit', cleanup);

// ---- realm/ on one origin, the backend proxied onto it -------------------------------------
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
	'.wasm': 'application/wasm', '.png': 'image/png', '.css': 'text/css', '.bin': 'application/octet-stream' };

const web = http.createServer((req, res) => {
	const url = new URL(req.url, BASE);
	if (API_PATHS.test(url.pathname)) {
		const chunks = [];
		req.on('data', (c) => chunks.push(c));
		req.on('end', () => {
			const body = Buffer.concat(chunks);
			const up = http.request({
				host: '127.0.0.1', port: apiPort, path: url.pathname + url.search, method: req.method,
				headers: { ...req.headers, host: `127.0.0.1:${apiPort}`, 'content-length': body.length },
			}, (r2) => {
				res.writeHead(r2.statusCode, { ...r2.headers, 'Access-Control-Allow-Origin': '*' });
				r2.pipe(res);
			});
			up.on('error', () => { res.writeHead(502).end('{}'); });
			up.end(body);
		});
		return;
	}
	const file = path.join(REALM, url.pathname === '/' ? 'index.html' : url.pathname.slice(1));
	if (!file.startsWith(REALM) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
		res.writeHead(404).end('no');
		return;
	}
	res.writeHead(200, {
		'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
		'Cross-Origin-Opener-Policy': 'same-origin',
		'Cross-Origin-Embedder-Policy': 'require-corp',
	});
	fs.createReadStream(file).pipe(res);
});
await new Promise((ok) => web.listen(webPort, '127.0.0.1', ok));
await new Promise((ok) => setTimeout(ok, 2500));   // let the backend finish booting

// ---- the app --------------------------------------------------------------------------------
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const ctx = await browser.newContext({
	userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
	viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true,
});
const page = await ctx.newPage();
const persisted = [];
await page.addInitScript(() => {
	// Exactly what ShellModel.installInjection writes, plus the API pin. A real shell pins the
	// live backend; the host here is this page's own origin, which is the one other thing
	// chiki-ios.js's ALLOWED_HOSTS permits.
	window.CHIK_IOS_APP = { v: 1, platform: 'ios', version: '1.0.0', build: '1', keychain: true,
		deviceId: 'e2e-device', active: '', accounts: [], deviceName: 'iPhone' };
	window.CHIK_API = location.origin;
	window.__persists = [];
	window.webkit = { messageHandlers: { chikiLink: { postMessage: (m) => { window.__persists.push(m); } } } };
});
// Stop the 176 MB pack download — this suite is about the policy layer, not the engine, and the
// boot test next door already proves the pack mounts.
await page.route('**/*.bin', (r) => r.abort());
await page.route('**/index.wasm*', (r) => r.abort());
await page.goto(BASE + '/index.html', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForFunction(() => !!window.CHIK_LINK, null, { timeout: 30000 });

console.log('\nthe policy layer is live and says what this build is');
{
	const f = await page.evaluate(() => window.CHIK_FEATURES);
	check(f.platform === 'ios-app', 'CHIK_FEATURES says ios-app');
	check(f.account_create === true, 'account_create is on — the app can make an account');
	check(f.wallet_bind === true, 'wallet_bind is on — it can offer to connect one later');
	check(f.can_sell === false, '*** can_sell is FALSE ***');
	check(f.token_gate === false, '*** token_gate is FALSE — the 500,000 $CHIKI entry gate is off ***');
	check(f.trading_post === false && f.marketplace === false && f.crypto === false, 'and the money surfaces are still off');
	// Every key must exist in BOTH branches: ChikFeat.on() reads a missing key as TRUE, so an
	// omission would read as "on", which for any of these is exactly backwards.
	const webSide = await page.evaluate(() => {
		const src = document.querySelector('script[src*="chiki-ios"]');
		return !!src;
	});
	check(webSide, 'chiki-ios.js is loaded from the page, not inlined by the test');
}

console.log('\nan account is made on the device, with no wallet anywhere');
let made;
{
	made = await page.evaluate(async () => {
		try { return { ok: true, ...(await window.CHIK_LINK.create()) }; }
		catch (e) { return { ok: false, error: String(e && e.message || e) }; }
	});
	check(made.ok === true, `CHIK_LINK.create() succeeds (${made.error || made.wallet})`);
	check(typeof made.wallet === 'string' && made.wallet.length >= 32, 'and yields an account address');
	check(made.walletless === true, 'which it reports as having no wallet');

	const st = await page.evaluate(() => window.CHIK_LINK.status());
	check(st.linked === true && st.wallet === made.wallet, 'status() now reports the account as linked');
	check(st.walletless === true, 'and flags it as one the app made');

	// The shell has to hear about it, or a cold launch comes back signed out.
	const msgs = await page.evaluate(() => window.__persists);
	const persist = msgs.filter((m) => m.kind === 'persist').pop();
	check(!!persist, 'the shell was sent a persist record');
	check(!!persist && persist.accounts.length === 1 && persist.accounts[0].token.length === 64,
		'carrying the device credential');
	check(!!persist && persist.accounts[0].appMade === true,
		'*** and the appMade flag, without which a cold launch forgets it can offer a wallet ***');
	check(msgs.some((m) => m.kind === 'linked' && m.walletless === true), 'and told the account has no wallet');
}

console.log('\nthe server agrees, and the gate is open');
{
	const v = await page.evaluate(async (w) => {
		const r = await fetch(location.origin + '/verify', {
			method: 'POST', headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ wallet: w, authMsg: 'x', authSig: 'CHIKI-LINK-V1' }),
		});
		return await r.json();
	}, made.wallet);
	check(v.signedIn === true, 'a /verify carrying the sentinel is swapped for the credential and signs in');
	check(v.eligible === true, '*** eligible — a player holding nothing is let in ***');
	// And the field the COMPILED PACK reads, which is a different one. Onboarding.gdc recomputes
	// the gate from the balance against its own hardcoded 500,000 and only `gateWaived` overrides
	// it; its identifier table contains `gateWaived` and `waived` but not `eligible`. Setting
	// `eligible` alone would pass every other check in this file and still ship a locked gate.
	check(v.gateWaived === true, '*** gateWaived is set — without it the pack keeps its own gate shut ***');
	check(v.walletless === true && v.canSell === false, 'the server independently says this account cannot sell');
	check(v.app === true, 'and that this is an app session');
}

console.log('\nselling is refused twice over — by the client, and by the server behind it');
{
	// FIRST: the page never even gets to ask. chiki-ios.js refuses the route inside window.fetch,
	// so the compiled pack's own HTTPRequest cannot reach it however it is called.
	const client = await page.evaluate(async (w) => {
		try {
			await fetch(location.origin + '/market/op', {
				method: 'POST', headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ wallet: w, op: 'list', listing: { id: 'l1' } }),
			});
			return { refused: false };
		} catch (e) { return { refused: true, message: String(e && e.message || e) }; }
	}, made.wallet);
	check(client.refused === true, 'the client guard refuses /market/op before it reaches the network');
	check(!/app ?store|buy|purchase|phantom\.app|magic ?eden/i.test(client.message || ''),
		'naming no outside destination');

	// SECOND, and this is the half that matters: a client is a client. Ask the server directly,
	// the way someone not using our app would, carrying this account's real credential. The token
	// comes from the persist record, because CHIK_LINK.create() deliberately does not hand it back
	// to its caller — only the shell, on its way to the Keychain, ever sees it.
	const token = await page.evaluate(() =>
		(window.__persists.filter((m) => m.kind === 'persist').pop() || { accounts: [{}] }).accounts[0].token);
	check(typeof token === 'string' && token.length === 64, 'the credential exists and is 64 characters');
	const v = await (await fetch(`http://127.0.0.1:${apiPort}/verify`, {
		method: 'POST', headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ wallet: made.wallet, linkToken: token, device_id: 'e2e-device' }),
	})).json();
	check(v.signedIn === true, 'the credential signs in when used straight against the API');
	for (const p of ['/market/op', '/claim', '/nft/market/list', '/assets/nft/mint', '/cup/register']) {
		const r = await fetch(`http://127.0.0.1:${apiPort}${p}`, {
			method: 'POST', headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ wallet: made.wallet, mktToken: v.mktToken, id: 'x' }),
		});
		check(r.status === 403, `  ${p} is refused by the server too`);
	}
}

console.log('\nthe app asks for a code to connect a wallet');
let code;
{
	const got = await page.evaluate(async () => {
		try { return { ok: true, ...(await window.CHIK_LINK.claim()) }; }
		catch (e) { return { ok: false, error: String(e && e.message || e) }; }
	});
	check(got.ok === true && /^[A-Z0-9]{8}$/.test(got.code || ''), `CHIK_LINK.claim() mints a code (${got.code})`);
	code = got.code;
}

console.log('\nthe wallet claims it on the website');
let owner;
{
	const kp = nacl.sign.keyPair();
	const wallet = bs58.encode(kp.publicKey);
	const authMsg = `Chikoria sign-in\nwallet:${wallet}\nts:${Date.now()}`;
	const authSig = Buffer.from(nacl.sign.detached(Buffer.from(authMsg, 'utf8'), kp.secretKey)).toString('base64');
	owner = { wallet, authMsg, authSig };

	const r = await fetch(`http://127.0.0.1:${apiPort}/link/bind`, {
		method: 'POST', headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ wallet, authMsg, authSig, code }),
	});
	const body = await r.json();
	check(r.status === 200 && body.ok === true, '/link/bind accepts a signed wallet');
	check(body.from === made.wallet && body.to === wallet, 'and moves the account onto it');
}

console.log('\n*** and the phone catches up on its own, without re-pairing ***');
{
	// The device still believes its address is the retired one. This is the next /verify it makes.
	const v = await page.evaluate(async (w) => {
		const r = await fetch(location.origin + '/verify', {
			method: 'POST', headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ wallet: w, authMsg: 'x', authSig: 'CHIKI-LINK-V1' }),
		});
		return await r.json();
	}, made.wallet);
	check(v.signedIn === true, 'it is signed in, not bounced to a sign-in screen');
	check(v.wallet === owner.wallet, 'at the new address');
	check(v.movedFrom === made.wallet, 'and told where it moved from');
	check(v.walletless === undefined, 'the account is no longer walletless');

	await page.waitForFunction((want) => window.CHIK_LINK.status().wallet === want, owner.wallet, { timeout: 5000 })
		.then(() => check(true, 'the policy layer re-stamped the stored account to the new address'))
		.catch(() => check(false, 'the policy layer re-stamped the stored account to the new address'));

	const st = await page.evaluate(() => window.CHIK_LINK.status());
	check(st.walletless === false, 'and stopped calling it walletless');
	check(st.linked === true, 'while staying linked — the credential never changed');

	const msgs = await page.evaluate(() => window.__persists);
	const persist = msgs.filter((m) => m.kind === 'persist').pop();
	check(!!persist && persist.accounts[0].wallet === owner.wallet, 'the shell was handed the new address');
	check(!!persist && !persist.accounts[0].appMade, 'with appMade cleared, so Account stops offering a wallet');
	check(msgs.some((m) => m.kind === 'rebound'), 'and told what happened');
}

await browser.close();
web.close();
cleanup();
console.log(failures === 0 ? `\nAll checks passed.\n` : `\n${failures} check(s) FAILED.\n`);
process.exit(failures === 0 ? 0 : 1);
