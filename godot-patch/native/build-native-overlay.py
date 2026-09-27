#!/usr/bin/env python3
"""Build godot-patch/native/overlay/ — the files the native iOS app's pack replaces or adds.

    python3 godot-patch/native/build-native-overlay.py /path/to/recovered /path/to/gdre_tools.x86_64

`recovered` is the project the web iOS pack is built from (the pack, trading and review patches
already applied — see ../README.md). This copies its scripts aside, applies native-edits.json (and
native-web-checks.json, where "production" checks are widened from the website to the app, and
native-hd.json, the full-detail world on 6 GB iPhones), adds
src/*.gd, compiles every script that changed with GDRE Tools (bytecode 4.6.0) and writes the .gdc
files, the .remap for each new script and override.cfg into overlay/. The recovered tree itself is
not touched.

Before compiling, it checks that `recovered` carries every edit in ../ios-trading-edits.json and
../ios-review-edits.json, so an App Review fix that is committed but not yet applied there cannot
be compiled out of the overlay (the overlay's scripts replace the pack's own copies).

It also writes overlay.sha256: the SHA-256 of every input in this repository (src/, assets/, the
native-*.json edits, this script, the ios-*-edits.json edits and the scripts that apply them) and
every file it produced, plus the SHA-256 of the published lite pack in ../../realm/ as `pack.zip`.
CI checks it (shasum -a 256 -c) right after fetch-pack.py downloads the live pack to pack.zip, so an
edit pushed without rebuilding the overlay, or a pack republished since, fails the build instead of
shipping stale bytecode. (Locally, without pack.zip: shasum -a 256 -c --ignore-missing.)
"""
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("trading", HERE.parent / "apply-ios-trading-patch.py")
_trading = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_trading)

OVERRIDE = """; Native iOS settings, loaded by the engine from res://override.cfg on top of the pack's own
; project settings. The web build never sees this file.
[application]

; every print reaches user://logs/godot.log at once, so a log copied mid-run is complete
run/flush_stdout_on_print=true

[autoload]

NativeAccount="*res://NativeAccount.gd"
NativeVitals="*res://NativeVitals.gd"
NativeSafeArea="*res://NativeSafeArea.gd"
NativeQuality="*res://NativeQuality.gd"
NativeHUD="*res://NativeHUD.gd"
NativeVoxelMesh="*res://NativeVoxelMesh.gd"

[debug]

; Engine output to user://logs/godot.log on the device, so a failure can be read back (CI pulls it
; out of the simulator's app container). Off by default on mobile.
file_logging/enable_file_logging=true
file_logging/enable_file_logging.pc=true

[display]

window/handheld/orientation=4
; 60 fps, not ProMotion's 120: the HD world at 120 Hz buys no gameplay and costs heat and battery
window/ios/allow_high_refresh_rate=false

[rendering]

; METAL. The website can only use the Compatibility renderer (OpenGL ES through WebGL); on iOS that
; means OpenGL ES, which Apple deprecated in 2018 and runs through a translation layer. The Mobile
; renderer draws with Metal, Apple's own graphics API, as native iOS games do. The game already
; carries tuning for it (Companion's skin gain table has "gl" and "fp" columns). If Metal cannot
; start (the CI simulator has none), Godot falls back to OpenGL on its own.
renderer/rendering_method.mobile="mobile"
rendering_device/driver.ios="metal"
rendering_device/fallback_to_opengl3=true
"""


PACK_MANIFEST = "realm/index.pck.ios.lite.manifest.json"  # the pack CI fetches (ios-native.yml PACK)
TEX_READ = re.compile(r"(?<![\w.)\]])\b(\w+)\.get_image\(\)")


def main() -> int:
	recovered, gdre = Path(sys.argv[1]), Path(sys.argv[2])
	_check_recovered(recovered)
	out = HERE / "overlay"
	with tempfile.TemporaryDirectory() as td:
		work = Path(td)
		for f in recovered.glob("*.gd"):
			shutil.copy(f, work / f.name)
		edits = json.loads((HERE / "native-edits.json").read_text())
		for extra in ("native-web-checks.json", "native-hd.json", "native-ui.json", "native-perf.json",
				"native-textures.json"):
			if (HERE / extra).exists():
				edits += json.loads((HERE / extra).read_text())
		changed = set()
		for e in edits:
			p = work / e["file"]
			s = p.read_text()
			if s.count(e["old"]) != 1:
				raise SystemExit(f"anchor not unique/absent in {e['file']}: {e['why']}")
			p.write_text(s.replace(e["old"], e["new"]))
			changed.add(e["file"])
		# the phone's textures are ASTC (tools/astc-pack.gd): every pixel read of a texture decompresses
		# first. `name.get_image()` only: a viewport's get_texture().get_image() is never compressed.
		reads = 0
		for p in sorted(work.glob("*.gd")):
			if p.name == "ChikFeat.gd":
				continue
			s, n = TEX_READ.subn(r"ChikFeat.plain_image(\1)", p.read_text())
			if n:
				p.write_text(s)
				changed.add(p.name)
				reads += n
		print(f"  texture pixel reads routed through ChikFeat.plain_image: {reads}")
		if reads < 14:
			raise SystemExit("fewer texture pixel reads than the 14 known: check TEX_READ")
		new = []
		for f in sorted((HERE / "src").glob("*.gd")):
			shutil.copy(f, work / f.name)
			changed.add(f.name)
			new.append(f.name)
		if out.exists():
			shutil.rmtree(out)
		out.mkdir()
		for name in sorted(changed):
			r = subprocess.run([str(gdre), "--headless", f"--compile={work / name}", "--bytecode=4.6.0",
				f"--output={out}"], capture_output=True, text=True)
			gdc = out / (name[:-3] + ".gdc")
			if not gdc.exists():
				print(r.stdout[-2000:], r.stderr[-2000:])
				raise SystemExit(f"compile failed: {name}")
			print(f"  {gdc.name}  {gdc.stat().st_size:,}")
		for name in new:
			(out / (name + ".remap")).write_text(f'[remap]\n\npath="res://{name[:-3]}.gdc"\n')
		(out / "override.cfg").write_text(OVERRIDE)
		for f in sorted((HERE / "assets").glob("*")):
			shutil.copy(f, out / f.name)
		# the edited sources, for reading and for the headless test; not part of the pack
		src_out = HERE / "patched-src"
		if src_out.exists():
			shutil.rmtree(src_out)
		src_out.mkdir()
		for name in sorted(changed):
			shutil.copy(work / name, src_out / name)
	_write_manifest()
	return 0


def _check_recovered(recovered: Path) -> None:
	"""Every web-pack edit must already be in `recovered`: the overlay is compiled from it.

	A trading edit a later review edit rewrote is the one exception (its new text is gone by design).
	"""
	trading = json.loads((HERE.parent / "ios-trading-edits.json").read_text(encoding="utf-8"))
	review = json.loads((HERE.parent / "ios-review-edits.json").read_text(encoding="utf-8"))
	missing = []
	for e, later in [(e, review) for e in trading] + [(e, []) for e in review]:
		if _trading._find((recovered / e["file"]).read_text(encoding="utf-8"), e["new"]) is not None:
			continue
		if any(r["file"] == e["file"] and (_trading._find(r["old"], e["new"]) is not None
				or _trading._find(e["new"], r["old"]) is not None) for r in later):
			continue
		missing.append(f"{e['file']}: {e['why'][:100]}")
	if missing:
		raise SystemExit("recovered lacks these web-pack edits (run ../apply-ios-*-patch.py on it first):\n  "
			+ "\n  ".join(missing))


def _write_manifest() -> None:
	root = HERE.parent.parent  # the repository: shasum -c runs from there
	files = [HERE / "build-native-overlay.py"]
	files += [HERE.parent / n for n in ("apply-ios-pack-patch.py", "apply-ios-trading-patch.py",
		"apply-ios-review-patch.py", "ios-trading-edits.json", "ios-review-edits.json")]
	files += sorted(HERE.glob("native-*.json"))
	for d in ("src", "assets", "overlay"):  # patched-src/ is not committed
		files += sorted(f for f in (HERE / d).rglob("*") if f.is_file())
	lines = [f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(root).as_posix()}" for f in files]
	# the lite pack the overlay goes over, as fetch-pack.py writes it in CI (its manifest's sha256 is
	# of the reassembled file): a republished pack must be matched by a rebuilt overlay
	pack = json.loads((root / PACK_MANIFEST).read_text())
	lines.append(f"{pack['sha256']}  pack.zip")
	(HERE / "overlay.sha256").write_text("\n".join(lines) + "\n")
	print(f"  overlay.sha256: {len(lines)} files")


if __name__ == "__main__":
	sys.exit(main())
