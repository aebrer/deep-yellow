#!/usr/bin/env python3
"""Render atlas strips into a labelled contact sheet, exactly as the game draws them.

Why a sheet instead of looking at the strip PNG: the strip is one wide image whose frames
are invisible next to each other at a glance, and the game discards every pixel under
alpha 128 (Sprite3D.ALPHA_CUT_DISCARD). Previews here apply the same cut and composite onto
a dim room grey, so a frame that lost a limb, gained a black fin, or drifted off its floor
line is obvious before it is installed.

Usage: qa_sheet.py <out.png> [--cell 190] [--fps 3] <strip.png> [strip.png ...]
"""
import argparse
import os
import numpy as np
from PIL import Image, ImageDraw

ROOM = (38, 40, 44)  # dim floor/wall grey, close to the lit average of a level-0 room
ALPHA_CUT = 128  # billboards; floor decals cut at 26 (alpha_scissor 0.1)


def cut(im, threshold=ALPHA_CUT):
    a = np.array(im.convert("RGBA"))
    a[a[..., 3] >= threshold, 3] = 255
    a[a[..., 3] < threshold, 3] = 0
    return Image.fromarray(a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--cell", type=int, default=190)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--alpha-cut", type=int, default=ALPHA_CUT)
    ap.add_argument("strips", nargs="+")
    args = ap.parse_args()

    cell, cols = args.cell, args.cols
    rows = len(args.strips)
    sheet = Image.new("RGB", (cols * cell, rows * cell), ROOM)
    d = ImageDraw.Draw(sheet)
    for r, path in enumerate(args.strips):
        strip = Image.open(path)
        n = max(1, strip.width // strip.height)
        name = os.path.basename(path).replace("_strip.png", "")
        for c in range(cols):
            f = c % n
            frame = cut(strip.crop((f * strip.height, 0, (f + 1) * strip.height, strip.height))
                        .resize((cell, cell), Image.LANCZOS), args.alpha_cut)
            sheet.paste(frame, (c * cell, r * cell), frame)
        d.text((4, r * cell + 3), name, fill=(240, 240, 160))
    sheet.save(args.out)
    print(f"{args.out}: {rows} rows x {cols} frames")


if __name__ == "__main__":
    main()