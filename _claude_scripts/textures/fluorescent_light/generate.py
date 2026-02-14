#!/usr/bin/env python3
"""
Fluorescent Ceiling Light Fixture - Sprite Generator

Generates a 64x64 RGBA pixel art sprite of a fluorescent ceiling light
fixture as viewed from below (billboard sprite). Designed for a Backrooms-
inspired roguelike with PSX retro art style.

The fixture is a rectangular panel with metal housing and warm white/yellow
fluorescent tubes glowing inside. Viewed from below, the dominant visual is
the bright diffuser panel framed by a thin metal housing edge.
"""

from PIL import Image, ImageDraw
import shutil
import os

# Configuration
SIZE = 64
OUTPUT_PATH = "output.png"
GAME_TEXTURE_PATH = "/home/drew/projects/deep_yellow/assets/textures/entities/fluorescent_light.png"

# Fixture dimensions (viewed from below, wider than tall)
# The fixture occupies the central area, rest is transparent
FIXTURE_W = 52  # Width of the entire fixture housing
FIXTURE_H = 24  # Height of the entire fixture housing
FIXTURE_X = (SIZE - FIXTURE_W) // 2  # Left edge
FIXTURE_Y = (SIZE - FIXTURE_H) // 2  # Top edge

# Color palette - limited, clean pixel art
# Metal housing (light grey, slightly warm to match the yellow environment)
HOUSING_OUTER = (140, 135, 125, 255)    # Outer edge of metal frame
HOUSING_INNER = (170, 165, 155, 255)    # Inner edge / bevel highlight
HOUSING_SHADOW = (105, 100, 90, 255)    # Shadow edge (bottom/right of frame)

# Diffuser panel (the translucent plastic cover over the tubes)
DIFFUSER_BRIGHT = (245, 235, 190, 255)  # Brightest center of diffuser
DIFFUSER_MID = (240, 228, 175, 255)     # Mid-tone diffuser
DIFFUSER_EDGE = (225, 210, 160, 255)    # Edge of diffuser (slightly dimmer)

# Fluorescent tubes (visible through diffuser as brighter bands)
TUBE_BRIGHT = (255, 248, 220, 255)      # Tube center - near white, warm
TUBE_MID = (250, 240, 200, 255)         # Tube sides
TUBE_CAP = (190, 185, 170, 255)         # Tube end caps (metal)

# Glow effect (semi-transparent halo around fixture)
GLOW_INNER = (255, 245, 200, 80)        # Close glow
GLOW_MID = (255, 240, 180, 40)          # Medium glow
GLOW_OUTER = (255, 235, 170, 18)        # Faint outer glow


def create_image():
    """Create a blank 64x64 RGBA image with transparent background."""
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def draw_glow(img):
    """Draw a soft rectangular glow halo around the fixture area."""
    pixels = img.load()

    # Center of fixture
    cx = SIZE // 2
    cy = SIZE // 2

    # Glow extends beyond the fixture bounds
    glow_layers = [
        # (x_expand, y_expand, color)
        (6, 6, GLOW_OUTER),
        (4, 4, GLOW_MID),
        (2, 2, GLOW_INNER),
    ]

    for x_exp, y_exp, color in glow_layers:
        gx1 = FIXTURE_X - x_exp
        gy1 = FIXTURE_Y - y_exp
        gx2 = FIXTURE_X + FIXTURE_W + x_exp - 1
        gy2 = FIXTURE_Y + FIXTURE_H + y_exp - 1

        for y in range(max(0, gy1), min(SIZE, gy2 + 1)):
            for x in range(max(0, gx1), min(SIZE, gx2 + 1)):
                # Skip pixels that are inside the fixture (will be drawn later)
                if (FIXTURE_X <= x < FIXTURE_X + FIXTURE_W and
                        FIXTURE_Y <= y < FIXTURE_Y + FIXTURE_H):
                    continue

                # Current pixel
                r0, g0, b0, a0 = pixels[x, y]

                # Alpha blend
                alpha = color[3] / 255.0
                r = int(r0 * (1 - alpha) + color[0] * alpha)
                g = int(g0 * (1 - alpha) + color[1] * alpha)
                b = int(b0 * (1 - alpha) + color[2] * alpha)
                a = min(255, a0 + color[3])

                pixels[x, y] = (r, g, b, a)


def draw_housing(draw):
    """Draw the metal housing frame of the fixture."""
    x1 = FIXTURE_X
    y1 = FIXTURE_Y
    x2 = FIXTURE_X + FIXTURE_W - 1
    y2 = FIXTURE_Y + FIXTURE_H - 1

    frame_thickness = 3

    # Outer frame rectangle
    draw.rectangle([x1, y1, x2, y2], fill=HOUSING_OUTER)

    # Highlight on top and left edges (light coming from above/left)
    # Top edge highlight
    draw.line([(x1, y1), (x2, y1)], fill=HOUSING_INNER, width=1)
    # Left edge highlight
    draw.line([(x1, y1), (x1, y2)], fill=HOUSING_INNER, width=1)

    # Shadow on bottom and right edges
    draw.line([(x1, y2), (x2, y2)], fill=HOUSING_SHADOW, width=1)
    draw.line([(x2, y1), (x2, y2)], fill=HOUSING_SHADOW, width=1)

    # Inner cutout (where the diffuser panel sits) - slightly recessed
    inner_x1 = x1 + frame_thickness
    inner_y1 = y1 + frame_thickness
    inner_x2 = x2 - frame_thickness
    inner_y2 = y2 - frame_thickness

    # Inner bevel shadow (makes it look recessed)
    draw.line([(inner_x1 - 1, inner_y1 - 1), (inner_x2 + 1, inner_y1 - 1)],
              fill=HOUSING_SHADOW, width=1)
    draw.line([(inner_x1 - 1, inner_y1 - 1), (inner_x1 - 1, inner_y2 + 1)],
              fill=HOUSING_SHADOW, width=1)

    return inner_x1, inner_y1, inner_x2, inner_y2


def draw_diffuser(draw, inner_x1, inner_y1, inner_x2, inner_y2):
    """Draw the translucent diffuser panel that covers the tubes."""
    # Fill diffuser area with mid-tone
    draw.rectangle([inner_x1, inner_y1, inner_x2, inner_y2],
                   fill=DIFFUSER_MID)

    # Slightly brighter center band
    center_y = (inner_y1 + inner_y2) // 2
    draw.rectangle([inner_x1 + 2, center_y - 2, inner_x2 - 2, center_y + 2],
                   fill=DIFFUSER_BRIGHT)

    # Dimmer edges of diffuser (1px border inside)
    # Top edge
    draw.line([(inner_x1, inner_y1), (inner_x2, inner_y1)],
              fill=DIFFUSER_EDGE, width=1)
    # Bottom edge
    draw.line([(inner_x1, inner_y2), (inner_x2, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)
    # Left edge
    draw.line([(inner_x1, inner_y1), (inner_x1, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)
    # Right edge
    draw.line([(inner_x2, inner_y1), (inner_x2, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)


def draw_tubes(img, inner_x1, inner_y1, inner_x2, inner_y2):
    """Draw two fluorescent tubes visible through the diffuser."""
    pixels = img.load()

    tube_margin_x = 4  # Gap from diffuser edge to tube end
    tube_start_x = inner_x1 + tube_margin_x
    tube_end_x = inner_x2 - tube_margin_x
    cap_width = 2  # Width of the metallic end caps

    # Two tubes, evenly spaced vertically within the diffuser
    panel_h = inner_y2 - inner_y1
    tube_spacing = panel_h // 3
    tube_centers = [
        inner_y1 + tube_spacing,
        inner_y1 + 2 * tube_spacing,
    ]

    tube_half_height = 2  # Each tube is ~5px tall (2 above center, center, 2 below)

    for tube_cy in tube_centers:
        for x in range(tube_start_x, tube_end_x + 1):
            for dy in range(-tube_half_height, tube_half_height + 1):
                y = tube_cy + dy
                if y < inner_y1 or y > inner_y2:
                    continue

                # Determine color based on position
                if x < tube_start_x + cap_width or x > tube_end_x - cap_width:
                    # End cap region
                    color = TUBE_CAP
                elif abs(dy) == tube_half_height:
                    # Top/bottom edge of tube
                    color = TUBE_MID
                elif abs(dy) == tube_half_height - 1:
                    # Near-edge
                    color = TUBE_MID
                else:
                    # Bright center
                    color = TUBE_BRIGHT

                # Alpha blend onto existing pixel
                r0, g0, b0, a0 = pixels[x, y]
                alpha = color[3] / 255.0

                r = int(r0 * (1 - alpha) + color[0] * alpha)
                g = int(g0 * (1 - alpha) + color[1] * alpha)
                b = int(b0 * (1 - alpha) + color[2] * alpha)
                a = max(a0, color[3])

                pixels[x, y] = (r, g, b, a)


def draw_fixture_details(img):
    """Add small details: center divider bar, mounting clips."""
    pixels = img.load()

    cx = SIZE // 2
    cy = SIZE // 2

    # Center divider bar (thin horizontal metal strip between tubes)
    divider_color = (155, 150, 140, 255)
    divider_y = cy
    for x in range(FIXTURE_X + 5, FIXTURE_X + FIXTURE_W - 5):
        pixels[x, divider_y] = divider_color

    # Small mounting detail marks at the ends (tiny darker rectangles)
    mount_color = HOUSING_SHADOW
    # Left mount
    for dy in range(-1, 2):
        for dx in range(0, 2):
            y = cy + dy
            x = FIXTURE_X + 1 + dx
            if 0 <= x < SIZE and 0 <= y < SIZE:
                pixels[x, y] = mount_color
    # Right mount
    for dy in range(-1, 2):
        for dx in range(0, 2):
            y = cy + dy
            x = FIXTURE_X + FIXTURE_W - 2 - dx
            if 0 <= x < SIZE and 0 <= y < SIZE:
                pixels[x, y] = mount_color


def generate_fluorescent_light():
    """Main generation function."""
    print("Generating fluorescent ceiling light sprite (64x64 RGBA)...")

    # Step 1: Create blank image
    img = create_image()

    # Step 2: Draw glow halo (behind everything)
    print("  - Drawing glow halo...")
    draw_glow(img)

    # Step 3: Draw metal housing frame
    print("  - Drawing metal housing frame...")
    draw = ImageDraw.Draw(img)
    inner_x1, inner_y1, inner_x2, inner_y2 = draw_housing(draw)

    # Step 4: Draw diffuser panel
    print("  - Drawing diffuser panel...")
    draw_diffuser(draw, inner_x1, inner_y1, inner_x2, inner_y2)

    # Step 5: Draw fluorescent tubes (visible through diffuser)
    print("  - Drawing fluorescent tubes...")
    draw_tubes(img, inner_x1, inner_y1, inner_x2, inner_y2)

    # Step 6: Add fixture details
    print("  - Adding fixture details...")
    draw_fixture_details(img)

    # Save output
    img.save(OUTPUT_PATH)
    print(f"  Saved to {OUTPUT_PATH}")

    # Copy to game texture directory
    os.makedirs(os.path.dirname(GAME_TEXTURE_PATH), exist_ok=True)
    shutil.copy2(OUTPUT_PATH, GAME_TEXTURE_PATH)
    print(f"  Copied to {GAME_TEXTURE_PATH}")

    # Print stats
    print(f"\n  Size: {SIZE}x{SIZE} pixels")
    print(f"  Format: RGBA PNG")
    print(f"  Mode: {img.mode}")

    # Count transparent vs opaque pixels
    pixels = img.load()
    transparent = 0
    for y in range(SIZE):
        for x in range(SIZE):
            if pixels[x, y][3] == 0:
                transparent += 1
    opaque = SIZE * SIZE - transparent
    print(f"  Transparent pixels: {transparent}")
    print(f"  Non-transparent pixels: {opaque}")

    return img


if __name__ == "__main__":
    try:
        generate_fluorescent_light()
        print("\nGeneration complete!")
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
