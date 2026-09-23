#!/usr/bin/env python3
"""Add a crisp, wrap-safe grout grid to a poolroom ceramic surface scan.

Why procedural instead of asking the model for tiles: the original pixel-art
floor_tile.png got its identity from HARD dark grout lines on an exact grid, and
a diffusion model asked for "tileable tiles" answers with a soft, washed-out
grid (the current texture has a mean luminance of 0.90 and grout you can barely
see). The glaze detail is what the model is good at; the grid is arithmetic, so
the grid is drawn here.

Everything is placed on exact cell multiples with wrap-aware distance, so the
result tiles by construction — no seam band, no feathering, no blur.

Usage: add_grout.py IN.png OUT.png [--cells 4] [--width 12]
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def wrap_distance(n: int, cell: float, phase: float = 0.0) -> np.ndarray:
    """Distance of each pixel to the nearest grid line, wrapping at the edges.

    phase is in cells: 0 puts a line on the texture's own wrap, 0.5 puts a line half a
    cell away so the wrap falls in the middle of a tile. A line that straddles the wrap is
    drawn as two half lines, and the two halves come out a different depth from the
    interior lines (about 9 luma here), which reads as a heavier grid every 2 m. Half a
    cell moves that join into a tile, where the tile's own edge hides it.
    """
    x = np.arange(n) + 0.5 - phase * cell
    return np.abs((x + cell / 2.0) % cell - cell / 2.0)


def add_grout(surface: np.ndarray, cells: int, width: int, edge: int,
              grout_rgb: tuple, grime: float, tile_var: float, seed: int,
              phase: float = 0.5) -> np.ndarray:
    h, w, nc = surface.shape
    rng = np.random.default_rng(seed)

    cell_x, cell_y = w / cells, h / cells
    dx = wrap_distance(w, cell_x, phase)[None, :, None]
    dy = wrap_distance(h, cell_y, phase)[:, None, None]
    d = np.minimum(dx, dy)  # distance to the nearest grout line (either axis)

    half = width / 2.0

    # Inside the line: hard-edged grout. Noise gives it a sandy, swept-in look;
    # grime darkens it away from the line centre so the grooves read as recessed.
    in_line = d <= half
    centre = 1.0 - np.clip(d / half, 0.0, 1.0)  # 1 at the line centre, 0 at its edge
    sandy = 1.0 + grime * (rng.random((h, w, 1)) - 0.5) * 2.0
    recess = 1.0 - grime * (1.0 - centre)
    base = np.array(grout_rgb, dtype=np.float32)
    grout = np.clip(base[None, None, :] * sandy * recess, 0.0, 1.0)

    # Just outside the line: shade the glaze down so the tiles look raised out of
    # the grout. Kept narrow and steep — a wide soft ramp is exactly the artefact
    # we are trying to get away from.
    shoulder = np.clip((d - half) / max(edge, 1), 0.0, 1.0)

    # Rotate/flip each cell at random before anything else. The glaze scan is one
    # continuous image, so any distinctive mark in it repeats once per tile and the
    # eye finds it; cutting the surface into independently oriented cells (invisible,
    # since grout hides the joins) decorrelates them and kills the giveaway.
    cw, ch = int(round(cell_x)), int(round(cell_y))
    ox, oy = int(round(phase * cell_x)) % cw, int(round(phase * cell_y)) % ch
    aligned = np.roll(surface, (-oy, -ox), axis=(0, 1))  # cell edges now sit on 0
    cells_img = aligned.copy()
    for cy in range(cells):
        for cx in range(cells):
            blk = aligned[cy * ch:(cy + 1) * ch, cx * cw:(cx + 1) * cw]
            k = int(rng.integers(0, 4))
            if bool(rng.integers(0, 2)):
                blk = blk[:, ::-1]
            cells_img[cy * ch:(cy + 1) * ch, cx * cw:(cx + 1) * cw] = np.rot90(blk, k)
    out = np.roll(cells_img, (oy, ox), axis=(0, 1)) * (1.0 - 0.28 * (1.0 - shoulder))

    # Per-tile tonal offset: the originals vary tile to tile, which stops a
    # repeating surface reading as one flat sheet. Applied as one luminance
    # factor per tile (plus a whisper of hue drift) — jittering the channels
    # independently turns a poolroom into a candy shop. Cell index wraps, so the
    # offsets stay consistent across tile seams.
    ix = ((np.arange(w) / cell_x - phase) % cells).astype(int)[None, :]
    iy = ((np.arange(h) / cell_y - phase) % cells).astype(int)[:, None]
    lum_jitter = 1.0 + tile_var * (rng.random((cells, cells)) - 0.5) * 2.0
    hue_jitter = 1.0 + tile_var * 0.25 * (rng.random((cells, cells, nc)) - 0.5) * 2.0
    out = out * (lum_jitter[:, :, None] * hue_jitter)[iy, ix]

    return np.where(in_line, grout, out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--cells", type=int, default=4, help="tiles per texture repeat")
    ap.add_argument("--width", type=int, default=14, help="grout line width in px")
    ap.add_argument("--edge", type=int, default=6, help="glaze shading outside the line")
    ap.add_argument("--grout", default="0.34,0.33,0.31", help="grout rgb 0..1")
    ap.add_argument("--grime", type=float, default=0.45)
    ap.add_argument("--tile-var", type=float, default=0.07, help="per-tile tonal jitter")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--phase", type=float, default=0.5,
                    help="grid offset in cells; 0.5 keeps a grout line off the texture wrap")
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = tuple(float(v) for v in args.grout.split(","))

    out = add_grout(a, args.cells, args.width, args.edge, rgb, args.grime,
                    args.tile_var, args.seed, args.phase)

    dst = Path(args.dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(dst)

    u8 = (np.clip(out, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(np.tile(u8, (2, 2, 1))).save(dst.with_name(dst.stem + "_2x2.png"))
    print(f"{args.src} -> {dst}  ({args.cells}x{args.cells} grid, {args.width}px grout)")


if __name__ == "__main__":
    sys.exit(main())