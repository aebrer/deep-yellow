#!/usr/bin/env python3
"""
Generate Bacteria Spreader entity texture for Backrooms Power Crawl.

The Bacteria Spreader: A support enemy that heals nearby bacteria.
Visually distinct from bacteria_spawn - more bulbous with spreading tendrils.
Darker, mottled green color scheme with golden-green spore cloud.
"""

from PIL import Image, ImageDraw
import math
import random
import numpy as np
from opensimplex import OpenSimplex

# Constants
SIZE = 64
OUTPUT_PATH = "output.png"

# Seed for reproducibility
random.seed(42)
np.random.seed(42)
noise_gen = OpenSimplex(seed=42)

# Create transparent background image (RGBA)
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Colors - darker, more sickly green
DARK_GREEN = (15, 50, 15, 255)
MID_GREEN = (30, 90, 30, 255)
LIGHT_GREEN = (50, 120, 50, 255)
HEAL_GLOW = (100, 180, 100, 180)  # Subtler healing glow
NUCLEUS = (40, 70, 40, 255)
GOLDEN_GREEN = (180, 200, 80, 255)  # Spore color

# Center of the entity
center_x = SIZE // 2
center_y = SIZE // 2

# Draw healing aura glow (outer ring)
for r in range(24, 20, -1):
    alpha = int(40 * (24 - r) / 4)
    glow_color = (100, 180, 100, alpha)
    draw.ellipse([center_x - r, center_y - r, center_x + r, center_y + r],
                 outline=glow_color, width=1)

# Draw main body
body_radius = 17
draw.ellipse([center_x - body_radius, center_y - body_radius,
              center_x + body_radius, center_y + body_radius],
             fill=MID_GREEN)

# Draw inner body gradient
inner_radius = 12
draw.ellipse([center_x - inner_radius, center_y - inner_radius,
              center_x + inner_radius, center_y + inner_radius],
             fill=LIGHT_GREEN)

# Draw spreading tendrils (6 directions)
num_tendrils = 6
tendril_length = 8
tendril_width = 3

for i in range(num_tendrils):
    angle = (2 * math.pi * i / num_tendrils) + math.pi / 6  # Offset for variety

    # Start from edge of body
    start_x = center_x + int(body_radius * 0.7 * math.cos(angle))
    start_y = center_y + int(body_radius * 0.7 * math.sin(angle))

    # End point
    end_x = center_x + int((body_radius + tendril_length) * math.cos(angle))
    end_y = center_y + int((body_radius + tendril_length) * math.sin(angle))

    # Draw tendril as tapered line
    draw.line([(start_x, start_y), (end_x, end_y)], fill=MID_GREEN, width=tendril_width)

    # Add blob at end of tendril
    blob_radius = 2
    draw.ellipse([end_x - blob_radius, end_y - blob_radius,
                  end_x + blob_radius, end_y + blob_radius],
                 fill=LIGHT_GREEN)

# Draw nucleus (darker center)
nucleus_radius = 5
draw.ellipse([center_x - nucleus_radius, center_y - nucleus_radius,
              center_x + nucleus_radius, center_y + nucleus_radius],
             fill=NUCLEUS)

# Draw inner detail - small healing symbol (plus sign)
plus_color = HEAL_GLOW
plus_size = 2
draw.line([(center_x - plus_size, center_y), (center_x + plus_size, center_y)],
          fill=plus_color, width=2)
draw.line([(center_x, center_y - plus_size), (center_x, center_y + plus_size)],
          fill=plus_color, width=2)

# Add some surface bubbles/spots for mottled texture
bubble_positions = [
    (center_x - 7, center_y - 6, 2),
    (center_x + 6, center_y - 5, 2),
    (center_x - 5, center_y + 7, 2),
    (center_x + 8, center_y + 4, 2),
    (center_x - 3, center_y - 10, 1),
    (center_x + 4, center_y + 9, 1),
]

for bx, by, br in bubble_positions:
    draw.ellipse([bx - br, by - br, bx + br, by + br], fill=DARK_GREEN)

# Convert to numpy array for noise application
img_array = np.array(img)

# Add base noise to non-transparent pixels
for y in range(SIZE):
    for x in range(SIZE):
        if img_array[y, x, 3] > 0:  # Only modify non-transparent pixels
            # Add random noise to RGB channels
            noise = np.random.randint(-15, 15, 3)
            for c in range(3):
                img_array[y, x, c] = np.clip(img_array[y, x, c] + noise[c], 0, 255)

# Add golden-green spore cloud using perlin noise
# Spores radiate from center with perlin-modulated density
spore_layer = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
noise_scale = 0.15  # Scale of perlin noise

for y in range(SIZE):
    for x in range(SIZE):
        # Distance from center
        dx = x - center_x
        dy = y - center_y
        dist = math.sqrt(dx * dx + dy * dy)

        # Only add spores in a ring around the body (not too close, not too far)
        if 8 < dist < 28:
            # Perlin noise value at this position
            noise_val = noise_gen.noise2(x * noise_scale, y * noise_scale)
            noise_val = (noise_val + 1) / 2  # Normalize to 0-1

            # Fade based on distance from optimal ring (around radius 18)
            dist_factor = 1.0 - abs(dist - 18) / 10
            dist_factor = max(0, min(1, dist_factor))

            # Combined probability
            spore_prob = noise_val * dist_factor * 0.7

            if random.random() < spore_prob:
                # Add a golden-green spore pixel
                alpha = int(150 + random.randint(-50, 50))
                alpha = max(80, min(220, alpha))
                spore_layer[y, x] = [GOLDEN_GREEN[0] + random.randint(-20, 20),
                                     GOLDEN_GREEN[1] + random.randint(-20, 20),
                                     GOLDEN_GREEN[2] + random.randint(-20, 20),
                                     alpha]

# Composite spore layer on top
for y in range(SIZE):
    for x in range(SIZE):
        if spore_layer[y, x, 3] > 0:
            # Alpha blend
            src_alpha = spore_layer[y, x, 3] / 255.0
            dst_alpha = img_array[y, x, 3] / 255.0

            if dst_alpha == 0:
                # No existing pixel, just use spore
                img_array[y, x] = spore_layer[y, x]
            else:
                # Blend on top
                out_alpha = src_alpha + dst_alpha * (1 - src_alpha)
                for c in range(3):
                    img_array[y, x, c] = int(
                        (spore_layer[y, x, c] * src_alpha +
                         img_array[y, x, c] * dst_alpha * (1 - src_alpha)) / out_alpha
                    )
                img_array[y, x, 3] = int(out_alpha * 255)

# Convert back to PIL Image
img = Image.fromarray(img_array, 'RGBA')

# Save the texture
img.save(OUTPUT_PATH)
print(f"✓ Generated Bacteria Spreader texture: {OUTPUT_PATH}")
print(f"  Size: {SIZE}x{SIZE} RGBA (transparent background)")
print(f"  Features: Bulbous body + spreading tendrils + healing glow")
