#!/usr/bin/env python3
"""
Generate Smiler entity texture for DEEP YELLOW.

The Smiler: A classic Backrooms entity - glowing eyes and an unnerving
wide smile floating in darkness.
"""

from PIL import Image, ImageDraw

# Constants
SIZE = 64
OUTPUT_PATH = "output.png"

# Create transparent background image (RGBA)
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Define entity features (scaled for 64x64)
# Eyes: positioned in upper third, glowing white-yellow
eye_y = 16
eye_left_x = 18
eye_right_x = 46
eye_width = 6
eye_height = 8

# Smile: wide crescent in lower half
smile_center_x = SIZE // 2
smile_center_y = 38
smile_width = 42
smile_height = 16

# Draw glowing eyes with slight glow effect
def draw_glowing_eye(x, y, width, height):
    # Outer glow (faint yellow)
    glow_color = (100, 100, 60, 255)
    draw.ellipse([x - width//2 - 2, y - height//2 - 2,
                  x + width//2 + 2, y + height//2 + 2],
                 fill=glow_color)

    # Mid glow (brighter)
    glow_color2 = (180, 180, 120, 255)
    draw.ellipse([x - width//2 - 1, y - height//2 - 1,
                  x + width//2 + 1, y + height//2 + 1],
                 fill=glow_color2)

    # Core (bright yellow-white)
    core_color = (250, 250, 200, 255)
    draw.ellipse([x - width//2, y - height//2,
                  x + width//2, y + height//2],
                 fill=core_color)

# Draw both eyes
draw_glowing_eye(eye_left_x, eye_y, eye_width, eye_height)
draw_glowing_eye(eye_right_x, eye_y, eye_width, eye_height)

# Draw the smile with visible teeth - organic half-moon curve
import math

num_teeth = 12
tooth_width = 4
tooth_height = 8

# Use a smooth arc (half moon) for tooth positions
tooth_positions = []
for i in range(num_teeth):
    # Angle along a half-circle arc (pi radians = 180 degrees)
    # Goes from left to right
    angle = math.pi * (1 - i / (num_teeth - 1))  # pi to 0

    # X and Y follow circular arc (positive sin for upward smile)
    x = smile_center_x + (smile_width / 2) * math.cos(angle)
    y = smile_center_y + (smile_height * 0.8) * math.sin(angle)

    tooth_positions.append((x, y))

    # Draw each tooth as bright white rectangle
    draw.rectangle(
        [x - tooth_width//2, y - tooth_height//2,
         x + tooth_width//2, y + tooth_height//2],
        fill=(255, 255, 255, 255)
    )

# Draw white outline along top of smile for consistency
for i in range(len(tooth_positions) - 1):
    x1, y1 = tooth_positions[i]
    x2, y2 = tooth_positions[i + 1]
    draw.line(
        [(x1, y1 - tooth_height//2), (x2, y2 - tooth_height//2)],
        fill=(255, 255, 255, 255),
        width=2
    )

# Draw vertical black lines between teeth
for i in range(num_teeth - 1):
    x1, y1 = tooth_positions[i]
    x2, y2 = tooth_positions[i + 1]

    gap_x = (x1 + x2) / 2
    gap_y = (y1 + y2) / 2

    draw.line(
        [(gap_x, gap_y - tooth_height//2 + 1), (gap_x, gap_y + tooth_height//2)],
        fill=(0, 0, 0, 255),
        width=1
    )

# Draw horizontal black line in the middle to show two rows of teeth
for i in range(len(tooth_positions) - 1):
    x1, y1 = tooth_positions[i]
    x2, y2 = tooth_positions[i + 1]
    draw.line(
        [(x1, y1), (x2, y2)],
        fill=(0, 0, 0, 255),
        width=1
    )

# Save the texture
img.save(OUTPUT_PATH)
print(f"✓ Generated Smiler texture: {OUTPUT_PATH}")
print(f"  Size: {SIZE}x{SIZE} RGBA (transparent background)")
print(f"  Features: Glowing eyes + white smile with black tooth lines")
