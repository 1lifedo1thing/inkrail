#!/usr/bin/env python3
"""Render the shared wax-seal atlas. Requires NumPy and Pillow for artwork edits."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


RESOURCE = Path(__file__).resolve().parents[1] / "Sources/Inkrail/Resources/letter-seal-wax.png"
SCALE = 3
WIDTH, HEIGHT = 120 * SCALE, 96 * SCALE
COLORS = ("923e36", "466653", "3f526e", "734964")
SHAPES = ("round", "oval", "scalloped")


def wax_variation(rng, points):
    """Smooth, deterministic variation at a given spacing in display points."""
    size = (round(96 / points), round(120 / points))
    samples = rng.uniform(-1, 1, size).astype(np.float32)
    image = Image.fromarray(samples).resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC)
    return np.asarray(image)


def surface(shape):
    """Height of the pressed wax above the paper, measured in display points."""
    iy, ix = np.indices((HEIGHT, WIDTH))
    x = (ix + 0.5) / SCALE - 60.7
    y = (iy + 0.5) / SCALE - 45.7
    rx, ry = (53.6, 36.1) if shape == "oval" else (43.4, 40.2)
    radius = np.hypot(x / rx, y / ry)
    angle = np.arctan2(y / ry, x / rx)
    phase = {"round": 0.25, "oval": 1.7, "scalloped": -0.65}[shape]
    # A larger pool to one side of the die, with smaller ripples where it set.
    edge = (1 + .064 * np.cos(angle - 2.35) + .036 * np.sin(3 * angle + phase)
            + .024 * np.sin(4 * angle - 1.1) + .014 * np.cos(7 * angle + phase)
            + .009 * np.sin(10 * angle + 1.5))
    if shape == "scalloped":
        edge += .054 * np.cos(11 * angle + .48 * np.sin(2 * angle))

    die = .788 + .005 * np.sin(3 * angle + .8) + .004 * np.cos(7 * angle)
    radial_scale = np.hypot(rx * np.cos(angle), ry * np.sin(angle))
    edge_depth = (edge - radius) * radial_scale
    die_depth = (die - radius) * radial_scale
    lip_width = (edge - die) * radial_scale
    t = np.clip(-die_depth / lip_width, 0, 1)

    # The die leaves an almost flat face. Displaced wax rises around its edge
    # and returns to a thin meniscus at the paper. The broadest pools sit lower.
    face = 1.85 + .085 * np.sin(x / 10.4 + y / 14) + .05 * np.cos(y / 5.1 - x / 12)
    crown = np.maximum(0, np.sin(np.pi * t ** .73)) ** .9
    lip_height = 3.1 + .52 * np.sin(angle + .2) + .34 * np.cos(5 * angle + phase)
    rng = np.random.default_rng(2716 + SHAPES.index(shape))
    cloud = wax_variation(rng, 5.8)
    height = face + lip_height * crown + (.085 + .12 * crown) * cloud
    height += .018 * wax_variation(rng, 1.2)
    # A single worn bead transferred from the fine engraving on the stamp.
    bead = .49 + .11 * np.sin(2 * angle - .5) + .07 * np.cos(7 * angle)
    height += bead * np.exp(-((die_depth - 2.15) / .49) ** 2)
    height -= .23 * np.exp(-((die_depth - .22) / .61) ** 2)
    # Folds broaden and fade around the shoulder rather than forming a
    # continuous concentric band. The stamp's face stays smooth enough to read.
    fold_depth = 2.8 + .62 * np.sin(3 * angle) + .38 * np.sin(8 * angle)
    fold = np.exp(-((edge_depth - fold_depth) / .95) ** 2)
    height += .30 * fold * crown * (.5 + .5 * np.cos(3 * angle - .9)) ** 2
    pores = ((-26, 12, .47), (22, -20, .34), (12, 21, .31), (35, 5, .45), (-18, -20, .30))
    for cx, cy, width in pores:
        height -= .22 * np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / width ** 2)
    height *= np.sqrt(np.clip(edge_depth / 1.15, 0, 1))
    return x, y, height, edge_depth, die_depth, crown, cloud


def render_shape(shape):
    x, y, height, edge_depth, die_depth, crown, cloud = surface(shape)
    dy, dx = np.gradient(height, 1 / SCALE)
    length = np.sqrt(dx ** 2 + dy ** 2 + 1)
    nx, ny, nz = -dx / length, -dy / length, 1 / length
    light = np.array([-.47, -.62, .63])
    light /= np.linalg.norm(light)
    half = light + [0, 0, 1]
    half /= np.linalg.norm(half)
    diffuse = np.maximum(0, nx * light[0] + ny * light[1] + nz * light[2])
    reflection = np.maximum(0, nx * half[0] + ny * half[1] + nz * half[2])
    # Saturated pigments under a soft upper-left light. A broad, low sheen on
    # the wax gives way to a smaller glint on the curved crown.
    occlusion = .115 * np.exp(-(die_depth / 1.45) ** 2)
    tone = .56 + .62 * diffuse - occlusion - .04 * (y / 40)
    tone += .013 * cloud + .013 * np.sin(x / 6 + y / 12) + .006 * np.cos(x / 3.4 - y / 7)
    patch = (np.exp(-((x + 22) / 18) ** 2 - ((y + 30) / 19) ** 2)
             + .72 * np.exp(-((x - 24) / 18) ** 2 - ((y - 21) / 14) ** 2))
    sheen = .05 * reflection ** 7 + (.055 + (.10 + .12 * patch) * crown) * reflection ** 22

    alpha = np.clip(edge_depth * SCALE + .5, 0, 1)
    mask = Image.fromarray(np.uint8(np.rint(255 * alpha)))
    shadow = Image.new("RGBA", (WIDTH, HEIGHT))
    for offset, blur, opacity in [((1.0, 2.0), 1.15, .28), ((.25, .65), .45, .35)]:
        contact = Image.new("L", mask.size)
        contact.paste(mask, (round(offset[0] * SCALE), round(offset[1] * SCALE)))
        layer = Image.new("RGBA", mask.size, (47, 30, 21))
        layer.putalpha(contact.filter(ImageFilter.GaussianBlur(blur * SCALE)).point(lambda a: a * opacity))
        shadow.alpha_composite(layer)

    for color in COLORS:
        pigment = np.array(tuple(bytes.fromhex(color)))
        rgb = pigment * tone[..., None] + np.array([236, 213, 186]) * sheen[..., None]
        wax = Image.fromarray(np.uint8(np.clip(np.rint(rgb), 0, 255)))
        wax.putalpha(mask)
        yield Image.alpha_composite(shadow, wax)


if __name__ == "__main__":
    atlas = Image.new("RGBA", (WIDTH * len(COLORS), HEIGHT * len(SHAPES)))
    for row, shape in enumerate(SHAPES):
        for column, seal in enumerate(render_shape(shape)):
            atlas.paste(seal, (column * WIDTH, row * HEIGHT))
    atlas.save(RESOURCE, optimize=True)
