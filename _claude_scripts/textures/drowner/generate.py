#!/usr/bin/env python3
"""Generate a PSX-style Drowner enemy sprite."""

import os
from PIL import Image, ImageDraw

# Canvas setup
SIZE = 64
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# PSX-style limited palette (dark blue-black submerged tones)
PALETTE = {
    "deep_black": (5, 8, 18, 255),
    "dark_navy": (12, 20, 40, 255),
    "mid_navy": (22, 35, 60, 255),
    "drown_blue": (30, 50, 80, 255),
    "highlight": (45, 70, 100, 255),
    "submerged_fade": (15, 25, 45, 180),
    "eye_glow": (60, 90, 120, 200),
}

# Helper to draw low-poly style polygons
def poly(color, *points):
    draw.polygon(points, fill=color)

# === BODY / TORSO ===
# Main torso - broad at shoulders, tapers down (submerged feel)
poly(PALETTE["deep_black"], (28, 18), (36, 18), (38, 32), (34, 44), (30, 44), (26, 32))
poly(PALETTE["dark_navy"], (30, 20), (34, 20), (36, 30), (33, 40), (31, 40), (28, 30))

# === HEAD ===
# Slightly oversized head, tilted forward
poly(PALETTE["deep_black"], (29, 8), (35, 8), (37, 16), (34, 20), (30, 20), (27, 16))
poly(PALETTE["dark_navy"], (30, 10), (34, 10), (35, 15), (33, 18), (31, 18), (29, 15))

# Eyes - faint glowing slits
poly(PALETTE["eye_glow"], (30, 13), (31, 13), (31, 14), (30, 14))
poly(PALETTE["eye_glow"], (33, 13), (34, 13), (34, 14), (33, 14))

# === LEFT ARM (viewer's left) ===
# Reaching out and down - segmented low-poly style
# Upper arm
poly(PALETTE["deep_black"], (28, 20), (22, 26), (18, 34), (20, 36), (26, 30), (29, 22))
poly(PALETTE["dark_navy"], (27, 21), (23, 26), (20, 32), (22, 33), (26, 28), (28, 22))

# Forearm - extends further out, fingers implied
poly(PALETTE["deep_black"], (20, 34), (12, 40), (10, 46), (14, 48), (20, 42), (22, 36))
poly(PALETTE["mid_navy"], (19, 35), (14, 40), (12, 44), (15, 45), (19, 41), (20, 36))

# === RIGHT ARM (viewer's right) ===
# Reaching across slightly
poly(PALETTE["deep_black"], (36, 20), (42, 26), (46, 34), (44, 36), (38, 30), (35, 22))
poly(PALETTE["dark_navy"], (37, 21), (41, 26), (44, 32), (42, 33), (38, 28), (36, 22))

# Forearm
poly(PALETTE["deep_black"], (44, 34), (52, 40), (54, 46), (50, 48), (44, 42), (42, 36))
poly(PALETTE["mid_navy"], (45, 35), (50, 40), (52, 44), (49, 45), (45, 41), (44, 36))

# === SUBMERGED DETAILS ===
# Suggest waterline / wet sheen on shoulders
poly(PALETTE["highlight"], (28, 19), (36, 19), (35, 21), (29, 21))

# Chest highlight - ribcage suggestion
poly(PALETTE["mid_navy"], (30, 24), (34, 24), (33, 28), (31, 28))
poly(PALETTE["drown_blue"], (31, 25), (33, 25), (32, 27), (32, 27))

# Lower body fading into water - use translucent overlay
poly(PALETTE["submerged_fade"], (28, 38), (36, 38), (38, 50), (34, 56), (30, 56), (26, 50))
poly(PALETTE["dark_navy"], (30, 40), (34, 40), (35, 48), (32, 52), (30, 52), (27, 48))

# === WATER RIPPLE EFFECTS (subtle, around figure) ===
# Small pixel clusters to suggest disturbed water surface
poly(PALETTE["submerged_fade"], (22, 48), (24, 48), (24, 49), (22, 49))
poly(PALETTE["submerged_fade"], (40, 50), (42, 50), (42, 51), (40, 51))
poly(PALETTE["submerged_fade"], (30, 54), (33, 54), (33, 55), (30, 55))
poly(PALETTE["submerged_fade"], (16, 44), (18, 44), (18, 45), (16, 45))
poly(PALETTE["submerged_fade"], (46, 46), (48, 46), (48, 47), (46, 47))

# Additional arm submerged fade
poly(PALETTE["submerged_fade"], (12, 44), (16, 48), (14, 50), (10, 46))
poly(PALETTE["submerged_fade"], (48, 44), (52, 48), (50, 50), (46, 46))

# === PSX STYLE PIXEL DITHERING / NOISE ===
# Add some single-pixel highlights for that PSX affine-texture look
psx_pixels = [
    (29, 12, PALETTE["highlight"]),
    (35, 11, PALETTE["highlight"]),
    (25, 28, PALETTE["mid_navy"]),
    (39, 29, PALETTE["mid_navy"]),
    (31, 35, PALETTE["drown_blue"]),
    (33, 36, PALETTE["drown_blue"]),
    (20, 38, PALETTE["mid_navy"]),
    (44, 38, PALETTE["mid_navy"]),
    (28, 46, PALETTE["submerged_fade"]),
    (36, 47, PALETTE["submerged_fade"]),
]

for x, y, col in psx_pixels:
    img.putpixel((x, y), col)

# === FINAL PSX POST-PROCESS ===
# Slight color banding simulation by posterizing alpha and colors
# (Keep it subtle - just reduce color depth slightly)

def posterize(value, bits=5):
    """Reduce color precision to simulate PSX color depth."""
    return (value >> (8 - bits)) << (8 - bits)

pixels = img.load()
for y in range(SIZE):
    for x in range(SIZE):
        r, g, b, a = pixels[x, y]
        if a > 0:
            pixels[x, y] = (
                posterize(r),
                posterize(g),
                posterize(b),
                posterize(a, 4) if a < 255 else 255,
            )

# Save output
output_dir = os.path.dirname(os.path.abspath(__file__))
output_path = os.path.join(output_dir, "output.png")
img.save(output_path)

print(f"Saved Drowner sprite to: {output_path}")
print(f"Size: {img.size}, Mode: {img.mode}")
