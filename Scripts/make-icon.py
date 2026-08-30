#!/usr/bin/env python3
"""Draws the application icon, at every size macOS asks for.

The icon is the letter **L**, built out of six lamps on a dark plate: four down
the stem, three along the foot, the corner counted once. Four tall and three
wide is exactly six lamps, and the product has exactly six states — so the
letter carries the whole vocabulary instead of merely being an initial, and the
lamps are laid along the path the eye takes anyway. Down the stem and out along
the foot, urgency falls: the orange that is asking for you, the green that has
an answer, the yellow that is working, the blue that is waiting on something it
started, then the two reds.

    python3 Scripts/make-icon.py            # Resources/LampBoard.icns
    python3 Scripts/make-icon.py --preview  # plus a legibility contact sheet

WHAT IT REPLACED, AND WHY
Three lamps in a row on a dark tile had four things wrong with it, and only the
first was ever noticed. It was **horizontal** while the product is a column. It
was, more damagingly, **the macOS window controls** — red, amber and green in a
row on a dark rounded tile is close, minimise, zoom, and in the Dock the eye
parsed it as a piece of window chrome rather than as an application. It said
**traffic light**, which is one lamp with three states, where this is many lamps
with six. And it was painted in **Apple's system colours** rather than the
product's own, so the icon and the panel were not the same orange.

A LETTER NEEDS EVERY STROKE LIT
The honest pose — one lamp asking, the rest at rest — was drawn and rejected:
with half the lamps dark the L breaks in two and what is left is a constellation.
So the letter and the six states are not two options, they are the same option.
The one concession is the resting red, which is dimmed but never switched off,
because a hole in the foot reads as a letter fading out rather than as a lamp at
rest. The two reds sit next to each other at the end of the foot on purpose:
`failed` and `idle` share a hue in this product and are told apart by brightness,
so the pair states that grammar instead of hiding it.

The rules that keep it readable are arithmetic with assertions under them rather
than taste a redraw can quietly lose: the lamps never close up into a bar, the
figure never reaches past the plate, and at the smallest size a lamp is still
wide enough to be a lamp.

The small sizes are not the large one shrunk. Below 64 px the gradient and the
glow land on fractions of a pixel, where they only mute the colour — and colour,
with the shape, is the whole of what still reads. Those sizes get flat discs,
drawn slightly larger: the compensation a designer makes by hand, written down.
"""

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

TILE_TOP = (54, 54, 61)
TILE_BOTTOM = (23, 23, 27)

# The product's own palette, from Sources/LampBoardApp/UI/StatusPalette.swift.
# Not Apple's system colours: the icon has to be the same orange the panel is,
# or the two are quietly different products.
AWAITING = (255, 115, 26)
READY = (51, 217, 107)
WORKING = (250, 191, 41)
WAITING = (107, 168, 250)
IDLE = (217, 61, 61)

# The L, in lamp positions: down the stem, then out along the foot. The corner
# belongs to both and is counted once, which is what makes four-by-three come to
# six rather than seven.
PATH = [(0, 0), (0, 1), (0, 2), (0, 3), (1, 3), (2, 3)]

# One state per lamp, in the order the eye reads them. The last two are the same
# hue at two brightnesses, which is how the panel itself separates a session that
# failed from one at rest.
STATES = [
    (AWAITING, 255),
    (READY, 255),
    (WORKING, 255),
    (WAITING, 255),
    (IDLE, 158),
    (IDLE, 255),
]

GLASS_RATIO = 0.158     # lamp diameter, as a fraction of the tile side
PITCH_FACTOR = 1.30     # centre-to-centre = 1.30 × diameter
# How much larger the lamps are drawn below 64 px. It was 1.14 until the second
# rule below refused it: four lifted lamps at that pitch stand 0.87 of the tile
# tall and touch the rounded edge. 1.10 is the most the plate will take.
SMALL_LIFT = 1.10
OPTICAL_NUDGE = 0.34    # how far the L is pulled back towards its own ink
GLOW = 0.26             # halo radius on a lit lamp, as a fraction of its own

# The smallest size macOS asks for. Every rule below has to survive it.
SMALLEST = 16


def lamp_geometry(tile, glass_ratio=GLASS_RATIO, pitch_factor=PITCH_FACTOR):
    """Diameter and spacing, with three legibility rules asserted rather than hoped.

    1. **The lamps stay apart.** The gap between two neighbours is at least a
       fifth of a lamp. Below that the stem closes into a bar, the foot closes
       into a dash, and the L stops being a letter and becomes a corner.

    2. **The figure stays on the plate.** Four lamps tall must fit inside the
       tile with a real margin. A mark that reaches the rounded edge reads as a
       rendering fault rather than as a design.

    3. **A lamp is still a lamp at 16 px.** Two whole pixels is the floor: at one
       pixel the six lamps become six specks and the shape they make is the only
       thing left, which is not enough to carry a letter.
    """
    glass = tile * glass_ratio
    pitch = glass * pitch_factor
    gap = pitch - glass
    assert gap >= glass * 0.20, (
        f"lamps {gap:.2f} apart at {glass:.2f} across: the stem will close into a bar"
    )

    height = 3 * pitch + glass
    assert height <= tile * 0.86, (
        f"the L is {height:.1f} tall on a {tile:.1f} tile: it will touch the edge"
    )

    smallest = SMALLEST * TILE_RATIO * glass_ratio * SMALL_LIFT
    assert smallest >= 2.0, (
        f"a lamp is {smallest:.2f} px across at {SMALLEST} px: too small to read"
    )
    return glass, pitch


def lamp_centres(canvas, pitch):
    """Where the six lamps go, centred on their own ink rather than on their box.

    An L is heavy at the bottom left. Centring the three-by-four bounding box
    leaves the figure visibly low and left of the plate's middle, so the whole
    thing is pulled back towards the mean of the lamps actually drawn. Only part
    of the way: the full correction over-corrects and pushes the foot out past
    the tile's rounded corner.
    """
    cols = [c for c, _ in PATH]
    rows = [r for _, r in PATH]
    box_cx = (max(cols) + min(cols)) / 2.0
    box_cy = (max(rows) + min(rows)) / 2.0
    ink_cx = sum(cols) / len(cols)
    ink_cy = sum(rows) / len(rows)
    x0 = canvas / 2.0 - box_cx * pitch + (box_cx - ink_cx) * pitch * OPTICAL_NUDGE
    y0 = canvas / 2.0 - box_cy * pitch + (box_cy - ink_cy) * pitch * OPTICAL_NUDGE
    return [(x0 + c * pitch, y0 + r * pitch) for c, r in PATH]


def radial_glass(diameter, colour, resolution=192):
    """One lamp face: bright off-centre, deepening to the rim.

    Built small and scaled up. The gradient is smooth by nature, so the
    resampling costs nothing visible and saves computing a quarter of a million
    pixels in Python at 2048.

    The light is placed up and to the left, where every other lens on the screen
    is lit from, and the colour deepens *into itself* rather than towards black:
    a lamp shaded towards black reads as a switched-off lamp with a reflection.
    """
    n = resolution
    lighter = tuple(min(255, int(c + (255 - c) * 0.22)) for c in colour)
    deeper = tuple(max(0, int(c * 0.76)) for c in colour)

    face = Image.new("RGB", (n, n))
    pixels = face.load()
    cx, cy = n * 0.38, n * 0.34          # the highlight's centre, not the disc's
    reach = n * 0.92
    for y in range(n):
        dy = (y - cy) / reach
        for x in range(n):
            dx = (x - cx) / reach
            t = min(1.0, (dx * dx + dy * dy) ** 0.5)
            t = t * t                     # slow near the centre, quick at the rim
            pixels[x, y] = tuple(
                round(lighter[i] + (deeper[i] - lighter[i]) * t) for i in range(3)
            )

    face = face.resize((diameter, diameter), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (diameter, diameter), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, diameter - 1, diameter - 1], fill=255)
    face.putalpha(mask)
    return face


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


def _expanded(mask, size, origin):
    """Puts the tile mask back on the full canvas, so nothing spills outside."""
    full = Image.new("L", (size, size), 0)
    full.paste(mask, (origin, origin))
    return full


def draw(size, ornament=True, glass_ratio=GLASS_RATIO, pitch_factor=PITCH_FACTOR,
         supersample=4):
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

    glass, pitch = lamp_geometry(tile, glass_ratio, pitch_factor)
    inside = _expanded(tile_mask(tile, radius), S, origin)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    for (cx, cy), (colour, alpha) in zip(lamp_centres(S, pitch), STATES):
        r = glass / 2.0

        # A halo, and only on a lamp that is fully lit. The resting red does not
        # get one: it is the one lamp in the letter that is meant to sit back.
        if ornament and alpha == 255:
            halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            hr = r * (1.0 + GLOW)
            ImageDraw.Draw(halo).ellipse([cx - hr, cy - hr, cx + hr, cy + hr],
                                         fill=colour + (110,))
            halo = halo.filter(ImageFilter.GaussianBlur(r * GLOW * 0.60))
            layer.alpha_composite(halo)

        d = max(2, int(round(glass)))
        if ornament:
            face = radial_glass(d, colour)
        else:
            # No gradient: at 16 px the disc *is* the lamp, and the only things
            # that have to survive are the hue and where it sits in the letter.
            face = Image.new("RGBA", (d, d), colour + (255,))
            mask = Image.new("L", (d, d), 0)
            ImageDraw.Draw(mask).ellipse([0, 0, d - 1, d - 1], fill=255)
            face.putalpha(mask)

        if alpha < 255:
            faded = face.getchannel("A").point(lambda v: v * alpha // 255)
            face.putalpha(faded)

        layer.alpha_composite(face, (int(round(cx - d / 2)), int(round(cy - d / 2))))

    layer.putalpha(Image.composite(layer.getchannel("A"),
                                   Image.new("L", (S, S), 0), inside))
    canvas.alpha_composite(layer)

    return canvas.resize((size, size), Image.LANCZOS)


# 16, 32 and 64 are drawn, not shrunk: flat discs, drawn larger. Below 128 the
# gradient and the halo land between pixels and only mute the colour.
SIZES = [
    (16, dict(ornament=False, glass_ratio=GLASS_RATIO * SMALL_LIFT,
              pitch_factor=1.28, supersample=16)),
    (32, dict(ornament=False, glass_ratio=GLASS_RATIO * SMALL_LIFT,
              pitch_factor=1.29, supersample=12)),
    (64, dict(ornament=False, glass_ratio=GLASS_RATIO * 1.08,
              pitch_factor=1.30, supersample=8)),
    (128, dict(supersample=6)),
    (256, dict(supersample=4)),
    (512, dict(supersample=3)),
    (1024, dict(supersample=2)),
]


def render_all():
    return {size: draw(size, **options) for size, options in SIZES}


def build_icns(images, destination):
    iconset = os.path.join(ROOT, ".build", "LampBoard.iconset")
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
    icns = build_icns(rendered, os.path.join(ROOT, "Resources", "LampBoard.icns"))
    print(f"✓ {icns}")
    if "--preview" in sys.argv:
        out = os.path.join(ROOT, ".build", "icon-preview.png")
        print(f"✓ {contact_sheet(rendered, out)}")
        rendered[1024].save(os.path.join(ROOT, ".build", "icon-1024.png"))
        print(f"✓ {os.path.join(ROOT, '.build', 'icon-1024.png')}")
