#!/usr/bin/env python3
"""
Generate itch.io cover image for DEEP YELLOW.

Creates a 630x500px promotional image using existing game assets.
REVISION 2: Based on user feedback:
- Removed dark title background bar (text directly on image)
- Increased title text size
- Better centered title text
- Fixed sprite cutoffs with proper margins
- Added more collage elements (more items scattered around)
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
from pathlib import Path

# Paths
PROJECT_ROOT = Path("/home/drew/projects/deep_yellow")
OUTPUT_PATH = PROJECT_ROOT / "media" / "itch_assets" / "cover.png"

# Asset paths
ASSETS = {
    "wallpaper": PROJECT_ROOT / "assets/levels/level_00/textures/wallpaper_yellow.png",
    "player": PROJECT_ROOT / "assets/sprites/player/hazmat_suit.png",
    "smiler": PROJECT_ROOT / "assets/textures/entities/smiler.png",
    "bacteria_spreader": PROJECT_ROOT / "assets/textures/entities/bacteria_spreader.png",
    "bacteria_motherload": PROJECT_ROOT / "assets/textures/entities/bacteria_motherload.png",
    "almond_water": PROJECT_ROOT / "assets/textures/items/almond_water.png",
    "baseball_bat": PROJECT_ROOT / "assets/textures/items/baseball_bat.png",
    "wheatie_os": PROJECT_ROOT / "assets/textures/items/wheatie_os.png",
    "drinking_bird": PROJECT_ROOT / "assets/textures/items/drinking_bird.png",
    "shovel": PROJECT_ROOT / "assets/textures/items/shovel.png",
    "binoculars": PROJECT_ROOT / "assets/textures/items/binoculars.png",
    "brass_knuckles": PROJECT_ROOT / "assets/textures/items/brass_knuckles.png",
    "roman_coin": PROJECT_ROOT / "assets/textures/items/roman_coin.png",
    "trail_mix": PROJECT_ROOT / "assets/textures/items/trail_mix.png",
    "lucky_rabbits_foot": PROJECT_ROOT / "assets/textures/items/lucky_rabbits_foot.png",
    "coachs_whistle": PROJECT_ROOT / "assets/textures/items/coachs_whistle.png",
}

# Canvas size
WIDTH, HEIGHT = 630, 500


def tile_texture(img, width, height):
    """Tile a texture to fill the given dimensions."""
    tile_w, tile_h = img.size
    result = Image.new("RGBA", (width, height))

    for y in range(0, height, tile_h):
        for x in range(0, width, tile_w):
            result.paste(img, (x, y))

    return result


def darken_image(img, factor=0.85):
    """Darken an image by multiplying RGB values."""
    arr = np.array(img).astype(float)
    for i in range(3):  # RGB channels only
        arr[:, :, i] *= factor
    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def desaturate_image(img, factor=0.7):
    """Reduce saturation of an image."""
    arr = np.array(img).astype(float)

    # Convert to grayscale (preserve shape)
    gray = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]

    # Blend with original
    for i in range(3):
        arr[:, :, i] = arr[:, :, i] * factor + gray * (1 - factor)

    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def add_vignette(img, intensity=0.6):
    """Add a darkening vignette around the edges."""
    width, height = img.size
    arr = np.array(img).astype(float)

    # Create radial gradient
    y_center, x_center = height / 2, width / 2
    y, x = np.ogrid[:height, :width]

    # Distance from center, normalized
    max_dist = np.sqrt(x_center**2 + y_center**2)
    dist = np.sqrt((x - x_center)**2 + (y - y_center)**2) / max_dist

    # Apply vignette (darker at edges)
    vignette = 1 - (dist ** 2) * intensity
    vignette = np.clip(vignette, 0, 1)

    # Apply to RGB channels only
    for i in range(3):
        arr[:, :, i] *= vignette[:, :]

    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def add_scanlines(img, line_spacing=2, intensity=0.2):
    """Add CRT scanline effect."""
    width, height = img.size
    arr = np.array(img).astype(float)

    # Create scanline pattern
    scanlines = np.ones((height, width))
    scanlines[::line_spacing, :] = 1 - intensity

    # Apply to RGB channels
    for i in range(3):
        arr[:, :, i] *= scanlines

    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def add_noise(img, intensity=0.04):
    """Add subtle noise for PSX texture."""
    arr = np.array(img).astype(float)
    noise = np.random.normal(0, intensity * 255, arr.shape)
    arr = np.clip(arr + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def add_glow_to_eyes(canvas, smiler_img, position, scale):
    """Add glowing effect to smiler's eyes."""
    # Create a bright yellow glow layer
    glow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))

    # The smiler sprite should have eyes as bright pixels
    # We'll extract bright pixels and create a glow
    arr = np.array(smiler_img)

    # Find bright pixels (likely the eyes)
    brightness = arr[:, :, 0] + arr[:, :, 1] + arr[:, :, 2]
    bright_mask = brightness > 600  # Very bright pixels

    # Create glow source
    glow_source = Image.new("RGBA", smiler_img.size, (0, 0, 0, 0))
    glow_arr = np.array(glow_source)
    glow_arr[bright_mask] = [255, 255, 100, 255]  # Bright yellow
    glow_source = Image.fromarray(glow_arr, mode="RGBA")

    # Scale glow source
    glow_scaled = glow_source.resize(
        (smiler_img.width * scale, smiler_img.height * scale),
        Image.NEAREST
    )

    # Apply blur for glow effect
    glow_blurred = glow_scaled.filter(ImageFilter.GaussianBlur(radius=8))

    # Paste onto glow layer
    glow_layer.paste(glow_blurred, position, glow_blurred)

    # Composite with canvas
    return Image.alpha_composite(canvas, glow_layer)


def draw_text_with_outline(text, outline_width=3):
    """Draw text with thick black outline for maximum readability."""
    # Use PIL's default font (bitmap font)
    # We'll simulate large text by drawing the default font scaled
    # For production, you'd use a real font file with ImageFont.truetype()

    # Since we don't have a TTF font, we'll draw chunky pixel text
    # by repeatedly drawing the default font with offsets

    # Text colors
    outline_color = (0, 0, 0, 255)      # Black outline
    text_color = (255, 210, 50, 255)    # Deep yellow text

    # Default font
    font = ImageFont.load_default()

    # Scale factor to simulate larger text (we'll draw it multiple times)
    scale = 8  # Each "pixel" of text becomes 8x8 pixels (bigger!)

    # Create a temporary draw context to measure text
    temp_img = Image.new("RGBA", (1, 1))
    temp_draw = ImageDraw.Draw(temp_img)
    bbox = temp_draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Create a small surface for the text
    small_surface = Image.new("RGBA", (text_width + 10, text_height + 10), (0, 0, 0, 0))
    small_draw = ImageDraw.Draw(small_surface)

    # Draw text on small surface (deep yellow)
    small_draw.text((5, 5), text, fill=text_color, font=font)

    # Scale up using nearest neighbor for crisp pixels
    large_surface = small_surface.resize(
        (small_surface.width * scale, small_surface.height * scale),
        Image.NEAREST
    )

    # Create outline by drawing the text multiple times offset
    outline_surface = Image.new("RGBA",
                                 (large_surface.width + outline_width * 2,
                                  large_surface.height + outline_width * 2),
                                 (0, 0, 0, 0))

    # Draw black outline (8 directions + cardinal)
    for dx in range(-outline_width, outline_width + 1):
        for dy in range(-outline_width, outline_width + 1):
            if dx == 0 and dy == 0:
                continue
            # Create black version
            black_surface = Image.new("RGBA", large_surface.size, (0, 0, 0, 0))
            black_arr = np.array(black_surface)
            large_arr = np.array(large_surface)
            # Copy alpha channel to create black outline
            black_arr[:, :, 3] = large_arr[:, :, 3]
            black_surface = Image.fromarray(black_arr, mode="RGBA")
            outline_surface.paste(black_surface, (outline_width + dx, outline_width + dy), black_surface)

    # Paste yellow text on top
    outline_surface.paste(large_surface, (outline_width, outline_width), large_surface)

    return outline_surface, (large_surface.width, large_surface.height)


def create_cover():
    """Generate the itch.io cover image."""
    print("Loading assets...")

    # Load all assets
    assets = {}
    for name, path in ASSETS.items():
        if not path.exists():
            print(f"Warning: Missing asset {name} at {path}")
            continue
        assets[name] = Image.open(path).convert("RGBA")
        print(f"  Loaded {name}: {assets[name].size}")

    print("\nCreating canvas...")
    # Create base canvas with tiled wallpaper
    wallpaper = assets["wallpaper"]
    canvas = tile_texture(wallpaper, WIDTH, HEIGHT)

    # Darken and desaturate background so sprites pop
    print("Adjusting background...")
    canvas = darken_image(canvas, factor=0.75)
    canvas = desaturate_image(canvas, factor=0.6)

    # Add vignette (stronger this time)
    print("Adding vignette...")
    canvas = add_vignette(canvas, intensity=0.6)

    # Composite sprites - NEW COMPOSITION with clear focal point
    print("Compositing sprites...")

    # Define margins to prevent cutoff
    MARGIN = 15  # Pixels from edge

    # PLAYER - CENTER, VERY LARGE (focal point)
    if "player" in assets:
        player = assets["player"]
        player_scale = 5  # Much bigger!
        player_scaled = player.resize(
            (player.width * player_scale, player.height * player_scale),
            Image.NEAREST
        )
        # Position in center-bottom with margin
        player_x = WIDTH // 2 - player_scaled.width // 2
        player_y = HEIGHT - player_scaled.height - MARGIN

        # Boost saturation on player's yellow suit
        player_arr = np.array(player_scaled).astype(float)
        # Identify yellow pixels (high R+G, low B)
        yellow_mask = (player_arr[:, :, 0] + player_arr[:, :, 1] > 300) & (player_arr[:, :, 2] < 150)
        # Boost saturation
        player_arr[yellow_mask, 0] = np.clip(player_arr[yellow_mask, 0] * 1.3, 0, 255)
        player_arr[yellow_mask, 1] = np.clip(player_arr[yellow_mask, 1] * 1.3, 0, 255)
        player_scaled = Image.fromarray(player_arr.astype(np.uint8), mode="RGBA")

        canvas.paste(player_scaled, (player_x, player_y), player_scaled)

    # SMILER - ABOVE/BEHIND PLAYER, LARGE
    if "smiler" in assets:
        smiler = assets["smiler"]
        smiler_scale = 6  # Very large, menacing
        smiler_scaled = smiler.resize(
            (smiler.width * smiler_scale, smiler.height * smiler_scale),
            Image.NEAREST
        )
        # Position above player, slightly to right, with margin check
        smiler_x = min(WIDTH // 2 - smiler_scaled.width // 2 + 50, WIDTH - smiler_scaled.width - MARGIN)
        smiler_y = HEIGHT // 2 - smiler_scaled.height // 2 - 30

        # Add glow to eyes BEFORE pasting
        canvas = add_glow_to_eyes(canvas, smiler, (smiler_x, smiler_y), smiler_scale)

        canvas.paste(smiler_scaled, (smiler_x, smiler_y), smiler_scaled)

    # BACTERIA - FLANKING PLAYER (left side)
    if "bacteria_spreader" in assets:
        spreader = assets["bacteria_spreader"]
        spreader_scale = 3
        spreader_scaled = spreader.resize(
            (spreader.width * spreader_scale, spreader.height * spreader_scale),
            Image.NEAREST
        )
        spreader_x = MARGIN
        spreader_y = HEIGHT - spreader_scaled.height - MARGIN - 60
        canvas.paste(spreader_scaled, (spreader_x, spreader_y), spreader_scaled)

    # BACTERIA MOTHERLOAD - FLANKING PLAYER (right side)
    if "bacteria_motherload" in assets:
        motherload = assets["bacteria_motherload"]
        motherload_scale = 3
        motherload_scaled = motherload.resize(
            (motherload.width * motherload_scale, motherload.height * motherload_scale),
            Image.NEAREST
        )
        motherload_x = WIDTH - motherload_scaled.width - MARGIN
        motherload_y = HEIGHT - motherload_scaled.height - MARGIN - 60
        canvas.paste(motherload_scaled, (motherload_x, motherload_y), motherload_scaled)

    # ITEMS - COLLAGE scattered around, various sizes (1.5x to 3x)
    # Using random seed for consistent placement
    np.random.seed(42)

    item_positions = [
        # Original 4 items
        ("almond_water", MARGIN + 5, HEIGHT - 60, 2.0),
        ("baseball_bat", WIDTH - 70, HEIGHT - 70, 2.5),
        ("wheatie_os", MARGIN + 20, 200, 2.0),
        ("drinking_bird", WIDTH - 60, 220, 2.0),

        # New items - scattered chaotically
        ("shovel", MARGIN + 80, HEIGHT - 100, 2.5),
        ("binoculars", WIDTH - 100, HEIGHT - 140, 1.8),
        ("brass_knuckles", MARGIN + 40, 140, 1.5),
        ("roman_coin", WIDTH - 45, 160, 1.5),
        ("trail_mix", MARGIN + 120, HEIGHT - 140, 2.2),
        ("lucky_rabbits_foot", WIDTH - 80, HEIGHT - 200, 1.8),
        ("coachs_whistle", MARGIN + 10, 260, 2.0),
    ]

    for item_name, x, y, scale in item_positions:
        if item_name in assets:
            item = assets[item_name]
            item_scaled = item.resize(
                (int(item.width * scale), int(item.height * scale)),
                Image.NEAREST
            )
            # Ensure item doesn't go off edge
            safe_x = max(MARGIN, min(x, WIDTH - item_scaled.width - MARGIN))
            safe_y = max(MARGIN, min(y, HEIGHT - item_scaled.height - MARGIN))
            canvas.paste(item_scaled, (safe_x, safe_y), item_scaled)

    # Add PSX effects (more prominent scanlines)
    print("Adding PSX effects...")
    canvas = add_scanlines(canvas, line_spacing=2, intensity=0.2)
    canvas = add_noise(canvas, intensity=0.04)

    # TITLE - TOP CENTER, HUGE, NO BACKGROUND BAR
    print("Adding title...")

    # Create text surfaces with outline (thicker outline)
    print("  Rendering 'DEEP'...")
    backrooms_surface, (br_w, br_h) = draw_text_with_outline(
        "DEEP", outline_width=5
    )

    print("  Rendering 'YELLOW'...")
    powercrawl_surface, (pc_w, pc_h) = draw_text_with_outline(
        "YELLOW", outline_width=5
    )

    # Calculate total title block height
    total_title_height = br_h + pc_h + 15  # 15px gap between lines

    # Position titles (centered horizontally and vertically in upper portion)
    # Upper portion = top 200px of canvas
    upper_portion_center_y = 100

    br_x = WIDTH // 2 - br_w // 2
    br_y = upper_portion_center_y - total_title_height // 2
    pc_x = WIDTH // 2 - pc_w // 2
    pc_y = br_y + br_h + 15

    # Paste titles
    canvas.paste(backrooms_surface, (br_x, br_y), backrooms_surface)
    canvas.paste(powercrawl_surface, (pc_x, pc_y), powercrawl_surface)

    # Apply chromatic aberration to title area only
    print("Adding chromatic aberration to title...")
    # Define region that covers both title lines
    title_top = max(0, br_y - 10)
    title_bottom = min(HEIGHT, pc_y + pc_h + 10)
    title_region = canvas.crop((0, title_top, WIDTH, title_bottom))
    title_arr = np.array(title_region)

    # Shift RGB channels
    shift_amount = 3
    shifted = title_arr.copy()
    shifted[:, shift_amount:, 0] = title_arr[:, :-shift_amount, 0]  # Red shift right
    shifted[:, :-shift_amount, 2] = title_arr[:, shift_amount:, 2]  # Blue shift left

    title_region_shifted = Image.fromarray(shifted, mode="RGBA")
    canvas.paste(title_region_shifted, (0, title_top))

    # Save output
    print(f"\nSaving to {OUTPUT_PATH}...")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUTPUT_PATH)

    # Verify output
    file_size = OUTPUT_PATH.stat().st_size
    print(f"✓ Cover image generated!")
    print(f"  Size: {WIDTH}x{HEIGHT}")
    print(f"  File size: {file_size / 1024:.1f} KB")
    print(f"  Path: {OUTPUT_PATH}")
    print("\nRevision 2 changes:")
    print("  - REMOVED dark title background bar (text directly on image)")
    print("  - INCREASED title text size (8x scale, up from 6x)")
    print("  - BETTER CENTERED title text (vertically in upper portion)")
    print("  - FIXED sprite cutoffs (15px margins, safe positioning)")
    print("  - ADDED 7 more collage items (shovel, binoculars, brass knuckles, etc.)")
    print("  - Items at various scales (1.5x to 3x) for chaotic collage feel")
    print("  - Thicker outline on title (5px, up from 4px)")
    print("\nRetained from v1:")
    print("  - Giant smiler grin with glowing eyes")
    print("  - Hazmat player as central focal point")
    print("  - Bacteria enemies flanking player")
    print("  - Chromatic aberration on title")
    print("  - PSX effects (scanlines, noise)")
    print("  - Darkened/desaturated wallpaper background")


if __name__ == "__main__":
    create_cover()
