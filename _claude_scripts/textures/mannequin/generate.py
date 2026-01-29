#!/usr/bin/env python3
"""
Generate a 64x64 pixel art sprite of a department store plastic mannequin.
PSX-style horror aesthetic for Backrooms Power Crawl.
"""

from PIL import Image, ImageDraw
import numpy as np

# Constants
SIZE = 64
OUTPUT_PATH = "output.png"

# Color palette - pale beige plastic mannequin
MANNEQUIN_BASE = (217, 191, 165, 255)  # Pale beige/flesh-toned plastic
MANNEQUIN_SHADOW = (180, 155, 130, 255)  # Darker contour
MANNEQUIN_DARK = (140, 115, 95, 255)    # Deep shadow areas
MANNEQUIN_HIGHLIGHT = (235, 215, 195, 255)  # Subtle highlights
TRANSPARENT = (0, 0, 0, 0)

def create_mannequin_sprite():
    """Generate a creepy department store mannequin sprite."""

    # Create image with transparency
    img = Image.new('RGBA', (SIZE, SIZE), TRANSPARENT)
    pixels = img.load()

    # Center coordinates
    cx = SIZE // 2

    # Define mannequin proportions (pixel-based, front view)
    # HEAD
    head_top = 6
    head_bottom = 18
    head_width = 10

    # NECK
    neck_top = 18
    neck_bottom = 22
    neck_width = 4

    # SHOULDERS/TORSO
    shoulder_y = 22
    shoulder_width = 24
    torso_bottom = 45
    waist_width = 16

    # ARMS
    arm_top = 22
    arm_bottom = 42
    arm_width = 4

    # HIPS/LEGS
    hip_top = 45
    hip_bottom = 50
    hip_width = 18
    leg_bottom = 62
    leg_width = 5
    leg_gap = 2

    # Draw function with anti-aliasing simulation (dithering at edges)
    def draw_ellipse_filled(x_center, y_top, y_bottom, width, color, shadow_color):
        """Draw a filled ellipse representing a body part."""
        height = y_bottom - y_top
        for y in range(y_top, y_bottom):
            # Calculate ellipse width at this y position
            ratio = abs((y - (y_top + height/2)) / (height/2))
            current_width = int(width * (1 - ratio**2)**0.5)

            # Determine color based on position (add basic shading)
            if y < y_top + height * 0.3:
                pixel_color = shadow_color  # Top shadow
            elif y > y_bottom - height * 0.2:
                pixel_color = shadow_color  # Bottom shadow
            else:
                pixel_color = color

            # Draw the horizontal line
            for x in range(x_center - current_width, x_center + current_width):
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    pixels[x, y] = pixel_color

    def draw_rect_filled(x_center, y_top, y_bottom, width, color, shadow_color):
        """Draw a filled rectangle with rounded edges."""
        for y in range(y_top, y_bottom):
            # Add slight tapering
            ratio = (y - y_top) / max(1, (y_bottom - y_top))
            current_width = int(width * (1 - ratio * 0.1))

            # Shading
            if y < y_top + 2:
                pixel_color = shadow_color
            elif y > y_bottom - 2:
                pixel_color = shadow_color
            else:
                pixel_color = color

            for x in range(x_center - current_width // 2, x_center + current_width // 2):
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    pixels[x, y] = pixel_color

    # DRAW MANNEQUIN FROM BACK TO FRONT

    # 1. LEGS (behind body)
    leg_left_x = cx - leg_width - leg_gap // 2
    leg_right_x = cx + leg_width + leg_gap // 2

    # Left leg
    draw_rect_filled(leg_left_x, hip_bottom, leg_bottom, leg_width, MANNEQUIN_BASE, MANNEQUIN_SHADOW)
    # Right leg
    draw_rect_filled(leg_right_x, hip_bottom, leg_bottom, leg_width, MANNEQUIN_BASE, MANNEQUIN_SHADOW)

    # 2. ARMS (at sides, slightly out)
    arm_left_x = cx - shoulder_width // 2 - 2
    arm_right_x = cx + shoulder_width // 2 + 2

    # Left arm
    draw_rect_filled(arm_left_x, arm_top, arm_bottom, arm_width, MANNEQUIN_SHADOW, MANNEQUIN_DARK)
    # Right arm
    draw_rect_filled(arm_right_x, arm_top, arm_bottom, arm_width, MANNEQUIN_SHADOW, MANNEQUIN_DARK)

    # 3. HIPS/PELVIS
    for y in range(hip_top, hip_bottom):
        width_ratio = (y - hip_top) / (hip_bottom - hip_top)
        current_width = int(waist_width + (hip_width - waist_width) * width_ratio)
        for x in range(cx - current_width // 2, cx + current_width // 2):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                pixels[x, y] = MANNEQUIN_BASE

    # 4. TORSO (tapers from shoulders to waist)
    for y in range(shoulder_y, torso_bottom):
        width_ratio = (y - shoulder_y) / (torso_bottom - shoulder_y)
        current_width = int(shoulder_width - (shoulder_width - waist_width) * width_ratio)

        # Add shading on sides
        for x in range(cx - current_width // 2, cx + current_width // 2):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                # Side shading
                distance_from_center = abs(x - cx)
                if distance_from_center > current_width // 2 - 2:
                    pixels[x, y] = MANNEQUIN_SHADOW
                else:
                    pixels[x, y] = MANNEQUIN_BASE

    # 5. NECK
    draw_rect_filled(cx, neck_top, neck_bottom, neck_width, MANNEQUIN_SHADOW, MANNEQUIN_DARK)

    # 6. HEAD (oval/egg shape, featureless)
    draw_ellipse_filled(cx, head_top, head_bottom, head_width, MANNEQUIN_BASE, MANNEQUIN_SHADOW)

    # Add subtle facial area (no features, just shape suggestion)
    # Create a very subtle indentation where face would be
    face_y_start = head_top + 4
    face_y_end = head_bottom - 2
    for y in range(face_y_start, face_y_end):
        for x in range(cx - 4, cx + 4):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                if pixels[x, y] == MANNEQUIN_BASE:
                    # Slightly darker in face area to suggest flatness
                    pixels[x, y] = tuple(max(0, c - 10) if i < 3 else c for i, c in enumerate(MANNEQUIN_BASE))

    # Add some PSX-style dithering/noise for texture
    noise_gen = np.random.RandomState(42)  # Deterministic
    for y in range(SIZE):
        for x in range(SIZE):
            if pixels[x, y] != TRANSPARENT and pixels[x, y][3] > 0:
                # 10% chance of slight color variation
                if noise_gen.random() < 0.1:
                    current = list(pixels[x, y])
                    variation = noise_gen.randint(-8, 8)
                    current[0] = max(0, min(255, current[0] + variation))
                    current[1] = max(0, min(255, current[1] + variation))
                    current[2] = max(0, min(255, current[2] + variation))
                    pixels[x, y] = tuple(current)

    # Add slight highlight on head (top-left, like overhead lighting)
    for y in range(head_top, head_top + 4):
        for x in range(cx - 4, cx + 2):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                if pixels[x, y] != TRANSPARENT and pixels[x, y][3] > 0:
                    pixels[x, y] = MANNEQUIN_HIGHLIGHT

    return img

def main():
    print("Generating 64x64 mannequin sprite...")

    mannequin_sprite = create_mannequin_sprite()

    # Save output
    mannequin_sprite.save(OUTPUT_PATH)
    print(f"✓ Saved to {OUTPUT_PATH}")
    print(f"  Size: {mannequin_sprite.size}")
    print(f"  Mode: {mannequin_sprite.mode}")
    print("  PSX-style plastic mannequin with transparent background")

if __name__ == "__main__":
    main()
