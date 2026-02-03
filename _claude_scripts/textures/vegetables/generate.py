"""
Generate a 64x64 PSX-style pixel art sprite of a brown paper bag with vegetables.
"""

from PIL import Image, ImageDraw

# Canvas size
SIZE = 64

# Color palette (PSX-style limited colors)
TRANSPARENT = (0, 0, 0, 0)
BAG_DARK = (101, 67, 33, 255)      # Dark brown for bag shadows
BAG_MID = (139, 90, 43, 255)        # Medium brown for bag body
BAG_LIGHT = (181, 136, 99, 255)     # Light brown for bag highlights
CARROT_ORANGE = (230, 126, 34, 255) # Orange for carrot
CARROT_DARK = (175, 96, 26, 255)    # Dark orange for carrot shading
CARROT_GREEN = (46, 125, 50, 255)   # Green for carrot top
CELERY_GREEN = (139, 195, 74, 255)  # Light green for celery
CELERY_DARK = (85, 139, 47, 255)    # Dark green for celery shading
TOMATO_RED = (211, 47, 47, 255)     # Red for tomato
TOMATO_DARK = (136, 14, 79, 255)    # Dark red for tomato shading
TOMATO_SHINE = (239, 154, 154, 255) # Light red for tomato highlight

# Create transparent canvas
img = Image.new('RGBA', (SIZE, SIZE), TRANSPARENT)
pixels = img.load()

def draw_rect(x1, y1, x2, y2, color):
    """Draw a filled rectangle."""
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                pixels[x, y] = color

def draw_pixel(x, y, color):
    """Draw a single pixel."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        pixels[x, y] = color

def draw_line(x1, y1, x2, y2, color, thickness=1):
    """Draw a line using Bresenham's algorithm."""
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx - dy

    while True:
        for t in range(thickness):
            draw_pixel(x1 + t, y1, color)
            if thickness > 1:
                draw_pixel(x1, y1 + t, color)

        if x1 == x2 and y1 == y2:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x1 += sx
        if e2 < dx:
            err += dx
            y1 += sy

# --- Draw Brown Paper Bag ---
# MUCH SHORTER BAG - only bottom 40% of sprite

# Main bag body (trapezoid shape - wider at top)
# Bottom of bag
draw_rect(22, 50, 42, 58, BAG_MID)

# Middle section
draw_rect(21, 42, 43, 49, BAG_MID)

# Top section (wider to show bag opening)
draw_rect(20, 32, 44, 41, BAG_MID)

# Bag shadows (left side)
for y in range(32, 59):
    draw_pixel(20, y, BAG_DARK)
    draw_pixel(21, y, BAG_DARK)

# Bag highlights (right side)
for y in range(32, 59):
    draw_pixel(43, y, BAG_LIGHT)
    draw_pixel(44, y, BAG_LIGHT)

# Bottom shadow
draw_rect(22, 57, 42, 58, BAG_DARK)

# Top crumpled edge (irregular opening)
for x in range(20, 45):
    if x % 3 == 0:
        draw_pixel(x, 31, BAG_DARK)
        draw_pixel(x, 32, BAG_LIGHT)
    elif x % 3 == 1:
        draw_pixel(x, 32, BAG_MID)

# --- Draw Vegetables Poking Out ---
# MUCH LARGER VEGETABLES - these are the visual focus!

# CARROT (left side, orange with green top) - LARGE!
# Carrot greens (leafy top) - tall and prominent
draw_rect(22, 8, 24, 10, CARROT_GREEN)  # Left leaf cluster
draw_rect(25, 6, 27, 9, CARROT_GREEN)   # Middle leaf cluster (tallest)
draw_rect(28, 8, 29, 11, CARROT_GREEN)  # Right leaf cluster
# Extra leaf details
draw_pixel(23, 11, CARROT_GREEN)
draw_pixel(26, 10, CARROT_GREEN)

# Carrot body - thick and chunky
draw_rect(23, 12, 28, 14, CARROT_DARK)  # Top darker section
draw_rect(23, 15, 29, 20, CARROT_ORANGE)  # Main body
draw_rect(24, 21, 29, 25, CARROT_ORANGE)
draw_rect(25, 26, 28, 29, CARROT_ORANGE)
draw_pixel(26, 30, CARROT_ORANGE)
draw_pixel(27, 30, CARROT_ORANGE)
draw_pixel(27, 31, CARROT_DARK)

# Carrot shading (left side)
for y in range(15, 30):
    draw_pixel(23, y, CARROT_DARK)
for y in range(21, 26):
    draw_pixel(24, y, CARROT_DARK)

# CELERY (right side, green stalks) - TALL!
# Celery stalk 1 (left stalk)
draw_rect(38, 8, 40, 30, CELERY_GREEN)
draw_rect(38, 8, 40, 10, CELERY_DARK)  # Dark top
# Celery stalk 2 (right stalk, slightly taller)
draw_rect(42, 6, 44, 32, CELERY_GREEN)
draw_rect(42, 6, 44, 8, CELERY_DARK)  # Dark top
# Celery ridges/texture
for y in range(12, 32, 3):
    draw_pixel(38, y, CELERY_DARK)
    draw_pixel(42, y, CELERY_DARK)
    draw_pixel(39, y+1, CELERY_DARK)
    draw_pixel(43, y+1, CELERY_DARK)

# TOMATO (center, red and round) - BIG!
# Tomato body (more circular, larger)
draw_rect(31, 18, 36, 26, TOMATO_RED)  # Main body
# Expand for rounder shape
draw_rect(30, 20, 37, 24, TOMATO_RED)
draw_pixel(29, 21, TOMATO_RED)
draw_pixel(29, 22, TOMATO_RED)
draw_pixel(29, 23, TOMATO_RED)
draw_pixel(38, 21, TOMATO_RED)
draw_pixel(38, 22, TOMATO_RED)
draw_pixel(38, 23, TOMATO_RED)

# Tomato shading (bottom and left)
draw_rect(30, 25, 36, 26, TOMATO_DARK)
draw_rect(29, 23, 30, 24, TOMATO_DARK)
draw_pixel(31, 27, TOMATO_DARK)
draw_pixel(32, 27, TOMATO_DARK)
draw_pixel(33, 27, TOMATO_DARK)

# Tomato highlight (top right for contrast)
draw_rect(34, 18, 36, 19, TOMATO_SHINE)
draw_pixel(35, 20, TOMATO_SHINE)

# Tomato stem (green bit on top) - larger
draw_rect(32, 15, 35, 16, CARROT_GREEN)
draw_pixel(33, 14, CARROT_GREEN)
draw_pixel(34, 14, CARROT_GREEN)
draw_pixel(33, 17, CARROT_GREEN)

# --- Final Details ---

# Add some bag wrinkles/creases for texture (adjusted for shorter bag)
for y in range(38, 55, 8):
    draw_line(22, y, 42, y + 2, BAG_DARK, 1)

# Save output
img.save('output.png')
print("Generated 64x64 vegetables sprite at output.png")
print("Palette: 12 colors (brown paper bag + vegetables)")
print("Style: PSX-era pixel art with chunky pixels and clean silhouette")
