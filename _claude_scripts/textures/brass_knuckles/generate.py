#!/usr/bin/env python3
"""
Brass Knuckles sprite generator for DEEP YELLOW
Generates a 64x64 PSX-style sprite of brass knuckles (BODY item)
"""
from PIL import Image, ImageDraw
import random
import math

SIZE = 64

# Brass/gold color palette
BRASS_DARK = (140, 110, 50)       # Dark brass shadows
BRASS_MID = (196, 168, 75)        # Mid brass tone
BRASS_LIGHT = (220, 190, 100)     # Light brass
BRASS_HIGHLIGHT = (255, 220, 130) # Bright metallic highlight
SHADOW = (80, 60, 30)             # Deep shadow areas

def add_grain(img, intensity=12):
    """Add PSX-style grain/noise to the image"""
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a > 0:
                noise = random.randint(-intensity, intensity)
                r = max(0, min(255, r + noise))
                g = max(0, min(255, g + noise))
                b = max(0, min(255, b + noise))
                pixels[x, y] = (r, g, b, a)

def draw_finger_hole(draw, center_x, center_y, width, height, fill_color):
    """Draw a rounded rectangular finger hole"""
    # Outer ring
    draw.ellipse(
        [center_x - width//2, center_y - height//2,
         center_x + width//2, center_y + height//2],
        fill=fill_color
    )
    # Inner hole (transparency)
    inner_width = int(width * 0.6)
    inner_height = int(height * 0.65)
    draw.ellipse(
        [center_x - inner_width//2, center_y - inner_height//2,
         center_x + inner_width//2, center_y + inner_height//2],
        fill=(0, 0, 0, 0)
    )
    # Inner shadow edge
    shadow_width = int(width * 0.62)
    shadow_height = int(height * 0.67)
    draw.ellipse(
        [center_x - shadow_width//2, center_y - shadow_height//2 + 1,
         center_x + shadow_width//2, center_y + shadow_height//2 + 1],
        fill=SHADOW + (180,), outline=None
    )

def draw_brass_knuckles():
    """Generate the brass knuckles sprite"""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # View from above at slight angle - 4 finger holes visible
    # Center the knuckles
    center_x = SIZE // 2
    center_y = SIZE // 2 - 2

    # Main body bar (horizontal piece across knuckles)
    bar_width = 48
    bar_height = 10
    bar_y = center_y + 8

    # Draw main bar with depth
    # Bottom shadow layer
    draw.rectangle(
        [center_x - bar_width//2, bar_y,
         center_x + bar_width//2, bar_y + bar_height],
        fill=BRASS_DARK + (255,)
    )

    # Mid layer
    draw.rectangle(
        [center_x - bar_width//2, bar_y - 1,
         center_x + bar_width//2, bar_y + bar_height - 2],
        fill=BRASS_MID + (255,)
    )

    # Top highlight
    draw.rectangle(
        [center_x - bar_width//2 + 2, bar_y - 1,
         center_x + bar_width//2 - 2, bar_y + 2],
        fill=BRASS_LIGHT + (255,)
    )

    # Draw 4 finger holes
    hole_spacing = 11
    hole_width = 9
    hole_height = 14

    # Starting position for first hole
    first_hole_x = center_x - (hole_spacing * 1.5)

    for i in range(4):
        hole_x = int(first_hole_x + i * hole_spacing)
        hole_y = center_y

        # Slight size variation for perspective (middle fingers slightly larger)
        if i == 1 or i == 2:
            w = hole_width + 1
            h = hole_height + 1
        else:
            w = hole_width
            h = hole_height

        draw_finger_hole(draw, hole_x, hole_y, w, h, BRASS_MID + (255,))

        # Add metallic highlight on top edge of each hole
        draw.ellipse(
            [hole_x - w//2 + 1, hole_y - h//2,
             hole_x + w//2 - 1, hole_y - h//2 + 2],
            fill=BRASS_HIGHLIGHT + (200,)
        )

    # Add side stabilizer bars (connect to palm grip)
    # Left side
    left_x = center_x - bar_width//2
    draw.polygon(
        [(left_x, bar_y),
         (left_x - 6, bar_y + 4),
         (left_x - 6, bar_y + bar_height + 2),
         (left_x, bar_y + bar_height)],
        fill=BRASS_DARK + (255,)
    )
    draw.polygon(
        [(left_x, bar_y - 1),
         (left_x - 6, bar_y + 3),
         (left_x - 6, bar_y + 4),
         (left_x, bar_y)],
        fill=BRASS_LIGHT + (240,)
    )

    # Right side
    right_x = center_x + bar_width//2
    draw.polygon(
        [(right_x, bar_y),
         (right_x + 6, bar_y + 4),
         (right_x + 6, bar_y + bar_height + 2),
         (right_x, bar_y + bar_height)],
        fill=BRASS_DARK + (255,)
    )
    draw.polygon(
        [(right_x, bar_y - 1),
         (right_x + 6, bar_y + 3),
         (right_x + 6, bar_y + 4),
         (right_x, bar_y)],
        fill=BRASS_LIGHT + (240,)
    )

    # Add rivets/studs for detail
    rivet_positions = [
        (center_x - 18, bar_y + bar_height//2),
        (center_x - 6, bar_y + bar_height//2),
        (center_x + 6, bar_y + bar_height//2),
        (center_x + 18, bar_y + bar_height//2),
    ]

    for rivet_x, rivet_y in rivet_positions:
        # Rivet body
        draw.ellipse(
            [rivet_x - 2, rivet_y - 2, rivet_x + 2, rivet_y + 2],
            fill=BRASS_DARK + (255,)
        )
        # Rivet highlight
        draw.ellipse(
            [rivet_x - 1, rivet_y - 2, rivet_x + 1, rivet_y - 1],
            fill=BRASS_HIGHLIGHT + (220,)
        )

    # Add metallic sheen across top
    draw.rectangle(
        [center_x - bar_width//2 + 4, bar_y - 2,
         center_x + bar_width//2 - 4, bar_y],
        fill=BRASS_HIGHLIGHT + (150,)
    )

    # Apply PSX-style grain
    add_grain(img, intensity=14)

    return img

def main():
    print("Generating Brass Knuckles sprite (64x64, PSX-style)...")
    print("- Warm brass/gold coloring")
    print("- 4 finger holes visible from above")
    print("- Metallic sheen with grain texture")

    img = draw_brass_knuckles()
    img.save('output.png', 'PNG')

    print("✓ Generated: output.png")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print("  Format: RGBA (transparent background)")

if __name__ == '__main__':
    main()
