#!/usr/bin/env python3
"""Make a generated material swatch tile without blurring its borders.

Why this exists: a diffusion model asked for a "tileable" texture fakes it by
smoothing a band around the border, so every tile seam reads as a soft grout
line (measured: border band 2-7x smoother than the tile interior). Instead of
asking the model to tile, we take a full-bleed swatch and make it tile ourselves
without throwing away detail:

  1. Roll by half size. The wrap adjacency moves to the centre, so every
     artefact the model put at the borders (soft band, dark grout cross) is now
     a cross through the middle, and the image's outer edges are clean interior
     content that already wraps.
  2. Repair the cross: replace its LOW frequencies with a Laplace continuation
     between the two strips either side (that is what removes the grout line and
     the soft ramp), and keep its HIGH frequencies, gain-matched to the interior
     so the band stays as crisp as the rest of the tile.
  3. Repeat per axis, then verify.

Usage: make_tileable.py IN.png OUT.png [--band 40] [--iterations 600]
"""

import argparse
import warnings
import sys
from pathlib import Path

import numpy as np
from PIL import Image

LUMA = np.array([0.2126, 0.7152, 0.0722])


def lum(a: np.ndarray) -> np.ndarray:
    return a @ LUMA


def _blur_axes(g: np.ndarray, radius: int) -> np.ndarray:
    out = g
    for axis in (0, 1):
        acc = np.zeros_like(out)
        n = 0
        for k in range(-radius, radius + 1):
            acc += np.roll(out, k, axis=axis)
            n += 1
        out = acc / n
    return out


def laplace_fill(band: np.ndarray, axis: int, iters: int) -> np.ndarray:
    """Fill a seam band with the smoothest surface that meets both sides.

    `axis` is the short axis of the band — the one carrying the two boundary
    strips. Those two strips stay pinned (Dirichlet boundary) while everything
    between them converges to the Laplace solution by Jacobi iterations. The
    long axis wraps, because the seam runs the full length of the tile and its
    ends meet their own copies.
    """
    u = band.astype(np.float32).copy()
    edge_a = u.take(0, axis=axis).copy()
    edge_b = u.take(-1, axis=axis).copy()
    inner = [slice(None)] * 2
    inner[axis] = slice(1, -1)
    at_a = [slice(None)] * 2
    at_a[axis] = 0
    at_b = [slice(None)] * 2
    at_b[axis] = -1
    for _ in range(iters):
        nbr = np.roll(u, 1, axis=0) + np.roll(u, -1, axis=0) \
                + np.roll(u, 1, axis=1) + np.roll(u, -1, axis=1)
        u[tuple(inner)] = 0.25 * nbr[tuple(inner)]
        u[tuple(at_a)] = edge_a
        u[tuple(at_b)] = edge_b
    return u


def repair_seam(img: np.ndarray, axis: int, band: int, iters: int, blur_r: int,
		detail: str = "patch", tone: float = 0.0) -> np.ndarray:
    """Repair the seam running down the middle of `img` along `axis`.

    axis=1 -> vertical seam (constant x), axis=0 -> horizontal seam (constant y).

    The band is rebuilt, not blurred: a Laplace continuation carries the tone
    across (that is what deletes the model's grout line and soft ramp), and real
    material grain from elsewhere in the tile is laid on top of it. Taking grain
    from the tile's own interior keeps the band as crisp as the rest of the tile
    and, for noise-like materials, invisible.
    """
    out = img.copy()
    n = img.shape[axis]
    c = n // 2
    lo, hi = c - band, c + band

    def sl(a: int, s0, s1) -> list:
        x = [slice(None)] * 2
        x[a] = slice(s0, s1)
        return x

    band_px = img[tuple(sl(axis, lo, hi))].astype(np.float32)
    interior = np.concatenate(
        [img[tuple(sl(axis, lo - band, lo))].astype(np.float32),
         img[tuple(sl(axis, hi, hi + band))].astype(np.float32)],
        axis=axis,
    )

    # The rebuilt band: smooth continuation between the two sides of the cut, with
    # real material grain laid on top. Grain comes from an interior strip of the
    # same size, far enough from the seam that it is not the soft border band we
    # are replacing.
    base = laplace_fill(band_px, axis, iters)
    if detail == "patch":
        src0 = hi + band
        patch = np.take(img.astype(np.float32),
                        [(src0 + k) % n for k in range(2 * band)], axis=axis)
        high = patch - _blur_axes(patch, blur_r)
        # Strip the grain layer's mean ALONG the seam. A patch's high-pass is not
        # exactly zero mean per line, so injecting it shifts the band's tone by a
        # hair and leaves a bright (or dark) rule exactly where tiles meet — the
        # same class of artefact as the grout line this script removes. Zeroing the
        # mean along the long axis leaves the Laplace base in full control of tone,
        # and that base is pinned to the neighbouring strips at both cut edges.
        long_axis = 1 - axis
        high = high - high.mean(axis=long_axis, keepdims=True)
        rebuilt = base + high
    else:
        # The band's own detail, gain-matched to the interior: weaker than a patch,
        # but it keeps whatever structure the model drew across the seam
        own_high = band_px - _blur_axes(band_px, blur_r)
        sd_band, sd_int = float(own_high.std()), float((interior - _blur_axes(interior, blur_r)).std())
        if sd_band > 1e-6:
            own_high = own_high * (sd_int / sd_band)
        own_high = own_high - own_high.mean(axis=1 - axis, keepdims=True)
        rebuilt = base + own_high

    # Cross-fade original -> rebuilt across the band, touching nothing at the
    # edges. Applying the rebuild at full strength everywhere leaves a step in the
    # texture's local statistics two band-widths apart, which reads as a thin grid
    # line once the tile repeats — much like the artefact this whole script exists
    # to remove.
    d = 2 * band
    t = np.abs(np.linspace(-1.0, 1.0, d))
    shape = [1, 1, 1]
    shape[axis] = d
    w = ((1.0 - t ** 2) ** 1.5 * tone).reshape(shape)
    out[tuple(sl(axis, lo, hi))] = np.clip(band_px * (1.0 - w) + rebuilt * w, 0.0, 1.0)
    return out


def soften(a: np.ndarray, radius: int) -> np.ndarray:
    """Low-pass the swatch to what the renderer can actually resolve.

    Floors are sampled with texture_filter_nearest on a UV grid snapped to 128
    texels per 2 m tile, so anything above ~64 cycles per tile is point-sampled
    and folds back as moire. Incoherent grain folds back into more grain and is
    harmless; a coherent weave or fine stripe folds back into a moving grid. This
    takes the coherent stuff off before it can alias.
    """
    return _blur_axes(a, max(1, radius)) if radius > 0 else a


def flatten_lows(a: np.ndarray, radius: int, amount: float) -> np.ndarray:
    """Suppress low-frequency tone drift so repetition does not read as a grid.

    A tileable material that carries a big soft light/dark gradient announces its
    tile boundaries every time it repeats — the eye locks onto the patch, not the
    surface. Removing part of that gradient (wrap-aware, so the wrap point is not
    singled out) keeps every bit of the fibre/grain detail while making the
    repetition much harder to notice.
    """
    big = _blur_axes(a, radius)
    return np.clip(a - amount * (big - big.mean()), 0.0, 1.0)


def match_ring(a: np.ndarray, ref: np.ndarray, std_blend: float = 0.5) -> np.ndarray:
    """Pull a variant tile's colour onto the base tile it sits next to.

    Variant floor tiles (cardboard, puddle) are generated separately from their
    base carpet, so each comes back with its own white balance — side by side in
    the same room they read as three different carpets. Statistics are measured on
    the outer quarter ring, which is pure carpet on every one of them, and applied
    across the whole tile so the subject moves with its ground.
    """
    q = min(a.shape[0], a.shape[1]) // 4

    def ring(x):
        return np.concatenate([x[:q].reshape(-1, 3), x[-q:].reshape(-1, 3),
                               x[:, :q].reshape(-1, 3), x[:, -q:].reshape(-1, 3)])

    src, dst = ring(a), ring(ref)
    out = a.copy()
    for c in range(3):
        m0, s0 = src[:, c].mean(), src[:, c].std()
        m1, s1 = dst[:, c].mean(), dst[:, c].std()
        if s0 <= 1e-6:
            continue
        gain = 1.0 + std_blend * (s1 / s0 - 1.0)
        out[:, :, c] = (out[:, :, c] - m0) * gain + m1
    return np.clip(out, 0.0, 1.0)


def destripe(a: np.ndarray, win: int = 9) -> np.ndarray:
    """Remove 1-3px-wide brightness lines the model leaves as fake tile edges.

    Diffusion models often draw a faint bright/dark line somewhere in a "tileable"
    request. When the texture repeats, that line repeats too and reads as a seam
    even though the wrap point itself is fine. Only the narrow DC spike is removed:
    the baseline is a wrap-aware median over a small window, so real mottling and
    all detail survive, and the correction cannot introduce a seam of its own.
    """
    out = a.copy()
    for axis in (1, 0):  # columns then rows
        prof = out.mean(axis=tuple(i for i in range(3) if i != axis))
        half = win // 2
        padded = np.concatenate([prof[-half:], prof, prof[:half]])
        base = np.median(np.lib.stride_tricks.sliding_window_view(padded, win), axis=-1)
        out = out + (base - prof).reshape(
                (1, -1, 1) if axis == 1 else (-1, 1, 1))
    return np.clip(out, 0.0, 1.0)


def border_sharpness_ratio(a: np.ndarray, band: int) -> float:
    g = lum(a)
    h, w = g.shape
    b = max(4, min(band, w // 16, h // 16))
    gy, gx = np.gradient(g)
    mag = np.abs(gx) + np.abs(gy)
    inner = mag[b:-b, b:-b].mean()
    edge = np.concatenate([mag[:b].ravel(), mag[-b:].ravel(), mag[:, :b].ravel(), mag[:, -b:].ravel()]).mean()
    return float(edge / inner) if inner else float("nan")


def seam_discontinuity(a: np.ndarray, band: int = 8) -> float:
    """Edge-to-wrapped-edge difference relative to the same difference inland."""
    g = lum(a)
    h, w = g.shape
    seam = float(np.abs(g[:, -band:] - g[:, :band]).mean() + np.abs(g[-band:, :] - g[:band, :]).mean())
    inland_lr = float(np.mean([np.abs(g[:, x:x + band] - g[:, x + band:x + band * 2]).mean()
                               for x in range(band, w - band * 2, max(1, w // 32))]))
    inland_tb = float(np.mean([np.abs(g[y:y + band, :] - g[y + band:y + band * 2, :]).mean()
                               for y in range(band, h - band * 2, max(1, h // 32))]))
    inland = (inland_lr + inland_tb) * 0.5
    return seam * 0.5 / inland if inland else float("nan")


def make_tileable(img: np.ndarray, band: int, iters: int, blur_r: int,
		detail: str = "patch", tone: float = 0.0, keep_centre: bool = True) -> np.ndarray:
    """Return a tileable version of img.

    Rolling by half size is only a coordinate trick: it brings the wrap seam to
    the middle so the repair band is contiguous. Tileability is a property of the
    wrap adjacency, so rolling back afterwards keeps it and leaves the artwork
    where the artist put it — which matters for the composed variant tiles
    (cardboard box, puddle) whose subject is centred.
    """
    h, w, _ = img.shape
    if min(h, w) < 4 * band:
        raise SystemExit(f"image {w}x{h} too small for band={band}")
    rolled = np.roll(img, (h // 2, w // 2), axis=(0, 1))
    rolled = repair_seam(rolled, 1, band, iters, blur_r, detail, tone)  # vertical seam
    rolled = repair_seam(rolled, 0, band, iters, blur_r, detail, tone)  # horizontal seam
    if keep_centre:
        rolled = np.roll(rolled, (-h // 2, -w // 2), axis=(0, 1))
    return rolled


def object_mask(a: np.ndarray, scale: float = 1 / 16, k: float = 2.5) -> np.ndarray:
    """Mask the compact subject of a composed tile (cardboard sheet, puddle, hole).

    The profile equaliser below has to estimate the field's brightness per row and per
    column. An object that covers part of a row drags that estimate with it, and matching
    it would paint a compensating gradient across the rest of the tile, so anything that
    departs sharply from its neighbourhood is excluded first.
    """
    from scipy.ndimage import binary_dilation, gaussian_filter
    l = lum(a)
    sigma = max(2.0, min(a.shape[:2]) * scale)
    high = l - gaussian_filter(l, sigma=sigma, mode="wrap")
    m = np.abs(high) > k * high.std()
    return binary_dilation(m, iterations=max(1, int(sigma / 2)))


def flatten_profiles(a: np.ndarray, amount: float, mask=None) -> np.ndarray:
    """Remove the separable banding that repeats with the tile.

    Material scans come out framed: the outer few percent a few luma darker, the middle a
    few luma brighter, plus whatever tone shift the seam repair leaves behind. That part
    is separable (one offset per column, one per row), and separable banding is exactly
    what reads as a grid once the tile repeats. Subtracting it deletes the grid without
    touching grain, and since each column keeps its own offset the wrap stays consistent.

    `mask` excludes the subject of composed tiles from the estimate; see object_mask.
    """
    l = lum(a)
    if mask is not None and mask.any():
        l = np.where(mask, np.nan, l)
    with warnings.catch_warnings():
        # A row covered end to end by the subject has no field left to average.
        warnings.simplefilter("ignore", RuntimeWarning)
        rows = np.nanmean(l, axis=1)
        cols = np.nanmean(l, axis=0)
        base = float(np.nanmean(l))
    rows = np.nan_to_num(rows, nan=base) - base
    cols = np.nan_to_num(cols, nan=base) - base
    off = (rows * amount)[:, None] + (cols * amount)[None, :]
    return np.clip(a - off[:, :, None], 0, 1)


def flatten_frame(a: np.ndarray, width: int, amount: float) -> np.ndarray:
    """Taper out the dark frame the generator paints along the tile borders.

    Material scans come out with the outer few percent a handful of luma darker than the
    middle, and the repaired seam band lands in the same place. Both are border-local, so
    matching each border strip to the strip immediately inside it removes them together.
    The correction is tapered to zero at the inner edge so no new step is introduced, and
    the two halves join across the wrap into one band centred on the junction.

    Only the borders are touched, which is what keeps the variant tiles intact: their
    cardboard sheet and puddle sit in the middle of the tile and are content, not frame.
    """
    out = a.copy()
    h, w, _ = out.shape

    def strip(axis, n, lo, hi):
        sl = [slice(None)] * 3
        sl[axis] = slice(lo, hi)
        return out[tuple(sl)]

    for axis, n in ((0, h), (1, w)):
        b = max(2, min(width, n // 6))
        ramp = np.linspace(1.0, 0.0, b)
        for lo, hi, ref, t in ((0, b, (b, 2 * b), ramp),
                               (n - b, n, (n - 2 * b, n - b), ramp[::-1])):
            inner = strip(axis, n, *ref).reshape(-1, 3).mean(axis=0)
            edge = strip(axis, n, lo, hi).reshape(-1, 3).mean(axis=0)
            # Divide by the ramp's mean so the correction actually applied averages the
            # full difference, rather than half of it.
            delta = (inner - edge) * amount / ramp.mean()
            ramp_shape = [1, 1, 1]
            ramp_shape[axis] = b
            sl = [slice(None)] * 3
            sl[axis] = slice(lo, hi)
            out[tuple(sl)] = np.clip(
                    out[tuple(sl)] + delta.reshape(1, 1, 3) * t.reshape(ramp_shape), 0, 1)
    return out


def composite(a: np.ndarray, out: Path, reps: int = 3, crop: int = 480) -> None:
    """Write a 3x3 neighbourhood plus crops of the two places artefacts hide.

    _seam.png  : centred on a tile corner, i.e. the wrap point itself
    _cross.png : centred on the tile middle, i.e. the repaired cross
    """
    u8 = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    tile = np.tile(u8, (reps, reps, 1))
    Image.fromarray(tile).save(out.with_name(out.stem + "_3x3.png"))
    h, w, _ = a.shape
    cy, cx = h + h // 2, w + w // 2  # tile centre in the 3x3 grid
    Image.fromarray(tile[cy - crop // 2:cy + crop // 2, cx - crop // 2:cx + crop // 2]).save(
            out.with_name(out.stem + "_cross.png"))
    oy, ox = h, w  # tile corner in the 3x3 grid
    Image.fromarray(tile[oy - crop // 2:oy + crop // 2, ox - crop // 2:ox + crop // 2]).save(
            out.with_name(out.stem + "_seam.png"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--band", type=int, default=0, help="half-width of the repaired seam band (default size/24)")
    ap.add_argument("--iterations", type=int, default=600)
    ap.add_argument("--blur", type=int, default=0, help="high/low split radius (default band/3)")
    ap.add_argument("--detail", choices=["patch", "residual"], default="patch",
                    help="grain source for the repaired band")
    ap.add_argument("--match", default="", help="reference texture to pull colour onto")
    ap.add_argument("--match-std", type=float, default=0.5, help="0 = colour only, 1 = also contrast")
    ap.add_argument("--soften", type=int, default=0,
                    help="wrap-aware low-pass radius, to pre-filter detail the 128-px snap cannot resolve")
    ap.add_argument("--flatten", type=float, default=0.0,
                    help="how much low-frequency tone drift to remove (0..1)")
    ap.add_argument("--flatten-radius", type=int, default=0,
                    help="radius of the low-frequency reference (default size/10)")
    ap.add_argument("--destripe", type=int, default=9,
                    help="window for the narrow-line removal (0 = off)")
    ap.add_argument("--no-keep-centre", dest="keep_centre", action="store_false",
                    help="leave the repaired cross at the tile centre instead of the borders")
    ap.add_argument("--frame", type=float, default=0.0,
                    help="strength of the separable banding correction (0 = off, 1 = full)")
    ap.add_argument("--no-frame-mask", dest="frame_mask", action="store_false",
                    help="include the subject in the banding estimate (uniform materials only)")
    ap.add_argument("--antialias", type=int, default=0,
                    help="low-pass radius applied last, to remove detail the renderer's 128-texel "
                         "grid would fold back into moire (see game_sim.py for the measurement)")
    ap.add_argument("--tone", type=float, default=1.0,
                    help="how much of the band to rebuild (0 = untouched, 1 = full)")
    args = ap.parse_args()

    src, dst = Path(args.src), Path(args.dst)
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255.0

    if args.match:
        a = match_ring(a, np.asarray(Image.open(args.match).convert("RGB")
                                     .resize(im.size)).astype(np.float32) / 255.0,
                       args.match_std)

    if args.soften > 0:
        a = soften(a, args.soften)

    if args.flatten > 0.0:
        r = args.flatten_radius or max(8, min(im.size) // 10)
        a = flatten_lows(a, r, args.flatten)

    if args.destripe > 1:
        a = destripe(a, args.destripe)

    band = args.band or max(16, min(im.size) // 24)
    blur_r = args.blur or max(2, band // 3)

    before_border = border_sharpness_ratio(a, band)
    before_seam = seam_discontinuity(a, band)

    out = make_tileable(a, band, args.iterations, blur_r, args.detail, args.tone,
                       args.keep_centre)

    if args.frame > 0.0:
        mask = object_mask(out) if args.frame_mask else None
        out = flatten_profiles(out, args.frame, mask)

    # Last, so it also catches above-Nyquist grain injected by the seam repair.
    if args.antialias > 0:
        out = soften(out, args.antialias)

    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(dst)

    composite(out, dst)
    print(f"{src.name}: band={band}px blur_r={blur_r} iters={args.iterations} detail={args.detail} tone={args.tone}")
    print(f"  border/interior sharpness  {before_border:.2f} -> {border_sharpness_ratio(out, band):.2f}  (want ~1.0)")
    print(f"  seam/inland discontinuity  {before_seam:.2f} -> {seam_discontinuity(out, band):.2f}  (want <1.5)")
    print(f"  wrote {dst}")


if __name__ == "__main__":
    sys.exit(main())

def gridline_step(a: np.ndarray) -> float:
    """How much the tile seam stands out as a tone line once the tile repeats.

    The eye reads a repeating texture as a grid when the *average* tone jumps at
    the wrap point. Compares the wrap-column/wrap-row jump against the average
    jump between neighbouring columns/rows inland: 1.0 = the seam is as quiet as
    anywhere else in the tile, >2 = you will see a grid in game.
    """
    g = lum(a)
    jumps = []
    for prof in (g.mean(axis=0), g.mean(axis=1)):
        step = abs(prof[0] - prof[-1])
        inland = float(np.abs(np.diff(prof)).mean())
        if inland > 1e-9:
            jumps.append(step / inland)
    return float(np.mean(jumps)) if jumps else float("nan")
