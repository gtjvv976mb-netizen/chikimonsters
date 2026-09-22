"""Bake authentic 2D Chikimon portraits into website scenery.

This is deliberately deterministic: no creature is redrawn or synthesized. Run
from the repository root with `python3 scripts/composite-site-scenes.py`.
Requires Pillow. The original scene and dex portraits remain untouched.
"""

from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "site-assets"

# Names, x-center and feet position are scene-pixel coordinates; height controls
# apparent distance along the ground plane. Everything stays away from left-side
# hero/section copy on desktop. Mobile center crops retain a visible cast.
SCENES = {
    "chikoria": {
        "base": "scene-chikoria-depth.webp",
        "output": "scene-chikoria-cast.webp",
        "tone": (255, 199, 132),
        "cast": [
            ("dex-vesperos.webp", 964, 555, 90, 0.79, True),
            ("dex-rivaros.webp", 1086, 764, 117, 0.91, False),
            ("dex-solvarex.webp", 1518, 759, 103, 0.90, False),
            ("dex-bamboran.webp", 1248, 758, 108, 0.95, False),
            ("dex-galador.webp", 1410, 838, 151, 1.00, False),
            ("dex-firix.webp", 1160, 841, 165, 1.00, False),
        ],
    },
    "chikoria-mobile": {
        "base": "scene-chikoria-depth.webp",
        "output": "scene-chikoria-mobile-cast.webp",
        # The path, castle and waterfall all remain visible. On a 390:844
        # viewport, CSS cover trims ~47 source pixels from each side; every
        # creature below stays well within that extra safe margin.
        "crop": (1000, 0, 1529, 941),
        "tone": (255, 199, 132),
        "cast": [
            ("dex-bamboran.webp", 255, 695, 80, 0.94, False),
            ("dex-firix.webp", 165, 774, 128, 1.00, False),
            ("dex-galador.webp", 355, 777, 126, 1.00, False),
        ],
    },
    "gathering": {
        "base": "scene-gathering.webp",
        "output": "scene-gathering-cast.webp",
        "tone": (255, 210, 155),
        "cast": [
            ("dex-crysalune.webp", 538, 455, 88, 0.88, True),
            ("dex-bamboran.webp", 376, 584, 119, 0.96, False),
            ("dex-rivaros.webp", 649, 594, 107, 0.94, False),
            ("dex-galador.webp", 934, 552, 91, 0.94, False),
        ],
    },
    "gathering-mobile": {
        "base": "scene-gathering.webp",
        "output": "scene-gathering-mobile-cast.webp",
        "crop": (640, 0, 1063, 752),
        "tone": (255, 210, 155),
        "cast": [
            ("dex-galador.webp", 114, 546, 92, 0.96, False),
            ("dex-rivaros.webp", 288, 550, 81, 0.94, False),
        ],
    },
    "temple": {
        "base": "wicked-temple.webp",
        "output": "scene-temple-cast.webp",
        "tone": (170, 132, 246),
        "cast": [
            ("dex-vesperos.webp", 588, 394, 112, 0.85, True),
            ("dex-horoxyn.webp", 684, 584, 129, 0.97, False),
            ("dex-astragor.webp", 441, 615, 175, 1.00, False),
        ],
    },
    "temple-mobile": {
        "base": "wicked-temple.webp",
        "output": "scene-temple-mobile-cast.webp",
        "crop": (620, 0, 1043, 752),
        "tone": (170, 132, 246),
        "cast": [
            ("dex-vesperos.webp", 200, 400, 77, 0.86, True),
            ("dex-horoxyn.webp", 110, 575, 108, 0.96, False),
            ("dex-astragor.webp", 252, 555, 108, 0.98, False),
        ],
    },
    "arena": {
        "base": "chikiseum.webp",
        "output": "scene-arena-cast.webp",
        "tone": (192, 175, 240),
        "cast": [
            ("dex-firix.webp", 555, 716, 180, 0.99, False),
            ("dex-galador.webp", 1050, 716, 190, 0.99, False),
        ],
    },
    "arena-mobile": {
        "base": "chikiseum.webp",
        "output": "scene-arena-mobile-cast.webp",
        "crop": (550, 0, 1056, 900),
        "tone": (192, 175, 240),
        "cast": [
            ("dex-firix.webp", 117, 662, 118, 0.99, False),
            ("dex-galador.webp", 380, 663, 120, 0.99, False),
        ],
    },
}


def tinted_sprite(filename: str, height: int, tone: tuple[int, int, int], opacity: float) -> Image.Image:
    sprite = Image.open(ASSETS / filename).convert("RGBA")
    alpha = sprite.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise ValueError(f"Empty portrait: {filename}")
    sprite = sprite.crop(bbox)
    width = round(sprite.width * height / sprite.height)
    sprite = sprite.resize((width, height), Image.Resampling.LANCZOS)
    rgb = sprite.convert("RGB")
    # Blend only a whisper of the scene's illumination: creature identity and
    # card-art colors stay intact. Gentle near/far opacity provides atmosphere.
    wash = Image.new("RGB", sprite.size, tone)
    rgb = Image.blend(rgb, wash, 0.055)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.015)
    alpha = sprite.getchannel("A")
    # Tighten soft matte fringe, without eroding solid voxel details.
    alpha = alpha.point(lambda a: 0 if a < 14 else (round((a - 14) * 255 / 241) if a < 255 else 255))
    if opacity < 1:
        alpha = alpha.point(lambda a: round(a * opacity))
    rgb.putalpha(alpha)
    return rgb


def soft_ground_shadow(canvas: Image.Image, x: int, feet_y: int, width: int, opacity: float) -> None:
    # A low, elongated directional contact shadow—not a circular marker.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    radius_x = max(21, round(width * 0.39))
    radius_y = max(4, round(radius_x * 0.115))
    draw.ellipse((x - radius_x, feet_y - radius_y // 2, x + radius_x, feet_y + radius_y), fill=(14, 8, 30, round(74 * opacity)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(4, round(radius_y * 0.9))))
    canvas.alpha_composite(shadow)


def compose_scene(spec: dict) -> Path:
    background = Image.open(ASSETS / spec["base"]).convert("RGBA")
    if "crop" in spec:
        background = background.crop(spec["crop"])
    # Arena art is 1599×900, positions in that native coordinate system.
    for filename, x, feet_y, height, opacity, airborne in sorted(spec["cast"], key=lambda item: item[2]):
        sprite = tinted_sprite(filename, height, spec["tone"], opacity)
        top = feet_y - sprite.height
        left = x - sprite.width // 2
        if not airborne:
            soft_ground_shadow(background, x, feet_y, sprite.width, opacity)
        else:
            # Airborne figures still cast a very faint, distant floor shadow.
            shadow_y = min(background.height - 38, feet_y + 58)
            soft_ground_shadow(background, x + 12, shadow_y, sprite.width // 2, opacity * 0.38)
        background.alpha_composite(sprite, (left, top))
    output = ASSETS / spec["output"]
    background.convert("RGB").save(output, "WEBP", quality=91, method=6)
    return output


if __name__ == "__main__":
    selected = sys.argv[1:] or list(SCENES)
    for scene_name in selected:
        scene_spec = SCENES[scene_name]
        path = compose_scene(scene_spec)
        print(scene_name, path, path.stat().st_size)
