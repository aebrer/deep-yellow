#!/usr/bin/env python3
"""Build tiled composite sheets for a texture so seams are visible.

Outputs, per texture:
  <name>_3x3.png        -- 3x3 repeat, no scaling (shows the whole neighborhood)
  <name>_seam.png       -- 480x480 crop centred exactly on a tile seam crossing
  <name>_stats.txt      -- luminance stats + a wrap-discontinuity measurement

The seam crop is the important one: if the generator blurred the border band to
make the image "tileable", it shows up there as a soft band crossing the tiles.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent


def lum(a: np.ndarray) -> np.ndarray:
    return a @ np.array([0.2126, 0.7152, 0.0722])


def wrap_discontinuity(a: np.ndarray) -> dict:
    """Compare edge columns/rows against their wrapped neighbours.

    A properly tileable texture has left edge adjacent to right edge with the
    same local contrast as any interior pair. We measure mean abs difference of
    the wrapped edge pair vs the average of interior pairs (same distance).
    """
    g = lum(a)
    h, w = g.shape
    band = max(2, min(8, w // 32))  # pixels averaged at the seam

    def diff(p: np.ndarray, q: np.ndarray) -> float:
        return float(np.abs(p - q).mean())

    # seam: last `band` columns vs first `band` columns (adjacent when tiled)
    seam_lr = diff(g[:, -band:], g[:, :band])
    seam_tb = diff(g[-band:, :], g[:band, :])

    # interior reference: sample many interior pairs at the same offset
    offs = []
    for x in range(band, w - band * 2, max(1, (w - band * 3) // 64)):
        offs.append(diff(g[:, x:x + band], g[:, x + band:x + band * 2]))
    interior_lr = float(np.mean(offs)) if offs else 0.0

    offs = []
    for y in range(band, h - band * 2, max(1, (h - band * 3) // 64)):
        offs.append(diff(g[y:y + band, :], g[y + band:y + band * 2, :]))
    interior_tb = float(np.mean(offs)) if offs else 0.0

    return {
        "band_px": band,
        "seam_lr": seam_lr,
        "interior_lr": interior_lr,
        "ratio_lr": seam_lr / interior_lr if interior_lr else float("nan"),
        "seam_tb": seam_tb,
        "interior_tb": interior_tb,
        "ratio_tb": seam_tb / interior_tb if interior_tb else float("nan"),
    }


def local_sharpness(a: np.ndarray) -> dict:
    """Mean |gradient| inside the border band vs the interior.

    Tileability blurring shows up as a border band that is markedly smoother
    than the middle of the tile.
    """
    g = lum(a)
    h, w = g.shape
    band = max(4, min(24, w // 16))
    gy, gx = np.gradient(g)
    mag = np.abs(gx) + np.abs(gy)
    inner = mag[band:-band, band:-band]
    border = np.concatenate([
        mag[:band, :].ravel(), mag[-band:, :].ravel(),
        mag[:, :band].ravel(), mag[:, -band:].ravel(),
    ])
    return {
        "band_px": band,
        "interior_grad": float(inner.mean()),
        "border_grad": float(border.mean()),
        "border_over_interior": float(border.mean() / inner.mean()) if inner.mean() else float("nan"),
    }


def composite(path: Path) -> None:
    im = Image.open(path)
    has_alpha = im.mode == "RGBA"
    rgb = im.convert("RGB")
    a = np.asarray(rgb).astype(np.float32) / 255.0

    tile = np.tile(a, (3, 3, 1))
    Image.fromarray((tile * 255).astype(np.uint8)).save(OUT / f"{path.stem}_3x3.png")

    # seam crop centred on the crossing of tile (1,1) -> its top-left corner
    h, w, _ = a.shape
    cs = 480
    cy, cx = h, w
    y0 = max(0, cy - cs // 2)
    x0 = max(0, cx - cs // 2)
    crop = tile[y0:y0 + cs, x0:x0 + cs]
    Image.fromarray((crop * 255).astype(np.uint8)).save(OUT / f"{path.stem}_seam.png")

    d = wrap_discontinuity(a)
    s = local_sharpness(a)
    l = lum(a)
    lines = [
        f"file {path}",
        f"size {im.size} mode {im.mode} alpha={has_alpha}",
        f"meanL {l.mean():.3f} p5 {np.percentile(l,5):.3f} p50 {np.percentile(l,50):.3f} p95 {np.percentile(l,95):.3f}",
        f"meanRGB {a.reshape(-1,3).mean(0).round(3)}",
        f"wrap_seam_lr {d['seam_lr']:.4f} interior_lr {d['interior_lr']:.4f} ratio {d['ratio_lr']:.2f} (band {d['band_px']}px)",
        f"wrap_seam_tb {d['seam_tb']:.4f} interior_tb {d['interior_tb']:.4f} ratio {d['ratio_tb']:.2f}",
        f"sharpness interior_grad {s['interior_grad']:.4f} border_grad {s['border_grad']:.4f} ratio {s['border_over_interior']:.2f} (band {s['band_px']}px)",
    ]
    txt = "\n".join(lines) + "\n"
    (OUT / f"{path.stem}_stats.txt").write_text(txt)
    print(txt)


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        composite(Path(arg))