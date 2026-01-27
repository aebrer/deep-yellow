#!/usr/bin/env python3
"""
Generate tileable floor cardboard texture for Backrooms Power Crawl.
Loads existing carpet texture and overlays a flattened cardboard piece.
"""

from PIL import Image
import numpy as np
import random

# Constants
SIZE = 128
CARPET_PATH = "../../../assets/levels/level_00/textures/carpet_brown.png"
OUTPUT_PATH = "output.png"

# Cardboard properties
CARDBOARD_WIDTH = 70
CARDBOARD_HEIGHT = 50
CARDBOARD_CENTER_X = SIZE // 2
CARDBOARD_CENTER_Y = SIZE // 2

# Cardboard color — darker than carpet (mean ~115,92,64) for dirty/soggy look
CARDBOARD_BASE_COLOR = (85, 70, 50)  # Dark, water-damaged cardboard

def add_noise(img_array, intensity=10):
    """Add subtle noise to break up uniformity."""
    noise = np.random.randint(-intensity, intensity + 1, img_array.shape, dtype=np.int16)
    noisy = np.clip(img_array.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    return noisy

def draw_cardboard_pixel(img_array, x, y, base_color, edge_softness=0.0, corrugation_offset=0):
    """
    Draw a single cardboard pixel with proper blending.
    edge_softness: 0.0 = full cardboard, 1.0 = full carpet (for antialiasing edges)
    corrugation_offset: brightness offset for corrugated texture
    """
    if edge_softness >= 1.0:
        return  # Fully transparent, skip

    # Get current carpet color at this position (with modulo wrapping)
    carpet_color = img_array[y % SIZE, x % SIZE].copy()

    # Vary the cardboard color slightly for texture
    variation = np.random.randint(-8, 9, 3)
    cardboard_color = np.clip(np.array(base_color) + variation + corrugation_offset, 0, 255)

    # Blend cardboard with carpet based on edge softness
    if edge_softness > 0.0:
        alpha = 1.0 - edge_softness
        blended = (cardboard_color * alpha + carpet_color * (1.0 - alpha)).astype(np.uint8)
    else:
        blended = cardboard_color

    # Apply with modulo wrapping
    img_array[y % SIZE, x % SIZE] = blended

def draw_cardboard_box(img_array):
    """
    Draw a flattened cardboard piece on the carpet.
    The cardboard is rectangular with ragged/torn edges and corrugated texture.
    """
    # Define cardboard bounds (centered, but not touching tile edges)
    left = CARDBOARD_CENTER_X - CARDBOARD_WIDTH // 2
    right = CARDBOARD_CENTER_X + CARDBOARD_WIDTH // 2
    top = CARDBOARD_CENTER_Y - CARDBOARD_HEIGHT // 2
    bottom = CARDBOARD_CENTER_Y + CARDBOARD_HEIGHT // 2

    # Draw cardboard with corrugated texture and ragged edges
    for y in range(top, bottom):
        for x in range(left, right):
            # Calculate distance from cardboard edges
            dist_from_left = x - left
            dist_from_right = right - x - 1
            dist_from_top = y - top
            dist_from_bottom = bottom - y - 1

            # Find minimum distance to any edge
            min_edge_dist = min(dist_from_left, dist_from_right, dist_from_top, dist_from_bottom)

            # CORRUGATED TEXTURE - horizontal ridges (key cardboard visual!)
            # Ridges are ~2-3 pixels apart
            ridge_pattern = (y % 3)  # 0, 1, 2 repeating pattern
            if ridge_pattern == 0:
                corrugation = 10  # Ridge peak (lighter)
            elif ridge_pattern == 1:
                corrugation = -8  # Valley (darker)
            else:
                corrugation = 0  # Transition

            # MORE RAGGED/TORN edges - larger random cutouts
            if min_edge_dist < 5:
                # Much higher chance of torn edges
                if random.random() < 0.5:  # 50% chance near edges
                    continue
                # Add extra jaggedness
                if min_edge_dist < 3 and random.random() < 0.6:
                    continue
                # Soften the edge
                edge_softness = 0.4 if min_edge_dist < 2 else 0.1
            else:
                edge_softness = 0.0

            draw_cardboard_pixel(img_array, x, y, CARDBOARD_BASE_COLOR, edge_softness, corrugation)

    # Add PROMINENT crease lines (fold marks) - darker and more visible
    # Horizontal crease near top third
    crease_y = top + CARDBOARD_HEIGHT // 3
    for x in range(left + 5, right - 5):
        if random.random() < 0.8:  # More continuous line
            darker_color = tuple(max(0, c - 40) for c in CARDBOARD_BASE_COLOR)  # Darker crease
            draw_cardboard_pixel(img_array, x, crease_y, darker_color, 0.0, 0)
            # Shadow below crease
            if random.random() < 0.7:
                draw_cardboard_pixel(img_array, x, crease_y + 1, darker_color, 0.3, 0)

    # Vertical crease near center
    crease_x = CARDBOARD_CENTER_X + random.randint(-5, 5)
    for y in range(top + 5, bottom - 10):
        if random.random() < 0.8:  # More continuous line
            darker_color = tuple(max(0, c - 40) for c in CARDBOARD_BASE_COLOR)
            draw_cardboard_pixel(img_array, crease_x, y, darker_color, 0.0, 0)

    # Add tape residue marks (lighter rectangular spots)
    for _ in range(3):
        tape_x = random.randint(left + 15, right - 15)
        tape_y = random.randint(top + 10, bottom - 10)
        tape_width = random.randint(8, 15)
        tape_height = random.randint(3, 5)
        tape_color = tuple(min(255, c + 25) for c in CARDBOARD_BASE_COLOR)  # Lighter for tape residue

        for dy in range(tape_height):
            for dx in range(tape_width):
                if random.random() < 0.7:  # Patchy tape residue
                    draw_cardboard_pixel(img_array, tape_x + dx, tape_y + dy, tape_color, 0.2, 0)

    # Add some wear marks (darker spots) - more prominent
    for _ in range(10):
        wear_x = random.randint(left + 10, right - 10)
        wear_y = random.randint(top + 10, bottom - 10)
        wear_radius = random.randint(4, 9)
        wear_color = tuple(max(0, c - 45) for c in CARDBOARD_BASE_COLOR)  # Darker wear marks

        for dy in range(-wear_radius, wear_radius + 1):
            for dx in range(-wear_radius, wear_radius + 1):
                dist = np.sqrt(dx**2 + dy**2)
                if dist <= wear_radius:
                    # Soften edges of wear mark
                    softness = (dist / wear_radius) * 0.6
                    draw_cardboard_pixel(img_array, wear_x + dx, wear_y + dy, wear_color, softness, 0)

def main():
    # Load base carpet texture
    print(f"Loading carpet texture from {CARPET_PATH}...")
    carpet = Image.open(CARPET_PATH).convert('RGB')

    # Ensure it's the right size
    if carpet.size != (SIZE, SIZE):
        print(f"Warning: Carpet texture is {carpet.size}, resizing to {SIZE}x{SIZE}")
        carpet = carpet.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    # Convert to numpy array for manipulation
    img_array = np.array(carpet, dtype=np.uint8)

    print("Drawing cardboard piece...")
    # Draw the cardboard box on top of carpet
    draw_cardboard_box(img_array)

    # Add very subtle noise to the whole thing for PSX grittiness
    print("Adding subtle noise for PSX aesthetic...")
    img_array = add_noise(img_array, intensity=3)

    # Convert back to PIL Image and save
    print(f"Saving to {OUTPUT_PATH}...")
    output_img = Image.fromarray(img_array, mode='RGB')
    output_img.save(OUTPUT_PATH)

    print(f"✓ Generated {SIZE}x{SIZE} tileable floor cardboard texture")
    print(f"  - Cardboard: {CARDBOARD_WIDTH}x{CARDBOARD_HEIGHT}px, centered")
    print(f"  - Features: Corrugated texture, ragged/torn edges, crease lines, tape residue, wear marks")
    print(f"  - High contrast: Bright tan cardboard on dark brown carpet")
    print(f"  - Tileable: Cardboard fully contained within tile bounds")

if __name__ == "__main__":
    main()
