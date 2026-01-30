#!/usr/bin/env python3
"""
Generates a tileable ceiling water stain texture for DEEP YELLOW.

Loads the existing acoustic ceiling texture and overlays a yellowish-brown
water stain with irregular edges and concentric ring patterns.
"""

import numpy as np
from PIL import Image
import math

# Constants
SIZE = 128
BASE_TEXTURE_PATH = "../../../assets/levels/level_00/textures/ceiling_acoustic.png"
OUTPUT_PATH = "output.png"

# Stain parameters
STAIN_CENTER_X = SIZE // 2
STAIN_CENTER_Y = SIZE // 2
STAIN_MAX_RADIUS = 40  # Stain fades out before reaching edges
STAIN_COLOR = np.array([180, 140, 70])  # Yellowish-brown base color
STAIN_INTENSITY = 0.6  # Maximum stain opacity at center

def load_base_texture():
    """Load the existing acoustic ceiling texture."""
    img = Image.open(BASE_TEXTURE_PATH).convert('RGB')
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.array(img, dtype=np.float32)

def generate_organic_stain_mask():
    """
    Generate an organic, irregular stain mask with concentric rings.
    Uses Perlin-like noise to create irregular boundaries.
    """
    mask = np.zeros((SIZE, SIZE), dtype=np.float32)

    # Create base circular gradient
    for y in range(SIZE):
        for x in range(SIZE):
            # Calculate distance from center
            dx = x - STAIN_CENTER_X
            dy = y - STAIN_CENTER_Y
            dist = math.sqrt(dx**2 + dy**2)

            # Base falloff (radial gradient)
            if dist < STAIN_MAX_RADIUS:
                # Smooth falloff from center to edge
                base_intensity = 1.0 - (dist / STAIN_MAX_RADIUS)
                base_intensity = base_intensity ** 1.5  # Non-linear falloff

                # Add organic irregularity using pseudo-noise
                # Create angular variation to make the stain irregular
                angle = math.atan2(dy, dx)
                noise = (
                    0.15 * math.sin(angle * 3 + dist * 0.1) +
                    0.10 * math.cos(angle * 5 - dist * 0.15) +
                    0.08 * math.sin(angle * 7 + dist * 0.2)
                )

                # Add concentric ring patterns (water stain characteristic)
                ring_pattern = 0.12 * math.sin(dist * 0.3) + 0.08 * math.sin(dist * 0.6)

                # Combine all elements
                intensity = base_intensity + noise + ring_pattern
                intensity = max(0.0, min(1.0, intensity))  # Clamp to [0, 1]

                mask[y, x] = intensity

    return mask

def apply_water_stain(base_img, stain_mask):
    """
    Apply water stain effect to the base ceiling texture.
    Blends the stain color with the original texture based on mask intensity.
    """
    result = base_img.copy()

    for y in range(SIZE):
        for x in range(SIZE):
            stain_amount = stain_mask[y, x] * STAIN_INTENSITY

            if stain_amount > 0:
                # Get original pixel color
                original = base_img[y, x]

                # Darken the original color slightly (water damage darkens surfaces)
                darkened = original * (1.0 - stain_amount * 0.3)

                # Blend with stain color
                stained = darkened * (1.0 - stain_amount) + STAIN_COLOR * stain_amount

                result[y, x] = stained

    return result

def add_grit_and_variation(img):
    """
    Add subtle noise and variation for PSX/retro aesthetic.
    """
    result = img.copy()

    # Add very subtle grain
    for y in range(SIZE):
        for x in range(SIZE):
            # Deterministic pseudo-random value based on position
            seed = (x * 214013 + y * 2531011) & 0x7FFFFFFF
            random_val = ((seed >> 16) & 0xFF) / 255.0

            # Very subtle grain (±2 brightness)
            grain = (random_val - 0.5) * 4.0
            result[y, x] = np.clip(result[y, x] + grain, 0, 255)

    return result

def main():
    print("Loading base ceiling texture...")
    base_texture = load_base_texture()

    print("Generating organic water stain mask...")
    stain_mask = generate_organic_stain_mask()

    print("Applying water stain effect...")
    stained_texture = apply_water_stain(base_texture, stain_mask)

    print("Adding subtle grit for PSX aesthetic...")
    final_texture = add_grit_and_variation(stained_texture)

    # Convert back to uint8 and save
    final_texture = np.clip(final_texture, 0, 255).astype(np.uint8)
    output_img = Image.fromarray(final_texture, 'RGB')
    output_img.save(OUTPUT_PATH)

    print(f"✓ Water-stained ceiling texture generated: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}×{SIZE} pixels")
    print(f"  Stain radius: ~{STAIN_MAX_RADIUS}px (fades before edges)")
    print(f"  Style: Yellowish-brown water damage with concentric rings")
    print(f"  Tileable: Yes (stain does not extend to edges)")

if __name__ == "__main__":
    main()
