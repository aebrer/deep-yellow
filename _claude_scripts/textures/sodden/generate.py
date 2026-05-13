#!/usr/bin/env python3
"""Generate a PSX-style sprite texture for the 'Sodden' enemy."""

import os
import random
from PIL import Image, ImageDraw

# Fixed seed for reproducibility
random.seed(42)

# Canvas size
SIZE = 64

# Limited PSX-style palette (pale blue waterlogged tones)
COLORS = {
    "base": (140, 180, 200, 255),      # pale blue skin
    "mid": (100, 150, 180, 255),       # mid shadow
    "deep": (60, 100, 130, 255),       # deep shadow
    "dark": (35, 60, 80, 255),         # very dark / outline
    "highlight": (180, 210, 225, 255), # wet sheen
    "drip": (160, 200, 220, 200),      # water drip (semi-transparent)
    "drip_dark": (90, 130, 160, 180),  # darker drip
}


def draw_rect(draw, x1, y1, x2, y2, color):
    """Draw a filled rectangle."""
    draw.rectangle([x1, y1, x2, y2], fill=color)


def draw_poly(draw, points, color):
    """Draw a filled polygon."""
    draw.polygon(points, fill=color)


def add_dither(img, intensity=15):
    """Add subtle noise for PSX texture feel."""
    pixels = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = pixels[x, y]
            if a > 0:
                noise = random.randint(-intensity, intensity)
                pixels[x, y] = (
                    max(0, min(255, r + noise)),
                    max(0, min(255, g + noise)),
                    max(0, min(255, b + noise)),
                    a,
                )


def generate():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = SIZE // 2  # 32

    # --- LEGS ---
    # Left leg
    draw_rect(draw, cx - 10, 42, cx - 3, 55, COLORS["deep"])
    draw_rect(draw, cx - 9, 43, cx - 4, 54, COLORS["mid"])
    draw_rect(draw, cx - 8, 44, cx - 5, 53, COLORS["base"])
    # Right leg
    draw_rect(draw, cx + 3, 42, cx + 10, 55, COLORS["deep"])
    draw_rect(draw, cx + 4, 43, cx + 9, 54, COLORS["mid"])
    draw_rect(draw, cx + 5, 44, cx + 8, 53, COLORS["base"])

    # --- TORSO ---
    # Main torso block (wide, slightly tapering)
    draw_poly(draw, [(cx - 13, 24), (cx + 13, 24), (cx + 11, 44), (cx - 11, 44)], COLORS["deep"])
    draw_poly(draw, [(cx - 11, 25), (cx + 11, 25), (cx + 10, 43), (cx - 10, 43)], COLORS["mid"])
    draw_poly(draw, [(cx - 9, 26), (cx + 9, 26), (cx + 8, 42), (cx - 8, 42)], COLORS["base"])

    # Chest highlight (wet sheen)
    draw_poly(draw, [(cx - 5, 28), (cx + 3, 28), (cx + 2, 35), (cx - 4, 35)], COLORS["highlight"])

    # --- ARMS ---
    # Left arm (hanging down, slightly away from body)
    draw_rect(draw, cx - 17, 26, cx - 12, 38, COLORS["deep"])
    draw_rect(draw, cx - 16, 27, cx - 13, 37, COLORS["mid"])
    draw_rect(draw, cx - 15, 28, cx - 14, 36, COLORS["base"])
    # Right arm
    draw_rect(draw, cx + 12, 26, cx + 17, 38, COLORS["deep"])
    draw_rect(draw, cx + 13, 27, cx + 16, 37, COLORS["mid"])
    draw_rect(draw, cx + 14, 28, cx + 15, 36, COLORS["base"])

    # --- HEAD ---
    # Head shape (blocky, slightly rectangular with flat jaw)
    draw_rect(draw, cx - 8, 8, cx + 8, 24, COLORS["deep"])
    draw_rect(draw, cx - 7, 9, cx + 7, 23, COLORS["mid"])
    draw_rect(draw, cx - 6, 10, cx + 6, 22, COLORS["base"])

    # Jaw / chin
    draw_rect(draw, cx - 5, 20, cx + 5, 24, COLORS["mid"])
    draw_rect(draw, cx - 4, 21, cx + 4, 23, COLORS["base"])

    # --- FACE DETAILS (simplified, PSX style) ---
    # Eye sockets (dark hollows)
    draw_rect(draw, cx - 5, 14, cx - 2, 17, COLORS["dark"])
    draw_rect(draw, cx + 2, 14, cx + 5, 17, COLORS["dark"])
    # Eyes (dim glow / empty)
    draw_rect(draw, cx - 4, 15, cx - 3, 16, (60, 80, 100, 255))
    draw_rect(draw, cx + 3, 15, cx + 4, 16, (60, 80, 100, 255))
    # Mouth (slight frown)
    draw_rect(draw, cx - 3, 19, cx + 3, 20, COLORS["dark"])

    # Head highlight (wet top)
    draw_rect(draw, cx - 4, 10, cx + 2, 12, COLORS["highlight"])

    # --- DRIPPING WATER ---
    # Drips from arms
    for x_base, y_base in [(cx - 15, 37), (cx + 14, 37)]:
        h = random.choice([2, 3, 4])
        draw_rect(draw, x_base, y_base, x_base + 1, y_base + h, COLORS["drip"])
        if h > 2:
            draw_rect(draw, x_base, y_base + h, x_base + 1, y_base + h + 1, COLORS["drip_dark"])

    # Drips from torso bottom
    for x_base in [cx - 6, cx - 2, cx + 2, cx + 5]:
        h = random.choice([2, 3, 4, 5])
        draw_rect(draw, x_base, 44, x_base + 1, 44 + h, COLORS["drip"])
        if h > 3:
            draw_rect(draw, x_base, 44 + h, x_base + 1, 44 + h + 1, COLORS["drip_dark"])

    # Drips from legs/feet
    for x_base in [cx - 8, cx - 5, cx + 5, cx + 7]:
        h = random.choice([2, 3])
        draw_rect(draw, x_base, 55, x_base + 1, 55 + h, COLORS["drip"])

    # Larger water drips / runoff on torso
    draw_rect(draw, cx - 3, 30, cx - 2, 38, COLORS["drip"])
    draw_rect(draw, cx + 4, 32, cx + 5, 40, COLORS["drip_dark"])
    draw_rect(draw, cx + 1, 28, cx + 2, 34, COLORS["drip"])

    # Puddle at feet (semi-transparent ovalish)
    draw.ellipse([cx - 14, 54, cx + 14, 60], fill=(100, 140, 170, 80))
    draw.ellipse([cx - 10, 55, cx + 10, 59], fill=(120, 160, 190, 60))

    # --- OUTLINE ACCENTS (dark edges for low-poly feel) ---
    # Left outer edge of torso
    draw_rect(draw, cx - 13, 24, cx - 12, 44, COLORS["dark"])
    # Right outer edge
    draw_rect(draw, cx + 12, 24, cx + 13, 44, COLORS["dark"])
    # Head outline sides
    draw_rect(draw, cx - 8, 8, cx - 7, 24, COLORS["dark"])
    draw_rect(draw, cx + 7, 8, cx + 8, 24, COLORS["dark"])
    # Top of head
    draw_rect(draw, cx - 8, 8, cx + 8, 9, COLORS["dark"])

    # Add subtle dither/noise for PSX texture look
    add_dither(img, intensity=12)

    # Save
    out_path = os.path.join(os.path.dirname(__file__), "output.png")
    img.save(out_path)
    print(f"Saved: {out_path}")
    print(f"Size: {img.size}, Mode: {img.mode}")


if __name__ == "__main__":
    generate()
