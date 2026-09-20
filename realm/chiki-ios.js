/* chiki-ios.js — the policy layer that makes the native iOS app a gameplay-only client.
 *
 * WHY THIS FILE EXISTS, AND WHY IT IS THE RIGHT PLACE
 *
 * The realm is a Godot web export: compiled bytecode in index.pck, mounted by realm/index.html.
 * The game itself cannot reach Solana, Phantom, Magic Eden or an RPC node on its own — every one
 * of those capabilities is a JavaScript function this page defines and the engine calls through
 * JavaScriptBridge (__chikiBuy, __chikiMeSign, window.solana, fetch). So the loader is not merely
 * a convenient place to switch trading off: it is the ONLY gate the capability passes through, and
 * a capability that is never defined cannot be reached by any build of the pack, present or future.
 *
 * That matters because the pack in this repo is compiled bytecode and its source lives in no
 * repository we can reach (see godot-patch/README.md). We cannot delete the Trading Post BUTTON
 * today. We can — and here do — guarantee that pressing it moves nothing, reaches nothing and
 * signs nothing. Hiding the button is a one-line feature check in the next pack build, and the
 * flag it must read (window.CHIK_FEATURES) is published below so that build has something to read.
 *
 * WHAT THE APP IS
 *   - the same world, the same account, the same cloud save as chikimonsters.com
 *   - gathering, the Wicked Temple, and Chikiseum PvP against real players
 *   - no wallet, no signatures, no purchases, no trading, no wagers, no chain traffic at all
 *   - the player's assets arrive by REALM LINK: they pair the device once from the website, and
 *     the server hands this device a session for that account. See §6.
 *
 * Nothing here is cosmetic. Every block below refuses work rather than hiding a control.
 */
(function () {
	'use strict';

	// ------------------------------------------------------------------ §1 mode
	//
	// The native shell injects window.CHIK_IOS_APP from a WKUserScript at document start, so it is
	// already set by the time this file parses. ?nocrypto=1 turns the same policy on in an ordinary
	// browser so it can be reviewed and tested without a device build — it deliberately does NOT set
	// CHIK_IOS_APP, because that flag also selects the HD pack and would memory-kill a phone.
	var forced = /[?&]nocrypto=1(&|$)/.test(location.search);
	var isApp = !!window.CHIK_IOS_APP;
	var noCrypto = isApp || forced;

	window.CHIK_NO_CRYPTO = noCrypto;
	if (!noCrypto) {
		// On the web nothing here applies: the site keeps the Trading Post, the marketplace, story
		// payouts and SOL wagers exactly as they are. Publish the policy anyway so one object always
		// describes the surface, then stand down.
		window.CHIK_FEATURES = features(false);
		return;
	}

	// ------------------------------------------------------------------ §2 the feature policy
	//
	// The contract between this loader and the next pack build. The game reads it once at start-up
	// (JavaScriptBridge.eval("JSON.stringify(window.CHIK_FEATURES)")) and hides what is false. Until
	// that build ships the flags are advisory — §3–§5 are what actually enforces the policy — but
	// they are the whole of what the build needs, so the build can be a feature gate and nothing more.
	function features(locked) {
		return {
			// what this client is
			platform: locked ? 'ios-app' : 'web',
			account: locked ? 'link' : 'wallet',    // how the player signs in
			pvp_mode: locked ? 'season' : 'wager',  // stake-free server-hosted, or SOL wagers

			// the gameplay the app ships — the whole point of the build
			gathering: true,
			crafting: true,
			fishing: true,
			hatching: true,
			wicked_temple: true,
			chikiseum_pvp: true,
			chikoria_cup: true,
			quests: true,
			cloud_sync: true,

			// everything that touches money. FALSE on the app, and unreachable besides.
			//
			// NOTE WHAT IS *NOT* TURNED OFF HERE: earning. The app awards the real assets — the
			// fantasy fish, eggs, chikimon and resources — onto the player's linked account, on-chain
			// where the asset is on-chain, exactly as the website awards them. The player owns what
			// they win here. What the app has no surface for is turning any of it back into money:
			// that is the Trading Post and the marketplace, and both live on the website only.
			crypto: !locked,          // any wallet, signature or chain call whatsoever
			wallet_connect: !locked,
			trading_post: !locked,    // player-to-player $CHIKI market — SELLING, not earning
			marketplace: !locked,     // Magic Eden — SELLING, not earning
			wagers: !locked,          // SOL stakes on a PvP match
			token_purchase: !locked,
			token_gate: !locked,      // holding 500k $CHIKI is not how you get into the app
			story_payouts: !locked,   // chapters still pay; the $CHIKI is claimed on the website
			asset_rewards: true,      // gathering, hatching, the temple and the arena all pay out
			coin_pouch: true,         // in-game coins are not currency; they stay
		};
	}
	window.CHIK_FEATURES = features(true);

	// ------------------------------------------------------------------ §3 the network guard
	//
	// The strong rule, and the one that does not depend on knowing every route name: the app may
	// talk to its own origin and to Chikoria's backend, and to nothing else. That single sentence
	// removes Solana RPC nodes, Magic Eden, Jupiter, price oracles, explorers and every other chain
	// endpoint in one move, including ones added to a future pack that this file has never heard of.
	//
	// On top of it, the wager routes are refused BY NAME, because they are the one crypto surface
	// that lives on an origin the app is otherwise allowed to talk to.
	//
	// Deliberately, nothing else is denied by name. Trading is not dead here because a route string
	// matched — it is dead because §5 removes the only functions that can build or sign a
	// transaction, so there is no transaction for a route to carry. Guessing at backend route names
	// would buy nothing and would risk a guess colliding with a gameplay route and breaking the
	// game, which is the one failure this file must not cause.
	var ALLOWED_HOSTS = [
		location.host,
		'api.chikimonsters.com',
		'chiki-backend-singapore.onrender.com',
	];
	// The six routes named in godot-patch/README.md: wager_board, _mine, _post, _accept, _withdraw,
	// _deposit. Suspended on the app — PvP here is the server-hosted season match, which costs
	// nothing and pays fantasy fish, eggs and resources instead of SOL.
	var DENY_PATH = /\/chikiseum\/live\/v1\/wager_/i;

	/** The art CDN, if one is ever configured. It is set in the body, long after this file parses,
	 *  so it is read lazily rather than captured — a captured '' would lock the CDN out for good. */
	var cdnHost = null, cdnSeen;
	function cdn() {
		var raw = (window.CHIK_CDN || '');
		if (raw !== cdnSeen) {
			cdnSeen = raw;
			cdnHost = '';
			try { if (raw) { cdnHost = new URL(raw, location.href).host; } } catch (e) {}
		}
		return cdnHost;
	}

	var blocked = [];
	window.CHIK_POLICY_BLOCKED = blocked;   // diagnostics; QA reads this after a pass over the app

	function refuse(url, why) {
		if (blocked.length < 50) { blocked.push({ url: String(url).slice(0, 200), why: why, at: Date.now() }); }
		try { console.warn('[chiki-ios] blocked (' + why + '): ' + String(url).slice(0, 200)); } catch (e) {}
	}

	/** null when the request is fine, otherwise the reason it is refused. */
	function verdict(rawUrl) {
		var url = String(rawUrl || '');
		// blob:, data: and relative paths never leave the app.
		if (/^(blob:|data:|about:)/i.test(url)) { return null; }
		var u;
		try { u = new URL(url, location.href); } catch (e) { return null; }
		if (u.protocol !== 'http:' && u.protocol !== 'https:') { return null; }
		if (ALLOWED_HOSTS.indexOf(u.host) < 0 && u.host !== cdn()) { return 'origin'; }
		if (DENY_PATH.test(u.pathname)) { return 'route'; }
		return null;
	}

	var realFetch = window.fetch ? window.fetch.bind(window) : null;
	if (realFetch) {
		window.fetch = function (input, init) {
			var url = (typeof input === 'string') ? input : ((input && input.url) || '');
			var no = verdict(url);
			if (no) {
				refuse(url, no);
				// A rejected promise, not a hang: the game's pollers all have a failure branch and a
				// spinner that never resolves is the one failure mode a player cannot get out of.
				return Promise.reject(new Error('This is not available in the Chikoria app.'));
			}
			// §6 — wallet-less sign-in rides on the request the game already makes.
			var rewritten = rewriteVerify(url, input, init);
			if (rewritten) { return realFetch(rewritten[0], rewritten[1]); }
			return realFetch(input, init);
		};
	}

	// XMLHttpRequest as well. Godot's HTTPRequest compiles to fetch in the web export, but the pack
	// also carries hand-written JS shims, and a guard with a hole in it is not a guard.
	try {
		var xopen = XMLHttpRequest.prototype.open;
		XMLHttpRequest.prototype.open = function (method, url) {
			var no = verdict(url);
			if (no) {
				refuse(url, no);
				throw new Error('This is not available in the Chikoria app.');
			}
			this.__chikVerify = /\/verify(\?|$)/.test(String(url).split('#')[0]);
			return xopen.apply(this, arguments);
		};
		var xsend = XMLHttpRequest.prototype.send;
		XMLHttpRequest.prototype.send = function (body) {
			if (this.__chikVerify && body != null) {
				var text = bodyText(body);
				var swapped = text ? swapAuth(text) : null;
				if (swapped) {
					return xsend.call(this, (typeof body === 'string') ? swapped : new TextEncoder().encode(swapped));
				}
			}
			return xsend.apply(this, arguments);
		};
	} catch (e) { /* a locked-down WebView: the fetch guard still stands */ }

	// WebSocket and EventSource obey the same origin rule.
	try {
		var RealWS = window.WebSocket;
		if (RealWS) {
			var GuardWS = function (url, protocols) {
				var u = String(url || '');
				var host = '';
				try { host = new URL(u, location.href).host; } catch (e) {}
				if (host && ALLOWED_HOSTS.indexOf(host) < 0) {
					refuse(u, 'origin');
					throw new Error('This is not available in the Chikoria app.');
				}
				return protocols === undefined ? new RealWS(u) : new RealWS(u, protocols);
			};
			GuardWS.prototype = RealWS.prototype;
			['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (k, i) { GuardWS[k] = i; });
			window.WebSocket = GuardWS;
		}
	} catch (e) {}

	// ------------------------------------------------------------------ §4 no wallet, ever
	//
	// There is no Phantom in the app — no extension, and the shell injects no provider. This exists
	// for the case that is not in our hands: a future iOS that ships a wallet provider in WKWebView,
	// or a deep link that hands one in. The property is made permanently null and unwritable, so a
	// provider that arrives later cannot install itself and the game's "is a wallet present" probes
	// all answer no.
	['solana', 'phantom', 'solflare', 'backpack', 'ethereum', 'web3', 'SolanaWeb3', 'SplToken'].forEach(function (k) {
		try {
			delete window[k];
			Object.defineProperty(window, k, {
				configurable: false,
				enumerable: false,
				get: function () { return undefined; },
				set: function () { refuse('window.' + k, 'wallet'); },   // swallowed on purpose
			});
		} catch (e) { /* already non-configurable: nothing we can do, and nothing calls it anyway */ }
	});

	// ------------------------------------------------------------------ §5 the trading bridges refuse
	//
	// realm/index.html does not DEFINE __chikiBuy or the Magic Eden bridge when CHIK_NO_CRYPTO is
	// set, so the capability is genuinely absent. But the pack polls for a result, and an absent
	// function leaves a "purchasing…" modal up forever. So the bridges are replaced by ones that
	// answer immediately, in the exact shape the pollers already read, with a refusal.
	//
	// The poll shapes are __chikiBuy's (Done/Sig/Err) and the Magic Eden bridge's
	// (Busy/Done/Sig/Err/Code/Rejected/Path/Ready) — both documented in realm/index.html.
	// Worth being precise with the player: what they earn in the app IS the real asset, credited to
	// the same account, on-chain where the asset is on-chain. The app simply has no way to sell or
	// trade it. So this is a "that happens on the website", not a "your prizes are not real".
	var NOPE = 'Selling and trading happen on chikimonsters.com. Everything you earn here is already yours.';

	window.__chikiBuyDone = ''; window.__chikiBuySig = ''; window.__chikiBuyErr = '';
	window.__chikiBuy = function () {
		refuse('__chikiBuy', 'trading');
		window.__chikiBuySig = '';
		window.__chikiBuyErr = NOPE;
		window.__chikiBuyDone = '1';            // set LAST — the poller treats this as "flow finished"
		return Promise.resolve();
	};

	window.__chikiMeBusy = ''; window.__chikiMeDone = ''; window.__chikiMeSig = '';
	window.__chikiMeErr = ''; window.__chikiMeCode = ''; window.__chikiMeRejected = ''; window.__chikiMePath = '';
	window.__chikiMeSign = function () {
		refuse('__chikiMeSign', 'trading');
		window.__chikiMeSig = '';
		window.__chikiMeRejected = '';
		window.__chikiMeErr = NOPE;
		window.__chikiMeCode = 'no_wallet';     // a code the pack already branches on today
		window.__chikiMePath = '';
		window.__chikiMeDone = '1';
		return Promise.resolve();
	};
	// The capability probe answers honestly: nothing here can sign.
	window.__chikiMeReady = function () {
		return JSON.stringify({ ok: false, lib: false, phantom: false, connected: false, reason: 'ios_app' });
	};

	// ------------------------------------------------------------------ §6 REALM LINK
	//
	// The app has no wallet, but it must reach the player's real account — every chikimon, egg, fish,
	// resource and quest they own — and every gather and hatch it does must land on the same cloud
	// save the website reads. So identity is moved off the device:
	//
	//   1. On chikimonsters.com/link/ the player is signed in with their wallet and mints a code.
	//   2. The app redeems the code once: POST /link/redeem {code, device_id} -> {wallet, linkToken}.
	//      The token is this DEVICE's long-lived credential for that account. It is not a key, it
	//      cannot sign, it cannot move anything on-chain, and the player can revoke it from the web.
	//   3. From then on the app signs in with the token instead of a signature.
	//
	// The last step is what lets this ship without a pack rebuild. Chain.gd already knows how to
	// resume a session it did not create: sessionStorage 'chikResume' {a,m,s,t}, posted to /verify.
	// So we seed that resume with the wallet and a SENTINEL signature, and swap the sentinel for the
	// link token on the way out. Chain.gd is unchanged and never sees the token; the backend gets
	// {wallet, linkToken, device_id} and answers with the same envelope it answers a signature with.
	//
	// MULTIPLE ACCOUNTS. A player may link several wallets and switch between them in the app —
	// "all accounts of all wallets", one device. Each keeps its own token; switching reloads, which
	// is the path the wallet-switch reload already takes on the web.
	var ACCOUNTS_KEY = 'chikLinkAccounts';   // [{wallet, token, label, linkedAt}]
	var ACTIVE_KEY = 'chikLinkActive';       // wallet
	var SENTINEL = 'CHIKI-LINK-V1';          // never a real base64 ed25519 signature (those are 88 chars)

	function loadAccounts() {
		try {
			var v = JSON.parse(localStorage.getItem(ACCOUNTS_KEY) || '[]');
			return Array.isArray(v) ? v.filter(function (a) { return a && a.wallet && a.token; }) : [];
		} catch (e) { return []; }
	}
	function saveAccounts(list) {
		try { localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(list)); } catch (e) {}
	}
	function activeAccount() {
		var list = loadAccounts();
		if (!list.length) { return null; }
		var want = '';
		try { want = localStorage.getItem(ACTIVE_KEY) || ''; } catch (e) {}
		for (var i = 0; i < list.length; i++) { if (list[i].wallet === want) { return list[i]; } }
		return list[0];
	}

	// The shell may hand the token in from the Keychain, which outlives a WebView data purge.
	// Take it, store it, and REMOVE it from the injected object so the pack can never read it.
	try {
		var seed = window.CHIK_IOS_APP;
		if (seed && seed.linkToken && seed.wallet) {
			adopt(String(seed.wallet), String(seed.linkToken), seed.label ? String(seed.label) : '');
			try { delete seed.linkToken; } catch (e) { seed.linkToken = ''; }
		}
	} catch (e) {}

	function adopt(wallet, token, label) {
		var list = loadAccounts().filter(function (a) { return a.wallet !== wallet; });
		list.unshift({ wallet: wallet, token: token, label: label || '', linkedAt: Date.now() });
		saveAccounts(list);
		try { localStorage.setItem(ACTIVE_KEY, wallet); } catch (e) {}
		return list;
	}

	/** The token for whichever account is active, kept in this closure and nowhere reachable. */
	function activeToken() {
		var a = activeAccount();
		return a ? a.token : '';
	}
	function activeWallet() {
		var a = activeAccount();
		return a ? a.wallet : '';
	}

	/** Rewrite a /verify body that carries our sentinel into a link-token sign-in. */
	function swapAuth(bodyText) {
		var tok = activeToken();
		if (!tok) { return null; }
		var body;
		try { body = JSON.parse(bodyText); } catch (e) { return null; }
		if (!body || typeof body !== 'object') { return null; }
		if (body.authSig !== SENTINEL) { return null; }      // a real signature is left alone
		delete body.authSig;
		delete body.authMsg;
		body.linkToken = tok;
		body.device_id = deviceId();
		body.client = 'ios-app';
		try { return JSON.stringify(body); } catch (e) { return null; }
	}

	/** Godot's web HTTPRequest hands fetch a Uint8Array, not a string, so read both. */
	function bodyText(body) {
		if (typeof body === 'string') { return body; }
		try {
			if (body instanceof ArrayBuffer) { return new TextDecoder().decode(new Uint8Array(body)); }
			if (ArrayBuffer.isView(body)) { return new TextDecoder().decode(body); }
		} catch (e) {}
		return null;
	}

	function rewriteVerify(url, input, init) {
		var path = String(url || '').split('#')[0].split('?')[0];
		if (!/\/verify$/.test(path)) { return null; }
		if (verdict(url)) { return null; }                   // never send a token off-origin
		if (!init || init.body == null) { return null; }     // a Request object's body is a stream; leave it
		var text = bodyText(init.body);
		if (!text) { return null; }
		var swapped = swapAuth(text);
		if (!swapped) { return null; }
		var next = {};
		for (var k in init) { if (Object.prototype.hasOwnProperty.call(init, k)) { next[k] = init[k]; } }
		// Answer in the shape the caller used: a byte body stays a byte body, so Content-Length and
		// any downstream assumption about the request still hold.
		next.body = (typeof init.body === 'string') ? swapped : new TextEncoder().encode(swapped);
		return [input, next];
	}

	/** A stable per-install id, so the server can name and revoke this device. Not a fingerprint. */
	function deviceId() {
		var k = 'chikDeviceId';
		try {
			var v = localStorage.getItem(k);
			if (!v) {
				v = (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
					: 'd' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
				localStorage.setItem(k, v);
			}
			return v;
		} catch (e) { return 'd-ephemeral'; }
	}

	// Seed the resume Chain.gd already honours. Called by run() immediately before the engine starts,
	// mirroring the web's __chikSigninSeedResume hook so index.html has one call site for both.
	window.__chikSigninSeedResume = function () {
		try {
			var w = activeWallet();
			if (!w) { return; }                                   // not linked yet: the app shows the pairing screen
			sessionStorage.setItem('chikResume', JSON.stringify({
				a: w,
				m: 'Chikoria link\nwallet:' + w + '\nts:' + Date.now(),
				s: SENTINEL,
				t: Date.now(),
			}));
		} catch (e) {}
	};

	// ------------------------------------------------------------------ §7 what the shell calls
	//
	// The Swift side drives pairing through this object. Every function is safe to call at any time
	// and none of them expose a token: status() reports the wallet, never the credential.
	function announce(kind, detail) {
		var payload = Object.assign({ kind: kind }, detail || {});
		try { document.dispatchEvent(new CustomEvent('chiki-link', { detail: payload })); } catch (e) {}
		try {
			var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chikiLink;
			if (h) { h.postMessage(payload); }
		} catch (e) {}
	}

	/** The backend to pair against. Two bases are live (the arena client uses the Render one), so
	 *  the shell can pin whichever is current with window.CHIK_API rather than needing a web
	 *  release. Anything it names must still be on ALLOWED_HOSTS or its own guard refuses it. */
	function apiBase() {
		var pinned = String(window.CHIK_API || '').replace(/\/+$/, '');
		if (pinned) {
			try {
				if (ALLOWED_HOSTS.indexOf(new URL(pinned).host) >= 0) { return pinned; }
			} catch (e) {}
		}
		return 'https://api.chikimonsters.com';
	}

	window.CHIK_LINK = {
		/** {linked, wallet, accounts:[{wallet,label,linkedAt}], deviceId} — never the token. */
		status: function () {
			var a = activeAccount();
			return {
				linked: !!a,
				wallet: a ? a.wallet : '',
				deviceId: deviceId(),
				accounts: loadAccounts().map(function (x) {
					return { wallet: x.wallet, label: x.label || '', linkedAt: x.linkedAt || 0 };
				}),
			};
		},

		/** Redeem a code minted on chikimonsters.com/link/. Resolves to {wallet}. */
		redeem: function (code) {
			var clean = String(code || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
			if (clean.length < 6) { return Promise.reject(new Error('That code looks too short.')); }
			return realFetch(apiBase() + '/link/redeem', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					code: clean,
					device_id: deviceId(),
					device_name: (window.CHIK_IOS_APP && window.CHIK_IOS_APP.deviceName) || 'iPhone',
					client: 'ios-app',
				}),
			}).then(function (r) {
				return r.json().catch(function () { return {}; }).then(function (j) {
					if (!r.ok || !j.linkToken || !j.wallet) {
						throw new Error(j.error || 'That code is not valid any more. Mint a new one on the website.');
					}
					adopt(String(j.wallet), String(j.linkToken), String(j.label || ''));
					announce('linked', { wallet: j.wallet });
					return { wallet: String(j.wallet) };
				});
			});
		},

		/** Switch which linked account the app plays. Reloads, which is how the web switches wallets. */
		use: function (wallet) {
			var w = String(wallet || '');
			var found = loadAccounts().some(function (a) { return a.wallet === w; });
			if (!found) { return false; }
			try {
				localStorage.setItem(ACTIVE_KEY, w);
				sessionStorage.removeItem('chikResume');
			} catch (e) {}
			announce('switched', { wallet: w });
			location.reload();
			return true;
		},

		/** Drop one account from this device, telling the server so the token stops working. */
		forget: function (wallet) {
			var w = String(wallet || activeWallet());
			var gone = loadAccounts().filter(function (a) { return a.wallet === w; })[0];
			saveAccounts(loadAccounts().filter(function (a) { return a.wallet !== w; }));
			try { sessionStorage.removeItem('chikResume'); } catch (e) {}
			announce('unlinked', { wallet: w });
			if (!gone) { return Promise.resolve(); }
			return realFetch(apiBase() + '/link/revoke', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ wallet: w, linkToken: gone.token, device_id: deviceId() }),
			}).catch(function () { /* the device has forgotten it either way */ });
		},

		/** Everything, e.g. from a "sign out of this device" control. */
		forgetAll: function () {
			var all = loadAccounts();
			saveAccounts([]);
			try { localStorage.removeItem(ACTIVE_KEY); sessionStorage.removeItem('chikResume'); } catch (e) {}
			announce('unlinked', {});
			return Promise.all(all.map(function (a) {
				return realFetch(apiBase() + '/link/revoke', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({ wallet: a.wallet, linkToken: a.token, device_id: deviceId() }),
				}).catch(function () {});
			}));
		},

		/** For the shell to hand in a Keychain-held token on launch. */
		setToken: function (wallet, token, label) {
			if (!wallet || !token) { return false; }
			adopt(String(wallet), String(token), String(label || ''));
			announce('linked', { wallet: String(wallet) });
			return true;
		},

		features: function () { return window.CHIK_FEATURES; },
	};

	// Tell the shell where we stand as soon as the page is up, so it can decide between showing the
	// pairing screen and getting out of the way.
	announce('ready', { linked: !!activeAccount(), wallet: activeWallet() });
}());
