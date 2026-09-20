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

What it does, all three gated on the loader's published policy and therefore no-ops on the
website:

  1. adds `ChikFeat.gd`, a five-line reader for `window.CHIK_FEATURES`
  2. `GameHUD.open_market()` refuses when `trading_post` is off — that one function is the only
     way into the marketplace (`Player.gd` is its sole caller, at the Trading Post's world
     location), so gating it removes the Magic Eden tab and every Phantom purchase string with it
  3. the Chikiseum drops its **Chikoria Cup** tab when `crypto` is off, and stops claiming
     "champions win real SOL" in HOW TO BATTLE — the Cup pays a real SOL prize pool and is the
     Chikiseum's default tab, so it is the first thing a reviewer would see

It does NOT touch PvP. The Chikiseum's duels are already stake-free and stay exactly as they are.

Idempotent: running it twice is a no-op. `--check` reports what would change and writes nothing.

Afterwards — **re-import first**, then verify:

    godot --headless --path <project> --import
    godot --headless --path <project> --check-only --script res://GameHUD.gd

The import is not optional and the failure it prevents is misleading. `ChikFeat.gd` declares a
`class_name`, and a global class is only registered when Godot rescans the filesystem. Skip the
rescan and the two patched scripts fail with `Identifier "ChikFeat" not declared in the current
scope` — which reads like a bug in this patch and is not one.
"""

import sys
from pathlib import Path

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

EDITS = [
	("GameHUD.gd", MARKET_OLD, MARKET_NEW, "the Trading Post refuses when trading is off"),
	("Chikiseum.gd", TABS_OLD, TABS_NEW, "the Chikoria Cup tab is not built"),
	("Chikiseum.gd", OPEN_OLD, OPEN_NEW, "the Chikiseum opens on My Deck, not the Cup"),
	("Chikiseum.gd", HOW_OLD, HOW_NEW, '"champions win real SOL" is not drawn'),
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
		if new in text:
			done.append(f"{name}: {label} (already applied)")
		elif text.count(old) == 1:
			planned.append((name, (old, new), label))
		else:
			failed.append(f"{name}: {label} — anchor found {text.count(old)}x, expected 1")

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
		else:
			old, new = edit
			path.write_text(path.read_text(encoding="utf-8").replace(old, new, 1), encoding="utf-8")

	if not planned:
		print("\nNothing to do — already patched.")
		return 0

	print(f"\nApplied {len(planned)} change(s). Re-import FIRST, or the new class_name will not")
	print("be registered and the patched scripts will not parse:")
	print(f"  godot --headless --path {root} --import")
	for f in ("ChikFeat.gd", "GameHUD.gd", "Chikiseum.gd"):
		print(f"  godot --headless --path {root} --check-only --script res://{f}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
