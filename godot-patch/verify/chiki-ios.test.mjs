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
function boot({ app = null, search = '', store = {}, responder = null, handler = null } = {}) {
	const calls = [];
	const localStore = { ...store };
	const sessionStore = {};
	const mem = (s) => ({
		getItem: (k) => (k in s ? s[k] : null),
		setItem: (k, v) => { s[k] = String(v); },
		removeItem: (k) => { delete s[k]; },
	});

	// `responder` lets a test decide what the network says back; the default is a redeem success.
	const realFetch = (input, init) => {
		const url = typeof input === 'string' ? input : input.url;
		calls.push({ url, init });
		const r = responder ? responder(url, init) : null;
		const body = r ? r.body : { wallet: 'WalletB', linkToken: 'tok-B', label: 'Ledger' };
		const status = r ? r.status : 200;
		const res = {
			ok: status >= 200 && status < 300,
			status,
			json: () => Promise.resolve(body),
			clone: () => res,
		};
		return Promise.resolve(res);
	};

	// Everything the page posts to the native side, in order. This is the shell's whole view.
	const toShell = [];
	// Capture-phase listeners the policy installs, so a test can fire a click or submit at them.
	const listeners = { click: [], submit: [] };

	const win = {
		location: {
			host: 'chikimonsters.com',
			href: 'https://chikimonsters.com/realm/',
			pathname: '/realm/',
			search,
			reload: () => { calls.push({ reload: true }); },
		},
		localStorage: mem(localStore),
		sessionStorage: mem(sessionStore),
		fetch: realFetch,
		console,
		URL, TextEncoder, TextDecoder, Promise, Object, Array, JSON, Date, Math, String, Number, RegExp, Error,
		ArrayBuffer, Uint8Array,
		crypto: { randomUUID: () => 'uuid-fixed' },
		Response: class {
			constructor(body, init) { this._b = body; this.status = (init && init.status) || 200; this.ok = this.status < 300; }
			json() { return Promise.resolve(JSON.parse(this._b)); }
			text() { return Promise.resolve(this._b); }
		},
		document: {
			dispatchEvent: () => {},
			addEventListener: (type, fn, capture) => {
				if (listeners[type]) { listeners[type].push({ fn, capture }); }
			},
		},
		CustomEvent: class { constructor(t, o) { this.type = t; Object.assign(this, o); } },
		WebSocket: class { constructor(u) { this.url = u; } },
		EventSource: class { constructor(u) { this.url = u; } },
		// `language` matches what the policy fell back to before this stub existed, so the language
		// tests are unaffected; no `connection` key, so metered detection is unaffected too.
		navigator: {
			language: 'en-US',
			sendBeacon: (url, data) => { calls.push({ beacon: url, data }); return true; },
		},
		open: (url) => { calls.push({ opened: url }); return { closed: false }; },
		webkit: { messageHandlers: { chikiLink: { postMessage: (m) => { toShell.push(m); } } } },
		XMLHttpRequest: class {
			open(m, u) { this._m = m; this._u = u; this._on = {}; }
			addEventListener(t, fn) { (this._on[t] = this._on[t] || []).push(fn); }
			send(b) { calls.push({ xhr: this._u, body: b }); }
			// Let a test drive the response the policy's rejection watch reads.
			respond(status, body) {
				this.status = status;
				this.responseText = JSON.stringify(body);
				(this._on.load || []).forEach((fn) => fn.call(this));
			}
		},
	};
	if (app) { win.CHIK_IOS_APP = app; }
	if (handler === false) { delete win.webkit; }     // a shell-less browser
	win.window = win;
	win.self = win;
	createContext(win);
	runInContext(SRC, win);
	return { win, calls, localStore, sessionStore, realFetch, toShell, listeners };
}

/** Fire a synthetic anchor click at the capture-phase guard. Returns true if it was cancelled. */
function clickLink(boot, href) {
	let prevented = false;
	const ev = {
		target: { nodeName: 'A', getAttribute: () => href, href, parentNode: null },
		preventDefault: () => { prevented = true; },
		stopPropagation: () => {},
	};
	boot.listeners.click.forEach((l) => l.fn(ev));
	return prevented;
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

	// CHAT. The game has world chat, party chat and whispers between strangers; the backend has a
	// profanity filter but no report route and no block route, which is two of guideline 1.2's
	// four. The Godot project is gone, so the missing two cannot be built — the app ships without
	// chat instead. These are the real backend routes, read from server.js.
	check(await rejects('https://api.chikimonsters.com/chat/send'), 'posting a chat message is refused');
	check(await rejects('https://api.chikimonsters.com/chat'), 'reading world chat is refused');
	check(await rejects('https://api.chikimonsters.com/chat/react'), '/chat/react is refused');
	check(await rejects('https://api.chikimonsters.com/chat/pin'), '/chat/pin is refused');
	check(await rejects('https://api.chikimonsters.com/chat/online'), '/chat/online is refused');
	check(await rejects('https://api.chikimonsters.com/world/chat'), '/world/chat is refused');
	check(await rejects('https://api.chikimonsters.com/cup/chat'), '/cup/chat is refused');

	// …and NOT the world itself. Chat is plain HTTP while the WebSocket carries only /world/move,
	// so taking chat away leaves movement, presence and the rest of the game working.
	check(await resolves('https://api.chikimonsters.com/world/move'), 'player movement still works');
	check(await resolves('https://api.chikimonsters.com/world/state'), 'the world still works');
	check(await resolves('https://api.chikimonsters.com/chatter'), 'a route merely starting with "chat" is not caught');
	check(await resolves('https://api.chikimonsters.com/chikiseum/live/v1/lobby'), 'the arena lobby is allowed');
	check(await resolves('https://api.chikimonsters.com/chikiseum/live/v1/season_queue'), 'the season match is allowed');
	check(await resolves('https://chiki-backend-singapore.onrender.com/verify'), 'the backend is allowed');
	check(await resolves('index.pck.0.bin'), 'same-origin pack chunks are allowed');
	check(await resolves('blob:https://chikimonsters.com/abc'), 'blob URLs are allowed');
	check(win.CHIK_POLICY_BLOCKED.length === 12, 'every refusal is recorded for QA (got ' + win.CHIK_POLICY_BLOCKED.length + ')');

	let threw = false;
	try { const x = new win.XMLHttpRequest(); x.open('POST', 'https://api.mainnet-beta.solana.com'); }
	catch (e) { threw = true; }
	check(threw, 'XMLHttpRequest is guarded too');

	let wsThrew = false;
	try { new win.WebSocket('wss://api.mainnet-beta.solana.com'); } catch (e) { wsThrew = true; }
	check(wsThrew, 'WebSocket is guarded too');
}

console.log('\napp mode — the navigation guard (the engine hands the pack window.open)');
{
	const b = boot({ app: {} });
	const { win, calls } = b;

	win.open('https://magiceden.io/item/abc');
	check(!calls.some((c) => c.opened), 'window.open to a marketplace opens nothing');
	win.open('phantom://v1/connect');
	check(!calls.some((c) => c.opened), 'a wallet deep link opens nothing');
	// The dangerous same-origin case: /arena/ is the full SOL wager client and loads no policy.
	win.open('https://chikimonsters.com/arena/');
	check(!calls.some((c) => c.opened), 'SAME-ORIGIN /arena/ is refused too — only the realm is safe');
	win.open('https://chikimonsters.com/link/');
	check(!calls.some((c) => c.opened), 'and /link/, which carries a Phantom sign-in');
	win.open('https://chikimonsters.com/realm/?x=1');
	check(calls.some((c) => c.opened), 'inside the realm still opens');

	check(clickLink(b, 'https://magiceden.io/x'), 'an anchor to a marketplace is cancelled');
	check(clickLink(b, 'https://chikimonsters.com/arena/'), 'an anchor to /arena/ is cancelled');
	check(clickLink(b, 'https://solscan.io/token/abc'), 'an anchor to an explorer is cancelled');
	check(!clickLink(b, '#tab'), 'an in-page anchor is left alone');
	check(!clickLink(b, '/realm/index.html'), 'an anchor inside the realm is left alone');

	// The community links are legitimate, but they go to Safari via the shell, not in-app.
	const before = b.toShell.length;
	check(clickLink(b, 'https://discord.gg/J8Yf7jm2'), 'the Discord link is intercepted');
	const ext = b.toShell.slice(before).find((m) => m.kind === 'external-link');
	check(!!ext && /discord\.gg/.test(ext.url), 'and handed to the shell to open outside the app');

	let esThrew = false;
	try { new win.EventSource('https://api.mainnet-beta.solana.com/sse'); } catch (e) { esThrew = true; }
	check(esThrew, 'EventSource is guarded — §3 claimed this before it was true');
}

console.log('\napp mode — the HD pack is opt-in, and only the shell can grant it');
{
	// Measured on a real iPhone: the 313MB HD pack runs the device out of memory. The app used to
	// take it unconditionally. Default must now be "no".
	const plain = boot({ app: {} });
	check(plain.win.CHIK_HD === false, 'an app that says nothing gets the lite pack');

	const granted = boot({ app: { hd: true } });
	check(granted.win.CHIK_HD === true, 'a shell that has checked physical memory can grant HD');

	// Anything other than a literal true is a no. A shell sending a string, a number or an
	// object must not accidentally opt a 4GB phone into a pack that kills it.
	for (const value of ['true', 1, {}, 'yes', null]) {
		const b = boot({ app: { hd: value } });
		if (b.win.CHIK_HD !== false) { check(false, 'hd: ' + JSON.stringify(value) + ' must not grant HD'); }
	}
	check(true, 'only a literal true grants it — no truthy strings, numbers or objects');

	const web = boot();
	check(web.CHIK_HD === undefined, 'the website is untouched by any of this');
}

console.log('\napp mode — the in-game news feed is filtered');
{
	const feed = [
		{ title: 'Trading Post receipts', body: 'Sales land on Solscan.' },
		{ title: 'Magic Eden header', body: 'crisp and full-size' },
		{ title: 'Hold to play', body: 'Hold 500,000 $CHIKI to enter.' },
		{ title: 'Wicked Temple', body: 'Five sanctums and a Treasure Vault.' },
		{ title: 'Fishing', body: '44 named spots around the isle.' },
	];
	const { win } = boot({ app: {}, responder: (url) => (/updates\.json/.test(url) ? { status: 200, body: feed } : null) });
	const res = await win.fetch('updates.json');
	const out = await res.json();
	check(out.length === 2, 'the three money entries are dropped (kept ' + out.length + ')');
	check(out.every((e) => !/Trading Post|Magic Eden|\$CHIKI/.test(e.title + e.body)), 'nothing sells a surface the app refuses');
	check(out.some((e) => e.title === 'Wicked Temple') && out.some((e) => e.title === 'Fishing'),
		'and the gameplay entries survive');
}

console.log('\nweb mode — the news feed is NOT filtered');
{
	const feed = [{ title: 'Trading Post', body: 'Sales land on Solscan.' }];
	const { win } = boot({ responder: (url) => (/updates\.json/.test(url) ? { status: 200, body: feed } : null) });
	const out = await (await win.fetch('updates.json')).json();
	check(out.length === 1, 'the website keeps its own release notes');
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
	// The wording itself is asserted in the 3.1.1 section below; here only that it says something.
	check(win.__chikiBuyErr.length > 20, 'the player is given a real explanation, not an empty error');

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

console.log('\napp mode — the shell owns the credential (no plaintext localStorage)');
{
	const { win, localStore, toShell } = boot({ app: { keychain: true, deviceId: 'dev-from-keychain' } });
	win.CHIK_LINK.setToken('WalletA', 'tok-A', 'Phantom');

	check(JSON.stringify(localStore).indexOf('tok-A') < 0,
		'the token is NOT written to localStorage when the shell holds it');
	check(localStore.chikLinkAccounts === undefined, 'no account store is left on disk at all');
	check(win.CHIK_LINK.status().wallet === 'WalletA', 'but the page still has it, in memory');

	const persist = toShell.filter((m) => m.kind === 'persist').pop();
	check(!!persist, 'every change is pushed to the shell to write to the Keychain');
	check(persist.accounts[0].token === 'tok-A', 'the record carries the token the shell must store');
	check(persist.deviceId === 'dev-from-keychain',
		'and the device id, because the token is bound to it server-side');
	check(win.CHIK_LINK.deviceId() === 'dev-from-keychain', 'the injected device id wins over a fresh one');
}

console.log('\napp mode — the full credential set restores from the Keychain');
{
	const { win } = boot({ app: {
		keychain: true,
		deviceId: 'dev-1',
		active: 'WalletB',
		accounts: [
			{ wallet: 'WalletA', token: 'tok-A', label: 'Phantom', linkedAt: 1 },
			{ wallet: 'WalletB', token: 'tok-B', label: 'Ledger', linkedAt: 2 },
		],
	} });
	const st = win.CHIK_LINK.status();
	check(st.accounts.length === 2, 'both accounts come back');
	check(st.wallet === 'WalletB', 'and the one that was active');
	check(!win.CHIK_IOS_APP.accounts, 'the injected copy is stripped so the pack cannot read the tokens');
	win.__chikSigninSeedResume();
	check(JSON.parse(win.sessionStorage.getItem('chikResume')).a === 'WalletB', 'sign-in resumes that account');
}

console.log('\nno shell — localStorage is still the fallback');
{
	const { win, localStore } = boot({ app: {} });          // no keychain flag
	win.CHIK_LINK.setToken('WalletA', 'tok-A', '');
	check(localStore.chikLinkAccounts !== undefined,
		'without a shell to hold it, the link survives a reload the only way it can');
	check(win.CHIK_LINK.status().wallet === 'WalletA', 'and works');
}

console.log('\napp mode — a rejected link token is a recoverable state, not a dead screen');
{
	const { win, toShell, sessionStore } = boot({
		app: { keychain: true },
		responder: (url) => (/\/verify$/.test(url) ? { status: 401, body: { error: 'revoked' } } : null),
	});
	win.CHIK_LINK.setToken('WalletA', 'tok-A', '');
	win.__chikSigninSeedResume();
	check(sessionStore.chikResume !== undefined, 'the resume is seeded');

	await win.fetch('https://api.chikimonsters.com/verify', {
		method: 'POST', body: JSON.stringify({ wallet: 'WalletA', authSig: 'CHIKI-LINK-V1' }),
	});
	await new Promise((r) => setImmediate(r));

	check(win.CHIK_LINK.status().linked === false, 'the dead token is dropped, not retried forever');
	check(sessionStore.chikResume === undefined, 'the stale resume is cleared');
	const ev = toShell.filter((m) => m.kind === 'link-rejected').pop();
	check(!!ev, 'the shell is told, so it can show pairing instead of a dead screen');
	const persisted = toShell.filter((m) => m.kind === 'persist').pop();
	check(persisted.accounts.length === 0, 'and told to clear the Keychain');
}

console.log('\napp mode — a 200 that does not say signedIn is also a rejection');
{
	const { win, toShell } = boot({
		app: { keychain: true },
		responder: (url) => (/\/verify$/.test(url) ? { status: 200, body: { signedIn: false, code: 'DEVICE_REVOKED' } } : null),
	});
	win.CHIK_LINK.setToken('WalletA', 'tok-A', '');
	await win.fetch('https://api.chikimonsters.com/verify', {
		method: 'POST', body: JSON.stringify({ wallet: 'WalletA', authSig: 'CHIKI-LINK-V1' }),
	});
	await new Promise((r) => setImmediate(r));
	const ev = toShell.filter((m) => m.kind === 'link-rejected').pop();
	check(!!ev && ev.reason === 'DEVICE_REVOKED', "the server's code is carried through");
}

console.log('\napp mode — a 5xx is NOT treated as a dead token');
{
	const { win, toShell } = boot({
		app: { keychain: true },
		responder: (url) => (/\/verify$/.test(url) ? { status: 503, body: {} } : null),
	});
	win.CHIK_LINK.setToken('WalletA', 'tok-A', '');
	await win.fetch('https://api.chikimonsters.com/verify', {
		method: 'POST', body: JSON.stringify({ wallet: 'WalletA', authSig: 'CHIKI-LINK-V1' }),
	});
	await new Promise((r) => setImmediate(r));
	check(win.CHIK_LINK.status().linked === true, 'a backend having a bad day does not unlink the player');
	check(!toShell.some((m) => m.kind === 'link-rejected'), 'and the shell is not told to re-pair');
}

console.log('\napp mode — the shell version handshake and the maintenance switch');
{
	const { toShell } = boot({ app: { version: '0.9.0' } });
	check(toShell.some((m) => m.kind === 'stale-shell'), 'a shell below the minimum is told to update');

	const b2 = boot({ app: { version: '1.0.0' } });
	check(!b2.toShell.some((m) => m.kind === 'stale-shell'), 'a current shell is not');

	const b3 = boot({ app: { version: '1.0.0' } });
	b3.win.CHIK_LINK_CONFIG({ paused: true, message: 'Back in ten minutes.' });
	const paused = b3.toShell.filter((m) => m.kind === 'paused').pop();
	check(!!paused && paused.message === 'Back in ten minutes.',
		'the server can pause the app without an App Store release');

	const b4 = boot({ app: { version: '1.0.0' } });
	b4.win.CHIK_LINK_CONFIG({ min_shell: '2.0.0' });
	check(b4.toShell.some((m) => m.kind === 'stale-shell'), 'and can raise the floor on a shipped binary');
}

console.log('\napp mode — the refusal copy does not steer to an outside store (3.1.1)');
{
	const { win } = boot({ app: {} });
	await win.__chikiBuy();
	check(!/chikimonsters\.com|website/i.test(win.__chikiBuyErr),
		'the refusal names no outside destination');
	check(/not available in the app/i.test(win.__chikiBuyErr), 'it states the fact');
	check(/yours to keep/i.test(win.__chikiBuyErr), 'without implying the prizes are fake');
}

console.log('\napp mode — a Keychain token handed in by the shell');
{
	const { win } = boot({ app: { wallet: 'WalletK', linkToken: 'tok-K', deviceName: 'iPhone 17' } });
	check(win.CHIK_LINK.status().wallet === 'WalletK', 'the shell can restore a link after a data purge');
	check(!win.CHIK_IOS_APP.linkToken, 'the token is stripped off the injected object so the pack cannot read it');
}

console.log('\napp mode — navigator.sendBeacon obeys the same policy as fetch');
{
	const { win, calls } = boot({ app: {} });
	check(win.navigator.sendBeacon('https://chikimonsters.com/profile', 'x') === true,
		'a beacon to the game backend still goes out');
	check(calls.some((c) => c.beacon === 'https://chikimonsters.com/profile'), 'and reaches the real API');

	check(win.navigator.sendBeacon('https://telemetry.example.com/t', 'x') === false,
		'an off-origin beacon is refused');
	check(!calls.some((c) => c.beacon === 'https://telemetry.example.com/t'),
		'and never reaches the real API');

	let threw = false;
	try { win.navigator.sendBeacon('https://telemetry.example.com/t', 'x'); } catch (e) { threw = true; }
	check(!threw, 'refusal returns false rather than throwing, because pagehide handlers cannot throw');
}

console.log('\nweb mode — the beacon guard is not installed on the website');
{
	const { win, calls } = boot();
	check(win.navigator.sendBeacon('https://telemetry.example.com/t', 'x') === true,
		'the site keeps its own analytics');
	check(calls.some((c) => c.beacon === 'https://telemetry.example.com/t'), 'untouched');
}

console.log("\napp mode — the pack's \"get it free at phantom.app\" never reaches a player (3.1.1)");
{
	const { win } = boot({ app: {} });
	// Exactly what Chain.gd's injected sign-in JS does when no provider is present.
	win.__chikiPkErr = '';
	check(win.__chikiPkErr === '', 'the pack clearing the slot leaves it empty, so no stale error shows');

	win.__chikiPkErr = 'Phantom not found — get it free at phantom.app';
	check(!/phantom\.app/i.test(win.__chikiPkErr), 'the outside destination is gone');
	check(!/phantom/i.test(win.__chikiPkErr), 'so is the wallet brand');
	check(win.__chikiPkErr !== '', 'but it stays non-empty, so the pack still ends the flow');
	check(/not part of the app/i.test(win.__chikiPkErr), 'and says what is actually true');

	win.__chikiPkErr = 'Sign-in cancelled';
	check(/not part of the app/i.test(win.__chikiPkErr), 'every other sign-in failure reads the same way');
}

console.log('\napp mode — the sanitised refusal is localised');
{
	for (const [locale, needle] of [['ja-JP', 'ウォレット'], ['zh-CN', '钱包']]) {
		const { win } = boot({ app: { locale } });
		win.__chikiPkErr = 'Phantom not found — get it free at phantom.app';
		check(win.__chikiPkErr.indexOf(needle) >= 0, locale + ' gets its own wording');
		check(!/phantom\.app/i.test(win.__chikiPkErr), locale + ' names no outside destination either');
	}
}

console.log('\nweb mode — sign-in errors are left alone on the website');
{
	const { win } = boot();
	win.__chikiPkErr = 'Phantom not found — get it free at phantom.app';
	check(/phantom\.app/i.test(win.__chikiPkErr),
		'the site still tells a desktop player where to get a wallet');
}

console.log('\nno link yet — the game is not told to resume');
{
	const { win, sessionStore } = boot({ app: {} });
	win.__chikSigninSeedResume();
	check(sessionStore.chikResume === undefined, 'an unlinked device seeds nothing, so the app shows pairing');
}

console.log(failures === 0 ? '\nAll checks passed.\n' : '\n' + failures + ' check(s) FAILED.\n');
process.exit(failures === 0 ? 0 : 1);
