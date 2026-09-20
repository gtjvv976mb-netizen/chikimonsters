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

	// ------------------------------------------------------------------ §1b language
	//
	// The realm ships in English, Japanese and Chinese, and the player picks inside the game. This
	// file runs before the game does, so it cannot read that choice — it uses the shell's locale
	// (the device language, which is what the player has already told iOS) and falls back to the
	// browser's. Every player-facing string below goes through T().
	//
	// Note the loading screen's own panels have always been English-only markup; the rewrite in
	// realm/index.html does not change that either way. What is localised here is what this file
	// itself says to the player: the refusals and the pairing errors.
	var LANG = (function () {
		var raw = '';
		try {
			raw = String((window.CHIK_IOS_APP && window.CHIK_IOS_APP.locale)
				|| navigator.language || navigator.userLanguage || 'en');
		} catch (e) { raw = 'en'; }
		raw = raw.toLowerCase();
		if (raw.indexOf('ja') === 0) { return 'ja'; }
		if (raw.indexOf('zh') === 0) { return 'zh'; }
		return 'en';
	}());
	window.CHIK_LANG = LANG;

	var STRINGS = {
		blocked: {
			en: 'This is not available in the Chikoria app.',
			ja: 'この機能はチコリアアプリでは利用できません。',
			zh: '此功能在 Chikoria 应用中不可用。',
		},
		// Names no outside destination, in every language — see the note on guideline 3.1.1 below.
		noTrade: {
			en: 'Selling and trading are not available in the app. Everything you earn here is yours to keep.',
			ja: 'アプリでは売買・取引はできません。ここで手に入れたものは、すべてあなたのものです。',
			zh: '应用内无法买卖或交易。你在这里获得的一切都归你所有。',
		},
		codeShort: {
			en: 'That code looks too short.',
			ja: 'コードが短すぎるようです。',
			zh: '这个代码似乎太短了。',
		},
		codeBad: {
			en: 'That code is not valid any more. Mint a new one on the website.',
			ja: 'このコードは無効です。ウェブサイトで新しいコードを発行してください。',
			zh: '该代码已失效。请在网站上重新生成一个。',
		},
		maintenance: {
			en: 'Chikoria is down for maintenance. Try again shortly.',
			ja: 'チコリアはメンテナンス中です。しばらくしてからお試しください。',
			zh: 'Chikoria 正在维护中，请稍后再试。',
		},
		// Replaces whatever the pack says when wallet sign-in finds no provider. Like noTrade, it
		// states the fact and names no outside destination — see §4.
		noWallet: {
			en: 'Wallet sign-in is not part of the app. You are already playing on your own account.',
			ja: 'アプリではウォレット接続は使用しません。すでにご自身のアカウントでプレイ中です。',
			zh: '应用内不使用钱包登录。你当前已在自己的账号中游玩。',
		},
	};

	function T(key) {
		var row = STRINGS[key];
		if (!row) { return key; }
		return row[LANG] || row.en;
	}

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
			// The Cup's prize is a SOL pool, so it is a money surface however it is framed. On the
			// app it stays shut — the season match is the tournament-shaped thing here.
			chikoria_cup: !locked,
			quests: true,
			cloud_sync: true,

			// Chat is OFF in the app, and it is the one flag here that is a child-safety decision
			// rather than a money one. The game carries world chat, party chat and whispers between
			// strangers; App Review guideline 1.2 wants a filter, a report path, a block path and
			// published contact, and the backend has the filter but neither report nor block.
			// §3 refuses the routes outright, so this flag only asks a future pack build to stop
			// DRAWING the chat box — the messages cannot arrive either way.
			chat: !locked,
			whispers: !locked,

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
	// Two families are refused by name.
	//
	// 1. THE WAGER ROUTES — kept as a belt-and-braces measure, and now known to be unnecessary:
	//    the recovered pack has no wager route at all, and ChikiseumLiveClient refuses any
	//    response that is not `currency: "NONE"` with `real_sol_enabled: false`. Costs nothing to
	//    leave in place, and would catch a future build that added one.
	//
	// 2. CHAT — and this one is a safety decision, not a crypto one.
	//
	//    The game has world chat, party chat and private whispers between strangers, plus
	//    player-set handles. App Review guideline 1.2 requires four things of an app carrying
	//    user-generated content: a filter, a way to REPORT, a way to BLOCK, and published contact
	//    details. The filter exists (a server-authoritative profanity mask) and contact details
	//    now exist, but there is NO report route and NO block route — and `Chat.gd` has no report,
	//    block, mute or filter anywhere in its 1,169 lines. Two of four.
	//
	//    Building the missing two means rebuilding the pack, which needs a web export template
	//    that does not exist (`godot-patch/RECOVERY.md`). So the app ships without chat instead.
	//    That is possible only because of how chat is transported: it is plain HTTP, while the
	//    WebSocket carries ONLY /world/move. Blocking these routes takes the chat away and leaves
	//    player movement, presence and the rest of the world untouched.
	//
	//    THE ROUTES, read from the pack rather than from a network trace. `Chat.gd` calls exactly
	//    two endpoints, and an earlier version of this comment named neither of them:
	//
	//      /world/chat — world chat.       Caught by `\/chat(\/|$)`.
	//      /world/dm   — whispers AND party chat, both POSTing {to, text, …}.
	//
	//    **/world/dm was not matched, so private messages between strangers were still open in the
	//    app** — the exact surface guideline 1.2 is about, and the one with no report or block.
	//    It is matched by name now.
	//
	//    `\/chat(\/|$)` is kept broader than the pack needs so that a /chat or /chat/send on any
	//    other surface is caught too. It deliberately does not match /chatter or a
	//    /chat_tab_world.png asset, and `\/world\/dm(\/|$)` will not match /world/dmg either.
	var DENY_PATH = /\/chikiseum\/live\/v1\/wager_|\/chat(\/|$)|\/world\/dm(\/|$)/i;

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
			if (rewritten) { return watchVerify(realFetch(rewritten[0], rewritten[1])); }
			// §3c — the in-game news feed is filtered on its way in.
			if (isNewsFeed(url)) { return filterNews(realFetch(input, init)); }
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
				throw new Error(T('blocked'));
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
					// Same rejection watch as the fetch path — a dead token must not dead-end the app
					// just because the pack happened to use XHR for this call.
					try {
						this.addEventListener('load', function () {
							if (this.status >= 400 && this.status < 500) { return linkRejected('rejected'); }
							if (this.status !== 200) { return; }
							try {
								var j = JSON.parse(this.responseText || '{}');
								if (j && j.signedIn !== true) { linkRejected(String(j.code || 'rejected')); }
							} catch (e) {}
						});
					} catch (e) {}
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
					throw new Error(T('blocked'));
				}
				return protocols === undefined ? new RealWS(u) : new RealWS(u, protocols);
			};
			GuardWS.prototype = RealWS.prototype;
			['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (k, i) { GuardWS[k] = i; });
			window.WebSocket = GuardWS;
		}
	} catch (e) {}

	// EventSource. The comment above used to claim this was covered when it was not — a guard with a
	// hole in it is worse than no guard, because it is trusted.
	try {
		var RealES = window.EventSource;
		if (RealES) {
			var GuardES = function (url, cfg) {
				var no = verdict(url);
				if (no) {
					refuse(url, no);
					throw new Error(T('blocked'));
				}
				return cfg === undefined ? new RealES(url) : new RealES(url, cfg);
			};
			GuardES.prototype = RealES.prototype;
			['CONNECTING', 'OPEN', 'CLOSED'].forEach(function (k, i) { GuardES[k] = i; });
			window.EventSource = GuardES;
		}
	} catch (e) {}

	// navigator.sendBeacon. Found by reading the pack's own source rather than by guessing: Chain.gd
	// registers a `pagehide` / `visibilitychange` flush that does
	//
	//     if (!(navigator.sendBeacon && navigator.sendBeacon(window.__chikFlushUrl, b))) {
	//       fetch(window.__chikFlushUrl, {method:'POST', body:b, keepalive:true}).catch(...)
	//     }
	//
	// The fetch fallback was guarded from the start; the beacon was not. In the shipped build the
	// body is only ever filled once a wallet is linked (Chain.gd returns early while `wallet()` is
	// empty), which cannot happen in the app — so this is a closed door, not a leak that was running.
	// It is guarded anyway, because §3 is documented as covering egress and a guard that is trusted
	// while having a hole in it is the dangerous kind.
	//
	// sendBeacon must not throw: it is called from a pagehide handler, where an exception would take
	// the rest of the teardown with it. It reports refusal the way the real API reports failure —
	// by returning false — which is a value its one caller already handles.
	try {
		if (navigator && typeof navigator.sendBeacon === 'function') {
			var realBeacon = navigator.sendBeacon.bind(navigator);
			navigator.sendBeacon = function (url, data) {
				var no = verdict(url);
				if (no) { refuse(url, no); return false; }
				return data === undefined ? realBeacon(url) : realBeacon(url, data);
			};
		}
	} catch (e) { /* read-only navigator: nothing in the app fills the beacon body anyway */ }

	// ------------------------------------------------------------------ §3b the navigation guard
	//
	// THE HOLE THE REST OF §3 DOES NOT COVER. Everything above guards requests for DATA. None of it
	// guards NAVIGATION, and the engine hands the pack a navigation primitive directly: realm/index.js
	// defines _godot_js_os_shell_open(uri) as a bare window.open(uri, "_blank"), proxied back to the
	// main thread from pthreads. So GDScript's OS.shell_open() leaves the app without touching fetch.
	//
	// That matters twice over. Off-origin it is the marketplace/wallet deep link the whole policy
	// exists to prevent. ON-ORIGIN it is worse than it looks: location.host is an allowed host, and
	// /arena/ (the full SOL wager client) and /link/ (a Phantom sign-in) sit on that very origin and
	// load no policy layer at all. So "same origin" is NOT safe here — only the realm is.
	//
	// location.href assignment cannot be intercepted from script. The native WKNavigationDelegate is
	// the real backstop for that, and IOS-APP.md now requires it; this layer closes everything a page
	// CAN close, so the two together leave nothing.
	var REALM_ROOT = location.pathname.replace(/[^/]*$/, '');     // '/realm/' in production
	// The community links the loading screen legitimately offers. They are handed to the shell to
	// open in Safari rather than navigated to in-app — an in-app browser is its own review risk.
	var EXTERNAL_OK = /^https:\/\/([a-z0-9-]+\.)?(x\.com|twitter\.com|discord\.gg|discord\.com)\//i;

	/** 'ok' to allow in place, 'external' to hand to the shell, 'refuse' to block. */
	function navVerdict(rawUrl) {
		var url = String(rawUrl || '');
		if (!url || url.charAt(0) === '#' || /^javascript:/i.test(url)) { return 'ok'; }
		var u;
		try { u = new URL(url, location.href); } catch (e) { return 'refuse'; }
		if (u.protocol === 'blob:' || u.protocol === 'data:' || u.protocol === 'about:') { return 'ok'; }
		if (u.protocol !== 'http:' && u.protocol !== 'https:') { return 'refuse'; }  // phantom:, solflare:, itms://
		if (u.host === location.host) {
			return u.pathname.indexOf(REALM_ROOT) === 0 ? 'ok' : 'refuse';
		}
		return EXTERNAL_OK.test(u.href) ? 'external' : 'refuse';
	}

	/** Hand a legitimate outside link to the native shell, which opens it in Safari. */
	function openExternally(url) {
		try {
			var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chikiLink;
			if (h) { h.postMessage({ kind: 'external-link', url: String(url) }); return true; }
		} catch (e) {}
		return false;
	}

	try {
		var realOpen = window.open ? window.open.bind(window) : null;
		window.open = function (url) {
			var v = navVerdict(url);
			if (v === 'ok') { return realOpen ? realOpen.apply(null, arguments) : null; }
			if (v === 'external') { openExternally(url); return null; }
			refuse(url, 'navigate');
			return null;      // null, not a throw: OS.shell_open ignores the result either way
		};
	} catch (e) {}

	// Anchor clicks and form posts, caught in the CAPTURE phase so the page's own handlers never see
	// a navigation this policy would refuse.
	try {
		document.addEventListener('click', function (ev) {
			var el = ev.target;
			while (el && el !== document && el.nodeName !== 'A') { el = el.parentNode; }
			if (!el || el.nodeName !== 'A') { return; }
			var href = el.getAttribute('href') || '';
			var v = navVerdict(href);
			if (v === 'ok') { return; }
			ev.preventDefault();
			ev.stopPropagation();
			if (v === 'external') { openExternally(el.href); return; }
			refuse(href, 'navigate');
		}, true);
		document.addEventListener('submit', function (ev) {
			var action = (ev.target && ev.target.getAttribute('action')) || location.href;
			if (navVerdict(action) !== 'ok') {
				ev.preventDefault();
				ev.stopPropagation();
				refuse(action, 'navigate');
			}
		}, true);
	} catch (e) {}

	// ------------------------------------------------------------------ §3d metered connections
	//
	// A first launch pulls the HD pack: 313 MB of game data plus a 40 MB engine. The app takes it
	// on purpose — it is the third variant beside desktop and mobile web — but nothing anywhere
	// asked what network the phone is on, so a player on a cellular plan could burn 350 MB without
	// being told.
	//
	// THE PAGE CANNOT ANSWER THAT QUESTION ITSELF. The Network Information API
	// (navigator.connection, saveData, effectiveType) is not implemented in WebKit, so on iOS it is
	// simply undefined — in Safari and in a WKWebView alike. Only the native side can see the
	// interface, via NWPathMonitor's isExpensive/isConstrained. So the shell injects the verdict
	// and may update it while the app runs; this publishes it for the loader to act on.
	//
	// What the loader does with it: takes the LITE pack instead (174 MB, already published), which
	// is a 139 MB saving and needs no dialog. Chosen over asking because a modal in front of a
	// player who just opened a game is worse than a slightly lighter world.
	function readMetered() {
		var app = window.CHIK_IOS_APP;
		if (app && typeof app.metered === 'boolean') { return app.metered; }
		// Non-iOS browsers DO implement this, so honour it where it exists.
		try {
			var c = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
			if (c) {
				if (c.saveData === true) { return true; }
				if (typeof c.type === 'string' && c.type === 'cellular') { return true; }
				if (typeof c.effectiveType === 'string' && /^(slow-)?2g$/.test(c.effectiveType)) { return true; }
			}
		} catch (e) {}
		return false;
	}
	window.CHIK_METERED = readMetered();

	// THE HD PACK IS OPT-IN, AND ONLY THE NATIVE SIDE CAN GRANT IT.
	//
	// The app used to take the 313MB HD pack purely because it was the app. Measured on a real
	// iPhone that runs the device out of memory, so realm/index.html now gives a phone the 174MB
	// lite pack unless this flag says otherwise.
	//
	// The page cannot make this decision: there is no way to read physical memory from JavaScript
	// in WebKit — navigator.deviceMemory is not implemented. The shell reads
	// ProcessInfo.processInfo.physicalMemory and decides. Absent or false means lite, which is the
	// safe direction: a player on the lighter world is playing, and a player on a pack their phone
	// cannot hold is watching it die at 90%.
	window.CHIK_HD = !!(window.CHIK_IOS_APP && window.CHIK_IOS_APP.hd === true);

	// Progress, for a native layer that would otherwise show a black box for several minutes.
	// realm/index.html calls this from setBar()/say() when it exists.
	var lastSent = -1;
	window.CHIK_PROGRESS = function (fraction, note) {
		var pct = Math.round(Math.max(0, Math.min(1, Number(fraction) || 0)) * 100);
		if (pct === lastSent && !note) { return; }
		lastSent = pct;
		try {
			var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chikiLink;
			if (h) { h.postMessage({ kind: 'progress', percent: pct, note: String(note || ''), metered: !!window.CHIK_METERED }); }
		} catch (e) {}
	};

	// ------------------------------------------------------------------ §3c the news feed
	//
	// realm/updates.json is the in-game News panel: 169 entries of release notes, written for the
	// website. Fifteen of them sell the Trading Post, five name Magic Eden, seven name Phantom and
	// three quote the 500k gate. The pack renders it and the pack cannot be edited here — but the
	// pack has to FETCH it, and that request comes through this guard. So the feed is filtered on
	// the way in: an entry that advertises a surface the app refuses is dropped before the game
	// ever sees it.
	//
	// Dropping, not rewriting. These are historical release notes; editing what a past release said
	// would be a lie, whereas not showing an entry about a feature this client does not have is just
	// the right feed for the platform.
	var NEWS_BANNED = /trading post|magic eden|phantom|\$CHIKI|500,000|500k|SOL |wager|solscan|on-chain|marketplace/i;

	function isNewsFeed(url) {
		// The pack fetches it relatively ("updates.json"), so a leading slash must not be required.
		return /(^|\/)updates\.json(\?|$)/.test(String(url || '').split('#')[0]);
	}

	/** Re-serve the feed with the money entries removed, preserving its shape whatever that is. */
	function filterNews(promise) {
		return promise.then(function (res) {
			if (!res.ok) { return res; }
			return res.clone().json().then(function (feed) {
				var kept = 0, dropped = 0;
				function keep(entry) {
					if (!entry || typeof entry !== 'object') { return true; }
					var text = String(entry.title || '') + ' ' + String(entry.body || '');
					if (NEWS_BANNED.test(text)) { dropped++; return false; }
					kept++;
					return true;
				}
				var out;
				if (Array.isArray(feed)) { out = feed.filter(keep); }
				else if (feed && Array.isArray(feed.updates)) { out = Object.assign({}, feed, { updates: feed.updates.filter(keep) }); }
				else if (feed && Array.isArray(feed.entries)) { out = Object.assign({}, feed, { entries: feed.entries.filter(keep) }); }
				else { return res; }                       // a shape we do not know: pass it through untouched
				if (dropped) { console.log('[chiki-ios] news: kept ' + kept + ', dropped ' + dropped + ' money entries'); }
				return new Response(JSON.stringify(out), {
					status: 200,
					headers: { 'Content-Type': 'application/json' },
				});
			}).catch(function () { return res; });         // not JSON, or unreadable: leave it alone
		});
	}

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

	// ...which has a consequence the pack's own source spells out. Chain.gd does not use any bridge
	// realm/index.html provides — it injects its own sign-in JS through JavaScriptBridge:
	//
	//     var p = (window.phantom && window.phantom.solana) || window.solana;
	//     if (!p) { window.__chikiPkErr = 'Phantom not found — get it free at phantom.app'; return; }
	//
	// The block above is what makes `p` undefined, so in the app that branch is not an edge case:
	// it is the ONLY outcome, every time a player presses sign in. The pack then surfaces
	// __chikiPkErr to the player verbatim (Chain.gd: `signin_error = perr.left(180)`), and a toast
	// reading "get it free at phantom.app" is precisely the steering guideline 3.1.1 restricts —
	// shipped by us, in our own UI, pointing at an outside way to transact.
	//
	// The string cannot be edited without rebuilding the pack. It does not have to be: the pack
	// reads the error back out of `window`, so owning the property is enough. Every failure is
	// replaced, not just this one, because in the app there is no sign-in failure that is worth
	// explaining to a player — there is no sign-in. Empty stays empty: the pack clears these to ''
	// before each attempt and treats a non-empty value as "the flow finished, and it failed".
	//
	// Safe to define here: realm/index.html's stay-signed-in block, which is what otherwise owns
	// __chikiPk, returns at its first line when CHIK_NO_CRYPTO is set.
	try {
		var pkErr = '';
		Object.defineProperty(window, '__chikiPkErr', {
			configurable: false,
			enumerable: true,
			get: function () { return pkErr; },
			set: function (v) {
				var raw = (v === null || v === undefined) ? '' : String(v);
				if (raw) { refuse('__chikiPkErr: ' + raw.slice(0, 120), 'wallet'); }
				pkErr = raw ? T('noWallet') : '';
			},
		});
	} catch (e) { /* nothing else defines it; if this fails the app shows the pack's own wording */ }

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
	// trade it — so the message must not suggest their prizes are fake.
	//
	// IT MUST ALSO NOT NAME A DESTINATION. Pointing the player at an outside purchasing mechanism is
	// what App Review guideline 3.1.1 restricts, and the earlier wording ("Selling and trading happen
	// on chikimonsters.com") did exactly that. State the fact, offer no outside route.
	var NOPE = T('noTrade');

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
	//
	// WHO OWNS THE CREDENTIAL. The first version of this file wrote the tokens to localStorage and
	// claimed the pack could not read them. That was wrong twice over: localStorage is readable by
	// anything in this JS context, JavaScriptBridge.eval included, and a WKWebView data purge — the
	// exact event the Keychain exists to survive — takes it away. So ownership is inverted:
	//
	//   * In the app (the shell sets CHIK_IOS_APP.keychain === true) the tokens live ONLY in the
	//     closure below and in the shell's Keychain. Nothing is written to localStorage, and every
	//     mutation is pushed to the shell to persist. A reload starts empty and is re-seeded by the
	//     shell's injection, which is the same path a cold launch takes.
	//   * Without a shell to hold them (a browser running ?nocrypto=1, or an older shell that does
	//     not set the flag) localStorage is the fallback, because the alternative is a link that
	//     does not survive a reload at all.
	//
	// Be honest about the limit: this reduces exposure, it does not create isolation. Any script in
	// this realm — the pack included — can hook CHIK_LINK or read a closure's output. The property
	// that actually protects the player is server-side and stated in IOS-APP.md: a link token
	// authorises PLAY and is refused by every route that moves value.
	var ACCOUNTS_KEY = 'chikLinkAccounts';   // [{wallet, token, label, linkedAt}] — fallback store only
	var ACTIVE_KEY = 'chikLinkActive';       // wallet
	var DEVICE_KEY = 'chikDeviceId';
	var SENTINEL = 'CHIKI-LINK-V1';          // never a real base64 ed25519 signature (those are 88 chars)

	// True when a native shell is holding the credential for us.
	var shellHolds = !!(window.CHIK_IOS_APP && window.CHIK_IOS_APP.keychain === true);

	var memAccounts = null;                  // the in-memory store; authoritative when shellHolds
	var memActive = '';
	var memDeviceId = '';

	function loadAccounts() {
		if (shellHolds) { return memAccounts || (memAccounts = []); }
		try {
			var v = JSON.parse(localStorage.getItem(ACCOUNTS_KEY) || '[]');
			return Array.isArray(v) ? v.filter(function (a) { return a && a.wallet && a.token; }) : [];
		} catch (e) { return []; }
	}
	function saveAccounts(list) {
		if (shellHolds) { memAccounts = list; persistToShell(); return; }
		try { localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(list)); } catch (e) {}
	}
	function setActive(wallet) {
		if (shellHolds) { memActive = wallet; persistToShell(); return; }
		try { localStorage.setItem(ACTIVE_KEY, wallet); } catch (e) {}
	}
	function getActive() {
		if (shellHolds) { return memActive; }
		try { return localStorage.getItem(ACTIVE_KEY) || ''; } catch (e) { return ''; }
	}
	function activeAccount() {
		var list = loadAccounts();
		if (!list.length) { return null; }
		var want = getActive();
		for (var i = 0; i < list.length; i++) { if (list[i].wallet === want) { return list[i]; } }
		return list[0];
	}

	// THE KEYCHAIN HANDOFF. IOS-APP.md used to tell the shell to "persist the token to the Keychain"
	// while giving it no way to obtain one — announce() carried only the wallet. This is that missing
	// half: every change to the credential set is pushed to the shell as one complete record, so the
	// shell can write it and hand the identical thing back at next launch.
	//
	// device_id goes in the record deliberately. It is generated here and used to bind the token
	// server-side, so if a data purge regenerated it the restored token would arrive bound to an id
	// the server has never seen — the restore would fail for the one event it exists to survive.
	function persistToShell() {
		try {
			var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chikiLink;
			if (!h) { return; }
			h.postMessage({
				kind: 'persist',
				deviceId: deviceId(),
				active: memActive,
				accounts: (memAccounts || []).map(function (a) {
					return { wallet: a.wallet, token: a.token, label: a.label || '', linkedAt: a.linkedAt || 0 };
				}),
			});
		} catch (e) {}
	}

	// The shell hands the credential set in from the Keychain at document start. Take it, hold it in
	// the closure, and REMOVE it from the injected object so the pack cannot simply read the global.
	try {
		var seed = window.CHIK_IOS_APP;
		if (seed) {
			if (seed.deviceId) { memDeviceId = String(seed.deviceId); }
			if (Array.isArray(seed.accounts) && seed.accounts.length) {
				memAccounts = seed.accounts
					.filter(function (a) { return a && a.wallet && a.token; })
					.map(function (a) {
						return { wallet: String(a.wallet), token: String(a.token), label: String(a.label || ''), linkedAt: a.linkedAt || 0 };
					});
				memActive = String(seed.active || (memAccounts[0] && memAccounts[0].wallet) || '');
			} else if (seed.linkToken && seed.wallet) {
				// The single-account shape the first draft of the spec described. Still accepted.
				memAccounts = [{ wallet: String(seed.wallet), token: String(seed.linkToken), label: String(seed.label || ''), linkedAt: 0 }];
				memActive = String(seed.wallet);
			}
			try { delete seed.linkToken; delete seed.accounts; } catch (e) { seed.linkToken = ''; seed.accounts = null; }
			// A shell that injects a credential but does NOT claim custody (no keychain flag) still
			// has to be honoured, or its restore is silently dropped: loadAccounts() would read the
			// empty localStorage and the player would be asked to pair again. Write it through.
			if (!shellHolds && memAccounts && memAccounts.length) {
				saveAccounts(memAccounts);
				setActive(memActive || memAccounts[0].wallet);
				if (memDeviceId) { try { localStorage.setItem(DEVICE_KEY, memDeviceId); } catch (e) {} }
			}
		}
	} catch (e) {}

	function adopt(wallet, token, label) {
		var list = loadAccounts().filter(function (a) { return a.wallet !== wallet; });
		list.unshift({ wallet: wallet, token: token, label: label || '', linkedAt: Date.now() });
		if (shellHolds) { memAccounts = list; memActive = wallet; persistToShell(); }
		else { saveAccounts(list); setActive(wallet); }
		return list;
	}

	/** The token for whichever account is active. */
	function activeToken() {
		var a = activeAccount();
		return a ? a.token : '';
	}
	function activeWallet() {
		var a = activeAccount();
		return a ? a.wallet : '';
	}

	/** Forget one account (or all) from whichever store is authoritative. */
	function dropAccount(wallet) {
		var gone = loadAccounts().filter(function (a) { return a.wallet === wallet; })[0] || null;
		var left = loadAccounts().filter(function (a) { return a.wallet !== wallet; });
		if (shellHolds) {
			memAccounts = left;
			if (memActive === wallet) { memActive = (left[0] && left[0].wallet) || ''; }
			persistToShell();
		} else {
			saveAccounts(left);
			if (getActive() === wallet) { setActive((left[0] && left[0].wallet) || ''); }
		}
		return gone;
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

	// WHEN THE SERVER SAYS NO. A link token can be revoked from the website, expire, or belong to an
	// account the server no longer admits. Before this, the answer to all three was a dead screen:
	// the game's sign-in simply failed, the bad token stayed on the device, and the next launch
	// failed the same way forever — an app a player cannot get out of without deleting it.
	//
	// So a /verify carrying OUR token is watched. A 4xx, or a 200 that does not say signedIn, means
	// this credential is finished: drop it, tell the shell so it can clear the Keychain and put up
	// the pairing screen, and leave the device in the honest "not linked" state a fresh install has.
	function watchVerify(promise) {
		try {
			promise.then(function (res) {
				var dead = res.status >= 400 && res.status < 500;
				if (dead) { return linkRejected('rejected'); }
				if (!res.ok) { return; }                       // 5xx: the server is unwell, not the token
				res.clone().json().then(function (j) {
					if (j && j.signedIn !== true) { linkRejected(String(j && j.code || 'rejected')); }
				}).catch(function () {});
			}).catch(function () { /* offline: not the token's fault, keep it */ });
		} catch (e) {}
		return promise;
	}

	var rejectedOnce = false;
	function linkRejected(reason) {
		if (rejectedOnce) { return; }
		rejectedOnce = true;
		var w = activeWallet();
		dropAccount(w);
		try { sessionStorage.removeItem('chikResume'); } catch (e) {}
		refuse('/verify (' + reason + ')', 'link-rejected');
		// The shell owns the screen here — it has a pairing view and the web layer does not.
		announce('link-rejected', { wallet: w, reason: reason });
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

	/** A stable per-install id, so the server can name and revoke this device. Not a fingerprint.
	 *
	 *  IT MUST OUTLIVE A WEBVIEW DATA PURGE. The token is bound to it server-side, so an id that
	 *  regenerated when localStorage was cleared would make the Keychain restore fail for exactly
	 *  the event the Keychain exists to survive. Order: the shell's injected id wins, then the
	 *  fallback store, then a fresh one — and a fresh one is pushed straight back to the shell. */
	function deviceId() {
		if (memDeviceId) { return memDeviceId; }
		try {
			var v = localStorage.getItem(DEVICE_KEY);
			if (!v) {
				v = (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
					: 'd' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
				if (!shellHolds) { localStorage.setItem(DEVICE_KEY, v); }
			}
			memDeviceId = v;
			return v;
		} catch (e) { return memDeviceId || 'd-ephemeral'; }
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

	// ------------------------------------------------------------------ §6b shell version + pause
	//
	// A reviewed binary and a web layer that changes under it need two levers, because the App Store
	// update cycle is days and a bad deploy is hours:
	//
	//   1. THE PAGE CAN REFUSE A SHELL THAT IS TOO OLD. The shell injects its version; if the web
	//      layer has moved past what that build can drive (a new CHIK_LINK call, a changed persist
	//      record), it says so instead of failing in some subtler way. MIN_SHELL is raised here, in
	//      the same commit as the change that requires it.
	//   2. THE APP CAN BE PAUSED WITHOUT A RELEASE. CHIK_FEATURES is a local literal, so nothing
	//      server-side could ever turn the app off. applyRemoteConfig() lets the /verify envelope (or
	//      any allowed-host config the shell fetches) carry {paused, message, min_shell} and have it
	//      take effect on the next launch.
	//
	// Both only report. The shell owns the screen — it is the half with a view that is not the game.
	var MIN_SHELL = '1.0.0';

	function versionLess(a, b) {
		var x = String(a || '0').split('.').map(Number), y = String(b || '0').split('.').map(Number);
		for (var i = 0; i < 3; i++) {
			var p = x[i] || 0, q = y[i] || 0;
			if (p !== q) { return p < q; }
		}
		return false;
	}

	function checkShellVersion() {
		var v = window.CHIK_IOS_APP && window.CHIK_IOS_APP.version;
		if (!v) { return; }                       // an older shell that injects no version: nothing to compare
		if (versionLess(v, MIN_SHELL)) {
			announce('stale-shell', { version: String(v), minimum: MIN_SHELL });
		}
	}

	/** Let the server pause the app or raise the floor. Safe to call with anything. */
	window.CHIK_LINK_CONFIG = function (cfg) {
		if (!cfg || typeof cfg !== 'object') { return; }
		if (cfg.min_shell) { MIN_SHELL = String(cfg.min_shell); checkShellVersion(); }
		if (cfg.paused === true) {
			announce('paused', { message: String(cfg.message || T('maintenance')) });
		}
	};

	// ------------------------------------------------------------------ §7 what the shell calls
	//
	// The Swift side drives pairing through this object. status() reports the wallet and never the
	// credential; the credential reaches the shell only through the 'persist' record in §6, which is
	// the shell's own Keychain write.
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
			if (clean.length < 6) { return Promise.reject(new Error(T('codeShort'))); }
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
						throw new Error(j.error || T('codeBad'));
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
			setActive(w);
			try { sessionStorage.removeItem('chikResume'); } catch (e) {}
			announce('switched', { wallet: w });
			location.reload();
			return true;
		},

		/** Drop one account from this device, telling the server so the token stops working. */
		forget: function (wallet) {
			var w = String(wallet || activeWallet());
			var gone = dropAccount(w);
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
			setActive('');
			if (!shellHolds) { try { localStorage.removeItem(ACTIVE_KEY); } catch (e) {} }
			try { sessionStorage.removeItem('chikResume'); } catch (e) {}
			announce('unlinked', {});
			return Promise.all(all.map(function (a) {
				return realFetch(apiBase() + '/link/revoke', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({ wallet: a.wallet, linkToken: a.token, device_id: deviceId() }),
				}).catch(function () {});
			}));
		},

		/** For the shell to hand in a Keychain-held credential after document start. The injection in
		 *  §6 is the fast path; this is for a shell whose Keychain read finished too late for it. */
		setToken: function (wallet, token, label) {
			if (!wallet || !token) { return false; }
			adopt(String(wallet), String(token), String(label || ''));
			announce('linked', { wallet: String(wallet) });
			return true;
		},

		/** The device id the shell must store alongside the token — the token is bound to it. */
		deviceId: function () { return deviceId(); },

		features: function () { return window.CHIK_FEATURES; },
	};

	// Tell the shell where we stand as soon as the page is up, so it can decide between showing the
	// pairing screen and getting out of the way.
	checkShellVersion();
	announce('ready', {
		linked: !!activeAccount(),
		wallet: activeWallet(),
		deviceId: deviceId(),
		custody: shellHolds ? 'shell' : 'web',   // where the credential lives, so the shell can tell
	});
}());
