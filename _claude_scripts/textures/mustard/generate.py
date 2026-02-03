#!/usr/bin/env python3
"""
Generate a 64x64 pixel art sprite of a yellow mustard squeeze bottle.
PSX-era style with chunky pixels and limited palette.
"""

from PIL import Image, ImageDraw

# Canvas size
SIZE = 64

# Color palette (PSX-style limited colors)
TRANSPARENT = (0, 0, 0, 0)
OUTLINE = (40, 35, 30, 255)           # Dark brown outline
MUSTARD_BRIGHT = (255, 220, 0, 255)    # Bright yellow
MUSTARD_MID = (230, 190, 0, 255)       # Mid yellow
MUSTARD_DARK = (180, 150, 0, 255)      # Shadow yellow
CAP_HIGHLIGHT = (255, 240, 200, 255)   # Light cap highlight
CAP_MID = (240, 210, 150, 255)         # Cap mid tone
CAP_SHADOW = (200, 170, 120, 255)      # Cap shadow

# Create image
img = Image.new('RGBA', (SIZE, SIZE), TRANSPARENT)
pixels = img.load()

def draw_pixel(x, y, color):
    """Draw a single pixel if within bounds."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        pixels[x, y] = color

def draw_rect_filled(x1, y1, x2, y2, color):
    """Draw a filled rectangle."""
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            draw_pixel(x, y, color)

def draw_line_vertical(x, y1, y2, color):
    """Draw a vertical line."""
    for y in range(y1, y2 + 1):
        draw_pixel(x, y, color)

def draw_line_horizontal(x1, x2, y, color):
    """Draw a horizontal line."""
    for x in range(x1, x2 + 1):
        draw_pixel(x, y, color)

# Bottle dimensions (centered)
bottle_center_x = SIZE // 2

# Cap dimensions (tapered squeeze cap on top)
cap_top_y = 12
cap_bottom_y = 20
cap_width = 4

# Neck dimensions
neck_top_y = 20
neck_bottom_y = 24
neck_width = 6

# Body dimensions (wider, tapered bottle shape)
body_top_y = 24
body_mid_y = 40
body_bottom_y = 52
body_width_top = 10
body_width_mid = 14
body_width_bottom = 12

# --- DRAW MUSTARD BOTTLE ---

# 1. Draw bottle body outline and fill
# Top section (shoulders)
for y in range(body_top_y, body_mid_y):
    progress = (y - body_top_y) / (body_mid_y - body_top_y)
    width = int(body_width_top + (body_width_mid - body_width_top) * progress)
    half_width = width // 2

    # Fill body
    draw_line_horizontal(bottle_center_x - half_width + 1, bottle_center_x + half_width - 1, y, MUSTARD_MID)

    # Outline
    draw_pixel(bottle_center_x - half_width, y, OUTLINE)
    draw_pixel(bottle_center_x + half_width, y, OUTLINE)

# Mid to bottom section (taper back in)
for y in range(body_mid_y, body_bottom_y + 1):
    progress = (y - body_mid_y) / (body_bottom_y - body_mid_y)
    width = int(body_width_mid + (body_width_bottom - body_width_mid) * progress)
    half_width = width // 2

    # Fill body
    draw_line_horizontal(bottle_center_x - half_width + 1, bottle_center_x + half_width - 1, y, MUSTARD_MID)

    # Outline
    draw_pixel(bottle_center_x - half_width, y, OUTLINE)
    draw_pixel(bottle_center_x + half_width, y, OUTLINE)

# Bottom cap outline
half_bottom = body_width_bottom // 2
draw_line_horizontal(bottle_center_x - half_bottom, bottle_center_x + half_bottom, body_bottom_y, OUTLINE)

# 2. Draw neck
half_neck = neck_width // 2
for y in range(neck_top_y, neck_bottom_y + 1):
    draw_line_horizontal(bottle_center_x - half_neck + 1, bottle_center_x + half_neck - 1, y, CAP_MID)
    draw_pixel(bottle_center_x - half_neck, y, OUTLINE)
    draw_pixel(bottle_center_x + half_neck, y, OUTLINE)

# 3. Draw squeeze cap (tapered point)
for y in range(cap_top_y, cap_bottom_y + 1):
    progress = (y - cap_top_y) / (cap_bottom_y - cap_top_y)
    width = int(2 + cap_width * progress)
    half_width = width // 2

    # Fill cap
    draw_line_horizontal(bottle_center_x - half_width + 1, bottle_center_x + half_width - 1, y, CAP_MID)

    # Outline
    draw_pixel(bottle_center_x - half_width, y, OUTLINE)
    draw_pixel(bottle_center_x + half_width, y, OUTLINE)

# Top point
draw_pixel(bottle_center_x, cap_top_y - 1, OUTLINE)
draw_pixel(bottle_center_x, cap_top_y, CAP_HIGHLIGHT)

# 4. Add highlights (left side bright, right side dark for volume)
# Bottle body highlights
for y in range(body_top_y + 2, body_bottom_y - 2):
    progress = (y - body_top_y) / (body_bottom_y - body_top_y)

    if y < body_mid_y:
        width = int(body_width_top + (body_width_mid - body_width_top) * ((y - body_top_y) / (body_mid_y - body_top_y)))
    else:
        width = int(body_width_mid + (body_width_bottom - body_width_mid) * ((y - body_mid_y) / (body_bottom_y - body_mid_y)))

    half_width = width // 2

    # Left highlight (bright yellow)
    draw_pixel(bottle_center_x - half_width + 2, y, MUSTARD_BRIGHT)
    if half_width > 4:
        draw_pixel(bottle_center_x - half_width + 3, y, MUSTARD_BRIGHT)

    # Right shadow (dark yellow)
    draw_pixel(bottle_center_x + half_width - 2, y, MUSTARD_DARK)
    if half_width > 4:
        draw_pixel(bottle_center_x + half_width - 3, y, MUSTARD_DARK)

# 5. Cap highlights
for y in range(cap_top_y + 2, cap_bottom_y - 1):
    # Left highlight
    draw_pixel(bottle_center_x - 1, y, CAP_HIGHLIGHT)
    # Right shadow
    draw_pixel(bottle_center_x + 1, y, CAP_SHADOW)

# 6. Add label area suggestion (simple horizontal lines)
label_y = 34
draw_line_horizontal(bottle_center_x - 4, bottle_center_x + 4, label_y, MUSTARD_DARK)
draw_line_horizontal(bottle_center_x - 4, bottle_center_x + 4, label_y + 6, MUSTARD_DARK)

# Save output
output_path = 'output.png'
img.save(output_path)
print(f"✓ Generated mustard bottle sprite: {output_path}")
print(f"  Size: {SIZE}x{SIZE} RGBA")
print(f"  Style: PSX pixel art")
