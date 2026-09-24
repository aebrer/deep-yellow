#!/usr/bin/env python3
"""Assemble generated idle-animation frames into a horizontal atlas strip.

Usage: assemble_frames.py <base.png> <f2.png> <f3.png> <out_strip.png>
                          [--loop 1,2,3,2] [--anchor bottom|centre] [--size 512]
                          [--gif out.gif] [--iou-min 0.75]

Everything here is written against one rule: **the contract is what the game draws, not
what the PNG contains.** Billboards use Sprite3D.ALPHA_CUT_DISCARD at the default 0.5
threshold, so every pixel below alpha 128 is discarded — a generator's low-alpha haze
(measured at alpha 9-10/255) never reaches the screen, and the base sprite's own soft
artwork may not either. Frames are therefore binarised at 128 first, and compared to the
base frame on that rendered silhouette. Preview renders here apply the same cut, or the
sheet shows defects the player never sees and hides ones they do.

Steps:

* CUT. alpha >= 128 -> opaque, else fully transparent. Matches the shader, kills haze.

* DEFRINGE. RGBA output carries a magenta cast in edge pixels — the model's training-time
  stand-in for transparency. Only pixels near a discarded pixel AND close to the measured
  magenta key are replaced, so a sprite's own purple artwork survives. The base frame is
  never defringed: it is shipped, approved art.

* ALIGN. The generator does not hold position — measured ~15 px of bbox drift at 1024 (3%
  of canvas) on the smiler. Frames shift so the rendered centroid matches the base's.
  --anchor bottom then re-seats the lowest row on a common floor line (anything standing
  on the floor); --anchor centre is for floating things.

* MEASURE. IoU of each frame's rendered silhouette against the base. Idle motion should
  move the outline a little, not redraw the subject; a low IoU means regenerate.

* LOOP. Two generated extremes plus the base are enough: 1,2,3,2 plays neutral -> sway ->
  neutral -> sway -> neutral, closing with no pop, at two generations per sprite.
"""
import argparse
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

ALPHA_CUT = 128          # Sprite3D.ALPHA_CUT_DISCARD at the default 0.5 threshold
MAGENTA_KEY = np.array([150.7, 54.1, 192.0])   # measured from returned RGBA output
MAGENTA_TOL = 150.0      # summed abs RGB distance; the rim is a dark violet, not the key


def load_rgba(path, size):
    im = Image.open(path).convert("RGBA")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.array(im)


def cut(a):
    """Binarise alpha the way the shader does."""
    out = a.copy()
    out[:, :, 3] = np.where(out[:, :, 3] >= ALPHA_CUT, 255, 0)
    return out


def defringe(a):
    """Replace magenta cast pixels that border discarded space with a real sprite colour."""
    al = a[:, :, 3]
    vis = al > 0
    border = vis & ndimage.binary_dilation(~vis, iterations=2)
    dist = np.abs(a[:, :, :3].astype(np.float64) - MAGENTA_KEY).sum(axis=2)
    hit = border & (dist < MAGENTA_TOL)
    if not hit.any():
        return a, 0
    opaque = al >= 255
    if not opaque.any():
        return a, int(hit.sum())
    idx = np.arange(al.size).reshape(al.shape)
    nearest = idx[tuple(ndimage.distance_transform_edt(
        ~opaque, return_distances=False, return_indices=True))]
    src = a[:, :, :3].reshape(-1, 3)[nearest]
    out = a.copy()
    for c in range(3):
        out[:, :, c] = np.where(hit, src[:, :, c], out[:, :, c])
    return out, int(hit.sum())


def centroid(a):
    al = a[:, :, 3].astype(np.float64)
    if al.sum() < 1.0:
        h, w = al.shape
        return w / 2.0, h / 2.0
    ys, xs = np.mgrid[0:al.shape[0], 0:al.shape[1]]
    return (xs * al).sum() / al.sum(), (ys * al).sum() / al.sum()


def translate(a, dx, dy):
    h, w = a.shape[:2]
    out = np.zeros_like(a)
    ys, xs = np.mgrid[0:h, 0:w]
    sx, sy = xs - dx, ys - dy
    ok = (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
    out[ok] = a[sy[ok], sx[ok]]
    return out


def align(a, ref_xy, anchor, floor_row):
    cx, cy = centroid(a)
    out = translate(a, int(round(ref_xy[0] - cx)), int(round(ref_xy[1] - cy)))
    if anchor == "bottom":
        rows = np.where(out[:, :, 3] > 128)[0]
        if len(rows):
            shift = int(floor_row - rows.max())
            if shift:
                rolled = np.zeros_like(out)
                if shift > 0:
                    rolled[shift:] = out[:out.shape[0] - shift]
                else:
                    rolled[:out.shape[0] + shift] = out[-shift:]
                out = rolled
    return out


def iou(a, b):
    A, B = a[:, :, 3] > 128, b[:, :, 3] > 128
    union = (A | B).sum()
    return 1.0 if union == 0 else (A & B).sum() / union


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("f2"); ap.add_argument("f3"); ap.add_argument("out")
    ap.add_argument("--loop", default="1,2,3,2")
    ap.add_argument("--anchor", choices=["bottom", "centre"], default="bottom")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--gif", default=None)
    ap.add_argument("--iou-min", type=float, default=0.75)
    args = ap.parse_args()

    # The base is shipped art: cut it, but never repaint it. Generated frames are defringed
    # BEFORE the cut — the cut makes every surviving pixel opaque, which would leave no
    # interior for the fringe to borrow colour from.
    frames = {1: cut(load_rgba(args.base, args.size))}
    for k, p in ((2, args.f2), (3, args.f3)):
        a, n = defringe(load_rgba(p, args.size))
        a = cut(a)
        frames[k] = a
        print(f"  frame {k}: defringed {n} magenta edge pixels")

    base = frames[1]
    ref = centroid(base)
    rows = np.where(base[:, :, 3] > 128)[0]
    floor_row = int(rows.max()) if len(rows) else args.size - 1

    placed = {}
    worst = 1.0
    for k, v in frames.items():
        placed[k] = align(v, ref, args.anchor, floor_row)
        if k != 1:
            score = iou(base, placed[k])
            worst = min(worst, score)
            flag = "ok" if score >= args.iou_min else "DRIFTS TOO MUCH"
            print(f"  frame {k}: silhouette IoU vs base {score:.3f}  ({flag})")

    order = [int(x) for x in args.loop.split(",")]
    n = len(order)
    strip = np.zeros((args.size, args.size * n, 4), np.uint8)
    for i, k in enumerate(order):
        strip[:, i * args.size:(i + 1) * args.size] = placed[k]
    Image.fromarray(strip, "RGBA").save(args.out)
    print(f"{args.out}: {n} frames x {args.size}px, loop {order}, anchor={args.anchor}, "
          f"worst IoU {worst:.3f}")

    if args.gif:
        imgs = []
        for k in order:
            bg = Image.new("RGBA", (args.size, args.size), (26, 26, 26, 255))
            bg.alpha_composite(Image.fromarray(placed[k], "RGBA"))
            imgs.append(bg.convert("P", palette=Image.ADAPTIVE))
        imgs[0].save(args.gif, save_all=True, append_images=imgs[1:], duration=170, loop=0)
        print(f"  gif: {args.gif}")

    if worst < args.iou_min:
        print(f"  WARNING: at least one frame moves more than idle sway should; "
              f"regenerate it rather than ship a popping loop", file=sys.stderr)


if __name__ == "__main__":
    main()