#!/usr/bin/env python3
"""
Backrooms Level 0 Carpet Texture Generator
Generates a 128x128 tileable brown carpet texture with water staining and wear patterns.
"""

import numpy as np
from PIL import Image
import random

# Configuration
SIZE = 128
OUTPUT_PATH = "output.png"

# Base color range (brown/brownish-orange)
BASE_COLOR_MIN = np.array([92, 74, 58])    # #5C4A3A
BASE_COLOR_MAX = np.array([139, 111, 71])  # #8B6F47

# Stain color (darker, more saturated)
STAIN_COLOR = np.array([45, 35, 25])

# Wear color (lighter, more faded)
WEAR_COLOR = np.array([160, 130, 90])


def create_tileable_noise(size, scale=1.0, octaves=1):
    """
    Create tileable Perlin-like noise using NumPy.
    Uses simple gradient noise with proper wrapping.
    """
    # Create base noise that wraps properly
    noise = np.zeros((size, size))

    for octave in range(octaves):
        freq = 2 ** octave
        amp = 1.0 / (2 ** octave)

        # Generate random gradients at grid points
        grid_size = max(2, size // (4 * freq))
        gradients_x = np.random.randn(grid_size + 1, grid_size + 1) * amp
        gradients_y = np.random.randn(grid_size + 1, grid_size + 1) * amp

        # Make it wrap by copying edges
        gradients_x[-1, :] = gradients_x[0, :]
        gradients_x[:, -1] = gradients_x[:, 0]
        gradients_y[-1, :] = gradients_y[0, :]
        gradients_y[:, -1] = gradients_y[:, 0]

        # Interpolate to full resolution
        from scipy.ndimage import zoom
        grad_x = zoom(gradients_x[:-1, :-1], size / grid_size, order=1, mode='wrap')
        grad_y = zoom(gradients_y[:-1, :-1], size / grid_size, order=1, mode='wrap')

        # Combine into noise
        noise += (grad_x + grad_y) * scale

    return noise


def create_fiber_texture(size):
    """
    Create carpet fiber texture with directional grain.
    MORE PRONOUNCED for visibility.
    """
    # Random noise for fiber variation (INCREASED amplitude)
    fiber_noise = np.random.randn(size, size) * 25

    # Add directional texture (carpet pile direction) - MORE VISIBLE
    # Horizontal weave pattern
    for y in range(size):
        offset = int(np.sin(y * 0.5) * 3)
        fiber_noise[y] = np.roll(fiber_noise[y], offset)

    # Add vertical variation for weave effect
    for x in range(size):
        variation = np.sin(x * 0.4) * 2
        fiber_noise[:, x] += variation

    # Apply wrapping blur to smooth fibers
    try:
        from scipy.ndimage import gaussian_filter
        fiber_noise = gaussian_filter(fiber_noise, sigma=0.8, mode='wrap')
    except ImportError:
        pass

    return fiber_noise


def add_water_stains(img_array, num_stains=20):
    """
    Add MANY SMALL water stain patches for distributed wear.
    REDUCED radius to avoid breaking tiling.
    """
    for _ in range(num_stains):
        # Random center point
        cx = random.randint(0, SIZE - 1)
        cy = random.randint(0, SIZE - 1)

        # SMALLER radius (5-15px max) to avoid tiling issues
        radius = random.randint(5, 15)

        # REDUCED intensity for subtler effect
        intensity = random.uniform(0.15, 0.35)

        # Create stain with proper wrapping
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                # Calculate wrapped coordinates
                x = (cx + dx) % SIZE
                y = (cy + dy) % SIZE

                # Distance from center (NO wrapping for small stains)
                dist = np.sqrt(dx**2 + dy**2)

                if dist < radius:
                    # Soft falloff
                    falloff = 1.0 - (dist / radius) ** 2
                    stain_strength = falloff * intensity

                    # Shift toward darker brown (NOT near-black)
                    # Use BASE_COLOR_MIN instead of STAIN_COLOR
                    img_array[y, x] = (
                        img_array[y, x] * (1 - stain_strength) +
                        BASE_COLOR_MIN * stain_strength
                    )

    return img_array


def add_wear_patterns(img_array, num_patterns=30):
    """
    Add MANY SMALL wear patterns for distributed aging.
    SHORTER paths to avoid tiling breaks.
    """
    for _ in range(num_patterns):
        # Random starting point
        start_x = random.randint(0, SIZE - 1)
        start_y = random.randint(0, SIZE - 1)
        angle = random.uniform(0, 2 * np.pi)

        # SHORTER length (10-25px) to avoid edge seams
        length = random.randint(10, 25)

        # NARROWER width
        width = random.randint(4, 8)

        # Draw short path
        for i in range(length):
            cx = int(start_x + i * np.cos(angle)) % SIZE
            cy = int(start_y + i * np.sin(angle)) % SIZE

            # REDUCED intensity for subtle effect
            intensity = random.uniform(0.08, 0.15)

            # Add width to path with wrapping
            for dy in range(-width // 2, width // 2 + 1):
                for dx in range(-width // 2, width // 2 + 1):
                    x = (cx + dx) % SIZE
                    y = (cy + dy) % SIZE

                    dist = np.sqrt(dx**2 + dy**2)
                    if dist < width / 2:
                        falloff = 1.0 - (dist / (width / 2))
                        wear_strength = falloff * intensity

                        # Shift toward BASE_COLOR_MAX (lighter brown, stay in range)
                        img_array[y, x] = (
                            img_array[y, x] * (1 - wear_strength) +
                            BASE_COLOR_MAX * wear_strength
                        )

    return img_array


def generate_carpet_texture():
    """
    Generate the complete carpet texture.
    """
    print("Generating Backrooms carpet texture...")

    # Start with base color variation
    base_variation = np.random.rand(SIZE, SIZE)
    img_array = np.zeros((SIZE, SIZE, 3))

    for i in range(3):  # RGB channels
        img_array[:, :, i] = (
            BASE_COLOR_MIN[i] +
            (BASE_COLOR_MAX[i] - BASE_COLOR_MIN[i]) * base_variation
        )

    # Add fiber texture
    print("Adding fiber texture...")
    fiber = create_fiber_texture(SIZE)
    for i in range(3):
        img_array[:, :, i] += fiber

    # Add large-scale color variation (lighting, age)
    print("Adding color variation...")
    try:
        from scipy.ndimage import gaussian_filter
        large_scale = np.random.randn(SIZE, SIZE) * 20
        large_scale = gaussian_filter(large_scale, sigma=8, mode='wrap')
        for i in range(3):
            img_array[:, :, i] += large_scale
    except ImportError:
        # Fallback if scipy not available
        print("  (Skipping smooth variation - scipy not available)")

    # Add water stains (MANY SMALL ones)
    print("Adding water stains...")
    img_array = add_water_stains(img_array, num_stains=20)

    # Add wear patterns (MANY SMALL ones)
    print("Adding wear patterns...")
    img_array = add_wear_patterns(img_array, num_patterns=30)

    # Add fine detail noise with wrapping
    print("Adding fine detail...")
    detail_noise = np.random.randn(SIZE, SIZE, 3) * 5
    try:
        from scipy.ndimage import gaussian_filter
        # Apply wrapped blur to detail for smoothness
        for i in range(3):
            detail_noise[:, :, i] = gaussian_filter(detail_noise[:, :, i], sigma=0.5, mode='wrap')
    except ImportError:
        pass
    img_array += detail_noise

    # CRITICAL: Clamp to specified color range to avoid dark/bright outliers
    print("Clamping to color range...")
    img_array = np.clip(img_array, BASE_COLOR_MIN, BASE_COLOR_MAX).astype(np.uint8)

    # Convert to PIL Image
    img = Image.fromarray(img_array, mode='RGB')

    # Save
    print(f"Saving to {OUTPUT_PATH}...")
    img.save(OUTPUT_PATH)
    print(f"✓ Generated {SIZE}×{SIZE} tileable carpet texture")

    return img


def verify_tiling(img_path):
    """
    Create a 2x2 tiled version to visually verify seamlessness.
    """
    img = Image.open(img_path)
    width, height = img.size

    # Create 2x2 tiled image
    tiled = Image.new('RGB', (width * 2, height * 2))
    tiled.paste(img, (0, 0))
    tiled.paste(img, (width, 0))
    tiled.paste(img, (0, height))
    tiled.paste(img, (width, height))

    # Save tiled version for visual inspection
    tiled_path = OUTPUT_PATH.replace('.png', '_tiled_2x2.png')
    tiled.save(tiled_path)
    print(f"✓ Saved 2x2 tiled version to {tiled_path} for seam verification")

    return tiled


if __name__ == "__main__":
    # Set random seed for reproducibility
    np.random.seed(42)
    random.seed(42)

    generate_carpet_texture()

    # Verify output
    img = Image.open(OUTPUT_PATH)
    print(f"✓ Verified: {img.size[0]}×{img.size[1]} pixels, {img.mode} mode")

    # Verify tiling
    print("\nGenerating 2x2 tiled preview...")
    verify_tiling(OUTPUT_PATH)
