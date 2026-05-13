#!/usr/bin/env python3
"""
Poolrooms Broken/Off Recessed Light Sprite Generator

Generates a 64x64 RGBA pixel-art sprite for the entropy-locked off/flickered-out
counterpart to the Poolrooms recessed light. It keeps the same off-side viewing
angle and silhouette as the lit fixture, but uses a dark diffuser, cracked glass,
and only a faint cyan residual rim.
"""

from PIL import Image, ImageDraw
import math
import os
import random
import shutil

# Fixed seed for deterministic reruns.
random.seed(71002)

SIZE = 64
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "output.png")
GAME_TEXTURE_PATH = "/home/drew/projects/deep_yellow/assets/textures/entities/poolroom_light_broken.png"

TRANSPARENT = (0, 0, 0, 0)
FAINT_HALO = (24, 146, 164, 12)
METAL_DARK = (18, 46, 56, 255)
METAL_MID = (48, 86, 94, 255)
METAL_EDGE = (102, 154, 154, 255)
CERAMIC_DAMP = (78, 132, 136, 255)
CERAMIC_DIRTY = (40, 86, 96, 255)
RECESS = (4, 26, 40, 248)
LENS_DARK = (20, 62, 76, 255)
LENS_DIM = (38, 94, 106, 255)
LENS_EDGE = (58, 140, 150, 255)
CRACK = (6, 28, 38, 255)
CYAN_RESIDUAL = (54, 202, 204, 70)
WET_SPEC_DIM = (142, 208, 204, 112)

# Matches poolroom_light/generate.py so ON and BROKEN silhouettes align.
CX = 32
CY = 31
SHEAR = 0.22


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


def ellipse_norm(x, y, cx, cy, rx, ry, shear):
    sx = x - (cx + shear * (y - cy))
    sy = y - cy
    return math.sqrt((sx / rx) ** 2 + (sy / ry) ** 2)


def inside_ellipse(x, y, cx, cy, rx, ry, shear):
    return ellipse_norm(x, y, cx, cy, rx, ry, shear) <= 1.0


def fill_sheared_ellipse(img, cx, cy, rx, ry, shear, color_func):
    for y in range(max(0, int(cy - ry - 3)), min(SIZE, int(cy + ry + 4))):
        for x in range(max(0, int(cx - rx - 8)), min(SIZE, int(cx + rx + 8))):
            n = ellipse_norm(x, y, cx, cy, rx, ry, shear)
            if n <= 1.0:
                color = color_func(x, y, n)
                if color is not None and color[3] > 0:
                    blend_pixel(img, x, y, color)


def ellipse_point(cx, cy, rx, ry, shear, theta):
    y = cy + ry * math.sin(theta)
    x = cx + shear * (y - cy) + rx * math.cos(theta)
    return (int(round(x)), int(round(y)))


def draw_arc(draw, cx, cy, rx, ry, shear, theta1, theta2, color, width=1, steps=28):
    points = [ellipse_point(cx, cy, rx, ry, shear, theta1 + (theta2 - theta1) * i / steps) for i in range(steps + 1)]
    draw.line(points, fill=color, width=width)


def draw_faint_residual_halo(img):
    """A very dim cyan aura, not a bright active glow."""
    for y in range(SIZE):
        for x in range(SIZE):
            n = ellipse_norm(x, y, CX, CY, 30, 20, SHEAR * 0.65)
            if n < 1.0:
                alpha = int(FAINT_HALO[3] * (1.0 - n) ** 2)
                if alpha > 0:
                    blend_pixel(img, x, y, (FAINT_HALO[0], FAINT_HALO[1], FAINT_HALO[2], alpha))


def draw_housing(draw, img):
    """Same skewed fixture form as the lit version, dark and damp."""
    fill_sheared_ellipse(img, CX + 1, CY + 4, 25, 15, SHEAR, lambda x, y, n: (4, 22, 32, int(160 * (1.0 - n * 0.2))))

    def outer_color(x, y, n):
        vertical = (y - (CY - 14)) / 29.0
        base = mix(METAL_EDGE, METAL_DARK, max(0.0, min(1.0, vertical)))
        return quantize(base)

    fill_sheared_ellipse(img, CX, CY, 25, 15, SHEAR, outer_color)

    def trim_color(x, y, n):
        if inside_ellipse(x, y, CX, CY, 20, 11, SHEAR):
            return None
        vertical = (y - (CY - 13)) / 26.0
        return quantize(mix(CERAMIC_DAMP, CERAMIC_DIRTY, max(0.0, min(1.0, vertical))))

    fill_sheared_ellipse(img, CX, CY, 22, 13, SHEAR, trim_color)
    fill_sheared_ellipse(img, CX, CY + 1, 18, 10, SHEAR, lambda x, y, n: mix(RECESS, METAL_DARK, min(1.0, n)))

    # Dark front lip and accumulated grime.
    for y in range(CY + 3, CY + 17):
        for x in range(5, 60):
            if inside_ellipse(x, y, CX, CY, 25, 15, SHEAR) and not inside_ellipse(x, y, CX, CY, 17, 8, SHEAR):
                alpha = int(85 + (y - CY) * 9)
                blend_pixel(img, x, y, (2, 24, 34, min(220, alpha)))

    # Muted bevels and residual cyan ring.
    draw_arc(draw, CX, CY, 25, 15, SHEAR, math.pi * 1.05, math.pi * 1.92, (128, 182, 176, 150), 1)
    draw_arc(draw, CX, CY, 25, 15, SHEAR, math.pi * 0.02, math.pi * 0.92, (2, 24, 34, 240), 2)
    draw_arc(draw, CX, CY + 1, 18, 10, SHEAR, math.pi * 1.10, math.pi * 1.84, CYAN_RESIDUAL, 1)


def draw_dead_lens(draw, img):
    """Dark diffuser with cracked glass and no active bright core."""
    lcx = CX - 1
    lcy = CY

    fill_sheared_ellipse(img, lcx, lcy, 15, 8, SHEAR, lambda x, y, n: LENS_EDGE)

    def lens_gradient(x, y, n):
        color = mix(LENS_DIM, LENS_DARK, min(1.0, n * 0.85))
        if y > lcy + 2:
            color = mix(color, RECESS, 0.45)
        return quantize(color)

    fill_sheared_ellipse(img, lcx, lcy, 13, 7, SHEAR, lens_gradient)

    # Faint residual cyan on the upper rim only.
    draw_arc(draw, lcx, lcy, 15, 8, SHEAR, math.pi * 1.12, math.pi * 1.82, (64, 206, 202, 78), 1)
    draw_arc(draw, lcx, lcy, 15, 8, SHEAR, math.pi * 0.06, math.pi * 0.94, (2, 28, 38, 230), 1)

    # Cracked diffuser lines, dark rather than glowing.
    crack_lines = [
        [(29, 28), (32, 31), (34, 36)],
        [(32, 31), (37, 28), (43, 29)],
        [(31, 32), (25, 34), (21, 38)],
        [(34, 34), (39, 38)],
    ]
    for line in crack_lines:
        draw.line(line, fill=CRACK, width=1)
        for x, y in line:
            blend_pixel(img, x + 1, y, (88, 146, 150, 55))

    # A small dead dark spot where diffuser plastic has failed.
    fill_sheared_ellipse(img, lcx + 5, lcy + 2, 4, 2, SHEAR, lambda x, y, n: (2, 20, 28, 210))


def draw_details(draw, img):
    screw_angles = [math.pi * 1.18, math.pi * 1.80, math.pi * 0.18, math.pi * 0.80]
    for theta in screw_angles:
        sx, sy = ellipse_point(CX, CY, 20, 12, SHEAR, theta)
        set_pixel(img, sx, sy, (6, 28, 36, 255))
        blend_pixel(img, sx + 1, sy, (92, 142, 144, 140))
        blend_pixel(img, sx, sy + 1, (4, 22, 30, 190))

    # Dim wet flecks and grime marks.
    beads = [(23, 18), (40, 17), (15, 31), (50, 35), (25, 45), (39, 43)]
    for x, y in beads:
        blend_pixel(img, x, y, WET_SPEC_DIM)
        blend_pixel(img, x + 1, y + 1, (32, 116, 126, 75))

    grime = [
        (20, 17, 29, 16),
        (37, 17, 45, 18),
        (12, 35, 18, 33),
        (45, 28, 53, 27),
        (28, 46, 38, 45),
    ]
    for x1, y1, x2, y2 in grime:
        steps = max(abs(x2 - x1), abs(y2 - y1), 1)
        for i in range(steps + 1):
            x = x1 + int((x2 - x1) * i / steps)
            y = y1 + int((y2 - y1) * i / steps)
            blend_pixel(img, x, y, (4, 28, 34, 120))

    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a >= 180:
                n = (((x * 19 + y * 23 + (x * y) % 13) % 7) - 3) * 3
                pixels[x, y] = (clamp(r + n), clamp(g + n), clamp(b + n), a)


def generate_texture():
    img = Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    draw_faint_residual_halo(img)
    draw_housing(draw, img)
    draw_dead_lens(draw, img)
    draw_details(draw, img)

    return img


def main():
    print("Generating BROKEN/OFF Poolrooms recessed light sprite (64x64 RGBA)...")
    img = generate_texture()
    img.save(OUTPUT_PATH, "PNG")
    print(f"Saved to: {OUTPUT_PATH}")

    os.makedirs(os.path.dirname(GAME_TEXTURE_PATH), exist_ok=True)
    shutil.copy2(OUTPUT_PATH, GAME_TEXTURE_PATH)
    print(f"Copied to: {GAME_TEXTURE_PATH}")
    print(f"Size: {img.size}, Mode: {img.mode}")


if __name__ == "__main__":
    main()
