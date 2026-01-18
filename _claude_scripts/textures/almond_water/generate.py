#!/usr/bin/env python3
"""
Generate a 32x32 pixel art texture for Almond Water.
An iconic Backrooms item - a plastic water bottle with slightly cloudy/milky water.
"""

from PIL import Image, ImageDraw
import numpy as np

# Output configuration
SIZE = 32
OUTPUT_PATH = "output.png"

# Color palette (RGBA)
TRANSPARENT = (0, 0, 0, 0)
BOTTLE_LIGHT = (200, 220, 235, 180)  # Light blue-white translucent plastic
BOTTLE_MID = (160, 190, 210, 200)    # Slightly darker plastic
BOTTLE_DARK = (120, 150, 180, 220)   # Bottle outline/shadows
CAP_BASE = (80, 100, 120, 255)       # Cap color (grayish blue)
CAP_DARK = (50, 70, 90, 255)         # Cap shadow
WATER_LIGHT = (245, 240, 230, 200)   # Light almond/milky color
WATER_MID = (230, 220, 200, 220)     # Medium almond color
WATER_DARK = (210, 195, 170, 230)    # Darker almond color (bottom)
HIGHLIGHT = (255, 255, 255, 150)     # Shine/highlight on bottle

def create_almond_water_bottle():
    """Create a pixel art water bottle with almond-colored water."""

    # Create image with transparency
    img = Image.new('RGBA', (SIZE, SIZE), TRANSPARENT)
    pixels = img.load()

    # Bottle dimensions (centered, vertical bottle)
    bottle_width = 12
    bottle_height = 22
    bottle_x = (SIZE - bottle_width) // 2  # Center horizontally
    bottle_y = 8  # Start a bit from top for cap

    # Cap dimensions
    cap_width = 10
    cap_height = 4
    cap_x = (SIZE - cap_width) // 2
    cap_y = 5

    # Draw bottle outline first (dark)
    for y in range(bottle_y, bottle_y + bottle_height):
        for x in range(bottle_x, bottle_x + bottle_width):
            # Bottle shape - slightly narrower at neck
            if y < bottle_y + 4:  # Neck area
                neck_width = 8
                neck_x = (SIZE - neck_width) // 2
                if neck_x <= x < neck_x + neck_width:
                    pixels[x, y] = BOTTLE_DARK
            else:
                # Main body
                if x == bottle_x or x == bottle_x + bottle_width - 1:
                    pixels[x, y] = BOTTLE_DARK  # Side outline
                elif y == bottle_y + bottle_height - 1:
                    pixels[x, y] = BOTTLE_DARK  # Bottom outline

    # Fill bottle body with translucent plastic
    for y in range(bottle_y + 1, bottle_y + bottle_height - 1):
        for x in range(bottle_x + 1, bottle_x + bottle_width - 1):
            if y < bottle_y + 4:  # Neck
                neck_width = 8
                neck_x = (SIZE - neck_width) // 2
                if neck_x < x < neck_x + neck_width - 1:
                    pixels[x, y] = BOTTLE_MID
            else:
                pixels[x, y] = BOTTLE_LIGHT

    # Draw almond water inside bottle
    water_start_y = bottle_y + 5  # Start below neck
    water_end_y = bottle_y + bottle_height - 2
    water_height = water_end_y - water_start_y

    for y in range(water_start_y, water_end_y):
        for x in range(bottle_x + 2, bottle_x + bottle_width - 2):
            # Gradient from lighter at top to slightly darker at bottom
            progress = (y - water_start_y) / water_height

            if progress < 0.3:
                pixels[x, y] = WATER_LIGHT
            elif progress < 0.7:
                pixels[x, y] = WATER_MID
            else:
                pixels[x, y] = WATER_DARK

            # Add some subtle variation for cloudiness
            if (x + y) % 3 == 0:
                r, g, b, a = pixels[x, y]
                pixels[x, y] = (r - 5, g - 5, b - 3, a)

    # Draw cap
    for y in range(cap_y, cap_y + cap_height):
        for x in range(cap_x, cap_x + cap_width):
            # Cap outline
            if y == cap_y or y == cap_y + cap_height - 1 or x == cap_x or x == cap_x + cap_width - 1:
                pixels[x, y] = CAP_DARK
            else:
                # Slight gradient on cap
                if x < cap_x + cap_width // 2:
                    pixels[x, y] = CAP_BASE
                else:
                    pixels[x, y] = CAP_DARK

    # Add highlight shine on left side of bottle
    highlight_x = bottle_x + 2
    for y in range(bottle_y + 6, bottle_y + 16):
        if y % 2 == 0:  # Dashed highlight
            pixels[highlight_x, y] = HIGHLIGHT
            if y < bottle_y + 12:
                pixels[highlight_x + 1, y] = HIGHLIGHT

    # Add subtle bottom reflection/shadow
    shadow_y = bottle_y + bottle_height
    for x in range(bottle_x + 2, bottle_x + bottle_width - 2):
        if pixels[x, shadow_y] == TRANSPARENT:
            pixels[x, shadow_y] = (100, 100, 100, 80)

    return img

def main():
    """Generate the almond water texture."""
    print("Generating 32x32 Almond Water bottle texture...")

    # Generate the texture
    img = create_almond_water_bottle()

    # Save the output
    img.save(OUTPUT_PATH, 'PNG')
    print(f"✓ Texture saved to {OUTPUT_PATH}")
    print(f"  Size: {img.size[0]}x{img.size[1]} pixels")
    print(f"  Mode: {img.mode}")

    # Verify file exists
    import os
    if os.path.exists(OUTPUT_PATH):
        file_size = os.path.getsize(OUTPUT_PATH)
        print(f"  File size: {file_size} bytes")
    else:
        print("✗ Error: Output file was not created!")
        return 1

    return 0

if __name__ == "__main__":
    exit(main())
