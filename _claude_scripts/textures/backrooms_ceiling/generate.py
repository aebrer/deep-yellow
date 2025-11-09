#!/usr/bin/env python3
"""
Backrooms Level 0 Ceiling Texture Generator
Generates 128×128 tileable acoustic ceiling tile texture with perforation pattern
"""

from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import random

# Configuration
SIZE = 128
OUTPUT_PATH = "output.png"

# Color palette (off-white/beige/yellowed ceiling tiles)
BASE_COLOR = (220, 210, 195)  # Slightly more yellowed base
HIGHLIGHT_COLOR = (240, 232, 216)  # #F0E8D8 - lighter areas
STAIN_COLOR_LIGHT = (200, 176, 144)  # #C8B090 - yellowed water stain
STAIN_COLOR_DARK = (212, 188, 156)  # #D4BC9C - darker water stain
PERFORATION_COLOR = (160, 150, 135)  # Darker color for acoustic holes

# Set random seed for reproducibility
random.seed(42)
np.random.seed(42)


def create_base_layer():
    """Create base off-white/beige layer with more aging variation"""
    img_array = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)

    # Start with base color
    img_array[:, :] = BASE_COLOR

    # Add more pronounced color variation for aging effect
    from scipy.ndimage import gaussian_filter

    # Large-scale yellowing variation (aged patches)
    for c in range(3):
        # More variation, especially in red/yellow channels for aging
        variation_amount = 15 if c < 2 else 10  # More in R/G, less in B
        noise = np.random.randn(SIZE, SIZE) * variation_amount
        noise = gaussian_filter(noise, sigma=12, mode='wrap')
        img_array[:, :, c] = np.clip(img_array[:, :, c] + noise, 0, 255)

    # Add medium-scale blotchiness (uneven aging)
    for c in range(3):
        blotch = np.random.randn(SIZE, SIZE) * 8
        blotch = gaussian_filter(blotch, sigma=6, mode='wrap')
        img_array[:, :, c] = np.clip(img_array[:, :, c] + blotch, 0, 255)

    return img_array


def add_perforation_pattern(img_array):
    """Add acoustic tile perforation pattern - LARGER holes, WIDER spacing"""
    # Perforation grid parameters (2-4mm holes, 6-10mm spacing at scale)
    spacing = 10  # Distance between perforations (wider spacing)
    hole_radius = 1.8  # Radius of each perforation (larger holes)

    # Create perforation mask
    perf_mask = np.ones((SIZE, SIZE), dtype=float)

    for y in range(0, SIZE, spacing):
        for x in range(0, SIZE, spacing):
            # Add some randomness to perforation depth
            depth = random.uniform(0.65, 0.90)

            # Draw circular perforation with anti-aliasing
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    px = (x + dx) % SIZE
                    py = (y + dy) % SIZE

                    dist = np.sqrt(dx*dx + dy*dy)
                    if dist <= hole_radius:
                        # Anti-aliased edge
                        alpha = max(0, 1 - (dist / hole_radius))
                        perf_mask[py, px] *= (1 - alpha * (1 - depth))

    # Apply perforation mask to darken holes
    for c in range(3):
        img_array[:, :, c] = img_array[:, :, c] * perf_mask

    return img_array


def add_water_stains(img_array):
    """Add prominent brown/yellow water damage patches"""
    num_stains = random.randint(2, 3)  # 2-3 irregular patches

    for i in range(num_stains):
        # Random stain center (can wrap edges)
        cx = random.randint(0, SIZE - 1)
        cy = random.randint(0, SIZE - 1)

        # Stain size and intensity - MORE PROMINENT
        radius = random.randint(20, 45)
        intensity = random.uniform(0.35, 0.55)  # Stronger staining

        # Choose stain color (darker brown/yellow tones)
        stain_color = STAIN_COLOR_DARK if i % 2 == 0 else STAIN_COLOR_LIGHT

        # Create very irregular stain shape with multiple noise sources
        for y in range(SIZE):
            for x in range(SIZE):
                # Calculate wrapped distance
                dx = min(abs(x - cx), SIZE - abs(x - cx))
                dy = min(abs(y - cy), SIZE - abs(y - cy))
                dist = np.sqrt(dx*dx + dy*dy)

                if dist < radius:
                    # Very irregular falloff with strong noise
                    noise_factor = random.uniform(0.5, 1.5)
                    falloff = (1 - (dist / radius)) * noise_factor
                    falloff = max(0, min(1, falloff))

                    # Add organic tendrils and irregular edges
                    angle = np.arctan2(dy, dx)
                    tendril_noise = np.sin(angle * 4 + random.random() * 3) * 0.3
                    falloff = falloff * (1 + tendril_noise)
                    falloff = max(0, min(1, falloff))

                    alpha = intensity * falloff

                    # Blend toward darker yellowed stain color
                    for c in range(3):
                        current = img_array[y, x, c]
                        target = stain_color[c]
                        img_array[y, x, c] = int(current * (1 - alpha) + target * alpha)

    return img_array


def add_fine_texture(img_array):
    """Add pronounced surface texture with dimpling effect"""
    from scipy.ndimage import gaussian_filter

    # High-frequency noise for fiber texture
    fiber_noise = np.random.randn(SIZE, SIZE) * 8
    fiber_noise = gaussian_filter(fiber_noise, sigma=0.8, mode='wrap')

    # Medium-frequency dimpling (small depressions in surface)
    dimple_noise = np.random.randn(SIZE, SIZE) * 5
    dimple_noise = gaussian_filter(dimple_noise, sigma=2.5, mode='wrap')

    # Combine both texture types
    combined_noise = fiber_noise + dimple_noise

    # Apply to all channels
    for c in range(3):
        img_array[:, :, c] = np.clip(img_array[:, :, c] + combined_noise, 0, 255)

    return img_array


def add_tile_grid_lines(img_array):
    """Add MORE VISIBLE grid lines where ceiling tiles meet"""
    # Tiles are typically 2×2 feet (simulate 64×64 pixel tiles in 128×128 texture)
    tile_size = 64
    line_color = (170, 160, 145)  # Darker line color

    # Vertical line (wider, more visible)
    for y in range(SIZE):
        for offset in [-2, -1, 0, 1, 2]:
            x = (tile_size + offset) % SIZE
            # Stronger alpha, especially for center
            alpha = 0.5 if offset == 0 else 0.35

            for c in range(3):
                current = img_array[y, x, c]
                target = line_color[c]
                img_array[y, x, c] = int(current * (1 - alpha) + target * alpha)

    # Horizontal line (wider, more visible)
    for x in range(SIZE):
        for offset in [-2, -1, 0, 1, 2]:
            y = (tile_size + offset) % SIZE
            # Stronger alpha, especially for center
            alpha = 0.5 if offset == 0 else 0.35

            for c in range(3):
                current = img_array[y, x, c]
                target = line_color[c]
                img_array[y, x, c] = int(current * (1 - alpha) + target * alpha)

    return img_array


def add_age_darkening(img_array):
    """Add subtle overall darkening/aging effect"""
    # Slight darkening in corners and edges for depth
    darken_mask = np.ones((SIZE, SIZE), dtype=float)

    center_x, center_y = SIZE // 2, SIZE // 2

    for y in range(SIZE):
        for x in range(SIZE):
            # Distance from center using wrapping
            dx = min(abs(x - center_x), SIZE - abs(x - center_x))
            dy = min(abs(y - center_y), SIZE - abs(y - center_y))
            dist = np.sqrt(dx*dx + dy*dy)

            # Very subtle vignette
            max_dist = SIZE / 2
            vignette = 1 - (dist / max_dist) * 0.08
            darken_mask[y, x] = vignette

    # Apply darkening
    for c in range(3):
        img_array[:, :, c] = img_array[:, :, c] * darken_mask

    return img_array


def generate_ceiling_texture():
    """Main generation function"""
    print("Generating Backrooms ceiling texture (128×128)...")

    # Step 1: Base layer
    print("  • Creating base off-white layer...")
    img_array = create_base_layer()

    # Step 2: Perforation pattern
    print("  • Adding acoustic tile perforations...")
    img_array = add_perforation_pattern(img_array)

    # Step 3: Water stains
    print("  • Adding water stains and discoloration...")
    img_array = add_water_stains(img_array)

    # Step 4: Fine texture
    print("  • Adding fine fiber texture...")
    img_array = add_fine_texture(img_array)

    # Step 5: Tile grid lines
    print("  • Adding subtle tile grid lines...")
    img_array = add_tile_grid_lines(img_array)

    # Step 6: Age darkening
    print("  • Applying age darkening effect...")
    img_array = add_age_darkening(img_array)

    # Ensure values are in valid range
    img_array = np.clip(img_array, 0, 255).astype(np.uint8)

    # Convert to PIL Image
    img = Image.fromarray(img_array, mode='RGB')

    # Save
    img.save(OUTPUT_PATH)
    print(f"✓ Saved to {OUTPUT_PATH}")
    print(f"  Size: {SIZE}×{SIZE} pixels")
    print(f"  Format: PNG, RGB")
    print(f"  Tileable: Yes (seamless wrapping)")

    return img


if __name__ == "__main__":
    try:
        generate_ceiling_texture()
        print("\n✓ Generation complete!")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
