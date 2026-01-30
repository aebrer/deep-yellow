#!/usr/bin/env python3
"""
Generate itch.io banner for DEEP YELLOW
Output: 960x300 panoramic banner with game title and sprites
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import numpy as np
from pathlib import Path

# Constants
WIDTH = 960
HEIGHT = 300
OUTPUT_PATH = Path(__file__).parent / "output.png"

# Asset paths (relative to project root)
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
WALLPAPER_PATH = PROJECT_ROOT / "assets/levels/level_00/textures/wallpaper_yellow.png"
HAZMAT_PATH = PROJECT_ROOT / "assets/sprites/player/hazmat_suit.png"
SMILER_PATH = PROJECT_ROOT / "assets/textures/entities/smiler.png"
BACTERIA_PATH = PROJECT_ROOT / "assets/textures/entities/bacteria_spreader.png"
ITEMS_DIR = PROJECT_ROOT / "assets/textures/items"


def load_image(path, scale=1.0):
    """Load image and optionally scale it"""
    img = Image.open(path).convert("RGBA")
    if scale != 1.0:
        new_size = (int(img.width * scale), int(img.height * scale))
        img = img.resize(new_size, Image.NEAREST)
    return img


def tile_wallpaper():
    """Create tiled wallpaper background"""
    wallpaper = load_image(WALLPAPER_PATH)

    # Create base canvas
    bg = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))

    # Tile wallpaper
    tile_w, tile_h = wallpaper.size
    for y in range(0, HEIGHT, tile_h):
        for x in range(0, WIDTH, tile_w):
            bg.paste(wallpaper, (x, y), wallpaper)

    # Convert to RGB for processing
    bg = bg.convert("RGB")

    # Darken and desaturate slightly for contrast
    enhancer = ImageEnhance.Brightness(bg)
    bg = enhancer.enhance(0.7)

    enhancer = ImageEnhance.Color(bg)
    bg = enhancer.enhance(0.6)

    # Add vignette (darker edges)
    arr = np.array(bg, dtype=np.float32)

    # Create radial gradient for vignette
    y_coords, x_coords = np.ogrid[:HEIGHT, :WIDTH]
    center_y, center_x = HEIGHT / 2, WIDTH / 2

    # Distance from center, normalized
    max_dist = np.sqrt((WIDTH/2)**2 + (HEIGHT/2)**2)
    dist = np.sqrt((x_coords - center_x)**2 + (y_coords - center_y)**2)
    vignette = 1.0 - (dist / max_dist) * 0.5  # Darken edges by 50%

    # Apply vignette
    vignette = vignette[:, :, np.newaxis]  # Add channel dimension
    arr = arr * vignette
    arr = np.clip(arr, 0, 255).astype(np.uint8)

    return Image.fromarray(arr).convert("RGBA")


def add_scanlines(img):
    """Add PSX-style scanlines"""
    arr = np.array(img)

    # Every other row, darken slightly
    for y in range(0, HEIGHT, 2):
        arr[y] = (arr[y] * 0.85).astype(np.uint8)

    return Image.fromarray(arr)


def add_noise(img, intensity=0.03):
    """Add PSX-style noise"""
    arr = np.array(img, dtype=np.float32)

    # Generate noise
    noise = np.random.normal(0, intensity * 255, arr.shape)

    # Add noise
    arr = arr + noise
    arr = np.clip(arr, 0, 255).astype(np.uint8)

    return Image.fromarray(arr)


def draw_text_with_outline(draw, text, position, font_size=60, outline_width=4):
    """Draw text with thick black outline and chromatic aberration"""
    # Try to use a bold font, fall back to default
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except:
        font = ImageFont.load_default()

    x, y = position

    # Get text bounding box to properly center it
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]

    # Adjust x position to center the text
    x = x - text_width // 2

    # Draw black outline (offset in all directions)
    for offset_x in range(-outline_width, outline_width + 1):
        for offset_y in range(-outline_width, outline_width + 1):
            if offset_x != 0 or offset_y != 0:
                draw.text((x + offset_x, y + offset_y), text, font=font, fill=(0, 0, 0, 255))

    # Draw deep yellow main text
    draw.text((x, y), text, font=font, fill=(255, 210, 50, 255))

    return font


def add_chromatic_aberration(img, offset=2):
    """Add RGB split effect to the image"""
    arr = np.array(img)

    # Split channels
    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    a = arr[:, :, 3] if arr.shape[2] == 4 else None

    # Shift red left, blue right
    r_shifted = np.roll(r, -offset, axis=1)
    b_shifted = np.roll(b, offset, axis=1)

    # Recombine
    result = np.stack([r_shifted, g, b_shifted], axis=2)
    if a is not None:
        result = np.concatenate([result, a[:, :, np.newaxis]], axis=2)

    return Image.fromarray(result.astype(np.uint8))


def composite_sprite(canvas, sprite_path, position, scale=1.0, flip=False):
    """Paste sprite onto canvas at position"""
    sprite = load_image(sprite_path, scale)

    if flip:
        sprite = sprite.transpose(Image.FLIP_LEFT_RIGHT)

    # Paste with alpha
    canvas.paste(sprite, position, sprite)


def generate_banner():
    """Generate the complete banner"""
    print("Generating DEEP YELLOW itch.io banner...")

    # Create tiled wallpaper background
    print("  → Tiling wallpaper background...")
    canvas = tile_wallpaper()

    # Add title text in upper portion
    print("  → Adding title text...")
    draw = ImageDraw.Draw(canvas)

    # Title on one line
    title = "DEEP YELLOW"
    font = draw_text_with_outline(
        draw,
        title,
        (WIDTH // 2, 40),  # Centered horizontally, positioned in upper portion
        font_size=56,
        outline_width=5
    )

    # Add sprites scattered across the width
    print("  → Adding sprites...")

    # Shift offset for all collage sprites (up and to the left)
    SHIFT_X = -40
    SHIFT_Y = -30

    # Hazmat player (left-center area) - keep in bottom half
    composite_sprite(canvas, HAZMAT_PATH, (max(0, 200 + SHIFT_X), 160 + SHIFT_Y), scale=2.2)

    # Smiler lurking on right side (just eyes/grin peeking) - bottom right
    composite_sprite(canvas, SMILER_PATH, (max(0, 820 + SHIFT_X), 180 + SHIFT_Y), scale=1.8)

    # Bacteria spreader (left side) - bottom
    composite_sprite(canvas, BACTERIA_PATH, (max(0, 60 + SHIFT_X), 200 + SHIFT_Y), scale=1.5)

    # Scatter MANY items along the bottom - full width
    # Bottom portion = y > 150, spread across full 960px width

    # Left cluster (x: 0-300)
    if (ITEMS_DIR / "shovel.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "shovel.png", (max(0, 20 + SHIFT_X), 220 + SHIFT_Y), scale=1.8)

    if (ITEMS_DIR / "brass_knuckles.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "brass_knuckles.png", (max(0, 140 + SHIFT_X), 240 + SHIFT_Y), scale=1.5)

    if (ITEMS_DIR / "almond_water.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "almond_water.png", (max(0, 280 + SHIFT_X), 230 + SHIFT_Y), scale=1.2)

    # Left-center cluster (x: 300-480)
    if (ITEMS_DIR / "binoculars.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "binoculars.png", (max(0, 320 + SHIFT_X), 215 + SHIFT_Y), scale=1.6)

    if (ITEMS_DIR / "flashlight.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "flashlight.png", (max(0, 430 + SHIFT_X), 235 + SHIFT_Y), scale=1.4)

    if (ITEMS_DIR / "roman_coin.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "roman_coin.png", (max(0, 380 + SHIFT_X), 260 + SHIFT_Y), scale=2.0)

    # Center-right cluster (x: 480-660)
    if (ITEMS_DIR / "trail_mix.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "trail_mix.png", (max(0, 500 + SHIFT_X), 225 + SHIFT_Y), scale=1.5)

    if (ITEMS_DIR / "lucky_rabbits_foot.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "lucky_rabbits_foot.png", (max(0, 580 + SHIFT_X), 245 + SHIFT_Y), scale=1.7)

    if (ITEMS_DIR / "lucky_o_milk.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "lucky_o_milk.png", (max(0, 640 + SHIFT_X), 230 + SHIFT_Y), scale=1.3)

    # Right cluster (x: 660-840)
    if (ITEMS_DIR / "coachs_whistle.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "coachs_whistle.png", (max(0, 680 + SHIFT_X), 215 + SHIFT_Y), scale=1.6)

    if (ITEMS_DIR / "wheatie_os.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "wheatie_os.png", (max(0, 760 + SHIFT_X), 240 + SHIFT_Y), scale=1.4)

    if (ITEMS_DIR / "drinking_bird.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "drinking_bird.png", (max(0, 720 + SHIFT_X), 180 + SHIFT_Y), scale=2.5)

    # Far right (x: 840-960)
    if (ITEMS_DIR / "antigonous_notebook.png").exists():
        composite_sprite(canvas, ITEMS_DIR / "antigonous_notebook.png", (max(0, 890 + SHIFT_X), 220 + SHIFT_Y), scale=1.5)

    if (PROJECT_ROOT / "assets/textures/entities/bacteria_motherload.png").exists():
        composite_sprite(canvas, PROJECT_ROOT / "assets/textures/entities/bacteria_motherload.png", (max(0, 920 + SHIFT_X), 160 + SHIFT_Y), scale=1.2)

    # Add PSX effects
    print("  → Applying PSX effects...")
    canvas = add_scanlines(canvas)
    canvas = add_noise(canvas, intensity=0.02)
    canvas = add_chromatic_aberration(canvas, offset=2)

    # Save output
    print(f"  → Saving to {OUTPUT_PATH}...")
    canvas.save(OUTPUT_PATH)

    # Verify dimensions
    saved = Image.open(OUTPUT_PATH)
    print(f"\n✓ Banner generated successfully!")
    print(f"  Size: {saved.width}×{saved.height}")
    print(f"  Path: {OUTPUT_PATH}")


if __name__ == "__main__":
    generate_banner()
