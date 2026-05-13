#!/usr/bin/env python3
"""
Poolrooms Recessed Light Sprite Generator

Generates a 64x64 RGBA pixel-art sprite for a cool blue-green/white recessed
ceiling light in Level 1 Poolrooms. The fixture is viewed from underneath but
slightly off to one side, with a compressed/skewed elliptical housing and a
visible wet front lip.
"""

from PIL import Image, ImageDraw
import math
import os
import random
import shutil

# Fixed seed for deterministic reruns.
random.seed(71001)

SIZE = 64
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "output.png")
GAME_TEXTURE_PATH = "/home/drew/projects/deep_yellow/assets/textures/entities/poolroom_light.png"

TRANSPARENT = (0, 0, 0, 0)
GLOW_OUTER = (36, 204, 210, 22)
GLOW_MID = (72, 236, 228, 54)
GLOW_CORE = (196, 255, 250, 94)
METAL_DARK = (28, 70, 80, 255)
METAL_MID = (78, 128, 136, 255)
METAL_LIGHT = (164, 214, 210, 255)
CERAMIC = (190, 232, 230, 255)
CERAMIC_COOL = (116, 194, 202, 255)
RECESS = (12, 60, 86, 245)
LENS_EDGE = (90, 214, 220, 255)
LENS_MID = (164, 250, 248, 255)
LENS_CORE = (248, 255, 252, 255)
WATER_SPEC = (235, 255, 252, 190)
CYAN_RIM = (82, 236, 224, 145)

# Same perspective/silhouette values are used by the broken counterpart.
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


def draw_soft_glow(img):
    """Cool cyan light spill, compressed to match the side-view ellipse."""
    for y in range(SIZE):
        for x in range(SIZE):
            n = ellipse_norm(x, y, CX, CY, 31, 21, SHEAR * 0.65)
            if n < 1.0:
                strength = (1.0 - n) ** 2
                if n < 0.46:
                    c = GLOW_CORE
                elif n < 0.72:
                    c = GLOW_MID
                else:
                    c = GLOW_OUTER
                alpha = int(c[3] * strength)
                if alpha > 1:
                    blend_pixel(img, x, y, (c[0], c[1], c[2], alpha))


def draw_housing(draw, img):
    """Skewed elliptical ceiling fixture with visible lower/front lip."""
    # Drop-shadow/thickness visible on the lower edge from the off-side angle.
    fill_sheared_ellipse(img, CX + 1, CY + 4, 25, 15, SHEAR, lambda x, y, n: (10, 44, 62, int(150 * (1.0 - n * 0.25))))

    # Outer wet metal shell.
    def outer_color(x, y, n):
        vertical = (y - (CY - 14)) / 29.0
        base = mix(METAL_LIGHT, METAL_DARK, max(0.0, min(1.0, vertical)))
        return quantize(base)

    fill_sheared_ellipse(img, CX, CY, 25, 15, SHEAR, outer_color)

    # Ceramic trim ring.
    def trim_color(x, y, n):
        if inside_ellipse(x, y, CX, CY, 20, 11, SHEAR):
            return None
        vertical = (y - (CY - 13)) / 26.0
        return quantize(mix(CERAMIC, CERAMIC_COOL, max(0.0, min(1.0, vertical))))

    fill_sheared_ellipse(img, CX, CY, 22, 13, SHEAR, trim_color)

    # Recessed cavity.
    fill_sheared_ellipse(img, CX, CY + 1, 18, 10, SHEAR, lambda x, y, n: mix(RECESS, METAL_DARK, min(1.0, n)))

    # Front lower lip/shadow makes the light read as a fixture, not a flat panel.
    for y in range(CY + 3, CY + 17):
        for x in range(5, 60):
            if inside_ellipse(x, y, CX, CY, 25, 15, SHEAR) and not inside_ellipse(x, y, CX, CY, 17, 8, SHEAR):
                alpha = int(70 + (y - CY) * 8)
                blend_pixel(img, x, y, (8, 48, 68, min(205, alpha)))

    # Bevel arcs: bright back/top edge, darker near/front edge.
    draw_arc(draw, CX, CY, 25, 15, SHEAR, math.pi * 1.05, math.pi * 1.92, (220, 255, 250, 220), 1)
    draw_arc(draw, CX, CY, 25, 15, SHEAR, math.pi * 0.02, math.pi * 0.92, (8, 54, 76, 235), 2)
    draw_arc(draw, CX, CY + 1, 18, 10, SHEAR, math.pi * 1.08, math.pi * 1.88, CYAN_RIM, 1)


def draw_lens(draw, img):
    """Bright skewed diffuser set inside the recessed housing."""
    lcx = CX - 1
    lcy = CY

    fill_sheared_ellipse(img, lcx, lcy, 15, 8, SHEAR, lambda x, y, n: LENS_EDGE)

    def lens_gradient(x, y, n):
        color = mix(LENS_CORE, LENS_EDGE, min(1.0, n))
        if x < lcx + 1 and y < lcy:
            color = mix(color, (255, 255, 255, 255), 0.32)
        return quantize(color)

    fill_sheared_ellipse(img, lcx, lcy, 13, 7, SHEAR, lens_gradient)
    fill_sheared_ellipse(img, lcx - 1, lcy - 1, 7, 4, SHEAR, lambda x, y, n: mix(LENS_CORE, LENS_MID, n))

    # Compact glints follow the fixture angle rather than forming a Level 0 tube.
    for dx in range(-10, 11):
        x = lcx + dx
        y = lcy + int(dx * 0.12)
        a = max(0, 170 - abs(dx) * 16)
        blend_pixel(img, x, y, (248, 255, 252, a))
    for dy in range(-5, 6):
        x = lcx + int(SHEAR * dy)
        y = lcy + dy
        a = max(0, 118 - abs(dy) * 19)
        blend_pixel(img, x, y, (214, 255, 252, a))

    draw_arc(draw, lcx, lcy, 15, 8, SHEAR, math.pi * 0.04, math.pi * 0.95, (30, 112, 132, 210), 1)
    draw_arc(draw, lcx, lcy, 15, 8, SHEAR, math.pi * 1.12, math.pi * 1.85, (244, 255, 252, 230), 1)


def draw_details(draw, img):
    # Screws/fasteners on the skewed ring.
    screw_angles = [math.pi * 1.18, math.pi * 1.80, math.pi * 0.18, math.pi * 0.80]
    for theta in screw_angles:
        sx, sy = ellipse_point(CX, CY, 20, 12, SHEAR, theta)
        set_pixel(img, sx, sy, METAL_DARK)
        blend_pixel(img, sx + 1, sy, METAL_LIGHT)
        blend_pixel(img, sx, sy + 1, (16, 64, 80, 180))

    # Wet beads and short cyan caustics on the ceramic/metal housing.
    beads = [(23, 18), (40, 17), (15, 31), (50, 35), (25, 45), (39, 43)]
    for x, y in beads:
        blend_pixel(img, x, y, WATER_SPEC)
        blend_pixel(img, x + 1, y + 1, (56, 196, 204, 100))

    strokes = [
        (21, 16, 30, 15),
        (36, 16, 45, 17),
        (12, 34, 18, 32),
        (45, 27, 53, 26),
        (28, 46, 38, 45),
    ]
    for x1, y1, x2, y2 in strokes:
        steps = max(abs(x2 - x1), abs(y2 - y1), 1)
        for i in range(steps + 1):
            x = x1 + int((x2 - x1) * i / steps)
            y = y1 + int((y2 - y1) * i / steps)
            blend_pixel(img, x, y, (86, 240, 224, 112))

    # Deterministic pixel-art dither on solid fixture pixels only.
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

    draw_soft_glow(img)
    draw_housing(draw, img)
    draw_lens(draw, img)
    draw_details(draw, img)

    return img


def main():
    print("Generating Poolrooms recessed light sprite (64x64 RGBA)...")
    img = generate_texture()
    img.save(OUTPUT_PATH, "PNG")
    print(f"Saved to: {OUTPUT_PATH}")

    os.makedirs(os.path.dirname(GAME_TEXTURE_PATH), exist_ok=True)
    shutil.copy2(OUTPUT_PATH, GAME_TEXTURE_PATH)
    print(f"Copied to: {GAME_TEXTURE_PATH}")
    print(f"Size: {img.size}, Mode: {img.mode}")


if __name__ == "__main__":
    main()
