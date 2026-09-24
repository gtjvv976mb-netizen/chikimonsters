#!/usr/bin/env python3
"""The three images the iOS app's pack draws differently from the website's.

    python3 godot-patch/ios-app-art.py realm/ godot-patch/ios-overlay/app-art

The Meme Dynasty is not in the app yet (see apply-ios-review-patch.py), but two images show its
faces wherever a Meme Dynasty EGG or the class is mentioned — the Temple's reward wheel shows the
meme egg on every run, and the Temple's odds table shows the class badge. In the app's pack:

  * `egg_meme.png`        becomes the Legendary egg, shifted to pink — an egg, no faces
  * `ico_class_meme.png`  becomes the Meme Dynasty gem badge (`ico_meme_dynasty.png`), no faces
  * `app_title.jpg`       (new) the Chikoria key art `realm/loading.png`, which Title.gd shows in
                          place of `web_hero.png`, the meme line-up

The two textures are written as Godot `.ctex` files at the SAME imported paths the pack already
uses, built from the lite pack's own `.ctex` of the source image, so size and import settings stay
exactly what the phone pack has. `build-ios-pack.py` adds everything under the output directory.
Deterministic: same inputs, same bytes.
"""

import colorsys
import importlib.util
import io
import struct
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("build_ios_pack", HERE / "build-ios-pack.py")
_build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_build)

HUE_PINK = 50        # the Legendary egg is violet; +50 degrees lands it on the meme egg's pink


def _import_path(files: dict, src: str) -> str:
	"""The .ctex a texture's .import file remaps to, as a pack path."""
	for line in files[src + ".import"].decode("utf-8").splitlines():
		if line.startswith('path="res://'):
			return line[len('path="res://'):-1]
	raise SystemExit(f"error: {src}.import has no remap path")


def _read_ctex(blob: bytes) -> tuple[bytes, int, Image.Image, bool]:
	"""(header, format, image, lossless) of a GST2 texture holding one WebP image."""
	if blob[:4] != b"GST2":
		raise SystemExit("error: not a GST2 texture")
	df, _w, _h, mips, fmt = struct.unpack("<IHHII", blob[36:52])
	if df != 2 or mips != 0:
		raise SystemExit(f"error: expected one WebP image, got data format {df} with {mips} mipmaps")
	size = struct.unpack("<I", blob[52:56])[0]
	webp = blob[56:56 + size]
	return blob[:36], fmt, Image.open(io.BytesIO(webp)), webp[12:16] == b"VP8L"


def _write_ctex(header: bytes, fmt: int, img: Image.Image, lossless: bool) -> bytes:
	img = img.convert("RGBA" if fmt == 5 else "RGB")
	out = io.BytesIO()
	img.save(out, "WEBP", lossless=lossless, quality=100 if lossless else 90, method=6, exact=True)
	webp = out.getvalue()
	w, h = img.size
	head = bytearray(header)
	struct.pack_into("<II", head, 8, w, h)
	return bytes(head) + struct.pack("<IHHII", 2, w, h, 0, fmt) + struct.pack("<I", len(webp)) + webp


def _hue(img: Image.Image, degrees: int) -> Image.Image:
	img = img.convert("RGBA")
	px = img.load()
	shift = degrees / 360.0
	for y in range(img.height):
		for x in range(img.width):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
			r2, g2, b2 = colorsys.hsv_to_rgb((h + shift) % 1.0, s, v)
			px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
	return img


def main() -> int:
	if len(sys.argv) != 3:
		print(__doc__)
		return 2
	realm, out = Path(sys.argv[1]), Path(sys.argv[2])
	files = _build.read_base(realm)

	# the meme egg: the Legendary egg, pink
	target = _import_path(files, "egg_meme.png")
	header, fmt, _img, lossless = _read_ctex(files[target])
	_h2, _f2, src, _l2 = _read_ctex(files[_import_path(files, "egg_legendary.png")])
	blobs = {target: _write_ctex(header, fmt, _hue(src, HUE_PINK), lossless)}

	# the class badge: the gem badge, centred on the badge's canvas
	target = _import_path(files, "ico_class_meme.png")
	header, fmt, old, lossless = _read_ctex(files[target])
	_h2, _f2, gem, _l2 = _read_ctex(files[_import_path(files, "ico_meme_dynasty.png")])
	canvas = Image.new("RGBA", old.size, (0, 0, 0, 0))
	gem = gem.convert("RGBA")
	gem.thumbnail(old.size)
	canvas.paste(gem, ((old.width - gem.width) // 2, (old.height - gem.height) // 2), gem)
	blobs[target] = _write_ctex(header, fmt, canvas, lossless)

	# the title art: raw JPEG, loaded by Title.gd with Image.load_from_file
	key = Image.open(realm / "loading.png").convert("RGB")
	jpg = io.BytesIO()
	key.save(jpg, "JPEG", quality=88, optimize=True)
	blobs["app_title.jpg"] = jpg.getvalue()

	for rel, blob in blobs.items():
		p = out / rel
		p.parent.mkdir(parents=True, exist_ok=True)
		p.write_bytes(blob)
		print(f"  {rel}  {len(blob):,} bytes")
	return 0


if __name__ == "__main__":
	sys.exit(main())
