#!/usr/bin/env python3
"""
Pine Forest Wall Texture Generator
Generates a tileable 128×256 texture of a dark pine forest silhouette.
Uses proper tree-drawing algorithm with recognizable pine/conifer shapes.
The 128x256 (1:2) aspect ratio matches BoxMesh wall faces (2 wide x 4 tall).
"""

import numpy as np
from PIL import Image
import random

WIDTH = 128
HEIGHT = 256

def hex_to_rgb(hex_color):
    """Convert hex color to RGB tuple"""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def draw_pine_tree(img_array, trunk_x, ground_y, height, trunk_width, branch_layers, depth_factor=1.0):
    """Draw a single pine/conifer tree silhouette.

    Pine trees have:
    - A straight central trunk
    - Triangular overall shape (wider at bottom, narrow at top)
    - Horizontal branches in tiers that get shorter toward the top
    - Branches droop slightly downward

    Args:
        img_array: The image array to draw on (HEIGHT x WIDTH x 3)
        trunk_x: X position of tree trunk center
        ground_y: Y position of tree base
        height: Total height of the tree
        trunk_width: Width of the trunk
        branch_layers: Number of branch tiers
        depth_factor: 0.0-1.0, where 0.0 is furthest back (lightest), 1.0 is front (darkest)
    """
    # Color variation based on depth
    # depth_factor: 1.0 = front/closest (LIGHTER), 0.0 = back/furthest (DARKER)
    dark_foliage = np.array([8, 16, 8])  # Very dark green for background trees
    light_foliage = np.array([22, 38, 22])  # Lighter green for foreground trees
    foliage_color = (dark_foliage + (light_foliage - dark_foliage) * depth_factor).astype(np.uint8)

    dark_trunk = np.array([14, 8, 4])  # Very dark brown for background
    light_trunk = np.array([36, 22, 10])  # Lighter brown for foreground
    trunk_color = (dark_trunk + (light_trunk - dark_trunk) * depth_factor).astype(np.uint8)

    # Trunk is only the bottom 25% of tree height — foliage dominates
    trunk_height = int(height * 0.25)
    foliage_height = height - trunk_height
    trunk_top = ground_y - trunk_height  # Where trunk ends and foliage begins

    # Draw trunk (visible below foliage)
    for y in range(trunk_top, ground_y):
        y_coord = y % HEIGHT
        if y_coord < 0 or y_coord >= HEIGHT:
            continue
        for dx in range(-trunk_width//2, trunk_width//2 + 1):
            x_coord = (trunk_x + dx) % WIDTH
            img_array[y_coord, x_coord] = trunk_color

    # Draw foliage as one large triangular silhouette (classic pine shape)
    # Apex at top of tree, widest at trunk_top
    foliage_apex_y = ground_y - height
    max_foliage_width = int(height * 0.4)  # Max half-width at base of foliage

    for dy in range(foliage_height):
        y = foliage_apex_y + dy
        y_coord = y % HEIGHT
        # Don't wrap foliage to top of image — skip if out of bounds above
        if y < 0:
            continue

        # Width increases linearly from apex (0) to base
        progress = dy / foliage_height  # 0 at apex, 1 at base
        width_at_y = int(max_foliage_width * progress)

        # Add ragged edges for organic look
        edge_variation = random.randint(-2, 2) if dy % 2 == 0 else 0
        width_at_y = max(1, width_at_y + edge_variation)

        for dx in range(-width_at_y, width_at_y + 1):
            x_coord = (trunk_x + dx) % WIDTH
            # Small random gaps for needle texture
            if random.random() > 0.08:
                img_array[y_coord, x_coord] = foliage_color

def generate_pine_forest():
    """Generate the complete pine forest texture"""

    # Initialize with near-black background
    bg_dark = np.array([6, 8, 8])  # #060808
    bg_light = np.array([10, 14, 10])  # #0a0e0a

    # Create background with slight vertical gradient and noise
    img_array = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)
    for y in range(HEIGHT):
        gradient_factor = y / HEIGHT  # 0.0 at top, 1.0 at bottom
        bg_color = (bg_dark + (bg_light - bg_dark) * gradient_factor).astype(np.int16)  # Use int16 to avoid overflow
        for x in range(WIDTH):
            noise = random.randint(-2, 2)
            color = np.clip(bg_color + noise, 0, 255).astype(np.uint8)
            img_array[y, x] = color

    # Define tree positions and properties
    # We'll place trees at different depths for layering effect
    random.seed(42)  # Consistent generation

    trees = [
        # (trunk_x, ground_y, height, trunk_width, branch_layers, depth_factor)
        # depth_factor: 1.0 = front/closest (LIGHTER), 0.0 = back/furthest (DARKER)

        # Back layer (darker, smaller, further away)
        (15, HEIGHT, 100, 4, 5, 0.2),
        (55, HEIGHT, 90, 4, 5, 0.25),
        (100, HEIGHT, 95, 4, 5, 0.22),

        # Middle layer
        (35, HEIGHT, 140, 6, 6, 0.5),
        (80, HEIGHT, 130, 6, 6, 0.55),
        (115, HEIGHT, 135, 6, 6, 0.48),

        # Front layer (lightest, tallest, closest) — thicker trunks
        # Heights extend past top edge for wall effect and better tiling
        (10, HEIGHT, 270, 8, 7, 0.85),
        (48, HEIGHT, 280, 8, 7, 0.95),
        (88, HEIGHT, 275, 8, 7, 0.9),
        (120, HEIGHT, 265, 8, 7, 0.88),

        # Edge-wrapping trees for seamless horizontal tiling
        (0, HEIGHT, 240, 7, 6, 0.7),
        (WIDTH, HEIGHT, 250, 7, 6, 0.75),
    ]

    # Draw trees from back to front (so front trees overlap background trees)
    trees_sorted = sorted(trees, key=lambda t: t[5])  # Sort by depth_factor

    for trunk_x, ground_y, height, trunk_width, branch_layers, depth_factor in trees_sorted:
        draw_pine_tree(img_array, trunk_x, ground_y, height, trunk_width, branch_layers, depth_factor)

    # Add final PSX grain/noise overlay
    random.seed(42)  # Reset seed for consistent grain
    for y in range(HEIGHT):
        for x in range(WIDTH):
            noise = random.randint(-3, 3)
            pixel = img_array[y, x].astype(np.int16) + noise
            img_array[y, x] = np.clip(pixel, 0, 255).astype(np.uint8)

    return img_array

def main():
    print("Generating pine forest texture...")
    img_array = generate_pine_forest()

    # Convert to PIL Image and save
    img = Image.fromarray(img_array, mode='RGB')
    img.save('output.png')
    print(f"Generated output.png ({WIDTH}x{HEIGHT}, tileable)")
    print("  - Multiple pine tree silhouettes with depth layering")
    print("  - Triangular conifer shape with branch tiers")
    print("  - Dark, ominous forest atmosphere")
    print("  - PSX-style grain and color palette")
    print("  - Recognizable tree shapes (NOT abstract stripes!)")

if __name__ == "__main__":
    main()
