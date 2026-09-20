#!/usr/bin/env python3
"""Make the compiled game hide what the iOS app is not allowed to present.

    python3 godot-patch/apply-ios-pack-patch.py /path/to/recovered [--check]

`realm/chiki-ios.js` can already stop every crypto capability from *working* in the app — no
wallet, no transaction, no marketplace request. What it cannot do is stop the pack from *drawing*
a shop, because that is GDScript building its own UI. App Review guideline 3.1.1 is about what an
app presents, so the drawing has to stop too, and only a rebuilt pack can stop it.

This script is that change. It is deliberately a patcher rather than a diff: the project it edits
is recovered game source and must not be committed to this repository (`RECOVERY.md` explains
why), so what lives here is the *instruction*, not the code.

Eight changes, every one gated on the loader's published policy and therefore a no-op on the
website:

  1. adds `ChikFeat.gd`, a small reader for `window.CHIK_FEATURES`
  2. `GameHUD.open_market()` refuses when `trading_post` is off — that one function is the only
     way into the marketplace (`Player.gd` is its sole caller, at the Trading Post's world
     location), so gating it removes the Magic Eden tab and every Phantom purchase string with it
  3. the Chikiseum drops its **Chikoria Cup** tab when `crypto` is off, opens on My Deck instead,
     and stops claiming "champions win real SOL" in HOW TO BATTLE — the Cup pays a real SOL prize
     pool and was the default tab, so it is the first thing a reviewer would have seen
  4. the wallet gate stops naming Phantom and stops drawing its "Get Phantom ↗" button
  5. the token gate stops telling the player to "Hold 500,000 $CHIKI to enter"

It does NOT touch PvP. The Chikiseum's duels are already stake-free and stay exactly as they are.

It does not change any GATE'S BEHAVIOUR either — only what the gate says. Whether an app player
needs the 500k hold is an open product decision and the server's to enforce; this makes the refusal
readable without naming a token, an amount, or somewhere to go and get one.

Idempotent: running it twice is a no-op. `--check` reports what would change and writes nothing.

Afterwards — **re-import first**, then verify:

    godot --headless --path <project> --import
    godot --headless --path <project> --check-only --script res://GameHUD.gd

The import is not optional and the failure it prevents is misleading. `ChikFeat.gd` declares a
`class_name`, and a global class is only registered when Godot rescans the filesystem. Skip the
rescan and the two patched scripts fail with `Identifier "ChikFeat" not declared in the current
scope` — which reads like a bug in this patch and is not one.
"""

import re
import sys
from pathlib import Path


def _anchor(text: str) -> "re.Pattern[str]":
	"""An anchor that ignores trailing whitespace at the end of each line.

	Decompiled GDScript keeps a trailing space after some argument commas, and that space does not
	survive every editor, diff or copy-paste on the way here. Matching on it exactly means the
	script fails against a project that is, for its purposes, identical. Everything else — the
	indentation, which is tabs, and the text itself — still has to match exactly.
	"""
	return re.compile(r"[ \t]*\n".join(re.escape(line.rstrip()) for line in text.split("\n")) + r"[ \t]*")


def _find(text: str, old: str):
	"""Return the single match for `old`, or None if it is absent or ambiguous."""
	found = list(_anchor(old).finditer(text))
	return found[0] if len(found) == 1 else None

CHIKFEAT = '''class_name ChikFeat
## The feature policy the page publishes as window.CHIK_FEATURES.
##
## realm/chiki-ios.js sets it: every flag true on the website, the restricted set inside the iOS
## app. Read once and cached, because JavaScriptBridge.eval is not free and the policy cannot
## change within a session.
##
## A missing or unreadable policy means "not restricted". That is the website's behaviour and the
## right default for it; the app's guarantee does not rest on this file, it rests on the loader,
## which also removes the wallet and the transaction library. godot-patch/verify/
## loader-policy.test.mjs is the tripwire that keeps the loader wired up.

static var _cache: Dictionary = {}
static var _read: bool = false


static func _all() -> Dictionary:
	if _read:
		return _cache
	_read = true
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.CHIK_FEATURES || {})", true)
		if raw is String:
			var parsed: Variant = JSON.parse_string(String(raw))
			if parsed is Dictionary:
				_cache = parsed
	return _cache


static func on(key: String) -> bool:
	return bool(_all().get(key, true))
'''

MARKET_OLD = '''func open_market() -> void :
	if _intro.visible or not _refs():
		return
	if bool(_profile.get("demo")):'''

MARKET_NEW = '''func open_market() -> void :
	if _intro.visible or not _refs():
		return
	if not ChikFeat.on("trading_post"):
		_toast("The Trading Post is not part of the app. Everything you earn here is yours to keep.", Color(0.9, 0.8, 0.6))
		return
	if bool(_profile.get("demo")):'''

TABS_OLD = '''	for t in [["cup", "\U0001F3C6 Chikoria Cup"], ["deck", "\U0001F0CF My Deck"], ["how", "⚔️ How to Battle"]]:'''

TABS_NEW = '''	var _visible_tabs: Array = [["cup", "\U0001F3C6 Chikoria Cup"], ["deck", "\U0001F0CF My Deck"], ["how", "⚔️ How to Battle"]]
	if not ChikFeat.on("crypto"):
		_visible_tabs.remove_at(0)
	for t in _visible_tabs:'''

OPEN_OLD = '''	_tab = "cup"
	_rebuild()'''

OPEN_NEW = '''	_tab = "cup" if ChikFeat.on("crypto") else "deck"
	_rebuild()'''

HOW_OLD = '''	_lbl(rew, "\U0001F3DF The Chikiseum hosts only the CHIKORIA CUP — champions win real SOL.", 12, GOLD)'''

HOW_NEW = '''	if ChikFeat.on("crypto"):
		_lbl(rew, "\U0001F3DF The Chikiseum hosts only the CHIKORIA CUP — champions win real SOL.", 12, GOLD)'''

# The wallet gate in Onboarding._show_gate(). In the app this screen should not be reachable at all
# — Realm Link signs the player in before it matters — but it IS reachable when a link is rejected
# or /verify fails, and what it draws then is a "Get Phantom  →" button pointing at phantom.app.
# The navigation guard in chiki-ios.js stops that button from going anywhere (OS.shell_open compiles
# to window.open, which is guarded), so this is about what is on screen, not what it does.
#
# The `else` branch is no good as a fallback either: it sends the player to the browser version,
# which is an outside destination for a problem the app can state plainly instead.
GATE_OLD = '''		if OS.has_feature("web"):
			_wallet_primary(v, "Waiting for Phantom…" if signing else "Sign in with Phantom", _phantom_connect, not signing, "res://ico_connect.png")
			_wallet_security_strip(v)
			var getp: = _btn(v, "Get Phantom  ↗", func(): OS.shell_open("https://phantom.app/"), true)
			getp.custom_minimum_size = Vector2(150, 30)
		else:'''

GATE_NEW = '''		if not ChikFeat.on("crypto"):
			_wallet_notice(v, "This device is not linked", "Link it to your Chikoria account to play. You can do that from the app's pairing screen.", UISkin.RED)
		elif OS.has_feature("web"):
			_wallet_primary(v, "Waiting for Phantom…" if signing else "Sign in with Phantom", _phantom_connect, not signing, "res://ico_connect.png")
			_wallet_security_strip(v)
			var getp: = _btn(v, "Get Phantom  ↗", func(): OS.shell_open("https://phantom.app/"), true)
			getp.custom_minimum_size = Vector2(150, 30)
		else:'''

# The token gate. When the account holds less than 500,000 $CHIKI and no waiver applies, the app
# tells the player: "Hold 500,000 $CHIKI to enter." That is an instruction to go and acquire half a
# million units of a crypto token in order to play an App Store app, which is a 3.1.1 problem on its
# own and reads as a purchase requirement besides.
#
# This changes the WORDS ONLY. Whether an app player needs the hold at all is a product decision
# that is still open (IOS-APP.md), and it is the server's to enforce either way — so the gate still
# closes exactly when it closed before. It just stops naming a token and an amount, and stops
# offering a "check balance again" button whose only remedy is buying some.
GATE_HOLD_OLD = '''			_wallet_notice(v, "More $CHIKI required",
				"Hold 500,000 $CHIKI to enter. Your wallet is connected safely. Played during an Open Gates event? Your progress and cloud save are kept safe — hold 500,000 $CHIKI and sign in again to continue right where you left off.",
				UISkin.RED)
			_wallet_primary(v, "Check balance again", _recheck_wallet, true, "res://ico_wallet.png")'''

GATE_HOLD_NEW = '''			if ChikFeat.on("crypto"):
				_wallet_notice(v, "More $CHIKI required",
					"Hold 500,000 $CHIKI to enter. Your wallet is connected safely. Played during an Open Gates event? Your progress and cloud save are kept safe — hold 500,000 $CHIKI and sign in again to continue right where you left off.",
					UISkin.RED)
				_wallet_primary(v, "Check balance again", _recheck_wallet, true, "res://ico_wallet.png")
			else:
				_wallet_notice(v, "This account cannot enter yet",
					"Your progress and cloud save are safe. Nothing is lost — open Chikoria on the web with this account to see what it needs.",
					UISkin.RED)'''

# The notice above that block names Phantom too, so it cannot stand on its own in the app.
NOTICE_OLD = '''		_wallet_notice(v, "One secure step", "Approve a sign-in message in Phantom. This proves the wallet is yours and restores your cloud save.", Color("a98bff"), "res://ico_connect.png")'''

NOTICE_NEW = '''		if ChikFeat.on("crypto"):
			_wallet_notice(v, "One secure step", "Approve a sign-in message in Phantom. This proves the wallet is yours and restores your cloud save.", Color("a98bff"), "res://ico_connect.png")'''

EDITS = [
	("GameHUD.gd", MARKET_OLD, MARKET_NEW, "the Trading Post refuses when trading is off"),
	("Chikiseum.gd", TABS_OLD, TABS_NEW, "the Chikoria Cup tab is not built"),
	("Chikiseum.gd", OPEN_OLD, OPEN_NEW, "the Chikiseum opens on My Deck, not the Cup"),
	("Chikiseum.gd", HOW_OLD, HOW_NEW, '"champions win real SOL" is not drawn'),
	("Onboarding.gd", GATE_HOLD_OLD, GATE_HOLD_NEW, 'the 500k token gate stops naming a token'),
	("Onboarding.gd", NOTICE_OLD, NOTICE_NEW, 'the wallet gate stops naming Phantom'),
	("Onboarding.gd", GATE_OLD, GATE_NEW, 'the "Get Phantom" button is not drawn'),
]


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("-")]
	check = "--check" in sys.argv
	if len(args) != 1:
		print(__doc__)
		return 2

	root = Path(args[0])
	if not (root / "project.godot").is_file():
		print(f"error: {root} is not a Godot project (no project.godot)")
		return 1

	planned, done, failed = [], [], []

	target = root / "ChikFeat.gd"
	if target.exists():
		done.append("ChikFeat.gd already present")
	else:
		planned.append(("ChikFeat.gd", None, "adds the window.CHIK_FEATURES reader"))

	for name, old, new, label in EDITS:
		path = root / name
		if not path.is_file():
			failed.append(f"{name}: missing")
			continue
		text = path.read_text(encoding="utf-8")
		if _find(text, new):
			done.append(f"{name}: {label} (already applied)")
		elif _find(text, old):
			planned.append((name, (old, new), label))
		else:
			n = len(list(_anchor(old).finditer(text)))
			failed.append(f"{name}: {label} — anchor found {n}x, expected 1")

	for line in done:
		print(f"  --  {line}")
	for name, edit, label in planned:
		print(f"  {'??' if check else '->'}  {name}: {label}")
	for line in failed:
		print(f"  !!  {line}")

	if failed:
		print("\nRefusing to patch: the project does not match what this script was written "
		      "against.\nIt targets the build recovered from pack 1eb4980816 — see RECOVERY.md.")
		return 1

	if check:
		print(f"\n--check: {len(planned)} change(s) would be made, nothing written.")
		return 0

	for name, edit, _label in planned:
		path = root / name
		if edit is None:
			path.write_text(CHIKFEAT, encoding="utf-8")
			continue
		old, new = edit
		text = path.read_text(encoding="utf-8")
		hit = _find(text, old)
		if hit is None:
			print(f"  !!  {name}: anchor moved while patching — nothing further written")
			return 1
		path.write_text(text[:hit.start()] + new + text[hit.end():], encoding="utf-8")

	if not planned:
		print("\nNothing to do — already patched.")
		return 0

	print(f"\nApplied {len(planned)} change(s). Re-import FIRST, or the new class_name will not")
	print("be registered and the patched scripts will not parse:")
	print(f"  godot --headless --path {root} --import")
	for f in ("ChikFeat.gd", "GameHUD.gd", "Chikiseum.gd", "Onboarding.gd"):
		print(f"  godot --headless --path {root} --check-only --script res://{f}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
