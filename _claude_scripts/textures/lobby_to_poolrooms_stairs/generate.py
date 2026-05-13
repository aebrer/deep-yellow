#!/usr/bin/env python3
"""
Wet Tile Stairwell Floor Decal - Sprite Generator

Generates a 64x64 RGBA pixel-art floor decal for the transition into the
Poolrooms. The lower/player-side edge has broad close stair treads; the stairs
recede upward into blue-green chlorinated darkness.
"""

from PIL import Image, ImageDraw
import math
import os
import random
import shutil

# Fixed seed for deterministic reruns.
random.seed(74175)

SIZE = 64
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "output.png")
GAME_TEXTURE_PATH = "/home/drew/projects/deep_yellow/assets/textures/entities/lobby_to_poolrooms_stairs.png"

TRANSPARENT = (0, 0, 0, 0)
DEEP_CHLORINE = (8, 54, 82, 230)
DARK_CYAN = (18, 82, 108, 235)
GROUT_DARK = (42, 116, 132, 255)
GROUT = (108, 182, 190, 255)
TILE_FAR = (72, 160, 178, 255)
TILE_MID = (148, 222, 228, 255)
TILE_NEAR = (224, 248, 248, 255)
HIGHLIGHT = (244, 255, 252, 255)
POOL_GLOW = (52, 226, 210, 72)
POOL_GLOW_FAINT = (42, 178, 198, 34)
WET_SHADOW = (14, 76, 104, 190)

# Far-to-near treads. The bottom/player-side treads are intentionally widest.
STEPS = [
    (26, 9, 38, 15),
    (23, 15, 41, 21),
    (19, 21, 45, 28),
    (14, 28, 50, 36),
    (8, 36, 56, 47),
    (2, 47, 62, 61),
]


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def in_bounds(x, y):
    return 0 <= x < SIZE and 0 <= y < SIZE


def blend_pixel(img, x, y, color):
    if not in_bounds(x, y):
        return
    px = img.load()
    r0, g0, b0, a0 = px[x, y]
    r1, g1, b1, a1 = color
    alpha = a1 / 255.0
    out_a = clamp(a0 + a1 * (1.0 - a0 / 255.0))
    if out_a == 0:
        px[x, y] = TRANSPARENT
        return
    px[x, y] = (
        clamp(r0 * (1.0 - alpha) + r1 * alpha),
        clamp(g0 * (1.0 - alpha) + g1 * alpha),
        clamp(b0 * (1.0 - alpha) + b1 * alpha),
        out_a,
    )


def set_pixel(img, x, y, color):
    if in_bounds(x, y):
        img.putpixel((x, y), color)


def mix(c1, c2, t):
    return tuple(clamp(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


def quantize(color):
    r, g, b, a = color
    return (int(r / 8) * 8, int(g / 8) * 8, int(b / 8) * 8, a)


def draw_line_pixels(img, x1, y1, x2, y2, color):
    dx = abs(x2 - x1)
    dy = -abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx + dy
    x = x1
    y = y1
    while True:
        blend_pixel(img, x, y, color)
        if x == x2 and y == y2:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy


def draw_poolroom_glow(img):
    """Transparent cyan halo plus darker chlorinated depth near the far/top end."""
    for y in range(4, 63):
        for x in range(1, 63):
            # Broad wet glow around the decal.
            dx = (x - 32) / 31.0
            dy = (y - 38) / 28.0
            d = math.sqrt(dx * dx + dy * dy)
            if d < 1.0:
                alpha = int(44 * (1.0 - d) ** 2)
                if alpha > 2:
                    blend_pixel(img, x, y, (POOL_GLOW[0], POOL_GLOW[1], POOL_GLOW[2], alpha))

            # Far/top chlorine darkness, still blue-green rather than black.
            dx2 = (x - 32) / 18.0
            dy2 = (y - 12) / 10.0
            d2 = math.sqrt(dx2 * dx2 + dy2 * dy2)
            if d2 < 1.0:
                alpha = int(130 * (1.0 - d2))
                blend_pixel(img, x, y, (DEEP_CHLORINE[0], DEEP_CHLORINE[1], DEEP_CHLORINE[2], alpha))


def draw_steps(draw, img):
    pixels = img.load()

    # Small far landing/opening at the top, framed by distant tile.
    draw.polygon([(27, 5), (37, 5), (40, 10), (24, 10)], fill=(8, 48, 76, 225))
    draw.line([(26, 10), (38, 10)], fill=(70, 220, 210, 150), width=1)

    for idx, (x1, y1, x2, y2) in enumerate(STEPS):
        t = idx / max(1, len(STEPS) - 1)  # 0 far/top, 1 near/bottom
        tile_color = quantize(mix(TILE_FAR, TILE_NEAR, t))
        shadow_color = quantize(mix(DEEP_CHLORINE, WET_SHADOW, t * 0.35))

        # Main tread trapezoid, widening toward the player/lower edge.
        draw.polygon([(x1, y1), (x2, y1), (x2 + 1, y2), (x1 - 1, y2)], fill=tile_color)

        # Far steps stay darker; near steps carry stronger wet highlights.
        for y in range(y1 + 1, y2):
            row_t = (y - y1) / max(1, y2 - y1)
            left = int(x1 + (x1 - 1 - x1) * row_t)
            right = int(x2 + (x2 + 1 - x2) * row_t)
            for x in range(left + 2, right - 1):
                center_falloff = abs(x - 32) / max(1, (right - left) / 2)
                alpha = int((58 - idx * 4) * (1.0 - center_falloff * 0.42))
                if idx < 3:
                    alpha += int((3 - idx) * 18)
                if alpha > 0:
                    blend_pixel(img, x, y, (shadow_color[0], shadow_color[1], shadow_color[2], min(205, alpha)))

        # Riser and tread lips; near/bottom lines are visibly broader/brighter.
        lip = HIGHLIGHT if idx >= 3 else GROUT
        draw.line([(x1, y1), (x2, y1)], fill=GROUT_DARK if idx < 2 else GROUT, width=1)
        draw.line([(x1 - 1, y2), (x2 + 1, y2)], fill=lip, width=1 if idx < 4 else 2)
        draw.line([(x1, y1), (x1 - 1, y2)], fill=(30, 104, 124, 205), width=1)
        draw.line([(x2, y1), (x2 + 1, y2)], fill=(22, 92, 118, 220), width=1)

        # Tile grout seams converge toward the top to reinforce perspective.
        seam_count = 2 if idx < 2 else 3 if idx < 5 else 4
        for seam in range(1, seam_count + 1):
            sx_top = x1 + int((x2 - x1) * seam / (seam_count + 1))
            sx_bot = (x1 - 1) + int(((x2 + 1) - (x1 - 1)) * seam / (seam_count + 1))
            draw.line([(sx_top, y1 + 1), (sx_bot, y2 - 1)], fill=(92, 172, 184, 150), width=1)

    # Ordered dither/noise on opaque tile pixels for PSX-style material texture.
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a > 160:
                n = (((x * 17 + y * 31 + (x ^ y) * 5) % 9) - 4) * 3
                pixels[x, y] = (clamp(r + n), clamp(g + n), clamp(b + n), a)


def draw_wet_shimmer(img):
    shimmer = (236, 255, 252, 155)
    cyan = (72, 236, 222, 110)
    lines = [
        (29, 13, 35, 12, cyan),
        (24, 20, 38, 18, shimmer),
        (20, 27, 42, 25, cyan),
        (15, 35, 33, 33, shimmer),
        (36, 41, 54, 39, cyan),
        (7, 50, 28, 48, shimmer),
        (34, 56, 59, 53, cyan),
    ]
    for x1, y1, x2, y2, color in lines:
        draw_line_pixels(img, x1, y1, x2, y2, color)
        blend_pixel(img, x2, y2, (255, 255, 255, 150))

    beads = [(31, 16, 90), (21, 31, 120), (45, 33, 105), (13, 45, 135), (28, 54, 150), (49, 55, 130)]
    for x, y, a in beads:
        blend_pixel(img, x, y, (238, 255, 252, a))
        blend_pixel(img, x + 1, y, (58, 210, 214, max(55, a - 55)))


def generate_texture():
    img = Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    draw_poolroom_glow(img)
    draw_steps(draw, img)
    draw_wet_shimmer(img)

    return img


def main():
    print("Generating wet tile stairwell floor decal (64x64 RGBA)...")
    img = generate_texture()
    img.save(OUTPUT_PATH, "PNG")
    print(f"Saved to: {OUTPUT_PATH}")

    os.makedirs(os.path.dirname(GAME_TEXTURE_PATH), exist_ok=True)
    shutil.copy2(OUTPUT_PATH, GAME_TEXTURE_PATH)
    print(f"Copied to: {GAME_TEXTURE_PATH}")
    print(f"Size: {img.size}, Mode: {img.mode}")


if __name__ == "__main__":
    main()
