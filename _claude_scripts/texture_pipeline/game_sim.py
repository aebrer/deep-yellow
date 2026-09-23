"""Preview a texture exactly as the floor shader samples it.

psx_base snaps albedo UVs to an N-texel grid per texture repeat and samples with
filter_nearest, so the renderer reads texel centres on a fixed stride rather than
an anti-aliased downsample. Resizing with a filtering resampler here hides the
moire the player would actually see.
"""
import numpy as np
from PIL import Image


def snap_sample(tex: np.ndarray, snap: int = 128) -> np.ndarray:
    h, w, _ = tex.shape
    idx_y = np.clip((np.arange(snap) + 0.5) * h / snap, 0, h - 1).astype(int)
    idx_x = np.clip((np.arange(snap) + 0.5) * w / snap, 0, w - 1).astype(int)
    return tex[np.ix_(idx_y, idx_x)]


def tiled(tex_path: str, snap: int = 128, reps: int = 4, upscale: int = 2) -> np.ndarray:
    tex = np.asarray(Image.open(tex_path).convert("RGB"))
    cell = snap_sample(tex, snap)
    grid = np.tile(cell, (reps, reps, 1))
    return np.asarray(Image.fromarray(grid).resize(
            (grid.shape[1] * upscale, grid.shape[0] * upscale), Image.NEAREST))
