#!/usr/bin/env python3
"""
Generate a tileable white ceramic tile wall texture.
Subway tile style (vertical rectangles), gray grout, damp/wet streaks.
PSX low-res pixel art aesthetic. 128x128 pixels.
"""

import numpy as np
from PIL import Image
import math

SIZE = 128
OUTPUT_PATH = "output.png"

# Tile grid: vertical subway tiles
# Cell dimensions including grout - must divide SIZE evenly
CELL_W = 16   # 8 cells across
CELL_H = 32   # 4 cells down
GROUT = 1     # 1 pixel grout line

TILE_W = CELL_W - GROUT  # 15
TILE_H = CELL_H - GROUT  # 31

assert SIZE % CELL_W == 0, "CELL_W must divide SIZE evenly"
assert SIZE % CELL_H == 0, "CELL_H must divide SIZE evenly"

# Create output array
img_array = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)


def hash2d(x, y):
    """Simple deterministic hash for 2D coordinates."""
    h = int(x * 374761393 + y * 668265263)
    h = (h ^ (h >> 13)) & 0x7fffffff
    return h


def rand01(x, y):
    """Return pseudo-random float in [0, 1) for tile coordinate."""
    return (hash2d(x, y) % 10000) / 10000.0


def randint(x, y, lo, hi):
    """Return pseudo-random int in [lo, hi] for tile coordinate."""
    return lo + (hash2d(x, y) % (hi - lo + 1))


def noise(x, y, seed=0):
    """Simple value noise."""
    ix = int(math.floor(x))
    iy = int(math.floor(y))
    fx = x - ix
    fy = y - iy

    def smooth(t):
        return t * t * (3 - 2 * t)

    fx = smooth(fx)
    fy = smooth(fy)

    v00 = rand01(ix + seed, iy + seed)
    v10 = rand01(ix + 1 + seed, iy + seed)
    v01 = rand01(ix + seed, iy + 1 + seed)
    v11 = rand01(ix + 1 + seed, iy + 1 + seed)

    vx0 = v00 * (1 - fx) + v10 * fx
    vx1 = v01 * (1 - fx) + v11 * fx

    return vx0 * (1 - fy) + vx1 * fy


# Generate texture
for y in range(SIZE):
    for x in range(SIZE):
        # Modulo wrapping for seamless tiling
        sx = x % SIZE
        sy = y % SIZE

        # Position within current cell
        cell_x = sx % CELL_W
        cell_y = sy % CELL_H

        # Which tile cell we're in
        tile_ix = sx // CELL_W
        tile_iy = sy // CELL_H

        # Grout lines
        if cell_x >= TILE_W or cell_y >= TILE_H:
            # Grout - medium gray with slight variation
            gv = 130 + randint(tile_ix, tile_iy, -10, 10)
            img_array[sy, sx] = [gv, gv, gv]
            continue

        # Base tile color: off-white ceramic
        base_white = 242

        # Per-tile color variation (manufacturing imperfection)
        tile_seed = tile_ix * 17 + tile_iy * 31
        tile_var = randint(tile_ix, tile_iy, -6, 4)

        # Subtle tile surface noise (ceramic texture)
        surf_noise = noise(x * 0.15, y * 0.15, seed=42) * 8 - 4

        # Water streaks: vertical darker streaks that span multiple tiles
        # Use world-space x for streak position, so they continue across tiles
        streak_pos = (x * 1.0) / SIZE
        streak_noise = noise(streak_pos * 8.0, y * 0.1, seed=7)

        # Determine if this pixel is in a water streak
        streak_intensity = 0.0
        if streak_noise > 0.55:
            # Taper streak intensity at edges
            streak_intensity = (streak_noise - 0.55) * 2.5
            streak_intensity = min(1.0, streak_intensity)

        # Dampness: slightly darker near grout lines (water accumulates)
        dist_left = cell_x
        dist_right = TILE_W - 1 - cell_x
        dist_top = cell_y
        dist_bottom = TILE_H - 1 - cell_y
        min_dist = min(dist_left, dist_right, dist_top, dist_bottom)

        dampness = 0
        if min_dist < 3:
            # Slight darkening near edges
            dampness = -(3 - min_dist) * 1.5

        # Combine
        val = base_white + tile_var + surf_noise - (streak_intensity * 18) + dampness

        # PSX-style: quantize to limited palette steps
        val = round(val / 4) * 4

        # Clamp
        val = max(200, min(252, int(val)))

        img_array[sy, sx] = [val, val, val + 2]  # slight blue tint for ceramic

# Save output
img = Image.fromarray(img_array)
img.save(OUTPUT_PATH)

print(f"Generated {OUTPUT_PATH}: {img.size[0]}x{img.size[1]} pixels")
