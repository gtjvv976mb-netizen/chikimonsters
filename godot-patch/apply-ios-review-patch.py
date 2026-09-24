#!/usr/bin/env python3
"""App Review changes to the iOS app's pack: no quests, and no third-party characters.

    python3 godot-patch/apply-ios-pack-patch.py     /path/to/recovered
    python3 godot-patch/apply-ios-trading-patch.py  /path/to/recovered
    python3 godot-patch/apply-ios-review-patch.py   /path/to/recovered [--check]

Run it LAST: its anchors are written against a project that already carries the other two.

Two changes, both app-only:

  * QUESTS ARE OFF IN THE APP. The story, the dailies, the side-quest chains and every pointer to
    them (the Quests tab, the pinned objective on the left dock, the how-to topic, tutorial copy)
    are gated on `ChikFeat.on("quests")`, which `realm/chiki-ios.js` sets false in the app and true
    on the website. Progress still COUNTS in the app — `quest_progress` is untouched and saves with
    the profile — so a player who later opens the website finds their chapters where they left
    them. This also retires the Chapter 36 problem: the chapter that required a Trading Post
    listing is no longer something an app player is asked to do.

  * THE MEME DYNASTY IS NOT IN THE APP (yet). Pepe, Doge, Grumpy Cat, Success Kid, This Is Fine, Moo
    Deng, Chill Guy and the caricatures of real people (Alon, Ansem, Side-eye Chloe) are third-party
    characters and likenesses — App Review 5.2.1 / 5.2.2. The owner's plan is to bring them into the
    app ONE AT A TIME, so the switch is per species: `CHIK_FEATURES.meme_allow` in
    `realm/chiki-ios.js` (empty today). Nothing is deleted from anyone's account. Profile.gd sets a
    hidden species' creatures (and, while none is allowed, meme eggs) ASIDE for the session and puts
    them back, exactly where they were, before every save, cloud upload and NFT hand-off — the save
    signature covers units and eggs, so the file on disk and the server copy are always complete.
    Hatching, the Chikidex, Mithra's egg card, the shop's display egg, other players' companions and
    the title art all skip what is hidden. `build-ios-pack.py` also swaps the two images that show
    meme faces (the meme egg and the Meme Dynasty class badge) for faceless ones in the app's pack.
    Known gap: a PvP opponent from the website can still field one in a Chikiseum match.

The edits live in `ios-review-edits.json`, applied with the same matcher and idempotency as
`apply-ios-trading-patch.py`.
"""

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

_spec = importlib.util.spec_from_file_location("ios_trading_patch", HERE / "apply-ios-trading-patch.py")
_trading = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_trading)


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
	return _trading.apply_edits(root, HERE / "ios-review-edits.json", check)


if __name__ == "__main__":
	sys.exit(main())
