#!/usr/bin/env python3
"""
Generate a tileable white ceramic pool tile floor texture.
PSX-style low-res pixel art aesthetic.
"""

import numpy as np
from PIL import Image
import random

SIZE = 128
TILE_SIZE = 15
GROUT = 1
CELL = TILE_SIZE + GROUT  # 16
OFFSET = TILE_SIZE // 2   # 7, ensures 128px boundary falls in middle of a tile

random.seed(42)
np.random.seed(42)

img_array = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)

TILES_ACROSS = SIZE // CELL  # 8

# Per-tile base colors: near-white with very faint cool/blue bias
base_colors = np.zeros((TILES_ACROSS, TILES_ACROSS, 3), dtype=np.float32)
for ty in range(TILES_ACROSS):
    for tx in range(TILES_ACROSS):
        r = 250 + random.randint(-4, 2)
        g = 254 + random.randint(-2, 1)
        b = 255 + random.randint(-2, 0)
        base_colors[ty, tx] = [r, g, b]

# Grout color: darker for better contrast against bright tiles
GROUT_COLOR = np.array([108, 112, 116], dtype=np.uint8)

# Per-tile highlight centers for glossy/wet specular look
# Each tile gets 1-3 small highlight clusters
tile_highlights = {}
for ty in range(TILES_ACROSS):
    for tx in range(TILES_ACROSS):
        num_highlights = random.choice([1, 2, 2, 3])
        highlights = []
        for _ in range(num_highlights):
            hx = random.randint(2, TILE_SIZE - 3)
            hy = random.randint(2, TILE_SIZE - 3)
            radius = random.choice([1.0, 1.5, 2.0])
            intensity = random.randint(18, 38)
            highlights.append((hx, hy, radius, intensity))
        tile_highlights[(ty, tx)] = highlights

# Grout dark spots for imperfect realism
grout_dark_spots = set()
for _ in range(40):
    gx = random.randint(0, SIZE - 1)
    gy = random.randint(0, SIZE - 1)
    grout_dark_spots.add((gx, gy))

for y in range(SIZE):
    for x in range(SIZE):
        # Offset grid so 128px boundary falls inside tiles, not on grout lines
        ox = x + OFFSET
        oy = y + OFFSET
        cx = ox % CELL
        cy = oy % CELL
        tx = (ox // CELL) % TILES_ACROSS
        ty = (oy // CELL) % TILES_ACROSS

        if cx >= TILE_SIZE or cy >= TILE_SIZE:
            # Grout line
            color = GROUT_COLOR.copy().astype(np.int16)
            # Occasional darker spot in grout for imperfection
            if (x, y) in grout_dark_spots:
                color -= random.randint(10, 28)
            img_array[y, x] = np.clip(color, 0, 255).astype(np.uint8)
        else:
            # Inside tile
            base = base_colors[ty, tx].copy()

            # Subtle tile surface noise
            noise = np.random.normal(0, 2.0)
            base += noise

            # Beveled edge / corner darkening
            edge_dist = min(cx, cy, TILE_SIZE - 1 - cx, TILE_SIZE - 1 - cy)
            if edge_dist < 2:
                darken = (2 - edge_dist) * 3.0
                base -= darken

            # Slight random corner wear per tile
            wear_seed = (tx * 7 + ty * 13) % 8
            if edge_dist < 1 and wear_seed > 3:
                base -= (wear_seed - 3) * 1.2

            # Glossy/wet specular highlights (2-3 pixel bright clusters)
            for (hx, hy, radius, intensity) in tile_highlights[(ty, tx)]:
                dist = max(abs(cx - hx), abs(cy - hy))  # Chebyshev for square-ish patch
                if dist < radius:
                    boost = intensity * (1.0 - dist / radius)
                    base += boost

            # PSX-style color quantization
            base = np.clip(base, 0, 255)
            base = (base // 4) * 4

            img_array[y, x] = base.astype(np.uint8)

# Slight overall dither for PSX feel
noise = np.random.randint(-2, 3, size=(SIZE, SIZE, 3), dtype=np.int16)
img_array = np.clip(img_array.astype(np.int16) + noise, 0, 255).astype(np.uint8)

# Very faint cool tint for pool water reflection
pool_tint = np.array([0, 1, 3], dtype=np.int16)
img_array = np.clip(img_array.astype(np.int16) + pool_tint, 0, 255).astype(np.uint8)

img = Image.fromarray(img_array, mode='RGB')
output_path = 'output.png'
img.save(output_path)
print(f"Saved {output_path} ({SIZE}x{SIZE})")
