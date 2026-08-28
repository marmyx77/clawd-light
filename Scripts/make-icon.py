#!/usr/bin/env python3
"""Draws the application icon, at every size macOS asks for.

The icon is three claw slashes — the name carries *claw*, the product is a
traffic light, and the three marks are the three states. It is generated
rather than drawn by hand for one reason: the rule that keeps it legible at
16 px is arithmetic, not taste. The gap between two slashes is never smaller
than a slash is wide, and here that is a line of code instead of something a
redraw can quietly lose.

    python3 Scripts/make-icon.py            # Resources/ClawdLight.icns
    python3 Scripts/make-icon.py --preview  # plus a legibility contact sheet

The small sizes are not the large one shrunk. Below 32 px the shadow and the
edge highlight land on nothing and the strokes go thin and grey, so those
sizes get thicker strokes and no ornament — the compensation a designer makes
by hand, written down.
"""

import math
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The Big Sur grid: on a 1024 canvas the rounded tile is 824 wide with a
# corner radius of 185.4. Getting this wrong is why home-made icons sit
# visibly larger or smaller than their neighbours in the Dock.
TILE_RATIO = 824.0 / 1024.0
CORNER_RATIO = 185.4 / 824.0

# macOS system colours, because the icon lives next to Apple's own.
RED = (255, 59, 48)
AMBER = (255, 159, 10)
GREEN = (48, 209, 88)

TILE_TOP = (54, 54, 61)
TILE_BOTTOM = (23, 23, 27)

ANGLE_DEG = 30.0        # from the vertical: a swipe, not a stack
STROKE_RATIO = 0.072    # stroke width, as a fraction of the tile side
GAP_FACTOR = 2.8        # centre-to-centre = 2.8 × width → edge gap = 1.8 × width
LENGTH_RATIO = 0.66     # slash length, as a fraction of the tile side
STAGGER_RATIO = 0.060   # how far each slash slides along its own direction
OPTICAL_LIFT = 0.018    # the group sits above the geometric centre


def lens(length, width, samples=220):
    """One claw mark: a lens with sharp tips, centred on the origin.

    A rounded rectangle reads as a bar; the sharp tip is the whole reason
    this reads as a claw. The profile is (1 - t²), which reaches zero with a
    finite slope — a point, not a blunt end — and the slight bias moves the
    fullest part off centre so the mark looks struck rather than drawn.
    """
    points = []
    for side in (1, -1):
        for i in range(samples + 1):
            t = -1.0 + 2.0 * i / samples
            if side < 0:
                t = -t
            half = 0.5 * width * (1.0 - t * t) * (1.0 + 0.10 * t)
            points.append((side * max(half, 0.0), t * length / 2.0))
    return points


def placed(points, centre, angle_rad):
    cos_a, sin_a = math.cos(angle_rad), math.sin(angle_rad)
    cx, cy = centre
    return [(cx + x * cos_a - y * sin_a, cy + x * sin_a + y * cos_a)
            for x, y in points]


def vertical_gradient(size, top, bottom):
    ramp = Image.new("RGB", (1, size))
    pixels = ramp.load()
    for y in range(size):
        k = y / max(size - 1, 1)
        pixels[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * k) for i in range(3))
    return ramp.resize((size, size), Image.BILINEAR)


def tile_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1],
                                           radius=radius, fill=255)
    return mask


def draw(size, ornament=True, stroke_ratio=STROKE_RATIO,
         length_ratio=LENGTH_RATIO, supersample=4):
    """Renders the icon at `size` pixels."""
    S = size * supersample
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    tile = int(round(S * TILE_RATIO))
    radius = int(round(tile * CORNER_RATIO))
    origin = (S - tile) // 2

    plate = vertical_gradient(tile, TILE_TOP, TILE_BOTTOM).convert("RGBA")
    plate.putalpha(tile_mask(tile, radius))

    if ornament:
        # A single lighter line inside the top edge: the whole glass hint.
        gloss = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
        ImageDraw.Draw(gloss).rounded_rectangle(
            [0, 0, tile - 1, tile - 1], radius=radius,
            outline=(255, 255, 255, 46), width=max(2, tile // 220))
        top_only = Image.new("L", (tile, tile), 0)
        ImageDraw.Draw(top_only).rectangle([0, 0, tile, int(tile * 0.42)], fill=255)
        top_only = top_only.filter(ImageFilter.GaussianBlur(tile * 0.05))
        gloss.putalpha(Image.composite(gloss.getchannel("A"),
                                       Image.new("L", (tile, tile), 0), top_only))
        plate.alpha_composite(gloss)

    canvas.alpha_composite(plate, (origin, origin))

    angle = math.radians(ANGLE_DEG)
    width = tile * stroke_ratio
    length = tile * length_ratio
    gap = width * GAP_FACTOR
    stagger = tile * STAGGER_RATIO

    # Perpendicular to the slash, so the gap is measured across them; and
    # along the slash, so they stagger like a swipe instead of a stack.
    across = (math.cos(angle), math.sin(angle))
    along = (-math.sin(angle), math.cos(angle))

    centre_x = S / 2.0
    centre_y = S / 2.0 - tile * OPTICAL_LIFT

    lengths = (0.94, 1.0, 0.94)
    slides = (1.0, 0.0, -1.0)
    colours = (RED, AMBER, GREEN)

    marks = []
    for i, (colour, k, slide) in enumerate(zip(colours, lengths, slides)):
        offset = (i - 1) * gap
        cx = centre_x + across[0] * offset + along[0] * slide * stagger
        cy = centre_y + across[1] * offset + along[1] * slide * stagger
        marks.append((colour, placed(lens(length * k, width), (cx, cy), angle)))

    if ornament:
        # A tight dark shadow, never a coloured glow: at 16 px a glow bleeds
        # from one slash into the next and the three colours turn to mud.
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        pen = ImageDraw.Draw(shadow)
        for _, polygon in marks:
            pen.polygon([(x + S * 0.006, y + S * 0.008) for x, y in polygon],
                        fill=(0, 0, 0, 130))
        shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.010))
        # Clipped to the tile, so the blur does not smudge past the corners.
        inside = _expanded(tile_mask(tile, radius), S, origin)
        shadow.putalpha(Image.composite(shadow.getchannel("A"),
                                        Image.new("L", (S, S), 0), inside))
        canvas.alpha_composite(shadow)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for colour, polygon in marks:
        if ornament:
            # Light along the mark, not a bevel on top of it: the colour is
            # graded from its own lighter self at the tip to its own deeper
            # self at the foot, inside the mark's own silhouette. A second
            # lighter copy laid over the first is what turned red into brown.
            lighter = tuple(min(255, c + 38) for c in colour)
            deeper = tuple(max(0, int(c * 0.80)) for c in colour)
            body = vertical_gradient(S, lighter, deeper).convert("RGBA")
        else:
            body = Image.new("RGBA", (S, S), colour + (255,))
        shape = Image.new("L", (S, S), 0)
        ImageDraw.Draw(shape).polygon(polygon, fill=255)
        body.putalpha(shape)
        layer.alpha_composite(body)
    inside = _expanded(tile_mask(tile, radius), S, origin)
    layer.putalpha(Image.composite(layer.getchannel("A"),
                                   Image.new("L", (S, S), 0), inside))
    canvas.alpha_composite(layer)

    return canvas.resize((size, size), Image.LANCZOS)


def _expanded(mask, size, origin):
    """Puts the tile mask back on the full canvas, so nothing spills outside."""
    full = Image.new("L", (size, size), 0)
    full.paste(mask, (origin, origin))
    return full


# 16 and 32 are drawn, not shrunk: fatter strokes, no ornament. Below that
# size the shadow and the gloss fall between pixels and only mute the colour.
SIZES = [
    (16, dict(ornament=False, stroke_ratio=0.132, length_ratio=0.70, supersample=16)),
    (32, dict(ornament=False, stroke_ratio=0.108, length_ratio=0.68, supersample=12)),
    (64, dict(ornament=True, stroke_ratio=0.092, length_ratio=0.67, supersample=8)),
    (128, dict(supersample=6)),
    (256, dict(supersample=4)),
    (512, dict(supersample=3)),
    (1024, dict(supersample=2)),
]


def render_all():
    return {size: draw(size, **options) for size, options in SIZES}


def build_icns(images, destination):
    iconset = os.path.join(ROOT, ".build", "ClawdLight.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)

    # Each entry appears twice, once as a size and once as another size's @2x.
    for base in (16, 32, 128, 256, 512):
        images[base].save(os.path.join(iconset, f"icon_{base}x{base}.png"))
        images[base * 2].save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))

    os.makedirs(os.path.dirname(destination), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", destination], check=True)
    shutil.rmtree(iconset, ignore_errors=True)
    return destination


def contact_sheet(images, destination):
    """The only review that matters: the sizes it will actually be seen at."""
    shown = [16, 32, 64, 128, 256]
    pad, scale = 16, 3
    width = pad + sum(s + pad for s in shown)
    height = max(shown) + 2 * pad
    sheet = Image.new("RGB", (width * scale, height * scale), (232, 232, 236))
    x = pad
    for size in shown:
        image = images[size]
        big = image.resize((size * scale, size * scale),
                           Image.NEAREST if size <= 32 else Image.LANCZOS)
        under = Image.new("RGBA", big.size, (232, 232, 236, 255))
        under.alpha_composite(big)
        sheet.paste(under.convert("RGB"),
                    (x * scale, (pad + (max(shown) - size) // 2) * scale))
        x += size + pad
    sheet.save(destination)
    return destination


if __name__ == "__main__":
    rendered = render_all()
    icns = build_icns(rendered, os.path.join(ROOT, "Resources", "ClawdLight.icns"))
    print(f"✓ {icns}")
    if "--preview" in sys.argv:
        out = os.path.join(ROOT, ".build", "icon-preview.png")
        print(f"✓ {contact_sheet(rendered, out)}")
        rendered[1024].save(os.path.join(ROOT, ".build", "icon-1024.png"))
        print(f"✓ {os.path.join(ROOT, '.build', 'icon-1024.png')}")
