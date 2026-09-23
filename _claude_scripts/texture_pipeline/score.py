"""Score a floor texture the way the player's eye does, at the renderer's sampling.

Two numbers matter and they pull against each other:

detail        Mean absolute gradient of the image the renderer actually produces
              (nearest sampling on the snap grid). Low detail reads as a flat plane.
grid          Amplitude of the tile-periodic component of that same image. Every
              texture repeats, so any structure that happens to line up with the tile
              pitch shows up as a grid laid over the floor. This is what a player
              notices as "I can see where the tiles are".

A good tile maximises detail while keeping grid near zero. Aliased high frequency
content looks like detail in isolation but raises grid, which is why the two are
reported together.
"""
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from game_sim import snap_sample  # noqa: E402

LUMA = np.array([0.2126, 0.7152, 0.0722])


def rendered(path, snap=128, reps=4):
    tex = np.asarray(Image.open(path).convert("RGB"))
    return np.tile(snap_sample(tex, snap), (reps, reps, 1)).astype(np.float32) / 255 @ LUMA


def score(path, snap=128, reps=4):
    g = rendered(path, snap, reps)
    gy, gx = np.gradient(g)
    detail = 255 * float((np.abs(gx) + np.abs(gy)).mean())

    # Fold the view onto one tile and look at what survives the fold: anything that
    # is in phase with the repeat is, by definition, tile-periodic.
    cell = g.reshape(reps, g.shape[0] // reps, reps, g.shape[1] // reps)
    rows = cell.mean(axis=(0, 2))
    cols = cell.mean(axis=(1, 2))
    # Absolute, in 0-255 luma: a 3-unit swing is a 3-unit swing whatever the tile's
    # own contrast is, so the number stays comparable between candidates.
    grid = 255 * float(max(rows.max() - rows.min(), cols.max() - cols.min()))

    filt = np.asarray(Image.open(path).convert("RGB").resize(
            (snap, snap), Image.LANCZOS)).astype(np.float32) / 255 @ LUMA
    fy, fx = np.gradient(filt)
    alias = detail / max(255 * float((np.abs(fx) + np.abs(fy)).mean()), 1e-9)
    return detail, grid, alias


if __name__ == "__main__":
    print(f"{'texture':34s} {'detail':>7s} {'grid':>7s} {'alias':>7s}   (luma 0-255)")
    for p in sys.argv[1:]:
        d, gr, al = score(p)
        print(f"{p.split('/')[-1]:34s} {d:7.2f} {gr:7.2f} {al:7.2f}x")