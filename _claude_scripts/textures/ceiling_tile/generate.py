#!/usr/bin/env python3
"""Generate a tileable white ceiling tile texture for a damp poolroom.

PSX-style, 128x128, seamless via modulo wrapping.
"""

import numpy as np
from PIL import Image
import os

np.random.seed(42)

SIZE = 128
TILE_W = 32
TILE_H = 32
GRID_THICKNESS = 1
OUTPUT = os.path.join(os.path.dirname(__file__), "output.png")


def seamless_noise(size, scale=8):
    """Generate seamless tileable noise using modulo wrapping."""
    base = np.random.rand(scale, scale)
    noise = np.zeros((size, size), dtype=np.float32)
    for y in range(size):
        for x in range(size):
            fx = x / (size / scale)
            fy = y / (size / scale)
            ix0 = int(np.floor(fx)) % scale
            iy0 = int(np.floor(fy)) % scale
            ix1 = (ix0 + 1) % scale
            iy1 = (iy0 + 1) % scale
            sx = fx - np.floor(fx)
            sy = fy - np.floor(fy)
            # bilinear interpolation with modulo wrapping
            a = base[iy0, ix0]
            b = base[iy0, ix1]
            c = base[iy1, ix0]
            d = base[iy1, ix1]
            noise[y, x] = (
                a * (1 - sx) * (1 - sy) +
                b * sx * (1 - sy) +
                c * (1 - sx) * sy +
                d * sx * sy
            )
    return noise


def main():
    img = np.ones((SIZE, SIZE, 3), dtype=np.float32)

    # Tile-local coordinates using modulo for seamlessness
    tile_x = np.arange(SIZE) % TILE_W
    tile_y = np.arange(SIZE) % TILE_H
    tx, ty = np.meshgrid(tile_x, tile_y)

    # Distance from each corner of the tile (for damp staining)
    # Corners are at (0,0), (TILE_W-1,0), (0,TILE_H-1), (TILE_W-1,TILE_H-1)
    d_tl = np.sqrt(tx**2 + ty**2) / np.sqrt((TILE_W-1)**2 + (TILE_H-1)**2)
    d_tr = np.sqrt((TILE_W - 1 - tx)**2 + ty**2) / np.sqrt((TILE_W-1)**2 + (TILE_H-1)**2)
    d_bl = np.sqrt(tx**2 + (TILE_H - 1 - ty)**2) / np.sqrt((TILE_W-1)**2 + (TILE_H-1)**2)
    d_br = np.sqrt((TILE_W - 1 - tx)**2 + (TILE_H - 1 - ty)**2) / np.sqrt((TILE_W-1)**2 + (TILE_H-1)**2)

    # Grid lines
    is_grid_x = (tx < GRID_THICKNESS)
    is_grid_y = (ty < GRID_THICKNESS)
    grid_mask = np.logical_or(is_grid_x, is_grid_y).astype(np.float32)

    # Base tile color: warm white with subtle noise
    tile_noise = seamless_noise(SIZE, scale=8)
    base_white = 0.92 + 0.06 * tile_noise

    # Dampness stain: accumulate corner influence with noise
    damp_noise = seamless_noise(SIZE, scale=16)
    corner_damp = (
        np.exp(-d_tl * 4) * (0.5 + 0.5 * damp_noise) +
        np.exp(-d_tr * 4) * (0.5 + 0.5 * damp_noise) +
        np.exp(-d_bl * 4) * (0.5 + 0.5 * damp_noise) +
        np.exp(-d_br * 4) * (0.5 + 0.5 * damp_noise)
    )
    corner_damp = np.clip(corner_damp, 0, 1)

    # Water stain color: yellowish-brownish grey
    stain_r = 0.55
    stain_g = 0.60
    stain_b = 0.50

    # Mix base white with stain in corners
    damp_factor = corner_damp * 0.55
    img[:, :, 0] = base_white * (1 - damp_factor) + stain_r * damp_factor
    img[:, :, 1] = base_white * (1 - damp_factor) + stain_g * damp_factor
    img[:, :, 2] = base_white * (1 - damp_factor) + stain_b * damp_factor

    # Add grid lines (dark grey)
    grid_color = 0.35
    img[:, :, 0] = np.where(grid_mask, grid_color, img[:, :, 0])
    img[:, :, 1] = np.where(grid_mask, grid_color, img[:, :, 1])
    img[:, :, 2] = np.where(grid_mask, grid_color, img[:, :, 2])

    # PSX-style: quantize to limited palette levels and downsample+upsample for pixel feel
    levels = 12
    img = np.floor(img * levels) / levels

    # Slight pixelation: blocky average within small cells
    block = 2
    psx = np.zeros_like(img)
    for by in range(0, SIZE, block):
        for bx in range(0, SIZE, block):
            # Seamless block averaging via modulo (blocks divide SIZE evenly)
            psx[by:by+block, bx:bx+block, :] = img[by:by+block, bx:bx+block, :].mean(axis=(0, 1))
    img = psx

    # Clamp and convert to uint8
    img = np.clip(img * 255, 0, 255).astype(np.uint8)

    Image.fromarray(img, mode="RGB").save(OUTPUT)
    print(f"Saved {OUTPUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
