/* Drives realm/chiki-ios.js in a stubbed browser, so the policy layer is checked rather than
 * merely written. It proves the guard's shape and logic — it cannot prove WKWebView behaviour,
 * which needs a device build.
 *
 * Run:
 *   node godot-patch/verify/chiki-ios.test.mjs        # exits non-zero on any failure
 */
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(HERE, '..', '..', 'realm', 'chiki-ios.js'), 'utf8');

let failures = 0;
function check(ok, label) {
	if (ok) { console.log('  ok    ' + label); }
	else { failures++; console.log('  FAIL  ' + label); }
}

/** A browser just real enough for the file under test. Returns the sandbox plus the call log. */
function boot({ app = null, search = '', store = {} } = {}) {
	const calls = [];
	const localStore = { ...store };
	const sessionStore = {};
	const mem = (s) => ({
		getItem: (k) => (k in s ? s[k] : null),
		setItem: (k, v) => { s[k] = String(v); },
		removeItem: (k) => { delete s[k]; },
	});

	const realFetch = (input, init) => {
		calls.push({ url: typeof input === 'string' ? input : input.url, init });
		return Promise.resolve({
			ok: true, status: 200,
			json: () => Promise.resolve({ wallet: 'WalletB', linkToken: 'tok-B', label: 'Ledger' }),
		});
	};

	const win = {
		location: { host: 'chikimonsters.com', href: 'https://chikimonsters.com/realm/', search, reload: () => { calls.push({ reload: true }); } },
		localStorage: mem(localStore),
		sessionStorage: mem(sessionStore),
		fetch: realFetch,
		console,
		URL, TextEncoder, TextDecoder, Promise, Object, Array, JSON, Date, Math, String, Number, RegExp, Error,
		ArrayBuffer, Uint8Array,
		crypto: { randomUUID: () => 'uuid-fixed' },
		document: { dispatchEvent: () => {} },
		CustomEvent: class { constructor(t, o) { this.type = t; Object.assign(this, o); } },
		WebSocket: class { constructor(u) { this.url = u; } },
		XMLHttpRequest: class {
			open(m, u) { this._m = m; this._u = u; }
			send(b) { calls.push({ xhr: this._u, body: b }); }
		},
	};
	if (app) { win.CHIK_IOS_APP = app; }
	win.window = win;
	win.self = win;
	createContext(win);
	runInContext(SRC, win);
	return { win, calls, localStore, sessionStore, realFetch };
}

const dec = (b) => (typeof b === 'string' ? b : new TextDecoder().decode(b));

console.log('\nweb mode — the site is untouched');
{
	const { win } = boot();
	check(win.CHIK_NO_CRYPTO === false, 'CHIK_NO_CRYPTO is false');
	check(win.CHIK_FEATURES.crypto === true, 'crypto stays on');
	check(win.CHIK_FEATURES.trading_post === true, 'the Trading Post stays on');
	check(win.CHIK_FEATURES.pvp_mode === 'wager', 'PvP keeps SOL wagers');
	check(win.CHIK_LINK === undefined, 'no Realm Link object is installed');
	check(win.__chikiBuy === undefined, 'the real __chikiBuy is left for index.html to define');
}

console.log('\napp mode — the feature policy');
{
	const { win } = boot({ app: {} });
	const f = win.CHIK_FEATURES;
	check(win.CHIK_NO_CRYPTO === true, 'CHIK_NO_CRYPTO is true');
	check(f.platform === 'ios-app' && f.account === 'link', 'platform and account name the app');
	check(f.crypto === false && f.wallet_connect === false, 'crypto and wallet connect are off');
	check(f.trading_post === false && f.marketplace === false, 'both markets are off');
	check(f.wagers === false && f.pvp_mode === 'season', 'wagers are off, PvP is the season match');
	check(f.token_gate === false && f.token_purchase === false, 'no token gate, no token purchase');
	check(f.gathering && f.wicked_temple && f.chikiseum_pvp && f.hatching && f.fishing,
		'gathering, the temple, PvP, hatching and fishing are all on');
	check(f.cloud_sync === true, 'the cloud save is on — this is the same account as the website');
	// Earning is not switched off: the app pays out the REAL assets onto the linked account.
	// Only selling and trading are website-only, which is what trading_post/marketplace cover.
	check(f.asset_rewards === true, 'EARNING real assets stays on — only selling is website-only');
}

console.log('\napp mode — ?nocrypto=1 reviews the policy without claiming to be the app');
{
	const { win } = boot({ search: '?nocrypto=1' });
	check(win.CHIK_NO_CRYPTO === true, 'the policy turns on');
	check(win.CHIK_IOS_APP === undefined, 'CHIK_IOS_APP is NOT set (it also picks the HD pack)');
}

console.log('\napp mode — the network guard');
{
	const { win } = boot({ app: {} });
	const rejects = async (url) => {
		try { await win.fetch(url); return false; } catch (e) { return true; }
	};
	const resolves = async (url) => {
		try { await win.fetch(url); return true; } catch (e) { return false; }
	};
	check(await rejects('https://api.mainnet-beta.solana.com'), 'a Solana RPC node is refused');
	check(await rejects('https://api-mainnet.magiceden.dev/v2/instructions/buy_now'), 'Magic Eden is refused');
	check(await rejects('https://unpkg.com/@solana/web3.js'), 'a CDN that could ship a wallet lib is refused');
	check(await rejects('https://api.chikimonsters.com/chikiseum/live/v1/wager_post'), 'wager_post is refused by name');
	check(await rejects('https://api.chikimonsters.com/chikiseum/live/v1/wager_deposit'), 'wager_deposit is refused by name');
	check(await resolves('https://api.chikimonsters.com/chikiseum/live/v1/lobby'), 'the arena lobby is allowed');
	check(await resolves('https://api.chikimonsters.com/chikiseum/live/v1/season_queue'), 'the season match is allowed');
	check(await resolves('https://chiki-backend-singapore.onrender.com/verify'), 'the backend is allowed');
	check(await resolves('index.pck.0.bin'), 'same-origin pack chunks are allowed');
	check(await resolves('blob:https://chikimonsters.com/abc'), 'blob URLs are allowed');
	check(win.CHIK_POLICY_BLOCKED.length === 5, 'every refusal is recorded for QA (got ' + win.CHIK_POLICY_BLOCKED.length + ')');

	let threw = false;
	try { const x = new win.XMLHttpRequest(); x.open('POST', 'https://api.mainnet-beta.solana.com'); }
	catch (e) { threw = true; }
	check(threw, 'XMLHttpRequest is guarded too');

	let wsThrew = false;
	try { new win.WebSocket('wss://api.mainnet-beta.solana.com'); } catch (e) { wsThrew = true; }
	check(wsThrew, 'WebSocket is guarded too');
}

console.log('\napp mode — there is no wallet');
{
	const { win } = boot({ app: {} });
	check(win.solana === undefined, 'window.solana is undefined');
	check(win.phantom === undefined, 'window.phantom is undefined');
	runInContext('window.solana = { connect: function () {} };', win);
	check(win.solana === undefined, 'a provider injected later cannot install itself');
	check(win.SolanaWeb3 === undefined && win.SplToken === undefined, 'the web3 library globals are gone');
}

console.log('\napp mode — the trading bridges refuse instead of hanging');
{
	const { win } = boot({ app: {} });
	await win.__chikiBuy('seller', 'team', 'mint', 1, 6, 'rpc', 0.75, 0.2, 0.05);
	check(win.__chikiBuyDone === '1', 'the buy poller is released');
	check(win.__chikiBuySig === '', 'no signature is reported');
	check(/chikimonsters\.com/.test(win.__chikiBuyErr), 'the player is told where trading lives');
	check(/already yours/.test(win.__chikiBuyErr),
		'and is not told their prizes are fake — only that selling happens on the website');

	await win.__chikiMeSign('AAAA');
	check(win.__chikiMeDone === '1', 'the marketplace poller is released');
	check(win.__chikiMeCode === 'no_wallet', 'it reports a code the pack already branches on');
	check(win.__chikiMeSig === '' && win.__chikiMeRejected === '', 'no signature, and not framed as a player cancel');
	const probe = JSON.parse(win.__chikiMeReady());
	check(probe.ok === false && probe.phantom === false && probe.reason === 'ios_app', 'the capability probe answers honestly');
}

console.log('\napp mode — Realm Link signs in without a wallet');
{
	const { win, calls, sessionStore } = boot({ app: {} });
	check(win.CHIK_LINK.status().linked === false, 'a fresh device is not linked');

	win.CHIK_LINK.setToken('WalletA', 'tok-A', 'Phantom');
	const st = win.CHIK_LINK.status();
	check(st.linked === true && st.wallet === 'WalletA', 'the account is adopted');
	check(JSON.stringify(st).indexOf('tok-A') < 0, 'status() NEVER reports the token');

	win.__chikSigninSeedResume();
	const resume = JSON.parse(sessionStore.chikResume);
	check(resume.a === 'WalletA', 'the resume names the wallet Chain.gd should load');
	check(resume.s === 'CHIKI-LINK-V1', 'the signature slot holds the sentinel, not a signature');
	check(JSON.stringify(resume).indexOf('tok-A') < 0, 'the token is NOT in sessionStorage — the pack cannot read it');

	calls.length = 0;
	await win.fetch('https://api.chikimonsters.com/verify', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ wallet: 'WalletA', authMsg: resume.m, authSig: resume.s }),
	});
	const sent = JSON.parse(dec(calls[0].init.body));
	check(sent.linkToken === 'tok-A', 'the sentinel is swapped for the device token on the way out');
	check(sent.authSig === undefined && sent.authMsg === undefined, 'no signature fields are sent');
	check(sent.wallet === 'WalletA' && sent.client === 'ios-app', 'the wallet and client are carried');
	check(typeof sent.device_id === 'string' && sent.device_id.length > 0, 'the device names itself so it can be revoked');
	check(calls[0].init.headers['Content-Type'] === 'application/json', 'the rest of the request is untouched');
}

console.log('\napp mode — the rewrite is narrow');
{
	const { win, calls } = boot({ app: {} });
	win.CHIK_LINK.setToken('WalletA', 'tok-A', '');

	await win.fetch('https://api.chikimonsters.com/verify', {
		method: 'POST', body: JSON.stringify({ wallet: 'WalletA', authMsg: 'real', authSig: 'a-real-88-char-signature' }),
	});
	const real = JSON.parse(dec(calls[0].init.body));
	check(real.authSig === 'a-real-88-char-signature' && real.linkToken === undefined,
		'a genuine signature is left completely alone');

	calls.length = 0;
	await win.fetch('https://api.chikimonsters.com/chikiseum/live/v1/roster', {
		method: 'POST', body: JSON.stringify({ authSig: 'CHIKI-LINK-V1' }),
	});
	check(dec(calls[0].init.body).indexOf('tok-A') < 0, 'the token is only ever attached to /verify');

	calls.length = 0;
	const bytes = new TextEncoder().encode(JSON.stringify({ wallet: 'WalletA', authSig: 'CHIKI-LINK-V1' }));
	await win.fetch('https://api.chikimonsters.com/verify', { method: 'POST', body: bytes });
	check(JSON.parse(dec(calls[0].init.body)).linkToken === 'tok-A', "Godot's byte-array body is rewritten too");
	check(typeof calls[0].init.body !== 'string', 'and it stays a byte array');
}

console.log('\napp mode — every wallet, one device');
{
	const { win, calls } = boot({ app: {} });
	win.CHIK_LINK.setToken('WalletA', 'tok-A', 'Phantom');
	await win.CHIK_LINK.redeem('abcd-1234');                       // a second wallet, from a code
	const st = win.CHIK_LINK.status();
	check(st.accounts.length === 2, 'both wallets are held on the device');
	check(st.wallet === 'WalletB', 'the newest link becomes the active account');
	check(JSON.stringify(st).indexOf('tok-') < 0, 'no token is exposed by the account list');

	const redeemCall = calls.find((c) => /\/link\/redeem$/.test(c.url || ''));
	check(!!redeemCall, 'redeem posts to /link/redeem');
	check(JSON.parse(redeemCall.init.body).code === 'ABCD1234', 'the code is normalised before it is sent');
	check(/^https:\/\/api\.chikimonsters\.com\//.test(redeemCall.url), 'to the default backend base');

	check(win.CHIK_LINK.use('WalletA') === true, 'the player can switch back to the first wallet');
	check(win.CHIK_LINK.status().wallet === 'WalletA', 'the switch takes effect');
	check(calls.some((c) => c.reload), 'switching reloads, which is how the web switches wallets');
	check(win.CHIK_LINK.use('WalletNeverLinked') === false, 'an unknown wallet cannot be selected');

	await win.CHIK_LINK.forget('WalletA');
	check(win.CHIK_LINK.status().accounts.length === 1, 'forgetting drops it from the device');
	check(calls.some((c) => /\/link\/revoke$/.test(c.url || '')), 'and tells the server to kill the token');
}

console.log('\napp mode — the shell can pin which backend to pair against');
{
	const { win, calls } = boot({ app: {} });
	win.CHIK_API = 'https://chiki-backend-singapore.onrender.com';
	await win.CHIK_LINK.redeem('ABCD1234');
	check(/onrender\.com\/link\/redeem$/.test(calls.find((c) => /redeem/.test(c.url || '')).url),
		'CHIK_API redirects pairing to the other live base');

	const { win: w2, calls: c2 } = boot({ app: {} });
	w2.CHIK_API = 'https://evil.example.com';
	await w2.CHIK_LINK.redeem('ABCD1234');
	check(/api\.chikimonsters\.com\/link\/redeem$/.test(c2.find((c) => /redeem/.test(c.url || '')).url),
		'but a base outside the allowlist is ignored, not trusted');
}

console.log('\napp mode — a Keychain token handed in by the shell');
{
	const { win } = boot({ app: { wallet: 'WalletK', linkToken: 'tok-K', deviceName: 'iPhone 17' } });
	check(win.CHIK_LINK.status().wallet === 'WalletK', 'the shell can restore a link after a data purge');
	check(!win.CHIK_IOS_APP.linkToken, 'the token is stripped off the injected object so the pack cannot read it');
}

console.log('\nno link yet — the game is not told to resume');
{
	const { win, sessionStore } = boot({ app: {} });
	win.__chikSigninSeedResume();
	check(sessionStore.chikResume === undefined, 'an unlinked device seeds nothing, so the app shows pairing');
}

console.log(failures === 0 ? '\nAll checks passed.\n' : '\n' + failures + ' check(s) FAILED.\n');
process.exit(failures === 0 ? 0 : 1);
