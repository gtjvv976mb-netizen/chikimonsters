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
"""
import importlib.util
import json
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

[debug]

; Engine output to user://logs/godot.log on the device, so a failure can be read back (CI pulls it
; out of the simulator's app container). Off by default on mobile.
file_logging/enable_file_logging=true
file_logging/enable_file_logging.pc=true

[display]

window/handheld/orientation=4

[rendering]

; The game is built and tuned on the Compatibility renderer (the only one the web has). Keep it,
; so the phone draws exactly what the website draws.
renderer/rendering_method.mobile="gl_compatibility"
"""


def main() -> int:
	recovered, gdre = Path(sys.argv[1]), Path(sys.argv[2])
	out = HERE / "overlay"
	with tempfile.TemporaryDirectory() as td:
		work = Path(td)
		for f in recovered.glob("*.gd"):
			shutil.copy(f, work / f.name)
		edits = json.loads((HERE / "native-edits.json").read_text())
		for extra in ("native-web-checks.json", "native-hd.json"):
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
	return 0


if __name__ == "__main__":
	sys.exit(main())
