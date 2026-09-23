"""Measure the banding that repeats with the tile, robust to what is on the tile.

Two separable defects make a tiled floor look like a grid, and both are invisible in a
single tile viewed on its own:

  centre   a cross or patch through the middle of the tile (the seam repair band, or the
           generator lighting the middle of the frame more brightly)
  border   a frame along the outer edge, which joins across the wrap into a line on every
           junction

Both are measured as the mean-luma difference between a region and the rest, using the
median along each border line so a cardboard sheet or a puddle sitting in the middle of
the tile does not register as a defect.

This assumes a material with no deliberate large-scale structure. A gridded surface
(the poolroom's ceramic tiles) is supposed to vary across the tile, so its border reading
means nothing there; check one with --lines instead, which measures whether every grout
line is drawn to the same depth.

    python banding.py <texture> [...]        # luma units, 0-255
    python banding.py --lines <texture>      # per-line depth and spread
"""
import sys

import numpy as np
from PIL import Image

LUMA = np.array([0.2126, 0.7152, 0.0722])
# A tile-periodic offset below this is not visible under the game's point lighting.
TOLERANCE = 1.5


def profiles(path, samples=128):
    """Per-column and per-row luma offset at the resolution the shader samples at.

    Median rather than mean: a variant tile's subject covers part of a line, and a mean
    would report the cardboard sheet as a banding defect. A line that is still mostly
    carpet has a carpet median.
    """
    img = Image.open(path).convert("RGB").resize((samples, samples), Image.LANCZOS)
    l = np.asarray(img).astype(np.float32) / 255 @ LUMA
    return np.median(l, axis=0), np.median(l, axis=1)


def dips(path, samples=128):
    cm, rm = profiles(path, samples)
    c0, c1 = samples * 56 // 128, samples * 72 // 128
    edge = 10 * samples // 128

    def centre(p):
        return 255 * (p[c0:c1].mean() - np.concatenate([p[:c0], p[c1:]]).mean())

    def border(p):
        return 255 * ((p[:edge].mean() + p[-edge:].mean()) / 2 - p[edge:-edge].mean())

    return centre(cm), centre(rm), border(cm), border(rm)


def decal_join(floor_tex, decal_tex, reps=5):
    """How visible the join is where a one-tile decal meets the ground around it.

    The four joins around a single decal tile are compared with the same four join
    positions when that tile holds an ordinary tile instead. Sampling the identical
    positions matters: a repaired floor tiles more cleanly at its own wrap than in the
    middle of the field, so comparing a decal join against the floor's wrap seam flatters
    the decal. A ratio near 1.0 means the decal's border is no more visible than the
    ground's own joins.
    """
    n = floor_tex.shape[0]
    c = reps // 2

    def build(with_decal):
        g = np.tile(floor_tex, (reps, reps, 1)).astype(np.float32)
        if with_decal:
            g[c * n:(c + 1) * n, c * n:(c + 1) * n] = decal_tex
        return (g / 255) @ LUMA * 255

    def joins(g):
        x0, x1 = c * n, (c + 1) * n
        return 0.5 * (np.abs(g[:, x0] - g[:, x0 - 1]).mean()
                      + np.abs(g[:, x1] - g[:, x1 - 1]).mean()
                      + np.abs(g[x0, :] - g[x0 - 1, :]).mean()
                      + np.abs(g[x1, :] - g[x1 - 1, :]).mean())

    return float(joins(build(True))), float(joins(build(False)))


def junction_contrast(tiled, snap=128):
    """Mean luma step across each tile junction, against the step between neighbours.

    A decal that covers one whole tile has to be indistinguishable from its neighbours at
    the join, which a plain tone match will not guarantee: the neighbouring tiles present
    their own borders, so the comparison is border-to-border. Returns the mean |dL| across
    every junction and across every ordinary neighbouring column/row pair, in 0-255 luma.
    A ratio near 1.0 means the joins are invisible.
    """
    step_x = np.abs(np.diff(tiled, axis=1)).mean(axis=0) * 255
    step_y = np.abs(np.diff(tiled, axis=0)).mean(axis=1) * 255
    jx = step_x[snap - 1::snap]
    jy = step_y[snap - 1::snap]
    keep = slice(snap - 1, None, snap)
    ordinary = np.concatenate([np.delete(step_x, keep), np.delete(step_y, keep)])
    return float(np.mean(np.concatenate([jx, jy]))), float(ordinary.mean())


def line_depths(path, samples=128, threshold=30.0):
    """Depth below the field of each dark grid line, at the renderer's sampling.

    A grid line that lands on the texture's own wrap is drawn as two half lines and comes
    out a different depth from the interior ones, which reads as a heavier grid once every
    2 m. A spread of a few luma is fine; anything over about 5 means the join is visible.
    """
    from game_sim import snap_sample
    img = Image.open(path).convert("RGB")
    g = snap_sample(np.asarray(img), samples).astype(np.float32) / 255 @ LUMA * 255
    out = []
    for axis in (0, 1):
        prof = g.mean(axis=axis)
        field = np.median(prof)
        dark = np.flatnonzero(prof < field - threshold)
        for idx in np.split(dark, np.flatnonzero(np.diff(dark) > 1) + 1) if dark.size else []:
            out.append((axis, int(idx[0]), len(idx), float(field - prof[idx].mean())))
    return out


def main(paths):
    print(f"{'texture':34s} {'centre x':>9s} {'centre y':>9s} {'border x':>9s} {'border y':>9s}   (luma 0-255, |x|<{TOLERANCE} ok)")
    for p in paths:
        cx, cy, bx, by = dips(p)
        worst = max(abs(v) for v in (cx, cy, bx, by))
        flag = "" if worst < TOLERANCE else f"   <-- {worst:.1f}"
        print(f"{p.split('/')[-1]:34s} {cx:+9.1f} {cy:+9.1f} {bx:+9.1f} {by:+9.1f}{flag}")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--lines"]:
        for p in sys.argv[2:]:
            rows = line_depths(p)
            for axis, name in ((0, "columns"), (1, "rows")):
                d = [r[3] for r in rows if r[0] == axis]
                pos = [(r[1], r[2]) for r in rows if r[0] == axis]
                if not d:
                    print(f"{p.split('/')[-1]:26s} {name}: no grid lines found")
                    continue
                print(f"{p.split('/')[-1]:26s} {name}: lines(pos,width)={pos}")
                print(f"{'':26s} depths={[round(v, 1) for v in d]}  spread={max(d) - min(d):.1f} luma")
    else:
        main(sys.argv[1:])