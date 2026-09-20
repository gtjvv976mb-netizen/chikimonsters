/* A TRIPWIRE FOR realm/index.html.
 *
 * Promoting a new Godot export OVERWRITES realm/index.html (DEPLOY.md and ../README.md both say
 * so). Every hook that makes the iOS app gameplay-only lives in that file, and losing one of them
 * does not fail loudly: the app would simply boot with a working Phantom bridge again and ship a
 * Trading Post to the App Store. So each hook is asserted here by name, and re-applying them after
 * an export is not done until this passes.
 *
 * It checks WIRING, not behaviour — chiki-ios.test.mjs is what proves the policy itself works.
 *
 * Run:
 *   node godot-patch/verify/loader-policy.test.mjs        # exits non-zero on any failure
 */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
const vm = require('node:vm');

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const html = readFileSync(join(ROOT, 'realm', 'index.html'), 'utf8');

let failures = 0;
function check(ok, label) {
	if (ok) { console.log('  ok    ' + label); }
	else { failures++; console.log('  FAIL  ' + label); }
}
const at = (needle) => html.indexOf(needle);
const policy = readFileSync(join(ROOT, 'realm', 'chiki-ios.js'), 'utf8');

/** Match a pattern tolerant of whitespace, so reformatting does not fail a correct file.
 *  Write the needle as source text; every run of spaces/newlines becomes \s+. */
function loose(text) {
	const escaped = text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	return new RegExp(escaped.replace(/\s+/g, '\\s*'));
}
const hasLoose = (src, text) => loose(text).test(src);

console.log('\nthe policy layer is loaded, and loaded first');
{
	const policy = at('<script src="chiki-ios.js"></script>');
	check(policy > 0, 'realm/index.html loads chiki-ios.js');

	// Every other script in the document must come after it: the guard has to be installed before
	// anything that could use a wallet, or could define one, has parsed.
	const scripts = [...html.matchAll(/<script\b/gi)].map((m) => m.index);
	check(scripts.length > 0 && Math.min(...scripts) === policy,
		'it is the FIRST script in the document');

	const head = html.indexOf('</head>');
	check(policy < head, 'and it is in <head>, before the body parses');
}

console.log('\nthe crypto bridges are gated');
{
	check(!/<script\s+src="solana-web3\.js"\s*>/.test(html),
		'there is no unconditional <script src="solana-web3.js">');
	check(hasLoose(html, `if (!window.CHIK_NO_CRYPTO) { document.write('<scr' + 'ipt src="solana-web3.js"`),
		'the Solana library is written only when crypto is allowed');

	check(hasLoose(html, 'if (!window.CHIK_NO_CRYPTO) { window.__chikiBuy = async function'),
		'the Trading Post bridge (__chikiBuy) is behind the guard');
	const guard = html.search(loose('if (!window.CHIK_NO_CRYPTO) { window.__chikiBuy = async function'));
	check(html.indexOf('// if (!window.CHIK_NO_CRYPTO)', guard) > guard, 'and that guard is closed');

	check(hasLoose(html, "if (window.CHIK_NO_CRYPTO) { return; } var B58 ="),
		'the Magic Eden bridge bails before it defines a signer');

	check(at('// THE APP HAS NO WALLET TO STAY SIGNED IN TO.') > 0
		&& hasLoose(html, "if (window.CHIK_NO_CRYPTO) { return; } var KEY = 'chikSignin';"),
		'the Phantom stay-signed-in bridge bails');
}

console.log('\nthe app is told to resume its linked account');
{
	check(at('window.__chikSigninSeedResume()') > 0,
		'run() still calls __chikSigninSeedResume before the engine starts');
	const src = readFileSync(join(ROOT, 'realm', 'chiki-ios.js'), 'utf8');
	check(/window\.__chikSigninSeedResume\s*=/.test(src),
		'chiki-ios.js defines it for the app (the web bridge defines its own)');
}

console.log('\nthe loading screen does not advertise what the app refuses to do');
{
	check(at("['rewards', 'token'].forEach") > 0, 'the REWARDS and $CHIKI tabs are removed in the app');
	check(at("bullet('lp-play2', 'Trade with players', null)") > 0, 'the Trading Post bullet is removed');
	check(at("bullet('lp-play2', 'Sign in with Phantom',") > 0, 'the Phantom sign-in bullet is rewritten');
	check(at('if (!window.CHIK_NO_CRYPTO) { return; }') > 0, 'and the whole rewrite is app-only');
	// The first pass rewrote WELCOME and HOW TO PLAY and missed ROLES entirely — the heaviest money
	// panel on the screen. These pin the panels that were missed so a re-export cannot lose them again.
	check(at("card('lp-roles', 'Merchant', null)") > 0, 'the Merchant role (it IS the marketplace) is removed');
	check(at("card('lp-roles', 'Gatherer',") > 0, 'the Gatherer role stops selling at the Trading Post');
	check(at("card('lp-roles', 'Battler',") > 0, 'the Battler role stops promising a SOL prize');
	check(at("card('lp-regions', 'Chikiville',") > 0, 'the Trading Post is not listed as a landmark');

	// EVERY money panel must be handled by name. If a new one is added upstream and nobody rewrites
	// it, this fails rather than shipping an app that advertises what it refuses.
	const MONEY_PANELS = ['lp-about', 'lp-play2', 'lp-roles', 'lp-regions'];
	const REMOVED_PANELS = ['lp-rewards', 'lp-token'];
	// Bound each panel by the START OF THE NEXT ONE. A fixed-size window overran into the following
	// panel and reported lp-chikis and lp-community as money-bearing because lp-play2 follows them.
	const marks = [...html.matchAll(/class="lpanel" id="(lp-[a-z0-9]+)"/gi)].map((m) => ({ id: m[1], at: m.index }));
	const moneyish = marks.filter((m, i) => {
		const end = i + 1 < marks.length ? marks[i + 1].at : html.indexOf('<div id="hero">', m.at);
		const body = html.slice(m.at, end > m.at ? end : m.at + 4000);
		return /\$CHIKI|Trading Post|Solscan|SOL prize|Magic Eden|on-chain/i.test(body);
	}).map((m) => m.id);
	const unhandled = moneyish.filter((id) => !MONEY_PANELS.includes(id) && !REMOVED_PANELS.includes(id));
	check(unhandled.length === 0,
		'no money-bearing loading panel is left unhandled' + (unhandled.length ? ' (found: ' + unhandled.join(', ') + ')' : ''));
}

console.log('\nthe policy layer still carries every guard');
{
	check(/window\.open\s*=\s*function/.test(policy), 'window.open is wrapped (the engine hands it to the pack)');
	check(/addEventListener\('click',[\s\S]*?\}, true\)/.test(policy), 'anchor clicks are caught in the capture phase');
	check(/addEventListener\('submit',[\s\S]*?\}, true\)/.test(policy), 'and form posts');
	check(/window\.EventSource\s*=\s*GuardES/.test(policy), 'EventSource is guarded');
	check(/function\s+isNewsFeed/.test(policy) && /function\s+filterNews/.test(policy),
		'the in-game news feed is filtered');
	check(/function\s+linkRejected/.test(policy), 'a rejected link token has a recovery path');
	check(/function\s+persistToShell/.test(policy), 'the Keychain handoff exists');
	check(/MIN_SHELL/.test(policy) && /stale-shell/.test(policy), 'the shell version handshake exists');
	check(/CHIK_LINK_CONFIG/.test(policy), 'the server can pause the app without a release');
	// The steering rule: the refusal copy must not name an outside destination (guideline 3.1.1).
	const nope = (policy.match(/var NOPE = '([^']+)'/) || [])[1] || '';
	check(nope.length > 0 && !/chikimonsters\.com|website/i.test(nope),
		'the refusal copy names no outside store');
}

console.log('\nevery inline script still parses');
{
	const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
	let m, n = 0, bad = 0;
	while ((m = re.exec(html))) {
		n++;
		try { new vm.Script(m[1], { filename: 'inline-' + n }); }
		catch (e) { bad++; console.log('        block ' + n + ': ' + e.message); }
	}
	check(n >= 10 && bad === 0, n + ' inline blocks, ' + bad + ' parse failures');
}

console.log(failures === 0 ? '\nAll checks passed.\n' : '\n' + failures + ' check(s) FAILED.\n');
process.exit(failures === 0 ? 0 : 1);
