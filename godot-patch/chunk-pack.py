#!/usr/bin/env python3
"""Turn a Godot web export into the chunked files `realm/` serves.

    python3 godot-patch/chunk-pack.py <webexport-dir> <out-dir> [--lite] [--verify-only]

GitHub's web uploader rejects files over 25 MB, so `realm/` stores the pack and the engine as
24 MiB pieces and `realm/index.html` streams them back into one Blob at runtime. Getting that
wrong is the failure `DEPLOY.md` warns about, and it does not fail loudly:

> A partial upload does not fail loudly: the loader assembles whatever chunks it gets and mounts
> a pack that is quietly wrong.

So this writes the pieces and the manifest together, then **reassembles them and compares the
sha256 against the source** before saying it worked.

What it writes, for a desktop pack:

    index.pck.0.bin … index.pck.N.bin       24 MiB each, remainder in the last
    index.pck.manifest.json                 {"total", "chunks", "v"}
    index.wasm.0.bin … index.wasm.M.bin     same scheme, if index.wasm is present
    virtual-files.json                      untouched — copy the existing one

`--lite` writes the `index.pck.lite.*` family instead, which is the pack phones and the iOS app
download. **For the iOS app that is usually the one that matters** — `realm/index.html` picks the
lite pack on a phone.

`v` is the build stamp the loader puts on every chunk URL so a browser can never mix chunks from
two builds. It is the first ten hex characters of the pack's sha256, so the same pack always
produces the same stamp and a different pack never reuses one.

BEFORE YOU COMMIT THE RESULT, read the Pages section of `DEPLOY.md`. Committing a fresh ~370 MB
of chunks on every release is what grew `.git` to about 45 GB and stopped Pages publishing
entirely. Replacing a pack in place is fine; keeping every old one is not.
"""

import hashlib
import json
import shutil
import sys
from pathlib import Path

CHUNK = 25165824          # 24 MiB — matches every chunk already in realm/


def sha256_of(path: Path) -> str:
	h = hashlib.sha256()
	with path.open("rb") as f:
		for block in iter(lambda: f.read(1 << 20), b""):
			h.update(block)
	return h.hexdigest()


def split(src: Path, out_dir: Path, stem: str, stamp: str | None) -> dict:
	"""Write <stem>.N.bin pieces plus <stem>.manifest.json. Returns the manifest."""
	total = src.stat().st_size
	digest = sha256_of(src)
	v = stamp or digest[:10]

	for stale in out_dir.glob(f"{stem}.*.bin"):
		stale.unlink()

	names = []
	with src.open("rb") as f:
		i = 0
		while True:
			block = f.read(CHUNK)
			if not block:
				break
			name = f"{stem}.{i}.bin"
			(out_dir / name).write_bytes(block)
			names.append(name)
			i += 1

	manifest = {"total": total, "chunks": names, "v": v}
	(out_dir / f"{stem}.manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
	return manifest | {"sha256": digest}


def verify(out_dir: Path, stem: str, expect_sha: str, expect_total: int) -> bool:
	"""Reassemble exactly as realm/index.html does and compare."""
	manifest = json.loads((out_dir / f"{stem}.manifest.json").read_text(encoding="utf-8"))
	h = hashlib.sha256()
	seen = 0
	for name in manifest["chunks"]:
		data = (out_dir / name).read_bytes()
		h.update(data)
		seen += len(data)
	ok = h.hexdigest() == expect_sha and seen == expect_total == manifest["total"]
	status = "OK" if ok else "MISMATCH"
	print(f"  verify {stem}: {seen:,} bytes over {len(manifest['chunks'])} chunk(s) — {status}")
	return ok


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	lite = "--lite" in sys.argv
	if len(args) != 2:
		print(__doc__)
		return 2

	src_dir, out_dir = Path(args[0]), Path(args[1])
	out_dir.mkdir(parents=True, exist_ok=True)

	pck = src_dir / "index.pck"
	wasm = src_dir / "index.wasm"
	if not pck.is_file():
		print(f"error: no index.pck in {src_dir} — point this at a Godot web export")
		return 1

	pck_stem = "index.pck.lite" if lite else "index.pck"
	print(f"{pck.name} -> {pck_stem}.*.bin")
	m = split(pck, out_dir, pck_stem, None)
	ok = verify(out_dir, pck_stem, m["sha256"], m["total"])
	print(f"  build stamp v = {m['v']}")

	if wasm.is_file():
		# The engine is shared: both packs mount against the same index.wasm, so it is only
		# rewritten for the desktop family. A --lite run leaves whatever is already there.
		if lite:
			print("index.wasm: skipped (--lite); the engine is shared with the desktop family")
		else:
			print(f"{wasm.name} -> index.wasm.*.bin")
			mw = split(wasm, out_dir, "index.wasm", m["v"])
			ok = verify(out_dir, "index.wasm", mw["sha256"], mw["total"]) and ok

	for extra in ("index.js", "index.audio.worklet.js", "index.audio.position.worklet.js"):
		s = src_dir / extra
		if s.is_file():
			shutil.copy2(s, out_dir / extra)
			print(f"  copied {extra}")

	print()
	if not ok:
		print("FAILED verification — do not publish these files.")
		return 1

	print("Verified: reassembling the chunks reproduces the export byte for byte.")
	print()
	print("Not copied, on purpose — these are yours and this export would clobber them:")
	print("  index.html      realm/index.html is the custom loader, NOT Godot's shell")
	print("  chiki-ios.js    the iOS policy layer")
	print("  virtual-files.json, loading screen art, icons, updates.json")
	print()
	print("After copying into realm/, re-run the tripwires before publishing:")
	print("  node godot-patch/verify/loader-policy.test.mjs")
	print("  node godot-patch/verify/chiki-ios.test.mjs")
	return 0


if __name__ == "__main__":
	sys.exit(main())
