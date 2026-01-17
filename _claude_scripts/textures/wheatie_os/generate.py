#!/usr/bin/env python3
"""
Wheatie-O's Cereal Box Texture Generator
PSX-style 64x64 pixel texture with dithering and grain
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
import random

# Configuration
SIZE = 64
OUTPUT_PATH = "output.png"

# PSX-era limited color palette (warm cereal box colors)
COLORS = {
    'orange_bright': (255, 140, 40),
    'orange_mid': (220, 100, 20),
    'orange_dark': (180, 70, 10),
    'yellow_bright': (255, 220, 80),
    'yellow_mid': (230, 180, 40),
    'red_bright': (240, 80, 60),
    'red_dark': (160, 40, 30),
    'brown_light': (180, 120, 70),
    'brown_dark': (100, 60, 30),
    'wheat_tan': (220, 200, 140),
    'wheat_dark': (160, 140, 80),
    'white': (240, 235, 220),
    'black': (20, 15, 10),
}

def apply_dithering(img_array, intensity=0.3):
    """Apply ordered dithering for PSX aesthetic"""
    # Bayer matrix for dithering
    bayer = np.array([
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5]
    ]) / 16.0

    h, w = img_array.shape[:2]
    for y in range(h):
        for x in range(w):
            threshold = bayer[y % 4, x % 4] * intensity * 255
            for c in range(3):  # RGB channels
                if random.random() < 0.5:
                    img_array[y, x, c] = np.clip(img_array[y, x, c] + threshold - (intensity * 255 / 2), 0, 255)
    return img_array

def add_grain(img_array, intensity=0.15):
    """Add film grain for PSX texture feel"""
    noise = np.random.normal(0, intensity * 255, img_array.shape)
    img_array = np.clip(img_array + noise, 0, 255).astype(np.uint8)
    return img_array

def draw_box_shape(draw, colors):
    """Draw the cereal box base shape with perspective"""
    # Box front face (slightly trapezoidal for perspective)
    box_points = [
        (10, 8),   # top-left
        (54, 8),   # top-right
        (58, 60),  # bottom-right
        (6, 60)    # bottom-left
    ]

    # Background (orange gradient effect with horizontal bands)
    for i in range(len(box_points) - 1):
        y_start = box_points[0][1]
        y_end = box_points[3][1]
        for y in range(y_start, y_end, 2):
            progress = (y - y_start) / (y_end - y_start)
            if progress < 0.3:
                color = colors['orange_bright']
            elif progress < 0.6:
                color = colors['orange_mid']
            else:
                color = colors['orange_dark']

            # Calculate x positions at this y
            x_left = 10 - int(4 * progress)
            x_right = 54 + int(4 * progress)
            draw.line([(x_left, y), (x_right, y)], fill=color, width=2)

    # Draw box outline
    draw.polygon(box_points, outline=colors['brown_dark'])

    # Add crumple lines (worn effect)
    crumple_lines = [
        [(20, 10), (22, 35)],
        [(45, 15), (43, 40)],
        [(15, 35), (50, 38)],
    ]
    for line in crumple_lines:
        draw.line(line, fill=colors['brown_dark'], width=1)

def draw_mascot(draw, colors):
    """Draw the muscular wheat stalk mascot"""
    # Mascot position (center-right of box)
    center_x, center_y = 38, 30

    # Body (thick wheat stalk - muscular!)
    body_color = colors['wheat_tan']
    shadow_color = colors['wheat_dark']

    # Main stalk (thick for muscles)
    draw.rectangle([center_x - 4, center_y, center_x + 4, center_y + 20],
                   fill=body_color, outline=shadow_color)

    # "Muscles" - shading on one side
    draw.rectangle([center_x + 2, center_y + 2, center_x + 4, center_y + 18],
                   fill=shadow_color)

    # Arms (flexing!)
    # Left arm
    draw.ellipse([center_x - 10, center_y + 5, center_x - 4, center_y + 11],
                 fill=body_color, outline=shadow_color)
    # Right arm
    draw.ellipse([center_x + 4, center_y + 5, center_x + 10, center_y + 11],
                 fill=body_color, outline=shadow_color)

    # Wheat head (spiky hair-like wheat grains on top)
    for i in range(5):
        x_offset = (i - 2) * 2
        grain_y = center_y - 3 - (abs(i - 2))
        draw.line([(center_x + x_offset, grain_y),
                   (center_x + x_offset, center_y - 1)],
                  fill=colors['yellow_mid'], width=1)
        # Grain tip
        draw.point((center_x + x_offset, grain_y - 1), fill=colors['yellow_bright'])

    # Face (simple but with a grin)
    face_y = center_y + 6
    # Eyes
    draw.point((center_x - 2, face_y), fill=colors['black'])
    draw.point((center_x + 2, face_y), fill=colors['black'])
    # Grin (curved smile)
    smile_points = [
        (center_x - 2, face_y + 3),
        (center_x, face_y + 4),
        (center_x + 2, face_y + 3)
    ]
    draw.line(smile_points, fill=colors['black'], width=1)

def draw_text_logo(draw, colors):
    """Draw the Wheatie-O's logo"""
    # Title area (top of box with banner)
    banner_y = 12

    # Banner background
    draw.rectangle([12, banner_y, 52, banner_y + 12],
                   fill=colors['red_bright'], outline=colors['red_dark'])

    # "WHEATIE-O'S" - draw pixel by pixel for control
    # Simplified letter forms at tiny scale
    # W
    draw.line([(14, banner_y + 2), (14, banner_y + 10)], fill=colors['white'])
    draw.line([(15, banner_y + 10), (16, banner_y + 6)], fill=colors['white'])
    draw.line([(16, banner_y + 6), (17, banner_y + 10)], fill=colors['white'])
    draw.line([(17, banner_y + 10), (18, banner_y + 2)], fill=colors['white'])

    # H
    draw.line([(19, banner_y + 2), (19, banner_y + 10)], fill=colors['white'])
    draw.line([(19, banner_y + 6), (21, banner_y + 6)], fill=colors['white'])
    draw.line([(21, banner_y + 2), (21, banner_y + 10)], fill=colors['white'])

    # E
    draw.line([(22, banner_y + 2), (22, banner_y + 10)], fill=colors['white'])
    draw.line([(22, banner_y + 2), (24, banner_y + 2)], fill=colors['white'])
    draw.line([(22, banner_y + 6), (24, banner_y + 6)], fill=colors['white'])
    draw.line([(22, banner_y + 10), (24, banner_y + 10)], fill=colors['white'])

    # A
    draw.line([(25, banner_y + 10), (26, banner_y + 2)], fill=colors['white'])
    draw.line([(26, banner_y + 2), (27, banner_y + 10)], fill=colors['white'])
    draw.line([(25, banner_y + 6), (27, banner_y + 6)], fill=colors['white'])

    # T
    draw.line([(28, banner_y + 2), (30, banner_y + 2)], fill=colors['white'])
    draw.line([(29, banner_y + 2), (29, banner_y + 10)], fill=colors['white'])

    # I
    draw.line([(31, banner_y + 2), (31, banner_y + 10)], fill=colors['white'])

    # E
    draw.line([(32, banner_y + 2), (32, banner_y + 10)], fill=colors['white'])
    draw.line([(32, banner_y + 2), (34, banner_y + 2)], fill=colors['white'])
    draw.line([(32, banner_y + 6), (34, banner_y + 6)], fill=colors['white'])
    draw.line([(32, banner_y + 10), (34, banner_y + 10)], fill=colors['white'])

    # -O'S (simplified as "OS")
    draw.ellipse([35, banner_y + 4, 38, banner_y + 9],
                 outline=colors['white'], fill=None)

    draw.line([(39, banner_y + 3), (40, banner_y + 2)], fill=colors['white'])
    draw.line([(40, banner_y + 2), (42, banner_y + 2)], fill=colors['white'])
    draw.line([(39, banner_y + 6), (42, banner_y + 6)], fill=colors['white'])
    draw.line([(39, banner_y + 10), (42, banner_y + 10)], fill=colors['white'])
    draw.line([(42, banner_y + 6), (42, banner_y + 10)], fill=colors['white'])

def draw_tagline(draw, colors):
    """Draw tagline at bottom"""
    # Simple text: "FORTIFIED!"
    tag_y = 52

    # Small pixel text (very simplified)
    # F
    draw.line([(14, tag_y), (14, tag_y + 5)], fill=colors['yellow_bright'])
    draw.line([(14, tag_y), (16, tag_y)], fill=colors['yellow_bright'])
    draw.line([(14, tag_y + 2), (16, tag_y + 2)], fill=colors['yellow_bright'])

    # O
    draw.rectangle([17, tag_y, 19, tag_y + 5], outline=colors['yellow_bright'])

    # R
    draw.line([(20, tag_y), (20, tag_y + 5)], fill=colors['yellow_bright'])
    draw.line([(20, tag_y), (22, tag_y)], fill=colors['yellow_bright'])
    draw.line([(20, tag_y + 2), (22, tag_y + 2)], fill=colors['yellow_bright'])
    draw.line([(22, tag_y), (22, tag_y + 2)], fill=colors['yellow_bright'])
    draw.line([(20, tag_y + 2), (22, tag_y + 5)], fill=colors['yellow_bright'])

def add_wear_and_fade(img_array, colors):
    """Add aged/faded effect like the box has been sitting in the Backrooms"""
    # Random dark spots (dirt/age)
    for _ in range(20):
        x, y = random.randint(0, SIZE-1), random.randint(0, SIZE-1)
        radius = random.randint(1, 3)
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if dx*dx + dy*dy <= radius*radius:
                    px, py = (x + dx) % SIZE, (y + dy) % SIZE
                    # Darken
                    img_array[py, px] = np.clip(img_array[py, px] * 0.7, 0, 255)

    return img_array

def main():
    # Create base image with alpha channel
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw all elements
    draw_box_shape(draw, COLORS)
    draw_text_logo(draw, COLORS)
    draw_mascot(draw, COLORS)
    draw_tagline(draw, COLORS)

    # Convert to numpy for post-processing
    img_array = np.array(img, dtype=np.float32)

    # Apply PSX effects
    img_array = add_wear_and_fade(img_array, COLORS)
    img_array = apply_dithering(img_array, intensity=0.25)
    img_array = add_grain(img_array, intensity=0.12)

    # Convert back to image
    img_array = np.clip(img_array, 0, 255).astype(np.uint8)
    final_img = Image.fromarray(img_array, mode='RGBA')

    # Save
    final_img.save(OUTPUT_PATH)
    print(f"✓ Generated {OUTPUT_PATH} ({SIZE}x{SIZE})")
    print(f"  PSX-style Wheatie-O's cereal box with mascot")

if __name__ == '__main__':
    main()
