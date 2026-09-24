#!/usr/bin/env python3
"""Take every remaining trading surface out of the iOS app's pack.

    python3 godot-patch/apply-ios-pack-patch.py    /path/to/recovered
    python3 godot-patch/apply-ios-trading-patch.py /path/to/recovered [--check]

Run it AFTER `apply-ios-pack-patch.py`: its anchors are written against a project that already
carries those nineteen changes (and the `ChikFeat` class they add).

The first patcher removed the surfaces a reviewer meets first — the shop, the welcome screen's
wallet button, the Cup tab, the chat box. This one removes the rest, found by sweeping every string
literal in the recovered project for wallet, market, token and SOL wording and then tracing each one
to whatever draws it:

  * the WALLET tab and its popup (Connect/Sign in with Phantom, Solscan, "Open browser version")
  * PlayerPanel's Magic Eden rail tab, the NFT certificate and minting cards, listing/escrow copy
  * the Trading Post's own world prompt, minimap label and every background toast it raises when a
    listing sells or a bid is outbid on the website (the app keeps crediting; it just stops talking)
  * the Open Gates card and gate events that name the 500,000 $CHIKI entry gate
  * Chain.gd's sign-in toasts ("verifying your $CHIKI hold…") that fire on every app launch
  * $CHIKI / SOL payout lines in quests, the Temple, the Chikiseum and the help pages
  * the in-game news and Dispatch items that advertise trading (filtered by a keyword test)
  * and, as a safety net, the game's balance is NAMED "coins" wherever it is drawn: `ChikFeat`
    installs a TranslationServer translation that renames "$CHIKI" (the game uses TranslationServer
    for nothing else, and every Label, Button and RichTextLabel passes its text through it)

What it deliberately does NOT change — the owner's rule is that the app earns and the website
sells, on one account:
  * earning, gathering, hatching, quests, the Temple, PvP, saving — all unchanged, all synced
  * the coin pouch and its Collect button stay: that is an in-game purse, daily quests refuse to
    pay into a full pouch, and hiding Collect would stall an app player
  * no network call, save field or function signature changes; the loader (`realm/chiki-ios.js`)
    and the server still refuse every value-moving route on their own

Every change is gated on a `ChikFeat` key ("crypto", "wallet_connect", "trading_post",
"marketplace", "chikoria_cup"), all of which are true on the website, so the website's pack and
behaviour are untouched even though the two share source.

The edits live in `ios-trading-edits.json` beside this file, in application order: each OLD is
matched with the same trailing-whitespace-tolerant anchor as the first patcher, must occur exactly
once, and an edit whose NEW text is already present is skipped, so running twice is a no-op.
`--check` reports and writes nothing.

Known limit, left for the owner to decide (not something a patch should invent): story Chapter 36,
"Open for Business", REQUIRES listing an item on the Trading Post. The app shows it as "Trading
isn't part of the app" and an app-only player's main story waits there until the account lists
something on the website. Making that chapter optional, or giving the app a different objective for
it, is a game-design change. (Since then quests are out of the app altogether —
apply-ios-review-patch.py — so no app player is ever asked to do it.)

Afterwards: `godot --headless --path <project> --import`, then `--check-only` each changed script,
then compile the changed scripts (`gdre_tools --compile=… --bytecode=4.6.0`) into
`godot-patch/ios-overlay/` and run `build-ios-pack.py` + `chunk-pack.py --ios --lite`.
"""

import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

_spec = importlib.util.spec_from_file_location("ios_pack_patch", HERE / "apply-ios-pack-patch.py")
_first = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_first)
_find = _first._find


def apply_edits(root: Path, edits_path: Path, check: bool) -> int:
	"""Apply one edits file to the project at `root`. Shared with apply-ios-review-patch.py."""
	edits = json.loads(edits_path.read_text(encoding="utf-8"))
	texts: dict[str, str] = {}
	done = todo = 0
	failed = []
	for e in edits:
		f = e["file"]
		t = texts.get(f)
		if t is None:
			t = (root / f).read_text(encoding="utf-8")
		# "Already applied" is tested FIRST, and the order matters: many edits wrap the old line in a
		# new `if ChikFeat.on(...)`, so the old text still occurs inside the new one and a second run
		# would otherwise wrap it again.
		if _find(t, e["new"]) is not None:
			done += 1
			texts[f] = t
			continue
		m = _find(t, e["old"])
		if m is None:
			failed.append(e)
			continue
		texts[f] = t[:m.start()] + e["new"] + t[m.end():]
		todo += 1
		print(f"  {'??' if check else 'ok'}  {f}: {e['why'][:100]}")

	if failed:
		print(f"\nFAILED: {len(failed)} edit(s) did not match. Nothing was written.")
		for e in failed:
			print(f"  {e['file']}: {e['why'][:100]}")
		print("\nIs this the recovered project for the pack in realm/, with apply-ios-pack-patch.py applied?")
		return 1
	if check:
		print(f"\n--check: {todo} change(s) would be made, {done} already applied, nothing written.")
		return 0
	for f, t in texts.items():
		(root / f).write_text(t, encoding="utf-8")
	print(f"\n{todo} change(s) applied, {done} already present, across {len(texts)} file(s).")
	print("Now re-import, check-only each file, and compile the overlay (see this file's docstring).")
	return 0


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	check = "--check" in sys.argv
	if len(args) != 1:
		print(__doc__)
		return 2
	root = Path(args[0])
	if not (root / "ChikFeat.gd").is_file():
		print("error: ChikFeat.gd is missing — run apply-ios-pack-patch.py first")
		return 1
	return apply_edits(root, HERE / "ios-trading-edits.json", check)


if __name__ == "__main__":
	sys.exit(main())
