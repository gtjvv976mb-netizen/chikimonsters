#!/usr/bin/env python3
"""Build the iOS app's pack: the SHIPPED pack, with only the patched scripts swapped in.

    python3 godot-patch/ios-app-art.py realm/ godot-patch/ios-overlay/app-art
    python3 godot-patch/build-ios-pack.py realm/ godot-patch/ios-overlay out/index.pck
    python3 godot-patch/chunk-pack.py out/ realm/ --ios --lite

The app must not draw a marketplace, a wallet button or a chat box. The website must keep all
three. Those are drawn by GDScript inside the pack, so the two cannot share one — but they can
share almost all of one.

This takes the pack `realm/` already serves and rewrites **twenty-two files**: the nineteen compiled
scripts `apply-ios-pack-patch.py` and `apply-ios-trading-patch.py` change, the new `ChikFeat.gdc`
with its `.remap`, and the global class cache that registers `ChikFeat` as a class name. Out of
5,479 files. Textures, scenes, audio, card
art and every other script are carried over byte for byte.

WHY SO SMALL A CHANGE, measured rather than assumed. Compiling the *recovered* project and diffing
its compiled scripts against the shipped ones gives:

    91 scripts, 74 byte-identical, 17 different — but only 6 were patched.

The other 11 differ purely because decompiling and recompiling GDScript does not round-trip
byte-exactly. A full re-export would carry all 11 into the app for no reason. This carries none.

NO TOOLCHAIN NEEDED. The base can be the published chunks themselves, so rebuilding the iOS pack
needs neither GDRE Tools, nor a Godot editor, nor a web export template — only this repo and
Python. `base` may be:

  * a directory holding `index.pck.lite.*.bin` + its manifest (i.e. `realm/`)
  * a single `.pck` / `.pcz` / `.zip` file
  * an already-extracted directory

The output is a ZIP, which is what the shipped lite pack already is. **Godot recognises a zip pack
by file extension**, so `chunk-pack.py` writes `"fs_name": "index.pcz"` into the manifest and
`realm/index.html` mounts it under that name. A zip mounted as `index.pck` is refused with
"Cannot open resource pack" — a pack that downloads perfectly and never opens.
"""

import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

# Every file the iOS patch touches. Explicit rather than "whatever differs", so a regenerated
# overlay cannot smuggle an unrelated script into the app.
OVERLAY_FILES = [
	"Chain.gdc",
	"Chat.gdc",
	"ChikFeat.gdc",
	"Chikiseum.gdc",
	"ChikiseumArena.gdc",
	"ChikiseumEntry.gdc",
	"ChikiseumLiveClient.gdc",
	"Econ.gdc",
	"GameHUD.gdc",
	"Gather.gdc",
	"InfoBar.gdc",
	"Main.gdc",
	"Market.gdc",
	"Minimap.gdc",
	"Net.gdc",
	"Onboarding.gdc",
	"Player.gdc",
	"PlayerPanel.gdc",
	"Profile.gdc",
	"Temple.gdc",
	"Title.gdc",
	"ChikFeat.gd.remap",
	".godot/global_script_class_cache.cfg",
]

# Files the lite base is MISSING and the app needs, copied out of the HD pack. The lite family was
# exported without the Chikiseum gate crest, and `ChikiseumReferenceWorld.gd` preloads it — so in a
# lite pack that script fails to parse ("Preload file ... does not exist") and the Chikiseum arena
# world never loads on a phone. The imported scene is self-contained (no textures of its own).
# Extract them with:
#   gdre_tools --headless --extract=index.pck --include=res://<path> --output=godot-patch/ios-overlay
ADDED_FILES = [
	"assets/glb/chikiseum_higgsfield_crest.glb.import",
	".godot/imported/chikiseum_higgsfield_crest.glb-d1be0047d91385f697321cfa785cd320.scn",
]


def join_chunks(base: Path) -> bytes | None:
	"""Reassemble a chunked family exactly as realm/index.html does, if one is there."""
	for stem in ("index.pck.lite", "index.pck"):
		manifest = base / f"{stem}.manifest.json"
		if not manifest.is_file():
			continue
		man = json.loads(manifest.read_text(encoding="utf-8"))
		data = b"".join((base / name).read_bytes() for name in man["chunks"])
		if len(data) != man["total"]:
			raise SystemExit(f"error: {stem} chunks total {len(data):,}, manifest says {man['total']:,}")
		if man.get("sha256") and hashlib.sha256(data).hexdigest() != man["sha256"]:
			raise SystemExit(f"error: {stem} chunks do not match the sha256 in its manifest")
		print(f"base: {stem} reassembled from {len(man['chunks'])} chunks ({len(data):,} bytes)")
		return data
	return None


def read_base(base: Path) -> dict[str, bytes]:
	"""Return {path_in_pack: bytes} for a chunk directory, a zip file, or an extracted tree."""
	if base.is_dir():
		data = join_chunks(base)
		if data is not None:
			tmp = base / ".chiki-base-tmp.zip"
			try:
				tmp.write_bytes(data)
				if not zipfile.is_zipfile(tmp):
					raise SystemExit(
						"error: the base pack is not a zip.\n"
						"Only the lite family is a zip; a GDPC pack has to be extracted first:\n"
						"  ./gdre_tools.x86_64 --headless --extract=<pack> --output=extracted")
				with zipfile.ZipFile(tmp) as z:
					return {i.filename: z.read(i) for i in z.infolist() if not i.is_dir()}
			finally:
				tmp.unlink(missing_ok=True)
		out = {}
		for dirpath, _dirs, files in os.walk(base):
			for name in files:
				p = Path(dirpath) / name
				out[str(p.relative_to(base))] = p.read_bytes()
		print(f"base: {len(out):,} files from {base}")
		return out

	if zipfile.is_zipfile(base):
		with zipfile.ZipFile(base) as z:
			out = {i.filename: z.read(i) for i in z.infolist() if not i.is_dir()}
		print(f"base: {len(out):,} files from {base}")
		return out

	raise SystemExit(f"error: {base} is neither a chunk directory, a zip pack, nor an extracted tree")


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	if len(args) != 3:
		print(__doc__)
		return 2
	base, overlay, out = Path(args[0]), Path(args[1]), Path(args[2])

	if not overlay.is_dir():
		print(f"error: {overlay} is not a directory")
		return 1
	missing = [f for f in OVERLAY_FILES + ADDED_FILES if not (overlay / f).is_file()]
	if missing:
		print("error: the overlay is incomplete:")
		for f in missing:
			print(f"  {f}")
		return 1

	files = read_base(base)
	absent = [f for f in OVERLAY_FILES if f not in files and not f.startswith("ChikFeat")]
	if absent:
		print("error: the base pack does not contain files this expects to replace:")
		for f in absent:
			print(f"  {f}")
		print("\nIs this the right pack? The overlay targets build 1eb4980816.")
		return 1

	# ios-app-art.py's output: the faceless meme egg and class badge at the pack's own imported
	# paths, and the app's title art. Replaced or added as they are.
	art = overlay / "app-art"
	art_files = sorted(str(p.relative_to(art)) for p in art.rglob("*") if p.is_file()) if art.is_dir() else []
	if not art_files:
		print("error: godot-patch/ios-overlay/app-art is empty — run godot-patch/ios-app-art.py first")
		return 1

	replaced = added = unchanged = 0
	for rel in art_files:
		if rel in files:
			replaced += 1
		else:
			added += 1
		files[rel] = (art / rel).read_bytes()
	for rel in ADDED_FILES:
		if rel not in files:
			files[rel] = (overlay / rel).read_bytes()
			added += 1
	for rel in OVERLAY_FILES:
		blob = (overlay / rel).read_bytes()
		if rel in files:
			if files[rel] == blob:
				unchanged += 1
			replaced += 1
		else:
			added += 1
		files[rel] = blob

	# Deterministic: sorted names and a fixed timestamp, which is also what the shipped pack uses
	# (every entry in it is dated 1980-01-01). Two runs over the same inputs give the same bytes,
	# so the pack can be diffed and its sha256 quoted in a release note.
	out.parent.mkdir(parents=True, exist_ok=True)
	with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
		for rel in sorted(files):
			info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
			info.compress_type = zipfile.ZIP_DEFLATED
			info.create_system = 3          # Unix, as the shipped pack reports
			info.external_attr = 0o644 << 16
			z.writestr(info, files[rel])

	with zipfile.ZipFile(out) as z:
		bad = z.testzip()
	if bad:
		print(f"FAILED: corrupt entry {bad}")
		return 1

	kept = len(files) - replaced - added
	print(f"wrote {out}  ({out.stat().st_size:,} bytes)")
	print(f"  {kept:,} files carried over byte-for-byte")
	print(f"  {replaced} replaced, {added} added"
	      + (f"  ** {unchanged} of the replacements were IDENTICAL — is the overlay stale? **" if unchanged else ""))
	print("\nzip verified. Now chunk it for realm/:")
	print(f"  python3 godot-patch/chunk-pack.py {out.parent} realm/ --ios --lite")
	return 0


if __name__ == "__main__":
	sys.exit(main())
