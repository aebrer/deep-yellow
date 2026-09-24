#!/usr/bin/env python3
"""Turn a generated sprite on a flat matte background into a clean cutout.

Two failure modes to avoid, both learned the hard way on this asset set:

  * Asking the model for a low-key sprite "in darkness" makes it paint a solid black
    field. That field renders as a black card, because sprites are alpha-cutout — but the
    darkness INSIDE the figure has to survive: the in-tone sprites keep a lot of opaque
    black (drowner 38% of its canvas, bacteria_motherload 38%). The withheld information
    is the art. Keying by luminance eats it, so key only what is CONNECTED TO THE BORDER.
  * Keying a black field on a black figure is unstable, because the two are the same
    value. So generate on a flat WHITE matte instead: same distance from the figure, but
    separable. This script keys either.

The cut threshold is measured from the border ring's own brightness rather than guessed,
and the edge is feathered so the silhouette dissolves into the room instead of being
die-cut out of it.
"""

import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def key_matte(path: str, out_path: str, bright: bool) -> None:
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)
    luma = 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]
    chroma = a[:, :, :3].max(axis=2) - a[:, :, :3].min(axis=2)  # 0 = achromatic

    ring = np.concatenate([
        luma[:3, :].ravel(), luma[-3:, :].ravel(), luma[:, :3].ravel(), luma[:, -3:].ravel()])
    if bright:
        thr = float(np.clip(np.percentile(ring, 8) - 6.0, 205.0, 250.0))
        matte = luma >= thr
    else:
        thr = float(np.clip(np.percentile(ring, 92) + 6.0, 8.0, 30.0))
        matte = luma <= thr

    labels, _ = ndimage.label(matte)
    touching = set(np.unique(np.concatenate([
        labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]]))) - {0}
    background = np.isin(labels, list(touching))

    if bright:
        # HARD alpha, no ramp. Ramping across the model's soft contact shadow looks
        # principled but produces semi-transparent pixels whose RGB is still the white
        # field's — over a dark sprite they survive the 0.5 alpha cut and blend as pale
        # specks ("white interior pixels that should be transparent"). And the blend cannot
        # be undone: an un-premultiply of pure white is still white at any alpha, so the
        # maths cannot tell "light subject at 35%" from "matte at 100%". So take the whole
        # pale region, shadow included, as matte and cut it off clean. These sprites are
        # point-sampled at 128px anyway, where a hard edge is what the look wants.
        #
        # Only BORDER-CONNECTED pale pixels go, so pale highlights inside the subject (a
        # drowned face, mould bloom, a fogged lens) survive; and enclosed pixels that are
        # the matte's exact colour are punched out too, because connectivity alone leaves
        # the field trapped under a raised arm or between legs.
        # A light-neutral band counts as matte as well: the model's contact shadow fades to a
# colourless grey wash that no single luma line can catch without eating the art. The
# art's own pale highlights are TINTED (a drowned face is blue-grey, mould is warm), so
# pale AND achromatic AND connected to the field is unambiguously matte.
        soft_lo = max(170.0, thr - 45.0)
        pale = (luma >= soft_lo) | ((luma >= 150.0) & (chroma < 10))
        pale_labels, _ = ndimage.label(pale)
        pale_touching = set(np.unique(np.concatenate([
            pale_labels[0, :], pale_labels[-1, :], pale_labels[:, 0], pale_labels[:, -1]]))) - {0}
        background = np.isin(pale_labels, list(pale_touching))
        enclosed = (luma >= thr) & (chroma < 8)
        alpha = np.where(background | enclosed, 0.0, 255.0)
    else:
        feather = ndimage.gaussian_filter(background.astype(np.float64), 1.2)
        alpha = a[:, :, 3] * np.clip(1.0 - feather * 1.35, 0.0, 1.0)
        alpha[background] = 0.0

    out = a.copy()
    out[:, :, 3] = alpha
    Image.fromarray(out.astype(np.uint8), "RGBA").save(out_path)

    kept = alpha >= 128
    v = luma[kept]
    print(f"{out_path.split('/')[-1]:<30} keyed {100 * background.mean():5.1f}% of canvas "
          f"(threshold luma {thr:.0f}) -> {100 * (alpha < 10).mean():5.1f}% transparent, "
          f"keeps {100 * (kept & (luma < 45)).mean():4.1f}% opaque black, "
          f"figure meanL {v.mean():5.1f}, dark {100 * (v < 45).mean():4.1f}%")


if __name__ == "__main__":
    mode, paths = sys.argv[1], sys.argv[2:]
    bright = mode == "white"
    for src in paths:
        key_matte(src, src.replace(".png", "_cut.png"), bright)