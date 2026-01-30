#!/usr/bin/env python3
"""
Generate a tileable floor puddle texture for DEEP YELLOW.

Creates a water puddle on brown carpet by:
1. Loading the base carpet texture
2. Darkening a puddle-shaped area
3. Adding blue/grey water tint
4. Adding subtle highlights for water reflection
5. Using modulo wrapping to ensure seamless tiling
"""

from PIL import Image
import numpy as np
import math

# Constants
SIZE = 128
BASE_CARPET_PATH = "../../../assets/levels/level_00/textures/carpet_brown.png"
OUTPUT_PATH = "output.png"

def load_base_carpet():
    """Load the base brown carpet texture."""
    img = Image.open(BASE_CARPET_PATH).convert('RGB')
    # Ensure it's 128x128
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.Resampling.NEAREST)
    return np.array(img, dtype=np.float32)

def create_puddle_mask(size):
    """
    Create a puddle-shaped alpha mask using Perlin-like noise.
    Returns values from 0 (dry) to 1 (fully wet).
    """
    mask = np.zeros((size, size), dtype=np.float32)

    # Create an organic puddle shape using multiple overlapping circles
    # with noise to make it irregular

    # Main puddle center (slightly off-center for more natural look)
    cx, cy = size // 2 + 10, size // 2 - 8

    # Multiple overlapping circular regions for organic shape
    puddle_regions = [
        (cx, cy, 40, 1.0),           # Main puddle center
        (cx - 15, cy + 12, 25, 0.8), # Extension to lower-left
        (cx + 18, cy - 10, 22, 0.7), # Extension to upper-right
        (cx + 5, cy + 20, 18, 0.6),  # Small lobe bottom
    ]

    for center_x, center_y, radius, intensity in puddle_regions:
        for y in range(size):
            for x in range(size):
                # Use modulo wrapping for toroidal distance calculation
                # This ensures the puddle tiles seamlessly
                dx_raw = x - center_x
                dy_raw = y - center_y

                # Wrap around edges (toroidal distance)
                dx = min(abs(dx_raw), size - abs(dx_raw))
                dy = min(abs(dy_raw), size - abs(dy_raw))

                dist = math.sqrt(dx * dx + dy * dy)

                if dist < radius:
                    # Smooth falloff from center
                    falloff = 1.0 - (dist / radius) ** 1.5
                    mask[y, x] = max(mask[y, x], falloff * intensity)

    # Add organic noise to puddle edges
    np.random.seed(42)  # Reproducible
    noise = np.random.rand(size, size) * 0.2 - 0.1
    mask = np.clip(mask + noise, 0, 1)

    # Smooth the mask slightly to reduce harsh edges
    from scipy.ndimage import gaussian_filter
    mask = gaussian_filter(mask, sigma=2.0)

    return mask

def apply_puddle_effect(carpet_array, puddle_mask):
    """
    Apply water puddle effect to carpet texture.

    - Darken the carpet in wet areas
    - Add blue/grey tint
    - Add subtle highlights for water reflection
    """
    result = carpet_array.copy()

    # Water color tint (dark blue-grey)
    water_tint = np.array([60, 70, 85], dtype=np.float32)

    # For each pixel, blend between dry carpet and wet carpet
    for y in range(SIZE):
        for x in range(SIZE):
            wetness = puddle_mask[y, x]

            if wetness > 0.01:  # Only process wet areas
                dry_color = carpet_array[y, x]

                # Wet effect: darken and add blue tint
                darkened = dry_color * (0.5 + 0.3 * (1 - wetness))  # Darker when wetter
                wet_color = darkened * 0.7 + water_tint * 0.3  # Mix in water tint

                # Blend based on wetness
                result[y, x] = dry_color * (1 - wetness) + wet_color * wetness

    # Add subtle specular highlights on water surface
    # Highlights appear at certain angles (simulate light reflection)
    highlight_center_x = SIZE // 2 + 20
    highlight_center_y = SIZE // 2 - 15

    for y in range(SIZE):
        for x in range(SIZE):
            wetness = puddle_mask[y, x]

            if wetness > 0.3:  # Only on wet areas
                # Calculate distance to highlight center (with wrapping)
                dx_raw = x - highlight_center_x
                dy_raw = y - highlight_center_y
                dx = min(abs(dx_raw), SIZE - abs(dx_raw))
                dy = min(abs(dy_raw), SIZE - abs(dy_raw))
                dist = math.sqrt(dx * dx + dy * dy)

                # Create a soft highlight spot
                if dist < 30:
                    highlight_strength = (1.0 - dist / 30) ** 2 * wetness * 0.25
                    result[y, x] = np.clip(result[y, x] + highlight_strength * 80, 0, 255)

    return result

def main():
    print("Loading base carpet texture...")
    carpet = load_base_carpet()

    print("Generating puddle mask...")
    puddle_mask = create_puddle_mask(SIZE)

    print("Applying puddle effect...")
    result = apply_puddle_effect(carpet, puddle_mask)

    print("Saving output...")
    result_img = Image.fromarray(result.astype(np.uint8), 'RGB')
    result_img.save(OUTPUT_PATH)

    print(f"✓ Generated tileable floor puddle texture: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}x{SIZE}")
    print(f"  Puddle coverage: ~{(puddle_mask > 0.1).sum() / (SIZE * SIZE) * 100:.1f}%")

if __name__ == "__main__":
    main()
