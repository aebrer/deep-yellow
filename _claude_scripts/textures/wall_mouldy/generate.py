#!/usr/bin/env python3
"""
Generates a tileable mouldy wall texture for Backrooms Level 0.
Based on the existing yellow wallpaper with dark mould/mildew patches.
Mould has dark greenish-black colonies with veiny tendrils spreading outward.
"""

import numpy as np
from PIL import Image
import random
import math

# Configuration
WIDTH = 128
HEIGHT = 256
BASE_TEXTURE_PATH = "../../../assets/levels/level_00/textures/wallpaper_yellow.png"
OUTPUT_PATH = "output.png"

# Mould colors (dark greenish-black)
MOULD_DARK = np.array([26, 37, 26])      # RGB: darkest core
MOULD_MID = np.array([35, 50, 35])       # RGB: mid-tone mould
MOULD_LIGHT = np.array([42, 58, 42])     # RGB: lighter edges

# Random seed for reproducibility
random.seed(42)
np.random.seed(42)


def draw_vein(mask, start_x, start_y, angle, length, thickness, decay=0.9):
    """
    Draw a branching vein-like tendril from a starting point.
    Veins can split and create organic spreading patterns.
    """
    # Current position
    x, y = start_x, start_y
    current_angle = angle
    current_thickness = thickness
    current_length = 0

    while current_length < length and current_thickness > 0.3:
        # Draw circular segment at current position
        radius = int(current_thickness)
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = math.sqrt(dx**2 + dy**2)
                if dist <= radius:
                    draw_y = int(y + dy)
                    draw_x = int(x + dx)

                    # Stay within bounds and away from edges
                    if 15 <= draw_y < HEIGHT - 15 and 15 <= draw_x < WIDTH - 15:
                        # Gaussian falloff from center of vein segment
                        intensity = math.exp(-0.5 * (dist / max(radius, 1)) ** 2)
                        mask[draw_y, draw_x] = max(mask[draw_y, draw_x], intensity * 0.9)

        # Move along the vein
        step_size = 1.5
        x += math.cos(current_angle) * step_size
        y += math.sin(current_angle) * step_size
        current_length += step_size

        # Gradually thin out
        current_thickness *= decay

        # Add some wiggle to the angle for organic look
        current_angle += random.uniform(-0.3, 0.3)

        # Occasionally branch
        if random.random() < 0.15 and current_length > 5:
            # Create a branch
            branch_angle = current_angle + random.choice([-0.8, 0.8])
            branch_length = length * random.uniform(0.3, 0.6)
            branch_thickness = current_thickness * 0.7
            draw_vein(mask, x, y, branch_angle, branch_length, branch_thickness, decay * 1.05)


def generate_mould_mask(num_colonies=5):
    """
    Generate a mask for mould growth with colonies and veiny tendrils.
    Returns a float array [0.0-1.0] representing mould intensity.
    """
    mask = np.zeros((HEIGHT, WIDTH), dtype=np.float32)

    # Keep colonies away from edges for tileability
    margin_x = 25
    margin_y = 25

    colonies = []

    # Generate main mould colonies
    for i in range(num_colonies):
        # Random position (away from edges)
        cx = random.randint(margin_x, WIDTH - margin_x)
        cy = random.randint(margin_y, HEIGHT - margin_y)

        # Vary colony sizes
        if i == 0:
            radius = random.randint(18, 25)  # One large colony
        else:
            radius = random.randint(10, 16)  # Smaller colonies

        colonies.append((cx, cy, radius))

        # Create dark central colony blob
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = math.sqrt(dx**2 + dy**2)

                if dist < radius:
                    # Strong intensity at center, falloff at edges
                    intensity = math.exp(-0.3 * (dist / radius) ** 2)

                    # Add organic irregularity
                    noise = random.uniform(0.75, 1.0)
                    intensity *= noise

                    # Apply to mask
                    y = cy + dy
                    x = cx + dx

                    if 0 <= y < HEIGHT and 0 <= x < WIDTH:
                        mask[y, x] = max(mask[y, x], intensity)

    # Generate veiny tendrils spreading from colonies
    for cx, cy, radius in colonies:
        # Number of main veins from this colony
        num_veins = random.randint(6, 10)

        for _ in range(num_veins):
            # Random angle for vein direction
            angle = random.uniform(0, 2 * math.pi)

            # Vein starts at edge of colony
            start_offset = radius * random.uniform(0.6, 0.9)
            start_x = cx + math.cos(angle) * start_offset
            start_y = cy + math.sin(angle) * start_offset

            # Vein properties (longer for taller texture)
            vein_length = random.uniform(20, 45)
            vein_thickness = random.uniform(1.2, 2.5)

            # Draw the vein with branching
            draw_vein(mask, start_x, start_y, angle, vein_length, vein_thickness)

    # Add some smaller spot details between colonies
    num_spots = random.randint(12, 18)
    for _ in range(num_spots):
        sx = random.randint(margin_x, WIDTH - margin_x)
        sy = random.randint(margin_y, HEIGHT - margin_y)
        spot_radius = random.randint(2, 4)

        for dy in range(-spot_radius, spot_radius + 1):
            for dx in range(-spot_radius, spot_radius + 1):
                dist = math.sqrt(dx**2 + dy**2)
                if dist < spot_radius:
                    intensity = 1.0 - (dist / spot_radius)
                    intensity *= random.uniform(0.5, 0.8)

                    y = sy + dy
                    x = sx + dx

                    if 0 <= y < HEIGHT and 0 <= x < WIDTH:
                        mask[y, x] = max(mask[y, x], intensity * 0.6)

    # Slight blur for organic feel (but keep veins sharp)
    from scipy.ndimage import gaussian_filter
    mask = gaussian_filter(mask, sigma=0.8)

    return mask


def apply_mould(base_img, mould_mask):
    """
    Apply dark greenish-black mould overlay to the base wallpaper texture.
    Mould dramatically darkens and shifts hue where present.
    """
    img_array = np.array(base_img, dtype=np.float32)

    # Expand mask to RGB channels
    mould_mask_rgb = np.stack([mould_mask] * 3, axis=-1)

    # Create mould color overlay (darker greenish-black)
    mould_overlay = np.zeros_like(img_array)
    for i in range(3):
        mould_overlay[:, :, i] = MOULD_DARK[i]

    # Strong darkening where mould is present
    # High mould intensity = very dark greenish-black
    # Low/no mould = original wallpaper
    darkening_factor = 1.0 - mould_mask_rgb * 0.85  # Heavy darkening
    result = img_array * darkening_factor

    # Shift hue strongly toward mould color
    result = result * (1.0 - mould_mask_rgb * 0.75) + mould_overlay * mould_mask_rgb * 0.75

    # Add texture variation to mould (organic surface texture)
    noise = np.random.uniform(0.85, 1.05, (HEIGHT, WIDTH, 3))
    mould_texture = result * noise
    result = result * (1.0 - mould_mask_rgb * 0.4) + mould_texture * mould_mask_rgb * 0.4

    # Add subtle green tint to mid-intensity areas (veins)
    mid_intensity = (mould_mask_rgb > 0.2) & (mould_mask_rgb < 0.7)
    green_tint = np.zeros_like(img_array)
    green_tint[:, :, 1] = 15  # Slight green boost
    result = np.where(mid_intensity, result + green_tint, result)

    # Clamp to valid range
    result = np.clip(result, 0, 255).astype(np.uint8)

    return Image.fromarray(result)


def main():
    print(f"Loading base texture from {BASE_TEXTURE_PATH}...")
    base_img = Image.open(BASE_TEXTURE_PATH).convert("RGB")

    if base_img.size != (WIDTH, HEIGHT):
        print(f"Warning: Base texture is {base_img.size}, resizing to {WIDTH}×{HEIGHT}")
        base_img = base_img.resize((WIDTH, HEIGHT), Image.LANCZOS)

    print("Generating mould colonies with veiny tendrils...")
    mould_mask = generate_mould_mask(num_colonies=5)

    print("Applying dark mould overlay...")
    result = apply_mould(base_img, mould_mask)

    print(f"Saving to {OUTPUT_PATH}...")
    result.save(OUTPUT_PATH)

    print("Done! Mouldy wall texture with veiny tendrils generated.")
    print(f"Output: {OUTPUT_PATH} ({WIDTH}×{HEIGHT}, tileable)")
    print("Features: Dark greenish-black mould colonies with spreading veins")


if __name__ == "__main__":
    main()
