"""Emit shuffled, neutrally-named game-resolution panels for a blinded review.

Panels go through game_sim, so a reviewer sees the texture at the resolution the
floor shader samples it at, with no filename or ordering hints. Pass subjects as
label=path pairs; a path may be "floor.png+decal.png" to composite a floor decal
onto one tile of its own floor, which is how the exit hole is drawn.

Prints the label key as JSON, so the mapping can stay out of the reviewer's prompt.
"""
import json
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from game_sim import snap_sample  # noqa: E402


def tex(path):
    return snap_sample(np.asarray(Image.open(path).convert("RGB")), 128)


def upscale(g, reps=4, factor=2):
    return np.asarray(Image.fromarray(g).resize((g.shape[1] * factor, g.shape[0] * factor),
                                                Image.NEAREST))


def build(spec):
    if "+" in spec:
        floor_path, decal_path = spec.split("+")
        g = np.tile(tex(floor_path), (4, 4, 1))
        g[128:256, 128:256] = tex(decal_path)
        return g
    return np.tile(tex(spec), (4, 4, 1))


def main(out_dir, prefix, specs, seed=7):
    panels = {}
    for s in specs:
        label, path = s.split("=", 1)
        panels[label] = build(path)

    order = sorted(panels)
    random.Random(seed).shuffle(order)
    key = {}
    for i, label in enumerate(order, 1):
        name = f"{prefix}{i}.png"
        Image.fromarray(upscale(panels[label])).save(f"{out_dir}/{name}")
        key[name] = label
    print(json.dumps(key, indent=1))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])