#!/usr/bin/env python3
"""Upgrade an extracted iOS pack to HD art from the website's HD pack.

    python3 hd-upgrade.py <website index.pck> <extracted iOS pack dir>

The iOS pack (index.pck.ios.lite) is the website's mobile-lite pack plus the App Review patches. It
halves every texture (the web view's memory ceiling), and the carts' voxel models are thinned. The
native app has no such ceiling on a 6 GB iPhone, so this takes, from the website's HD pack (GDPC),
every imported texture (.ctex) and cart voxel model (cart_*_vox.json) the iOS pack also has, and
writes it over the lite one. Scripts, scenes and everything else stay the iOS pack's own, so the
review patches and the native overlay are untouched. Both packs come from the same Godot 4.6 build,
and the textures are WebP inside the .ctex, which every iPhone decodes.
"""
import fnmatch
import os
import struct
import sys

TAKE = ("*.ctex", "cart_*_vox.json")


def entries(f):
	if f.read(4) != b"GDPC":
		raise SystemExit("not a GDPC pack")
	ver, _ma, _mi, _pa = struct.unpack("<4I", f.read(16))
	if ver < 3:
		raise SystemExit(f"pack format {ver}: expected 3 (Godot 4.4+)")
	flags, base = struct.unpack("<IQ", f.read(12))
	if flags & 1:
		raise SystemExit("encrypted pack")
	diroff, = struct.unpack("<Q", f.read(8))
	f.seek(diroff)
	n, = struct.unpack("<I", f.read(4))
	for _ in range(n):
		ln, = struct.unpack("<I", f.read(4))
		path = f.read(ln).rstrip(b"\0").decode()
		off, size = struct.unpack("<QQ", f.read(16))
		f.read(16 + 4)  # md5, flags
		yield path.removeprefix("res://"), base + off, size


def main() -> int:
	pck, root = sys.argv[1], sys.argv[2]
	done = added = 0
	with open(pck, "rb") as f:
		for path, off, size in list(entries(f)):
			name = os.path.basename(path)
			if not any(fnmatch.fnmatch(name, p) for p in TAKE):
				continue
			dst = os.path.join(root, path)
			if not os.path.exists(dst):
				continue
			old = os.path.getsize(dst)
			f.seek(off)
			data = f.read(size)
			os.unlink(dst)  # never write through a hard link into another tree
			with open(dst, "wb") as o:
				o.write(data)
			done += 1
			added += size - old
	print(f"HD art: {done} files from {os.path.basename(pck)}, {added / 1e6:+.1f} MB")
	if done < 1000:
		raise SystemExit("too few HD files matched; the packs no longer line up")
	return 0


if __name__ == "__main__":
	sys.exit(main())
