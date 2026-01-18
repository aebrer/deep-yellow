#!/usr/bin/env python3
"""
Generate a 64x64 texture for the Antigonous Family Notebook.
Shows the whole notebook as an object - a dark, weathered leather journal
with occult geometric patterns on the cover, viewed from slightly above.
"""

from PIL import Image, ImageDraw
import numpy as np
import random

# Set random seed for reproducibility
random.seed(42)
np.random.seed(42)

SIZE = 64

# Create base image with dark background (table surface or void)
img = Image.new('RGB', (SIZE, SIZE), color=(15, 12, 10))
img_array = np.array(img, dtype=np.float32)

# Define notebook dimensions (showing whole book, not filling canvas)
# Book positioned slightly off-center for 3D effect
book_left = 8
book_top = 6
book_width = 44
book_height = 52
book_right = book_left + book_width
book_bottom = book_top + book_height

# Dark leather base color (deep brown)
base_r, base_g, base_b = 45, 30, 20

# Spine/side color (darker, showing depth)
spine_r, spine_g, spine_b = 25, 18, 12

# Page edge color (aged cream)
page_r, page_g, page_b = 220, 210, 180

# Draw spine/left edge (showing 3D depth)
spine_width = 4
for y in range(book_top, book_bottom):
    for x in range(book_left, book_left + spine_width):
        # Leather grain variation
        noise = np.random.normal(0, 6)

        # Gradient to show curvature
        gradient = (x - book_left) / spine_width

        r = max(0, min(255, (spine_r + noise) * (0.6 + gradient * 0.4)))
        g = max(0, min(255, (spine_g + noise) * (0.6 + gradient * 0.4)))
        b = max(0, min(255, (spine_b + noise) * (0.6 + gradient * 0.4)))

        img_array[y, x] = [r, g, b]

# Draw page edges on right side (showing it's a book with pages)
page_edge_width = 3
for y in range(book_top, book_bottom):
    for x in range(book_right - page_edge_width, book_right):
        # Subtle layering effect for pages
        layer_noise = np.random.normal(0, 3)

        r = max(0, min(255, page_r + layer_noise))
        g = max(0, min(255, page_g + layer_noise))
        b = max(0, min(255, page_b + layer_noise))

        img_array[y, x] = [r, g, b]

# Draw main cover surface
cover_left = book_left + spine_width
cover_width = book_width - spine_width - page_edge_width

for y in range(book_top, book_bottom):
    for x in range(cover_left, book_right - page_edge_width):
        # Leather grain variation
        noise = np.random.normal(0, 8)

        # Subtle lighting gradient (lighter at top-left)
        light_y = (y - book_top) / book_height
        light_x = (x - cover_left) / cover_width
        light_factor = 1.0 + (1.0 - (light_y * 0.5 + light_x * 0.3)) * 0.15

        # Weathering (random dark spots)
        weather = 1.0
        if random.random() < 0.03:
            weather = random.uniform(0.75, 0.92)

        r = max(0, min(255, (base_r + noise) * light_factor * weather))
        g = max(0, min(255, (base_g + noise) * light_factor * weather))
        b = max(0, min(255, (base_b + noise) * light_factor * weather))

        img_array[y, x] = [r, g, b]

# Convert to PIL for drawing symbols
img = Image.fromarray(img_array.astype(np.uint8))
draw = ImageDraw.Draw(img)

# Symbol color (faded gold/ochre for occult symbols)
symbol_color = (140, 100, 40)

# Center point of cover (not canvas center - cover center!)
cover_cx = cover_left + cover_width // 2
cover_cy = book_top + book_height // 2

# Draw occult circle pattern (scaled for cover size)
circle_radius = 12
draw.ellipse([cover_cx - circle_radius, cover_cy - circle_radius,
              cover_cx + circle_radius, cover_cy + circle_radius],
             outline=symbol_color, width=1)

# Inner circle
inner_radius = 9
draw.ellipse([cover_cx - inner_radius, cover_cy - inner_radius,
              cover_cx + inner_radius, cover_cy + inner_radius],
             outline=symbol_color, width=1)

# Draw triangle inside (pointed up - mystical symbol)
triangle_size = 7
triangle_points = [
    (cover_cx, cover_cy - triangle_size),  # Top point
    (cover_cx - triangle_size, cover_cy + int(triangle_size * 0.6)),  # Bottom left
    (cover_cx + triangle_size, cover_cy + int(triangle_size * 0.6)),  # Bottom right
]
draw.polygon(triangle_points, outline=symbol_color, width=1)

# Draw inverted triangle (creates hexagram/occult symbol)
inv_triangle_points = [
    (cover_cx, cover_cy + triangle_size),  # Bottom point
    (cover_cx - triangle_size, cover_cy - int(triangle_size * 0.6)),  # Top left
    (cover_cx + triangle_size, cover_cy - int(triangle_size * 0.6)),  # Top right
]
draw.polygon(inv_triangle_points, outline=symbol_color, width=1)

# Draw mysterious lines radiating from center
for angle in [0, 45, 90, 135]:
    rad = np.radians(angle)
    # Short lines from center
    x1 = int(cover_cx + np.cos(rad) * 3)
    y1 = int(cover_cy + np.sin(rad) * 3)
    x2 = int(cover_cx + np.cos(rad) * 6)
    y2 = int(cover_cy + np.sin(rad) * 6)
    draw.line([(x1, y1), (x2, y2)], fill=symbol_color, width=1)

# Add corner ornaments on cover (scaled for cover size)
corner_offset = 4
corner_size = 2
# Position corners relative to cover area, not canvas
corners = [
    (cover_left + corner_offset, book_top + corner_offset),
    (book_right - page_edge_width - corner_offset, book_top + corner_offset),
    (cover_left + corner_offset, book_bottom - corner_offset),
    (book_right - page_edge_width - corner_offset, book_bottom - corner_offset),
]

for corner_x, corner_y in corners:
    # Small cross/plus symbol
    draw.line([(corner_x - corner_size, corner_y),
               (corner_x + corner_size, corner_y)],
              fill=symbol_color, width=1)
    draw.line([(corner_x, corner_y - corner_size),
               (corner_x, corner_y + corner_size)],
              fill=symbol_color, width=1)

# Add some age spots and wear on cover only
img_array = np.array(img, dtype=np.float32)
for _ in range(20):
    spot_x = random.randint(cover_left, book_right - page_edge_width - 1)
    spot_y = random.randint(book_top, book_bottom - 1)
    spot_radius = random.randint(1, 2)

    for dy in range(-spot_radius, spot_radius + 1):
        for dx in range(-spot_radius, spot_radius + 1):
            if dx*dx + dy*dy <= spot_radius*spot_radius:
                y = spot_y + dy
                x = spot_x + dx
                if book_top <= y < book_bottom and cover_left <= x < book_right - page_edge_width:
                    # Darken slightly
                    img_array[y, x] *= random.uniform(0.8, 0.95)

# Add subtle shadow under/around book for depth
shadow_img = Image.fromarray(img_array.astype(np.uint8))
draw = ImageDraw.Draw(shadow_img)

# Bottom-right shadow
shadow_offset = 2
shadow_alpha = 0.4
for i in range(shadow_offset + 1):
    opacity = shadow_alpha * (1.0 - i / (shadow_offset + 1))
    shadow_color = tuple(int(c * (1.0 - opacity)) for c in (15, 12, 10))
    # Draw shadow lines
    draw.line([(book_left + i, book_bottom + i), (book_right + i, book_bottom + i)],
              fill=shadow_color, width=1)
    draw.line([(book_right + i, book_top + i), (book_right + i, book_bottom + i)],
              fill=shadow_color, width=1)

# Final output
shadow_img.save('output.png')
print("✓ Generated antigonous_notebook texture (64x64)")
print("  - Shows WHOLE notebook as object within frame")
print("  - Dark leather cover with spine and page edges visible")
print("  - Occult geometric symbols on cover (scaled appropriately)")
print("  - 3D depth with shadows and lighting")
print("  - Ancient, weathered appearance")
print("  Output: output.png")
