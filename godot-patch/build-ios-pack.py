#!/usr/bin/env python3
"""Build the iOS app's pack from the SHIPPED pack plus only the scripts the patch changed.

    python3 godot-patch/build-ios-pack.py <shipped-extract> <patched-extract> <out.zip>

The iOS app needs a pack where the shop, the wallet button and the chat box are not drawn. The
website must keep the pack it has. The obvious way to get there — re-export the recovered project
and ship that to the app — replaces every asset and every script at once, and it is far more
change than the job needs.

This does the small version instead. Godot loads a ZIP as a pack (the shipped
`index.pck.lite.*.bin` family already is one), so the iOS pack is built as:

    everything from the shipped pack, byte for byte
    + the handful of compiled scripts `apply-ios-pack-patch.py` actually changed

Textures, scenes, audio, the card art and every other script stay exactly as they are today.

WHY THIS MATTERS, measured rather than assumed. Compiling the *recovered* project and diffing its
compiled scripts against the shipped ones:

    91 scripts, 74 byte-identical, 17 different — but only 6 were patched.

The other 11 differ purely because decompiling and recompiling GDScript does not round-trip
byte-exactly. Shipping a whole re-export would carry all 11 of those into the app for no reason.
Swapping only the patched files holds the exposure to the 6 that had to change.

`.godot/global_script_class_cache.cfg` comes across too: `ChikFeat` declares a `class_name`, and
that cache is what registers a global class at runtime. Without it the patched scripts load and
then fail on `Identifier "ChikFeat" not declared`.

Getting the two input directories (GDRE Tools, `--extract`, which copies bytes verbatim rather
than reconstructing them):

    ./gdre_tools.x86_64 --headless --extract=index.pck.lite      --output=shipped-lite
    ./gdre_tools.x86_64 --headless --extract=out/index.pck       --output=patched

Then chunk the result for `realm/` with `godot-patch/chunk-pack.py`.
"""

import hashlib
import os
import sys
import zipfile
from pathlib import Path

# Written by the patch; not present in the shipped pack.
ADDED = ["ChikFeat.gdc", "ChikFeat.gd.remap"]

# Changed by the patch. Kept explicit rather than "whatever differs", so a re-export that happens
# to perturb an unrelated script cannot smuggle it into the app.
REPLACED = [
	"GameHUD.gdc",
	"Chikiseum.gdc",
	"Onboarding.gdc",
	"Chat.gdc",
	"InfoBar.gdc",
	".godot/global_script_class_cache.cfg",
]


def sha(p: Path) -> str:
	return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	if len(args) != 3:
		print(__doc__)
		return 2
	shipped, patched, out = Path(args[0]), Path(args[1]), Path(args[2])

	for d in (shipped, patched):
		if not d.is_dir():
			print(f"error: {d} is not a directory")
			return 1

	missing = [f for f in ADDED + REPLACED if not (patched / f).is_file()]
	if missing:
		print("error: the patched export is missing files this script must copy:")
		for f in missing:
			print(f"  {f}")
		print("\nDid apply-ios-pack-patch.py run before the export?")
		return 1

	absent = [f for f in REPLACED if not (shipped / f).is_file()]
	if absent:
		print("error: the shipped pack does not contain files this script expects to replace:")
		for f in absent:
			print(f"  {f}")
		return 1

	swap = {f: patched / f for f in ADDED + REPLACED}
	unchanged = identical = 0

	out.parent.mkdir(parents=True, exist_ok=True)
	with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
		for dirpath, _dirs, files in os.walk(shipped):
			for name in sorted(files):
				src = Path(dirpath) / name
				rel = str(src.relative_to(shipped))
				if rel in swap:
					continue                      # written below, from the patched export
				z.write(src, rel)
				unchanged += 1
		for rel, src in sorted(swap.items()):
			shipped_copy = shipped / rel
			if shipped_copy.is_file() and sha(shipped_copy) == sha(src):
				identical += 1
			z.write(src, rel)

	print(f"wrote {out}  ({out.stat().st_size:,} bytes)")
	print(f"  {unchanged:,} files carried over byte-for-byte from the shipped pack")
	print(f"  {len(swap)} files taken from the patched export:")
	for rel in sorted(swap):
		note = "  (identical to shipped — patch had no effect here?)" if identical and sha(shipped / rel) == sha(swap[rel]) else ""
		print(f"      {rel}{note}")

	with zipfile.ZipFile(out) as z:
		bad = z.testzip()
	if bad:
		print(f"FAILED: corrupt entry {bad}")
		return 1
	print("\nzip verified. Chunk it for realm/ with:")
	print(f"  python3 godot-patch/chunk-pack.py <dir containing this as index.pck> realm/ --ios")
	return 0


if __name__ == "__main__":
	sys.exit(main())
