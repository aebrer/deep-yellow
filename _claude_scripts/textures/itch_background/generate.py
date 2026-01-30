#!/usr/bin/env python3
"""
Generate tileable background for itch.io page.

Based on the Backrooms Level 0 wallpaper texture, but heavily darkened
and desaturated to create a subtle, non-distracting background pattern.
"""

from PIL import Image, ImageEnhance, ImageFilter
import numpy as np

# Paths
SOURCE_TEXTURE = "/home/drew/projects/deep_yellow/assets/levels/level_00/textures/wallpaper_yellow.png"
OUTPUT_PATH = "/home/drew/projects/deep_yellow/media/itch_assets/background.png"

# Parameters
OUTPUT_SIZE = 256
BRIGHTNESS_FACTOR = 0.25  # Darken to 25% of original
SATURATION_FACTOR = 0.15  # Desaturate to 15% (nearly grayscale)
NOISE_INTENSITY = 8  # Subtle grain intensity
BLUR_AMOUNT = 0.5  # Tiny bit of blur to soften the pattern


def tile_image(img: Image.Image, target_size: int) -> Image.Image:
    """
    Tile the source image to fill the target size.

    Args:
        img: Source image (should be tileable)
        target_size: Target width/height (square output)

    Returns:
        Tiled image at target_size x target_size
    """
    src_w, src_h = img.size
    tiles_x = (target_size + src_w - 1) // src_w  # Ceiling division
    tiles_y = (target_size + src_h - 1) // src_h

    # Create tiled image
    tiled = Image.new('RGB', (tiles_x * src_w, tiles_y * src_h))
    for y in range(tiles_y):
        for x in range(tiles_x):
            tiled.paste(img, (x * src_w, y * src_h))

    # Crop to exact target size
    return tiled.crop((0, 0, target_size, target_size))


def add_grain(img: Image.Image, intensity: int) -> Image.Image:
    """
    Add subtle film grain / noise to the image.

    Args:
        img: Input image
        intensity: Noise intensity (0-255 range)

    Returns:
        Image with grain added
    """
    img_array = np.array(img, dtype=np.float32)

    # Generate noise
    noise = np.random.normal(0, intensity, img_array.shape)

    # Add noise and clamp
    noisy = img_array + noise
    noisy = np.clip(noisy, 0, 255).astype(np.uint8)

    return Image.fromarray(noisy)


def main():
    """Generate the itch.io background texture."""
    print(f"Loading source texture: {SOURCE_TEXTURE}")
    source = Image.open(SOURCE_TEXTURE).convert('RGB')
    print(f"  Source size: {source.size}")

    # Tile to target size if needed
    if source.size[0] != OUTPUT_SIZE or source.size[1] != OUTPUT_SIZE:
        print(f"Tiling to {OUTPUT_SIZE}x{OUTPUT_SIZE}...")
        img = tile_image(source, OUTPUT_SIZE)
    else:
        img = source

    # Heavily desaturate (nearly grayscale with hint of color)
    print(f"Desaturating to {SATURATION_FACTOR*100:.0f}%...")
    enhancer = ImageEnhance.Color(img)
    img = enhancer.enhance(SATURATION_FACTOR)

    # Heavily darken
    print(f"Darkening to {BRIGHTNESS_FACTOR*100:.0f}%...")
    enhancer = ImageEnhance.Brightness(img)
    img = enhancer.enhance(BRIGHTNESS_FACTOR)

    # Slight blur to soften the pattern
    if BLUR_AMOUNT > 0:
        print(f"Applying subtle blur (radius={BLUR_AMOUNT})...")
        img = img.filter(ImageFilter.GaussianBlur(radius=BLUR_AMOUNT))

    # Add subtle grain for texture
    print(f"Adding grain (intensity={NOISE_INTENSITY})...")
    img = add_grain(img, NOISE_INTENSITY)

    # Save output
    print(f"Saving to: {OUTPUT_PATH}")
    img.save(OUTPUT_PATH, 'PNG', optimize=True)

    # Report final stats
    img_array = np.array(img)
    avg_brightness = img_array.mean()
    print(f"\n✓ Background generated!")
    print(f"  Size: {img.size}")
    print(f"  Average brightness: {avg_brightness:.1f} / 255 ({avg_brightness/255*100:.1f}%)")
    print(f"  Output: {OUTPUT_PATH}")


if __name__ == '__main__':
    main()
