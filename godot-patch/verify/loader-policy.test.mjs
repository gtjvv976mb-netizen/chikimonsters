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
	check(at("if (!window.CHIK_NO_CRYPTO) { document.write('<scr' + 'ipt src=\"solana-web3.js\"") > 0,
		'the Solana library is written only when crypto is allowed');

	const guard = at('if (!window.CHIK_NO_CRYPTO) {\n\t\twindow.__chikiBuy = async function');
	check(guard > 0, 'the Trading Post bridge (__chikiBuy) is behind the guard');
	check(at("}   // if (!window.CHIK_NO_CRYPTO)") > guard, 'and that guard is closed');

	check(at('if (window.CHIK_NO_CRYPTO) { return; }\n\n\t\t\tvar B58 =') > 0,
		'the Magic Eden bridge bails before it defines a signer');

	check(at('// THE APP HAS NO WALLET TO STAY SIGNED IN TO.') > 0
		&& at('if (window.CHIK_NO_CRYPTO) { return; }\n\t\tvar KEY = \'chikSignin\';') > 0,
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
