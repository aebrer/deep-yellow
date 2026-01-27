#!/usr/bin/env python3
"""
Generate a cracked wall texture for Backrooms Level 0.
Uses the existing yellow wallpaper as base and adds visible cracks.
"""

from PIL import Image, ImageDraw
import numpy as np
import random

SIZE = 128
BASE_WALLPAPER = "/home/drew/projects/backrooms_power_crawl/assets/levels/level_00/textures/wallpaper_yellow.png"

def add_crack_segment(img_array, x1, y1, x2, y2, width=2, intensity=0.3):
    """
    Draw a crack line segment using Bresenham-like algorithm with modulo wrapping.
    Darkens pixels along the line and adds subtle shadows.
    """
    # Ensure coordinates are in valid range
    x1, y1 = int(x1), int(y1)
    x2, y2 = int(x2), int(y2)

    # Calculate line parameters
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx - dy

    # Track points along the line
    x, y = x1, y1
    steps = 0
    max_steps = SIZE * 2  # Safety limit

    while steps < max_steps:
        # Draw crack point with width variation
        for offset_y in range(-width, width + 1):
            for offset_x in range(-width, width + 1):
                # Don't use modulo here since we want cracks to stay internal
                py = y + offset_y
                px = x + offset_x

                # Skip if outside valid range (this keeps cracks internal)
                if py < 0 or py >= SIZE or px < 0 or px >= SIZE:
                    continue

                dist = np.sqrt(offset_x**2 + offset_y**2)
                if dist <= width:
                    # Darken the crack
                    factor = 1.0 - (intensity * (1.0 - dist / max(width, 1)))
                    for c in range(3):  # RGB channels
                        img_array[py, px, c] = int(img_array[py, px, c] * factor)

        # Check if we've reached the end
        if x == x2 and y == y2:
            break

        # Bresenham algorithm step
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy

        steps += 1

    return img_array

def generate_crack_pattern(img_array):
    """
    Generate 2-4 main cracks starting from central area, branching outward.
    Cracks fade out before reaching edges to maintain tileability.
    """
    random.seed(42)  # Reproducible cracks

    # Define safe zone - cracks start from center and don't reach edges
    margin = 20  # Don't let cracks reach within 20px of edges
    center_x, center_y = SIZE // 2, SIZE // 2

    # Generate 3 main cracks
    num_cracks = 3

    for i in range(num_cracks):
        # Start point near center (with some variation)
        start_x = center_x + random.randint(-15, 15)
        start_y = center_y + random.randint(-15, 15)

        # End point in a different direction, but not at edges
        angle = (i * (2 * np.pi / num_cracks)) + random.uniform(-0.3, 0.3)
        length = random.randint(30, 45)

        end_x = start_x + int(length * np.cos(angle))
        end_y = start_y + int(length * np.sin(angle))

        # Clamp to safe zone
        end_x = np.clip(end_x, margin, SIZE - margin)
        end_y = np.clip(end_y, margin, SIZE - margin)

        # Draw main crack
        width = random.randint(1, 2)
        img_array = add_crack_segment(img_array, start_x, start_y, end_x, end_y,
                                       width=width, intensity=0.5)

        # Add 1-2 branches from this crack
        num_branches = random.randint(1, 2)
        for j in range(num_branches):
            # Branch starts somewhere along main crack
            t = random.uniform(0.3, 0.7)
            branch_start_x = int(start_x + (end_x - start_x) * t)
            branch_start_y = int(start_y + (end_y - start_y) * t)

            # Branch goes in a different direction, shorter
            branch_angle = angle + random.uniform(-np.pi/3, np.pi/3)
            branch_length = random.randint(15, 25)

            branch_end_x = branch_start_x + int(branch_length * np.cos(branch_angle))
            branch_end_y = branch_start_y + int(branch_length * np.sin(branch_angle))

            # Clamp branch to safe zone
            branch_end_x = np.clip(branch_end_x, margin, SIZE - margin)
            branch_end_y = np.clip(branch_end_y, margin, SIZE - margin)

            # Draw thinner branch
            img_array = add_crack_segment(img_array, branch_start_x, branch_start_y,
                                           branch_end_x, branch_end_y,
                                           width=1, intensity=0.4)

    return img_array

def add_plaster_bits(img_array):
    """
    Add small bits of exposed plaster (lighter spots) near cracks.
    """
    random.seed(43)

    # Find dark pixels (likely cracks)
    grey = np.mean(img_array, axis=2)
    avg_grey = np.mean(grey)
    crack_mask = grey < (avg_grey * 0.7)

    # Add plaster bits near cracks
    num_bits = random.randint(8, 15)
    for _ in range(num_bits):
        # Find a crack pixel
        crack_coords = np.argwhere(crack_mask)
        if len(crack_coords) == 0:
            break

        cy, cx = crack_coords[random.randint(0, len(crack_coords) - 1)]

        # Add small lighter spot nearby
        offset_x = random.randint(-3, 3)
        offset_y = random.randint(-3, 3)
        px = cx + offset_x
        py = cy + offset_y

        if 0 <= px < SIZE and 0 <= py < SIZE:
            # Lighten slightly (exposed plaster)
            radius = random.randint(1, 2)
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if dx**2 + dy**2 <= radius**2:
                        py_actual = py + dy
                        px_actual = px + dx
                        if 0 <= py_actual < SIZE and 0 <= px_actual < SIZE:
                            # Lighten by adding beige/off-white tone
                            img_array[py_actual, px_actual, 0] = min(255, img_array[py_actual, px_actual, 0] + 15)
                            img_array[py_actual, px_actual, 1] = min(255, img_array[py_actual, px_actual, 1] + 12)
                            img_array[py_actual, px_actual, 2] = min(255, img_array[py_actual, px_actual, 2] + 8)

    return img_array

def main():
    # Load base wallpaper
    base_img = Image.open(BASE_WALLPAPER)
    if base_img.size != (SIZE, SIZE):
        print(f"Warning: Base wallpaper is {base_img.size}, resizing to {SIZE}x{SIZE}")
        base_img = base_img.resize((SIZE, SIZE), Image.NEAREST)

    # Convert to numpy array for pixel manipulation
    img_array = np.array(base_img, dtype=np.uint8)

    print("Generating crack pattern...")
    img_array = generate_crack_pattern(img_array)

    print("Adding plaster details...")
    img_array = add_plaster_bits(img_array)

    # Convert back to PIL image
    output_img = Image.fromarray(img_array, mode='RGB')

    # Save
    output_path = "output.png"
    output_img.save(output_path)
    print(f"✓ Saved cracked wall texture to {output_path}")
    print(f"  Size: {output_img.size}")
    print(f"  Cracks: 3 main + branches, fade out before edges")
    print(f"  Tileable: Yes (cracks don't reach edges)")

if __name__ == "__main__":
    main()
