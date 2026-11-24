#!/usr/bin/env python3
"""Build the app icons and template PNG from the Inkrail mark.
Requires ImageMagick 7, Pillow and NumPy. Only needed to edit the artwork.
"""
from io import BytesIO
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/Inkrail/Resources"
MARK = ROOT / "docs/assets/inkrail-mark.svg"


def render_mark():
    png = subprocess.check_output([
        "magick", "-background", "none", "-density", "768", str(MARK),
        "-strip", "PNG32:-",
    ])
    return Image.open(BytesIO(png)).convert("RGBA")


def keytop(mark):
    # Offsets put the brass bezel just above the centre of the enamel casting.
    size = 1024
    y, x = np.ogrid[:size, :size]
    rng = np.random.default_rng(1986)
    grain = rng.normal(0, 1, (size, size)).astype(np.float32)
    image = Image.new("RGBA", (size, size))
    distance = np.hypot(x - 512, y - 500)
    angle = np.arctan2(y - 500, x - 512)

    def layer(edge, color, light=0):
        # A signed distance gives the circles and bevels a subpixel edge.
        alpha = (np.clip(0.5 - edge, 0, 1) * 255).astype("uint8")
        rgb = np.clip(np.array(color) + np.asarray(light)[..., None], 0, 255)
        rgba = np.empty((size, size, 4), dtype="uint8")
        rgba[:, :, :3] = rgb
        rgba[:, :, 3] = alpha
        image.alpha_composite(Image.fromarray(rgba))

    def tile_edge(inset, drop=0):
        radius = 188 - inset
        dx = np.abs(x - 512) - (438 - inset - radius)
        dy = np.abs(y - (504 + drop)) - (438 - inset - radius)
        return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0) - radius

    # Baked enamel has a softly polished shoulder and a fine, irregular grain.
    edge = tile_edge(0, drop=9)
    layer(edge, (24, 37, 31), (1 - y / size) * 18)
    face = tile_edge(0)
    shoulder = np.exp(-((face + 2) / 2.5) ** 2)
    window_light = np.exp(-(((x - 303) / 630) ** 2 + ((y - 100) / 740) ** 2))
    layer(face, (27, 47, 39), window_light * 27 - 7 + shoulder * (32 - 45 * y / size) + grain * 1.4)

    # Soft contact shadow and a shallow seat underneath the rolled metal lip.
    shadow_mask = Image.fromarray((np.hypot(x - 514, y - 519) < 341).astype("uint8") * 148)
    shadow = Image.new("RGBA", image.size, (4, 13, 9))
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(13)))
    image.alpha_composite(shadow)
    layer(np.hypot(x - 512, y - 507) - 345, (29, 35, 26))
    layer(distance - 344, (85, 76, 54), -np.cos(angle - 0.9) * 22)

    # The three broad reflections follow the curve of the brushed brass rim.
    reflection = 22 * np.cos(2 * angle + 1) + 13 * np.sin(3 * angle - 1)
    polish = 38 * np.exp(-((distance - 338) / 3.5) ** 2) - 36 * np.exp(-((distance - 325) / 5) ** 2)
    layer(distance - 342, (167, 153, 116), reflection + polish + grain * 1.6)
    layer(distance - 323, (81, 79, 60), -np.cos(angle - 0.85) * 13)

    # Warm paper held under the rim. The inner shadow falls towards the lower right.
    inside = np.exp(-((distance - 323) / 8) ** 2)
    paper_light = (500 - y) * 0.016 - inside * (16 - np.cos(angle - 0.9) * 10)
    layer(distance - 320, (234, 226, 202), paper_light + grain * 1.7)

    # The mark sits optically centred. Its long R leg carries less weight than the two stems.
    stamp = mark.resize((486, 405), Image.Resampling.LANCZOS)
    image.alpha_composite(stamp, (269, 298))
    return image


if __name__ == "__main__":
    glyph = render_mark()
    glyph.resize((240, 200), Image.Resampling.LANCZOS).save(RESOURCES / "maker-mark.png", optimize=True)
    icon = keytop(glyph)
    icon.save(RESOURCES / "AppIcon.png", optimize=True)
    icon.resize((512, 512), Image.Resampling.LANCZOS).save(
        ROOT / "docs/assets/inkrail-app-icon.png", optimize=True
    )
    icon.save(ROOT / "packaging/windows/host/Inkrail.ico",
              sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
