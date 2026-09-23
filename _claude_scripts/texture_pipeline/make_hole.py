"""Build the exit-hole decal from a generated raw plate.

The decal is drawn over a floor tile with the same lit PSX shader and the same
128-texel pixel snap, so two things have to hold that the generator does not
guarantee: the snow around the hole has to sit at the same brightness as the floor
it lands on, and the fine grain has to be pre-filtered to what the snap can resolve.
The void itself is kept pure black, which is why the colour match is restricted to
ground pixels.
"""
import argparse

import numpy as np
from PIL import Image

import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from game_sim import snap_sample  # noqa: E402
from make_tileable import _blur_axes, flatten_profiles, lum, match_ring, soften  # noqa: E402


def detail(a: np.ndarray) -> float:
    """Mean luma step between neighbouring texels, as the renderer samples them."""
    t = snap_sample((np.clip(a, 0, 1) * 255).round().astype(np.uint8), 128).astype(np.float32) / 255
    g = lum(t)
    return float(np.mean([np.abs(np.diff(g, axis=0)).mean(), np.abs(np.diff(g, axis=1)).mean()]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hole")
    ap.add_argument("floor")
    ap.add_argument("dst")
    ap.add_argument("--antialias", type=int, default=2)
    ap.add_argument("--no-match-detail", dest="match_detail", action="store_false",
                    help="use --antialias instead of matching the floor's detail level")
    ap.add_argument("--std-blend", type=float, default=0.5)
    ap.add_argument("--void-threshold", type=float, default=0.06)
    ap.add_argument("--frame", type=float, default=0.85,
                    help="strength of the border-frame correction on the plate")
    ap.add_argument("--blend-border", type=int, default=48,
                    help="cross-fade this many source pixels of the plate's border onto the floor texture")
    ap.add_argument("--grain", type=float, default=1.0,
                    help="how far to pull the plate's grain amplitude onto the floor's")
    ap.add_argument("--rim", type=int, default=40,
                    help="pixels around the void excluded from the field estimate")
    args = ap.parse_args()

    hole = np.asarray(Image.open(args.hole).convert("RGB")).astype(np.float32) / 255
    floor = np.asarray(Image.open(args.floor).convert("RGB")).astype(np.float32) / 255

    # Filter the plate to the same resolvable detail as the floor it lands on. Matching
    # colour is not enough: the decal is drawn over one tile of that floor, so any extra
    # crispness in the plate shows up as a square of busier grain, and the join step is the
    # number that says so. The radius is searched rather than guessed because the plate and
    # the floor did not come out of the same pipeline.
    if args.match_detail:
        target = detail(floor)
        for r in range(0, 12):
            trial = soften(hole, r) if r else hole
            if detail(trial) <= target * 1.05:
                hole = trial
                print(f"  plate low-passed at radius {r} to match the floor's detail")
                break
        else:
            print(f"  WARNING: plate still {detail(hole)/target:.2f}x the floor's detail at radius 11")
    elif args.antialias > 0:
        hole = soften(hole, args.antialias)

    void = lum(hole) < args.void_threshold
    ground = ~void

    # The plate is a generated image, so it arrives framed: its outer edge is a few luma
    # brighter or darker than its middle. The decal covers exactly one floor tile, so that
    # frame lands on the junctions with the neighbouring tiles and the hole reads as a
    # square patch pasted onto the ground. Take the frame out first, estimating the field
    # away from the void and its rim, which are content rather than framing.
    if args.frame > 0.0:
        from scipy.ndimage import binary_dilation
        mask = binary_dilation(void, iterations=args.rim)
        hole = flatten_profiles(hole, args.frame, mask)

    # Match on the outer ring rather than the whole plate. The decal covers exactly one
    # floor tile, so its ring is what touches the neighbouring tiles: matching the ring
    # makes the junction invisible, while matching the whole plate would let the void drag
    # the ground tone and leave the seam. The void is put back to black afterwards, since
    # an offset on pure black would lift it off the floor.
    hole = match_ring(hole, floor, args.std_blend)

    # Cross-fade the plate's border onto the floor itself. The decal covers exactly one
    # tile, so its border is the join; using the ground's own pixels there makes the join
    # an ordinary ground-to-ground join, which no amount of colour matching can beat, and
    # the fade hides the swap. The void and its rim sit in the middle and are untouched.
    if args.blend_border > 0:
        b = args.blend_border
        r = np.minimum.outer(
                np.minimum(np.arange(hole.shape[0]), hole.shape[0] - 1 - np.arange(hole.shape[0])),
                np.minimum(np.arange(hole.shape[1]), hole.shape[1] - 1 - np.arange(hole.shape[1])))
        ramp = np.clip(1.0 - r / b, 0, 1)
        hole = hole * (1 - ramp[..., None]) + floor * ramp[..., None]

    # Match the grain amplitude as well as the tone. Two samples of the same material can
    # agree perfectly on colour and still join visibly if one is grainier than the other,
    # because the join then carries the difference in local contrast. Scaling the plate's
    # high-pass to the floor's leaves the void and its rim untouched: they are large
    # features, so they live in the low pass.
    if args.grain > 0.0:
        r = max(2, min(hole.shape[:2]) // 64)
        lo_h, lo_f = _blur_axes(hole, r), _blur_axes(floor, r)
        hp_h, hp_f = hole - lo_h, floor - lo_f
        ground_h = np.repeat(ground[..., None], 3, axis=2)
        amp_h = float(np.abs(hp_h[ground_h]).mean()) or 1e-6
        amp_f = float(np.abs(hp_f).mean())
        k = 1 - args.grain + args.grain * (amp_f / amp_h)
        hole = np.clip(lo_h + hp_h * k, 0, 1)

    hole = np.clip(hole, 0, 1)
    hole[void] = 0.0
    out = (hole * 255).round().astype(np.uint8)
    Image.fromarray(np.dstack([out, np.full(out.shape[:2], 255, np.uint8)])).save(args.dst)
    print(f"{args.dst}: ground meanL={lum(hole)[ground].mean():.3f} "
          f"(floor {lum(floor).mean():.3f}), void {100 * void.mean():.1f}% of area")


if __name__ == "__main__":
    main()