#!/usr/bin/env python3
"""Regenerate Inkrail's original grain, base icon and modeled typewriter actions.
Optional development tool. Requires numpy and Pillow; not needed to build/run.
The edited CC0 typewriter recordings are retained as bundled masters.
The base icon goes to .build; the finished packaging icon is preserved.
"""
from pathlib import Path
import math
import subprocess
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources" / "Inkrail" / "Resources"
RES.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(4816)

# Transparent, seamlessly tileable fine-grain paper. Very light fibers/dust.
size = 640
rgba = np.zeros((size, size, 4), dtype=np.uint8)
noise = rng.normal(0, 1, (size, size))
rgba[:, :, :3] = np.where(noise[:, :, None] > 0, 255, 52)
rgba[:, :, 3] = np.minimum(np.abs(noise) * 19, 64).astype(np.uint8)
paper = Image.fromarray(rgba)
draw = ImageDraw.Draw(paper)
for _ in range(360):
    x, y = rng.integers(0, size, 2)
    r = float(rng.uniform(0.35, 1.25))
    draw.ellipse((x-r, y-r, x+r, y+r), fill=(82, 77, 54, int(rng.integers(22, 78))))
for _ in range(100):
    x, y = rng.integers(0, size, 2)
    draw.line((int(x), int(y), int(x+rng.integers(2, 7)), int(y+rng.integers(-1, 2))), fill=(92, 81, 55, 22))
paper.save(RES / "paper-grain.png", optimize=True)

# Use the same reproducible audio generator as the standalone sound build.
subprocess.run([sys.executable, str(ROOT / "scripts/generate-sound-styles.py")], check=True)

# Procedural base icon for reference; the finished wordmark icon is maintained
# separately in Sources/Inkrail/Resources/AppIcon.png.
S = 1024
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(icon)
d.rounded_rectangle((62, 62, 962, 962), radius=210, fill=(32, 37, 33, 255))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle((220, 208, 820, 860), radius=45, fill=(0,0,0,120))
icon = Image.alpha_composite(icon, shadow.filter(ImageFilter.GaussianBlur(34)))
d = ImageDraw.Draw(icon)
d.rounded_rectangle((218, 172, 806, 829), radius=47, fill=(234,231,208,255))
for y, end in [(304, 650), (344, 697), (384, 595), (424, 666)]:
    d.rounded_rectangle((298, y, end, y+8), radius=2, fill=(71,78,62,175))
for yy in range(500, 525):
    shade = int(38 + 115 * math.exp(-((yy-505)/5)**2))
    d.rectangle((202, yy, 822, yy+1), fill=(shade, shade+6, shade, 255))
d.rounded_rectangle((202, 493, 220, 533), radius=5, fill=(44,53,45,255))
d.rounded_rectangle((804, 493, 822, 533), radius=5, fill=(44,53,45,255))
d.rectangle((540, 455, 547, 488), fill=(70,80,64,255))
d.rounded_rectangle((528,450,558,456), radius=1, fill=(68,77,63,255))
d.rounded_rectangle((465, 488, 623, 551), radius=30, fill=(204,202,186,255))
d.rounded_rectangle((466, 482, 622, 543), radius=30, fill=(236,234,221,255), outline=(165,166,148,255), width=2)
d.rounded_rectangle((486, 489, 601, 492), radius=1, fill=(255,254,245,255))
for i, fill in enumerate([(128,153,105,255),(154,117,97,255),(80,87,70,255)]):
    x = 489 + i * 12
    d.ellipse((x,510,x+6,516), fill=fill)
base_icon = ROOT / ".build" / "icon-base-generated.png"
base_icon.parent.mkdir(parents=True, exist_ok=True)
icon.save(base_icon, optimize=True)
print("Generated paper grain, sound profiles, and .build/icon-base-generated.png. Finished app icon preserved.")
