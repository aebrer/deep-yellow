"""Post-passes that fix the defects the generator keeps producing.

Every operation here is wrap-safe, so running it after make_tileable.py keeps the
texture seamless.

--pile        Directional pile streaks for carpet. The generator produces isotropic
              speckle, which averages to TV static once the floor is sampled on the
              renderer's 128-texel grid. Streaks stretched along one axis survive
              that downsample, so the material keeps reading as woven fibre.
--deepen      Push an already-dark region darker (wet look) without touching the field.
--cap-bright  Pull an over-bright object down to a target contrast over the field.
--soften-rim  Blur restricted to strong edges, to kill a die-cut pale outline, and lay
              a narrow contact shadow just outside it.
"""
import argparse

import numpy as np
from PIL import Image

import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from make_tileable import _blur_axes, lum, match_ring  # noqa: E402


def _grad_mag(a):
    gy, gx = np.gradient(lum(a))
    return np.abs(gx) + np.abs(gy)


def _streaks(shape, across, along, seed):
    """Wrap-safe anisotropic noise: white noise blurred harder along x than y, so
    the result is horizontal fibres. Gaussian with mode=wrap keeps it seamless."""
    from scipy.ndimage import gaussian_filter
    rng = np.random.default_rng(seed)
    n = rng.standard_normal(shape).astype(np.float32)
    s = gaussian_filter(n, sigma=(across, along), mode="wrap")
    return s / (s.std() + 1e-9)


def pile(a, amp, across=8, along=40, seed=0):
    """Two octaves of directional pile: fibre streaks plus broad wear lanes.

    across/along are gaussian sigmas in source pixels. Below about 6 px across the
    streaks stop being structure the renderer can resolve and start being noise, so
    the defaults sit where the streaks still read after the 128-texel downsample.
    """
    fine = np.clip(_streaks(a.shape[:2], across, along, seed) * 1.4, -2.5, 2.5) / 2.5
    lanes = np.clip(_streaks(a.shape[:2], across * 1.5, along * 2.5, seed + 1) * 1.4, -2.5, 2.5) / 2.5
    # Fibres vary mostly in brightness but keep some chroma, or they read as grey haze.
    tint = np.array([1.0, 0.93, 0.84], np.float32)
    return np.clip(a + (0.7 * fine + 0.3 * lanes)[..., None] * amp * tint, 0, 1)


def deepen(a, factor, thresh_delta=0.05):
    field = np.median(np.concatenate([
        lum(a)[:8].ravel(), lum(a)[-8:].ravel(), lum(a)[:, :8].ravel(), lum(a)[:, -8:].ravel()]))
    l = lum(a)
    mask = np.clip((field - thresh_delta - l) / max(field, 1e-3), 0, 1)
    return np.clip(a * (1 - factor * mask[..., None]), 0, 1)


def cap_bright(a, target_delta):
    """Scale the bright object so its mean sits target_delta above the field."""
    field = np.median(np.concatenate([
        lum(a)[:8].ravel(), lum(a)[-8:].ravel(), lum(a)[:, :8].ravel(), lum(a)[:, -8:].ravel()]))
    m = lum(a) > field + 0.10
    if not m.any():
        return a
    cur = lum(a)[m].mean() - field
    if cur <= target_delta:
        return a
    k = target_delta / cur
    out = a.copy()
    scaled = field + (a - field) * (1 + (k - 1) * np.clip((lum(a) - field - 0.05) / 0.15, 0, 1)[..., None])
    out[m] = np.clip(scaled, 0, 1)[m]
    return out


def soften_rim(a, radius=3, shadow=0.18):
    """Blur only where gradients are strong, then darken just outside those edges."""
    g = _grad_mag(a)
    edge = np.clip((g - np.percentile(g, 97)) / (np.percentile(g, 99.5) - np.percentile(g, 97) + 1e-9), 0, 1)
    w = _blur_axes(edge[None, ..., None], radius)[0, ..., 0]
    blurred = _blur_axes(a, radius)
    out = a * (1 - w[..., None]) + blurred * w[..., None]
    # Contact shadow: darken the band just outside a bright object's edge.
    l = lum(a)
    field = np.median(np.concatenate([l[:8].ravel(), l[-8:].ravel(), l[:, :8].ravel(), l[:, -8:].ravel()]))
    inner = l > field + 0.10
    outer = _blur_axes(inner.astype(np.float32)[None, ..., None], max(2, radius))[0, ..., 0]
    ring = np.clip(outer - inner * 2, 0, 1)
    return np.clip(out * (1 - shadow * ring[..., None]), 0, 1)


def protect_objects(before, after, tol=0.07, feather=6):
    """Keep placed objects (a cardboard sheet, a puddle) out of a whole-image pass.

    The pile streaks belong to the carpet pile. Where the image already departs from
    the surrounding field by more than tol, that is a separate object and it keeps its
    own surface, otherwise a sheet of cardboard ends up combed like the carpet under it.
    """
    def field(img):
        l = lum(img)
        return np.median(np.concatenate([l[:8].ravel(), l[-8:].ravel(), l[:, :8].ravel(), l[:, -8:].ravel()]))
    delta = np.abs(lum(after) - field(after))
    obj = np.clip((delta - tol) / tol, 0, 1)
    obj = _blur_axes(obj[None, ..., None], feather)[0, ..., 0]
    return after * (1 - obj[..., None]) + before * obj[..., None]


def match_object(a, ref, std_blend=0.5, thresh=0.10):
    """Pull a bright object (cardboard sheet) onto the reference object's colour.

    The whole-image colour match is driven by the field around the object, so the
    object itself keeps whatever tone the generator gave it. This matches the object
    region separately, using the same field-relative threshold on both images.
    """
    def field(img):
        l = lum(img)
        return np.median(np.concatenate([l[:8].ravel(), l[-8:].ravel(), l[:, :8].ravel(), l[:, -8:].ravel()]))
    fa, fr = field(a), field(ref)
    ma, mr = lum(a) > fa + thresh, lum(ref) > fr + thresh
    if not ma.any() or not mr.any():
        return a
    out = a.copy()
    for c in range(3):
        m0, s0 = a[..., c][ma].mean(), a[..., c][ma].std()
        m1, s1 = ref[..., c][mr].mean(), ref[..., c][mr].std()
        gain = 1 - std_blend + std_blend * (s1 / max(s0, 1e-6))
        out[..., c] = np.where(ma, (a[..., c] - m0) * gain + m1, a[..., c])
    return np.clip(out, 0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--match", default="",
                    help="reference to pull colour onto, applied last (make_tileable matches "
                         "before rebuilding the border, which moves the ring stats back)")
    ap.add_argument("--match-std", type=float, default=0.0)
    ap.add_argument("--pile", type=float, default=0.0)
    ap.add_argument("--pile-across", type=int, default=8)
    ap.add_argument("--pile-along", type=int, default=40)
    ap.add_argument("--pile-seed", type=int, default=0)
    ap.add_argument("--deepen", type=float, default=0.0)
    ap.add_argument("--cap-bright", type=float, default=0.0, help="target luminance delta of bright object over field")
    ap.add_argument("--match-object", default="", help="reference whose bright object region to copy colour from")
    ap.add_argument("--object-std", type=float, default=0.35)
    ap.add_argument("--protect-objects", action="store_true",
                    help="do not apply the pile pass to regions that differ from the field")
    ap.add_argument("--soften-rim", type=int, default=0)
    ap.add_argument("--rim-shadow", type=float, default=0.18)
    args = ap.parse_args()

    a = np.asarray(Image.open(args.src).convert("RGB")).astype(np.float32) / 255
    if args.pile > 0:
        src = a
        a = pile(a, args.pile, args.pile_across, args.pile_along, args.pile_seed)
        if args.protect_objects:
            a = protect_objects(src, a)
    if args.match_object:
        a = match_object(a, np.asarray(Image.open(args.match_object).convert("RGB")
                                       .resize(a.shape[1::-1])).astype(np.float32) / 255,
                         args.object_std)
    if args.cap_bright > 0:
        a = cap_bright(a, args.cap_bright)
    if args.deepen > 0:
        a = deepen(a, args.deepen)
    if args.soften_rim > 0:
        a = soften_rim(a, args.soften_rim, args.rim_shadow)
    if args.match:
        a = match_ring(a, np.asarray(Image.open(args.match).convert("RGB")
                                     .resize(a.shape[1::-1])).astype(np.float32) / 255,
                       args.match_std)
    Image.fromarray((a * 255).round().astype(np.uint8)).save(args.dst)
    print(f"{args.dst}  {a.shape[1]}x{a.shape[0]}")


if __name__ == "__main__":
    main()