#!/usr/bin/env python3
"""Draws the application icon, at every size macOS asks for.

The icon is a lamp board: three pilot lamps in a row on a dark panel, red then
amber then green. That is the product — one row of lights you read at a glance,
never a control you operate — and it is the object the name comes from, the
annunciator panel of a signal box or a control room.

It is generated rather than drawn by hand for one reason: the rule that keeps it
legible at 16 px is arithmetic, not taste. The gap between two lamps is never
smaller than a bezel is thick, and here that is a line of code with an assertion
under it instead of something a redraw can quietly lose.

    python3 Scripts/make-icon.py            # Resources/LampBoard.icns
    python3 Scripts/make-icon.py --preview  # plus a legibility contact sheet

The small sizes are not the large one shrunk. Below 64 px the bezel, the glass
and the specular highlight land on fractions of a pixel: the bezel turns the
lamp grey, the highlight eats its centre, and three lit lamps become three
smudges. Those sizes get bare discs, drawn slightly larger — the compensation a
designer makes by hand, written down.
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

# macOS system colours, because the icon lives next to Apple's own.
RED = (255, 59, 48)
AMBER = (255, 159, 10)
GREEN = (48, 209, 88)

TILE_TOP = (54, 54, 61)
TILE_BOTTOM = (23, 23, 27)

# The board the lamps are seated in: a shade darker than the plate, never a
# different colour. It exists to say "these three belong together", and a
# board that announces itself competes with the lamps for the same glance.
BOARD_DARK = (16, 16, 19)

BEZEL_DARK = (12, 12, 14)
BEZEL_LIGHT = (86, 86, 94)

GLASS_RATIO = 0.164     # lamp glass diameter, as a fraction of the tile side
BEZEL_RATIO = 0.024     # bezel thickness, same units
PITCH_FACTOR = 1.34     # centre-to-centre = 1.34 × outer diameter
OPTICAL_LIFT = 0.012    # the row sits above the geometric centre
BOARD_PAD = 0.048       # how far the board extends past the outer bezels


def lamp_geometry(tile, glass_ratio=GLASS_RATIO, bezel_ratio=BEZEL_RATIO,
                  pitch_factor=PITCH_FACTOR):
    """Diameters and spacing, with the legibility rule asserted rather than hoped.

    The rule: the space between two lamps is never narrower than a bezel. Below
    that the two glows meet, and at 16 px three lit lamps read as one wide
    smear of colour — the failure that is invisible at 1024 and fatal in the Dock.
    """
    glass = tile * glass_ratio
    bezel = tile * bezel_ratio
    outer = glass + 2 * bezel
    pitch = outer * pitch_factor
    gap = pitch - outer
    assert gap >= bezel, (
        f"lamps {gap:.2f} apart with a {bezel:.2f} bezel: they will merge when small"
    )
    return glass, bezel, outer, pitch


def radial_glass(diameter, colour, resolution=192):
    """One lit lamp face: bright off-centre, deepening to the rim.

    Built small and scaled up. The gradient is smooth by nature, so the
    resampling costs nothing visible and saves computing a quarter of a million
    pixels in Python at 2048.

    The light is placed up and to the left, where every other lens on the screen
    is lit from, and the colour deepens *into itself* rather than towards black:
    a lamp shaded towards black reads as a switched-off lamp with a reflection.
    """
    n = resolution
    lighter = tuple(min(255, int(c + (255 - c) * 0.20)) for c in colour)
    deeper = tuple(max(0, int(c * 0.74)) for c in colour)

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


def draw(size, ornament=True, glass_ratio=GLASS_RATIO, bezel_ratio=BEZEL_RATIO,
         pitch_factor=PITCH_FACTOR, supersample=4):
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

    glass, bezel, outer, pitch = lamp_geometry(
        tile, glass_ratio, bezel_ratio, pitch_factor
    )
    centre_x = S / 2.0
    centre_y = S / 2.0 - tile * OPTICAL_LIFT
    centres = [(centre_x + (i - 1) * pitch, centre_y) for i in range(3)]
    colours = (RED, AMBER, GREEN)

    inside = _expanded(tile_mask(tile, radius), S, origin)

    if ornament:
        # The board: what turns three lights into one instrument. Ornament only,
        # because at 32 px it is four pixels of near-black behind the lamps and
        # all it does there is dull the plate.
        pad = tile * BOARD_PAD
        half_w = pitch + outer / 2.0 + pad
        half_h = outer / 2.0 + pad
        board = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(board).rounded_rectangle(
            [centre_x - half_w, centre_y - half_h,
             centre_x + half_w, centre_y + half_h],
            radius=half_h * 0.42, fill=BOARD_DARK + (150,))
        board = board.filter(ImageFilter.GaussianBlur(S * 0.002))
        board.putalpha(Image.composite(board.getchannel("A"),
                                       Image.new("L", (S, S), 0), inside))
        canvas.alpha_composite(board)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pen = ImageDraw.Draw(layer)

    for (cx, cy), colour in zip(centres, colours):
        if ornament:
            # The bezel is a ring lit from the top, so the lamp sits *in* the
            # board instead of on it: light above, shadow below, one ellipse each.
            r_out = outer / 2.0
            pen.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out],
                        fill=BEZEL_DARK + (255,))
            pen.arc([cx - r_out, cy - r_out, cx + r_out, cy + r_out],
                    start=185, end=355, fill=BEZEL_LIGHT + (110,),
                    width=max(1, int(bezel * 0.30)))

        r_glass = glass / 2.0 if ornament else outer / 2.0
        d = max(2, int(round(r_glass * 2)))
        if ornament:
            face = radial_glass(d, colour)
        else:
            # No gradient, no bezel: at 16 px the disc *is* the lamp, and the
            # only thing that has to survive is the hue.
            face = Image.new("RGBA", (d, d), colour + (255,))
            mask = Image.new("L", (d, d), 0)
            ImageDraw.Draw(mask).ellipse([0, 0, d - 1, d - 1], fill=255)
            face.putalpha(mask)
        layer.alpha_composite(face, (int(round(cx - d / 2)), int(round(cy - d / 2))))

        if ornament:
            # One small specular, up and left, on its own so it is never blurred
            # into the glass gradient underneath.
            hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            hw, hh = glass * 0.30, glass * 0.20
            hx, hy = cx - glass * 0.13, cy - glass * 0.23
            ImageDraw.Draw(hl).ellipse([hx - hw / 2, hy - hh / 2,
                                        hx + hw / 2, hy + hh / 2],
                                       fill=(255, 255, 255, 82))
            hl = hl.filter(ImageFilter.GaussianBlur(glass * 0.045))
            layer.alpha_composite(hl)

    layer.putalpha(Image.composite(layer.getchannel("A"),
                                   Image.new("L", (S, S), 0), inside))
    canvas.alpha_composite(layer)

    return canvas.resize((size, size), Image.LANCZOS)


# 16, 32 and 64 are drawn, not shrunk: bare discs, drawn larger. Below 128 the
# bezel is a grey ring a pixel wide that turns the lamp the colour of the board.
SIZES = [
    (16, dict(ornament=False, glass_ratio=0.215, bezel_ratio=0.026,
              pitch_factor=1.28, supersample=16)),
    (32, dict(ornament=False, glass_ratio=0.208, bezel_ratio=0.026,
              pitch_factor=1.30, supersample=12)),
    (64, dict(ornament=False, glass_ratio=0.196, bezel_ratio=0.024,
              pitch_factor=1.32, supersample=8)),
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
