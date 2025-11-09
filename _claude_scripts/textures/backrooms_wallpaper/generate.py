#!/usr/bin/env python3
"""
Backrooms Level 0 Yellow Wallpaper Generator
Generates a tileable 128x128 texture with vertical lines and chevron patterns.
"""

from PIL import Image, ImageDraw
import numpy as np
import random

# Configuration
SIZE = 128
BASE_COLOR = (212, 197, 160)  # Greyish-yellow base
HIGHLIGHT_COLOR = (232, 217, 152)  # Lighter yellow for variation
PATTERN_COLOR = (140, 125, 90)  # MUCH darker for arrows to stand out
LINE_COLOR = (130, 115, 80)  # Darker for vertical lines to be more visible
SHADOW_COLOR = (200, 185, 145)  # Subtle shadows

# Pattern spacing
VERTICAL_REPEAT = 32  # Pattern repeats every 32px vertically (128÷32=4 exact rows for tiling)
COLUMN_WIDTH = 16  # Width of each pattern column (128÷16=8 exact columns for tiling)


def add_base_texture(img_array):
    """Add prominent noise and color variation to simulate aged wallpaper."""
    # Add more visible paper texture grain
    noise = np.random.normal(0, 8, (SIZE, SIZE, 3))
    img_array = np.clip(img_array + noise, 0, 255)

    # Add larger-scale noise for surface variation
    for scale in [16, 32]:
        coarse_noise = np.zeros((SIZE, SIZE, 3))
        for i in range(0, SIZE, scale):
            for j in range(0, SIZE, scale):
                value = np.random.normal(0, 12)
                coarse_noise[i:i+scale, j:j+scale] = value
        img_array = np.clip(img_array + coarse_noise, 0, 255)

    # Add more pronounced water damage stains
    for _ in range(8):
        cx, cy = random.randint(0, SIZE), random.randint(0, SIZE)
        radius = random.randint(15, 50)
        variation = np.random.randint(-35, -15)

        # Draw stain using modulo wrapping for seamless tiling
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = np.sqrt(dx**2 + dy**2)
                if dist <= radius:
                    # Calculate wrapped coordinates
                    y_coord = (cy + dy) % SIZE
                    x_coord = (cx + dx) % SIZE

                    # Apply falloff effect
                    falloff = max(0, 1 - (dist / radius))
                    darkening = variation * falloff

                    # Apply to pixel with modulo wrapping
                    img_array[y_coord, x_coord] = np.clip(
                        img_array[y_coord, x_coord] + darkening, 0, 255
                    )

    return img_array


def draw_chevron_up(img_array, x, y, height, width, jitter=True):
    """Draw an upward-pointing chevron (∧ shape) with pixel-based drawing and modulo wrapping.

    Args:
        img_array: numpy array to draw on
        x, y: Center position for the chevron (y is the BOTTOM of the chevron)
        height: Total height of chevron
        width: Width at the base (distance between the two bottom points)
    """
    if jitter:
        # Add slight randomness to make it look screen-printed
        x += random.randint(-1, 1)
        y += random.randint(-1, 1)

    # Calculate chevron points
    top_x = x
    top_y = y - height
    left_x = x - width // 2
    right_x = x + width // 2

    # Draw chevron pixel-by-pixel with modulo wrapping
    # Use Bresenham-style algorithm for line drawing
    line_thickness = 3

    # Draw left stroke (from bottom-left to top)
    draw_thick_line_wrapped(img_array, left_x, y, top_x, top_y, line_thickness, PATTERN_COLOR)

    # Draw right stroke (from bottom-right to top)
    draw_thick_line_wrapped(img_array, right_x, y, top_x, top_y, line_thickness, PATTERN_COLOR)


def draw_thick_line_wrapped(img_array, x0, y0, x1, y1, thickness, color):
    """Draw a thick line with modulo wrapping using Bresenham's algorithm.

    Args:
        img_array: numpy array to draw on
        x0, y0: Start point
        x1, y1: End point
        thickness: Line thickness
        color: RGB tuple
    """
    # Bresenham's line algorithm
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy

    x, y = x0, y0

    while True:
        # Draw thick pixel (thickness x thickness square centered on point)
        for dy_offset in range(-thickness // 2, thickness // 2 + 1):
            for dx_offset in range(-thickness // 2, thickness // 2 + 1):
                # Use modulo wrapping to ensure seamless tiling
                y_coord = (y + dy_offset) % SIZE
                x_coord = (x + dx_offset) % SIZE
                img_array[y_coord, x_coord] = color

        # Check if we've reached the end
        if x == x1 and y == y1:
            break

        # Calculate next point
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def draw_vertical_line(img_array, x, y_start, y_end, jitter=True):
    """Draw a vertical line with slight waviness using pixel-based drawing."""
    if jitter:
        x += random.randint(-1, 1)

    # Draw line in segments to add slight waviness
    segment_height = 4
    current_y = y_start
    line_thickness = 3  # Increased from 2 to 3 for better visibility

    while current_y < y_end:
        next_y = min(current_y + segment_height, y_end)
        x_offset = random.randint(-1, 1) if jitter else 0

        # Draw vertical line segment with modulo wrapping
        draw_thick_line_wrapped(
            img_array,
            x + x_offset, current_y,
            x + x_offset, next_y,
            line_thickness,
            LINE_COLOR
        )
        current_y = next_y


def generate_wallpaper():
    """Generate the complete wallpaper texture."""
    # Create base image with greyish-yellow
    img_array = np.full((SIZE, SIZE, 3), BASE_COLOR, dtype=np.float32)

    # Add base texture variations
    img_array = add_base_texture(img_array)

    # Draw repeating pattern directly on numpy array
    # Pattern: vertical line, arrows, vertical line, arrows...
    # Use exact division for perfect tiling (no extra drawings)
    num_columns = SIZE // COLUMN_WIDTH  # Exactly 8 columns

    for col in range(num_columns):
        x = col * COLUMN_WIDTH + COLUMN_WIDTH // 2  # Center elements in each column

        if col % 2 == 0:
            # Draw vertical lines column
            for row in range(SIZE // VERTICAL_REPEAT):  # Exactly 4 rows
                y_start = row * VERTICAL_REPEAT
                y_end = y_start + VERTICAL_REPEAT
                draw_vertical_line(img_array, x, y_start, y_end, jitter=True)
        else:
            # Draw chevrons column
            for row in range(SIZE // VERTICAL_REPEAT):  # Exactly 4 rows
                y_base = row * VERTICAL_REPEAT

                # Small chevron at top of cycle (adjusted for 32px repeat)
                small_chevron_bottom = y_base + 7
                draw_chevron_up(img_array, x, small_chevron_bottom, height=6, width=18, jitter=True)

                # Large chevron below small chevron (adjusted for 32px repeat)
                large_chevron_bottom = y_base + 25
                draw_chevron_up(img_array, x, large_chevron_bottom, height=16, width=26, jitter=True)

    # Add more pronounced grain overlay for aged paper texture
    grain = np.random.normal(0, 6, (SIZE, SIZE, 3))
    img_array = np.clip(img_array + grain, 0, 255)

    # Add random faded spots (wear patterns)
    for _ in range(12):
        cx, cy = random.randint(0, SIZE), random.randint(0, SIZE)
        radius = random.randint(8, 25)
        fade_amount = np.random.randint(10, 25)

        # Draw faded spot using modulo wrapping for seamless tiling
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = np.sqrt(dx**2 + dy**2)
                if dist <= radius:
                    # Calculate wrapped coordinates
                    y_coord = (cy + dy) % SIZE
                    x_coord = (cx + dx) % SIZE

                    # Apply falloff effect
                    falloff = max(0, 1 - (dist / radius))
                    lightening = fade_amount * falloff

                    # Apply to pixel with modulo wrapping
                    img_array[y_coord, x_coord] = np.clip(
                        img_array[y_coord, x_coord] + lightening, 0, 255
                    )

    # Add subtle streaking/drip marks (vertical wear)
    for _ in range(6):
        x = random.randint(0, SIZE)
        y_start = random.randint(0, SIZE // 2)
        y_end = random.randint(y_start + 20, SIZE)
        width = random.randint(2, 5)

        for y in range(y_start, y_end):
            x_wobble = x + random.randint(-1, 1)
            for dx in range(-width//2, width//2 + 1):
                # Apply with modulo wrapping for seamless tiling
                y_coord = y % SIZE
                x_coord = (x_wobble + dx) % SIZE
                darken = random.randint(-12, -5)
                img_array[y_coord, x_coord] = np.clip(
                    img_array[y_coord, x_coord] + darken, 0, 255
                )

    # Final image
    final_img = Image.fromarray(img_array.astype(np.uint8))

    return final_img


def main():
    """Generate and save the wallpaper texture."""
    print("Generating Backrooms Level 0 wallpaper texture...")

    # Set random seed for reproducibility (but with variation)
    random.seed(42)
    np.random.seed(42)

    # Generate texture
    wallpaper = generate_wallpaper()

    # Save output
    output_path = "output.png"
    wallpaper.save(output_path, "PNG")

    print(f"✓ Texture generated successfully!")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print(f"  Output: {output_path}")
    print(f"  Pattern: Vertical lines + chevron symbols (∧)")
    print(f"  Style: Aged, institutional wallpaper with subtle water damage")


if __name__ == "__main__":
    main()
