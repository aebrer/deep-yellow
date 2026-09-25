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

## The alpha a sprite must exceed to be drawn at all. Billboards use
## Sprite3D.ALPHA_CUT_DISCARD at the default 0.5 -> 128. Floor decals are different:
## psx_lit_decal.gdshader is set up with alpha_scissor 0.1 -> 26, so cutting a decal strip
## at 128 throws away pixels the game would draw (the shipped stairs decal has 20.9% of its
## area between 26 and 128 — the water). --alpha-cut overrides it.
ALPHA_CUT = 128
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


def match_colour(gen, base, clip=(0.7, 1.4), level_brightness=False, bands=1):
    """Remove COLOUR CAST from a generated frame without touching its brightness.

    The generator drifts palette between calls — bacteria_spawn came back a saturated lime
    against the shipped sprite's murky green, which reads as the object changing material
    mid-loop. But it also makes deliberate brightness changes that ARE the animation: the
    vending machine's frames differ because its case light rises and sags, and matching the
    overall level would delete the animation it was asked for.

    So the per-channel gain is split into the part common to all three channels (a
    brightness change — keep it) and the per-channel deviation (a cast — remove it).
    """
    out = gen.copy()
    factors = (1.0, 1.0, 1.0)
    h = gen.shape[0]
    # A cast is not always global. The stairs decal came back with its lower third lit by
    # the water and its dry upper steps tinted salmon — a whole-frame mean saw the two and
    # called the palette close enough. Matching per horizontal band catches a cast that
    # only covers part of the subject, which is what "change ONLY the water" breaks into.
    for i in range(bands):
        y0, y1 = h * i // bands, h * (i + 1) // bands
        sel = np.zeros((h, 1), bool); sel[y0:y1, 0] = True
        g = (gen[:, :, 3] >= ALPHA_CUT) & sel
        b = (base[:, :, 3] >= ALPHA_CUT) & sel
        if not g.any() or not b.any():
            continue
        gains = []
        for c in range(3):
            gm, bm = gen[:, :, c][g].mean(), base[:, :, c][b].mean()
            gains.append(bm / gm if gm > 1.0 else 1.0)
        overall = float(np.prod(gains) ** (1.0 / 3.0))
        if level_brightness:
            # Items: the model's brightness drift is bigger than any highlight slide it was
            # asked to draw, so level it out and keep only the cast correction. Entities
            # leave this off — for the vending machine and the glowing bacteria the
            # brightness change IS the animation.
            factors = [float(np.clip(k, *clip)) for k in gains]
        else:
            factors = [float(np.clip(k / overall, *clip)) if overall > 1e-6 else 1.0 for k in gains]
        for c in range(3):
            band = out[:, :, c].astype(np.float64)
            band[y0:y1] = np.clip(band[y0:y1] * factors[c], 0, 255)
            out[:, :, c] = band.astype(np.uint8)
    return out, tuple(round(k, 3) for k in factors)


def iou(a, b):
    A, B = a[:, :, 3] > 128, b[:, :, 3] > 128
    union = (A | B).sum()
    return 1.0 if union == 0 else (A & B).sum() / union


def main():
    global ALPHA_CUT
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("f2"); ap.add_argument("f3"); ap.add_argument("out")
    ap.add_argument("--loop", default="1,2,3,2")
    ap.add_argument("--anchor", choices=["bottom", "centre"], default="bottom")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--gif", default=None)
    ap.add_argument("--iou-min", type=float, default=0.75)
    ap.add_argument("--level-brightness", action="store_true",
                    help="also remove the overall brightness change (items: their drift is "
                         "bigger than the highlight slide that was asked for)")
    ap.add_argument("--alpha-cut", type=int, default=ALPHA_CUT,
                    help="alpha a pixel must reach to survive; 128 for billboards, 26 for "
                         "floor decals (psx_lit_decal.gdshader uses alpha_scissor 0.1)")
    ap.add_argument("--alpha-from-base", action="store_true",
                    help="floor decals: give every frame the base's alpha (its transparency "
                         "is authored art, and the generator repaints it)")
    ap.add_argument("--clip-to-base", action="store_true",
                    help="cut every frame to the base frame's silhouette (stops the "
                         "generator inventing drips and wisps outside the subject)")
    ap.add_argument("--max-brightness", type=float, default=10.0,
                    help="allowed spread of mean luminance across frames; glowing things "
                         "that pulse (vending machines, bacteria) need this raised")
    ap.add_argument("--band-match", type=int, default=1,
                    help="match colour cast per horizontal band (full-bleed tiles whose "
                         "change is confined to one part of the frame)")
    ap.add_argument("--no-match-colour", action="store_true",
                    help="skip pulling generated frames onto the base frame's palette")
    args = ap.parse_args()

    ALPHA_CUT = args.alpha_cut

    # The base is shipped art: cut it, but never repaint it. Generated frames are defringed
    # BEFORE the cut — the cut makes every surviving pixel opaque, which would leave no
    # interior for the fringe to borrow colour from.
    frames = {1: cut(load_rgba(args.base, args.size))}
    for k, p in ((2, args.f2), (3, args.f3)):
        a, n = defringe(load_rgba(p, args.size))
        a = cut(a)
        note = ""
        if not args.no_match_colour:
            a, gains = match_colour(a, frames[1], level_brightness=args.level_brightness,
                                                bands=args.band_match)
            note = f", cast correction RGB {gains}"
        frames[k] = a
        print(f"  frame {k}: defringed {n} magenta edge pixels{note}")

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

    if args.clip_to_base:
        # The generator cannot be talked out of adding a drip hanging off a fogged light
        # fixture — three attempts, three drips, and a drip that appears for one frame is a
        # rendering bug. The base frame IS the subject's extent, so cut every frame to it.
        keep = base[:, :, 3] >= ALPHA_CUT
        for k in placed:
            if k != 1:
                placed[k][~keep] = 0

    # Brightness report. Silhouette IoU cannot see a loop that keeps its outline and flips
    # its lighting: the poolroom downlight measured 0.97 on every frame while alternating
    # meanL 119 / 139, which reads as the fixture switching itself on and off — on top of a
    # flicker system that already does that on purpose. Report the swing; --max-brightness
    # decides when it is a failure rather than a look.
    lum = []
    for k in sorted(placed):
        a = placed[k]
        m = a[:, :, 3] >= ALPHA_CUT
        rgb = a[:, :, :3][m].astype(np.float64) if m.any() else np.zeros((1, 3))
        lum.append(float((rgb * np.array([0.299, 0.587, 0.114])).sum(axis=1).mean()))
    swing = max(lum) - min(lum)
    print("  mean luminance per frame: " + " ".join(f"{v:.1f}" for v in lum)
          + f"  (swing {swing:.1f})")
    if swing > args.max_brightness:
        print(f"  WARNING: brightness swings {swing:.1f} (limit {args.max_brightness}). For a "
              "fixture or a static item that reads as the object switching itself on and off; "
              "re-generate asking for the SAME light level, or assemble with "
              "--level-brightness.", file=sys.stderr)

    if args.alpha_from_base:
        # Floor decals: the shipped tile's alpha is authored art (the stairs' water is
        # deliberately semi-transparent so the floor reads through it) and the generator
        # repaints it however it likes — it filled the water fully opaque. Transparency is
        # not what was asked to animate, so every frame inherits the base's.
        for k in placed:
            if k != 1:
                placed[k][:, :, 3] = base[:, :, 3]

    if float((base[:, :, 3] > 128).mean()) > 0.95:
        print("  note: the base fills its canvas, so silhouette IoU cannot see anything "
              "here — judge this loop by eye")

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