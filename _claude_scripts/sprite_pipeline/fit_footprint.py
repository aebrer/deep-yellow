#!/usr/bin/env python3
"""Fit a replacement sprite into the footprint of the sprite it replaces.

A billboard's world size comes from its canvas (entities are sized on canvas WIDTH, in
Utilities.apply_snap_sprite), so pasting a new generation straight over an old PNG changes
how big the creature is whenever the model crops differently — and it changes where the
feet sit, because the scene offsets billboards by a fixed height.

Scale the new figure to CONTAIN inside the old figure's visible bounding box, preserving
its own aspect ratio, then bottom-align and centre it. Contain rather than match-height:
a crouched replacement should stay crouched instead of being inflated to the old figure's
height. "Visible" uses alpha >= 128, which is what the shader's alpha scissor keeps.
"""

import sys

import numpy as np
from PIL import Image

ALPHA_MIN = 128


def bbox(im: Image.Image) -> tuple[int, int, int, int]:
    a = np.asarray(im.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(a >= ALPHA_MIN)
    if len(xs) == 0:
        raise SystemExit("no pixels above the alpha scissor")
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def fit(new_path: str, old_path: str, out_path: str) -> None:
    old = Image.open(old_path).convert("RGBA")
    ox0, oy0, ox1, oy1 = bbox(old)
    ow, oh = ox1 - ox0, oy1 - oy0

    new = Image.open(new_path).convert("RGBA")
    nx0, ny0, nx1, ny1 = bbox(new)
    nw, nh = nx1 - nx0, ny1 - ny0
    crop = new.crop((nx0, ny0, nx1, ny1))

    scale = min(ow / nw, oh / nh)
    fw, fh = max(1, round(nw * scale)), max(1, round(nh * scale))
    crop = crop.resize((fw, fh), Image.LANCZOS)

    canvas = Image.new("RGBA", old.size, (0, 0, 0, 0))
    canvas.paste(crop, (int(round((ox0 + ox1) / 2 - fw / 2)), oy1 - fh), crop)

    # Re-lancering a hard-cut sprite reintroduces intermediate alpha, and where that lands
    # on a bright edge (a fogged lens) it leaves pale semi-transparent pixels — the same
    # class of defect as the keyed white specks. The renderer point-samples sprites at
    # sprite_pixel_snap and cuts alpha at 0.5, so partial alpha buys nothing here.
    arr = np.array(canvas)
    arr[:, :, 3] = np.where(arr[:, :, 3] >= ALPHA_MIN, 255, 0)
    canvas = Image.fromarray(arr, "RGBA")
    canvas.save(out_path)

    cx0, cy0, cx1, cy1 = bbox(canvas)
    print(f"{out_path.split('/')[-1]:<26} old figure {ow}x{oh} at ({ox0},{oy0}) "
          f"-> new {cx1 - cx0}x{cy1 - cy0} at ({cx0},{cy0}), "
          f"floor line {cy1} vs {oy1}, canvas {old.size[0]}px kept")
    if cy1 != oy1:
        print(f"  note: floor line moved by {oy1 - cy1}px "
              f"({abs(oy1 - cy1) / oh * 100:.1f}% of figure height)")


if __name__ == "__main__":
    fit(*sys.argv[1:4])