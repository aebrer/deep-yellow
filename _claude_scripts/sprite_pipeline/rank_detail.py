#!/usr/bin/env python3
"""Rank sprites by how much photographic micro-detail survives in-game sampling.

The world is deliberately band-limited: floor scans are antialiased down to what the
128-texel pixel snap can resolve, so they read as broad painted shapes. Sprites never
got the same treatment, so photographic micro-texture (pores, fabric weave, individual
hairs) survives and the characters look like a different art department.

Measure at the size the player actually sees. The Sprite Detail setting downscales a
sprite to sprite_pixel_snap px wide with a bilinear filter, so a 128px-wide version IS
the PSX look. On that, two numbers:

  micro  - std-dev of a 3x3 high-pass: broadband photographic grain
  macro  - std-dev of the image itself: overall tonal range

micro/macro is the ratio that matters. A high ratio means the tonal range is carried by
grain rather than by shape, which is exactly the "too photoreal" signature, and it is
scale-free so dark sprites and bright ones compare fairly.
"""

import glob
import sys

import numpy as np
from PIL import Image

SAMPLE = 128


def highpass_std(a: np.ndarray) -> float:
    """Std-dev of (image - 3x3 box blur), on the luminance channel."""
    p = np.pad(a, 1, mode="edge")
    acc = np.zeros_like(a, dtype=np.float64)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            acc += p[dy:dy + a.shape[0], dx:dx + a.shape[1]]
    return float((a - acc / 9.0).std())


def visible(im: Image.Image) -> np.ndarray:
    """Luminance over the sprite's own alpha, at the sampled size."""
    a = np.asarray(im.convert("RGBA"), dtype=np.float64)
    alpha = a[:, :, 3] >= 128  # the shader's alpha scissor
    lum = (0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2])
    return lum, alpha


def score(path: str) -> tuple[float, float, float] | None:
    im = Image.open(path).convert("RGBA")
    lum, alpha = visible(im)
    ys, xs = np.where(alpha)
    if len(xs) < 64:
        return None
    # Crop to the visible figure, then sample it the way the renderer does
    crop = im.crop((int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)))
    scale = SAMPLE / crop.size[1]
    w = max(8, round(crop.size[0] * scale))
    small = crop.resize((w, SAMPLE), Image.BILINEAR)
    lum, alpha = visible(small)
    vals = lum[alpha]
    if vals.size < 64:
        return None
    macro = float(vals.std())
    if macro < 1e-6:
        return None
    full = np.where(alpha, lum, float(vals.mean()))
    micro = highpass_std(full)
    return micro, macro, micro / macro


def main(patterns: list[str]) -> None:
    rows = []
    for pattern in patterns:
        for path in sorted(glob.glob(pattern)):
            r = score(path)
            if r:
                rows.append((r[2], r[0], r[1], path))
    rows.sort(reverse=True)
    ratios = np.array([r[0] for r in rows])
    med = float(np.median(ratios))
    print(f"{len(rows)} sprites sampled at {SAMPLE}px tall "
          f"(the PSX Sprite Detail size). median micro/macro = {med:.3f}\n")
    print(f"{'ratio':>6}  {'micro':>6}  {'macro':>6}  sprite")
    for ratio, micro, macro, path in rows:
        flag = "  <-- outlier" if ratio > med * 1.25 else ""
        print(f"{ratio:6.3f}  {micro:6.2f}  {macro:6.2f}  {path.replace('res://', '')}{flag}")
    print(f"\noutlier threshold (1.25x median): {med * 1.25:.3f}")


if __name__ == "__main__":
    main(sys.argv[1:] or ["assets/textures/entities/*.png", "assets/textures/items/*.png"])