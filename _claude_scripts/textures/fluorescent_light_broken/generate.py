#!/usr/bin/env python3
"""
Broken Fluorescent Ceiling Light Fixture - Sprite Generator

Generates a 64x64 RGBA pixel art sprite of a BROKEN/DEAD fluorescent ceiling
light fixture as viewed from below (billboard sprite). Designed for a Backrooms-
inspired roguelike with PSX retro art style.

This is the non-functional variant of the working fluorescent light. Same basic
fixture shape and dimensions, but the tubes are dark/dead, one tube is cracked
with a gap, and the housing shows more wear. No glow halo since the light is off.

Used to create dark pockets in the otherwise well-lit Level 0.
"""

from PIL import Image, ImageDraw
import random
import shutil
import os

# Deterministic seed for reproducible output
random.seed(42)

# Configuration
SIZE = 64
OUTPUT_PATH = "output.png"
GAME_TEXTURE_PATH = "/home/drew/projects/deep_yellow/assets/textures/entities/fluorescent_light_broken.png"

# Fixture dimensions - SAME as working version for visual consistency
FIXTURE_W = 52  # Width of the entire fixture housing
FIXTURE_H = 24  # Height of the entire fixture housing
FIXTURE_X = (SIZE - FIXTURE_W) // 2  # Left edge
FIXTURE_Y = (SIZE - FIXTURE_H) // 2  # Top edge

# Color palette - darker, worn, lifeless
# Metal housing (darker, more worn than the working version)
HOUSING_OUTER = (110, 105, 95, 255)     # Outer edge - darker, dirtier
HOUSING_INNER = (130, 125, 115, 255)    # Inner edge / bevel highlight - dimmer
HOUSING_SHADOW = (75, 70, 62, 255)      # Shadow edge - deeper shadow
HOUSING_GRIME = (90, 85, 75, 255)       # Accumulated grime/discoloration

# Dead diffuser panel (no longer lit - yellowed, dirty plastic)
DIFFUSER_DARK = (140, 132, 105, 255)    # Dark yellowed plastic
DIFFUSER_MID = (130, 122, 98, 255)      # Mid-tone dirty diffuser
DIFFUSER_EDGE = (115, 108, 88, 255)     # Edge of diffuser - darker still
DIFFUSER_STAIN = (105, 98, 78, 255)     # Water stain / discoloration spots

# Dead fluorescent tubes (dark, no glow at all)
TUBE_DEAD = (95, 92, 82, 255)          # Dead tube - dark grey with slight warmth
TUBE_DEAD_EDGE = (80, 77, 70, 255)     # Edge of dead tube
TUBE_CAP = (120, 115, 105, 255)        # Tube end caps (slightly shinier metal)
TUBE_CAP_DARK = (90, 85, 75, 255)      # Corroded end cap

# Cracked tube fragments
CRACK_DARK = (60, 58, 52, 255)         # Inside of broken tube (dark void)
CRACK_EDGE = (110, 106, 95, 255)       # Sharp edge of broken glass
CRACK_SHARD = (135, 130, 118, 255)     # Glass shard catching ambient light

# Subtle ambient shadow (instead of glow, a slight darkening around fixture)
SHADOW_FAINT = (30, 28, 25, 15)        # Very subtle dark halo


def create_image():
    """Create a blank 64x64 RGBA image with transparent background."""
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def draw_shadow(img):
    """Draw a very subtle dark shadow around the fixture (opposite of glow).

    A dead light doesn't illuminate -- it actually creates a darker spot
    on the ceiling from accumulated dust and the fixture blocking ambient light.
    """
    pixels = img.load()

    shadow_layers = [
        # (x_expand, y_expand, color)
        (5, 5, (25, 23, 20, 10)),
        (3, 3, (30, 28, 25, 15)),
        (1, 1, (35, 32, 28, 12)),
    ]

    for x_exp, y_exp, color in shadow_layers:
        gx1 = FIXTURE_X - x_exp
        gy1 = FIXTURE_Y - y_exp
        gx2 = FIXTURE_X + FIXTURE_W + x_exp - 1
        gy2 = FIXTURE_Y + FIXTURE_H + y_exp - 1

        for y in range(max(0, gy1), min(SIZE, gy2 + 1)):
            for x in range(max(0, gx1), min(SIZE, gx2 + 1)):
                # Skip pixels inside the fixture
                if (FIXTURE_X <= x < FIXTURE_X + FIXTURE_W and
                        FIXTURE_Y <= y < FIXTURE_Y + FIXTURE_H):
                    continue

                r0, g0, b0, a0 = pixels[x, y]
                alpha = color[3] / 255.0
                r = int(r0 * (1 - alpha) + color[0] * alpha)
                g = int(g0 * (1 - alpha) + color[1] * alpha)
                b = int(b0 * (1 - alpha) + color[2] * alpha)
                a = min(255, a0 + color[3])

                pixels[x, y] = (r, g, b, a)


def draw_housing(draw, img):
    """Draw the metal housing frame - more battered/worn than working version."""
    x1 = FIXTURE_X
    y1 = FIXTURE_Y
    x2 = FIXTURE_X + FIXTURE_W - 1
    y2 = FIXTURE_Y + FIXTURE_H - 1

    frame_thickness = 3

    # Outer frame rectangle - darker base color
    draw.rectangle([x1, y1, x2, y2], fill=HOUSING_OUTER)

    # Highlight on top and left edges (dimmer than working version)
    draw.line([(x1, y1), (x2, y1)], fill=HOUSING_INNER, width=1)
    draw.line([(x1, y1), (x1, y2)], fill=HOUSING_INNER, width=1)

    # Shadow on bottom and right edges
    draw.line([(x1, y2), (x2, y2)], fill=HOUSING_SHADOW, width=1)
    draw.line([(x2, y1), (x2, y2)], fill=HOUSING_SHADOW, width=1)

    # Add some grime/wear marks on the housing
    pixels = img.load()
    # Scattered darker spots on the metal frame
    grime_positions = [
        (x1 + 5, y1 + 1), (x1 + 12, y1 + 1), (x2 - 8, y1 + 1),
        (x1 + 1, y1 + 2), (x2 - 3, y2 - 1), (x1 + 20, y2 - 1),
        (x2 - 15, y2 - 1), (x1 + 2, y1 + 1),
    ]
    for gx, gy in grime_positions:
        if x1 <= gx <= x2 and y1 <= gy <= y2:
            pixels[gx, gy] = HOUSING_GRIME

    # Inner cutout (where the diffuser sits)
    inner_x1 = x1 + frame_thickness
    inner_y1 = y1 + frame_thickness
    inner_x2 = x2 - frame_thickness
    inner_y2 = y2 - frame_thickness

    # Inner bevel shadow (recessed look) - same structure as working version
    draw.line([(inner_x1 - 1, inner_y1 - 1), (inner_x2 + 1, inner_y1 - 1)],
              fill=HOUSING_SHADOW, width=1)
    draw.line([(inner_x1 - 1, inner_y1 - 1), (inner_x1 - 1, inner_y2 + 1)],
              fill=HOUSING_SHADOW, width=1)

    return inner_x1, inner_y1, inner_x2, inner_y2


def draw_diffuser(draw, img, inner_x1, inner_y1, inner_x2, inner_y2):
    """Draw the dirty, yellowed diffuser panel - no longer illuminated."""
    # Fill with dark yellowed plastic
    draw.rectangle([inner_x1, inner_y1, inner_x2, inner_y2],
                   fill=DIFFUSER_MID)

    # No bright center band -- the light is dead. Instead, subtle uneven tone.
    # Slightly lighter patch in center (ambient light reflection only)
    center_y = (inner_y1 + inner_y2) // 2
    draw.rectangle([inner_x1 + 4, center_y - 1, inner_x2 - 4, center_y + 1],
                   fill=DIFFUSER_DARK)

    # Dimmer edges of diffuser
    draw.line([(inner_x1, inner_y1), (inner_x2, inner_y1)],
              fill=DIFFUSER_EDGE, width=1)
    draw.line([(inner_x1, inner_y2), (inner_x2, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)
    draw.line([(inner_x1, inner_y1), (inner_x1, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)
    draw.line([(inner_x2, inner_y1), (inner_x2, inner_y2)],
              fill=DIFFUSER_EDGE, width=1)

    # Water stains / discoloration spots on the diffuser
    pixels = img.load()
    stain_centers = [
        (inner_x1 + 8, inner_y1 + 3),
        (inner_x2 - 12, inner_y2 - 3),
        (inner_x1 + 25, inner_y1 + 5),
    ]
    for sx, sy in stain_centers:
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                px, py = sx + dx, sy + dy
                if inner_x1 <= px <= inner_x2 and inner_y1 <= py <= inner_y2:
                    if abs(dx) + abs(dy) <= 1:  # Diamond shape
                        pixels[px, py] = DIFFUSER_STAIN


def draw_tubes(img, inner_x1, inner_y1, inner_x2, inner_y2):
    """Draw two dead fluorescent tubes.

    Top tube: intact but completely dark/dead
    Bottom tube: cracked with a gap/missing section
    """
    pixels = img.load()

    tube_margin_x = 4
    tube_start_x = inner_x1 + tube_margin_x
    tube_end_x = inner_x2 - tube_margin_x
    cap_width = 2

    # Two tubes, evenly spaced (same positions as working version)
    panel_h = inner_y2 - inner_y1
    tube_spacing = panel_h // 3
    tube_centers = [
        inner_y1 + tube_spacing,       # Top tube - dead but intact
        inner_y1 + 2 * tube_spacing,   # Bottom tube - cracked
    ]

    tube_half_height = 2

    # --- Top tube: dead but intact ---
    tube_cy = tube_centers[0]
    for x in range(tube_start_x, tube_end_x + 1):
        for dy in range(-tube_half_height, tube_half_height + 1):
            y = tube_cy + dy
            if y < inner_y1 or y > inner_y2:
                continue

            if x < tube_start_x + cap_width or x > tube_end_x - cap_width:
                color = TUBE_CAP_DARK
            elif abs(dy) == tube_half_height:
                color = TUBE_DEAD_EDGE
            elif abs(dy) == tube_half_height - 1:
                color = TUBE_DEAD_EDGE
            else:
                color = TUBE_DEAD

            pixels[x, y] = color

    # --- Bottom tube: cracked with missing section ---
    tube_cy = tube_centers[1]
    # The crack/break point - a gap in the tube
    crack_center_x = inner_x1 + (inner_x2 - inner_x1) * 2 // 5
    crack_width = 6  # Width of the broken gap

    for x in range(tube_start_x, tube_end_x + 1):
        for dy in range(-tube_half_height, tube_half_height + 1):
            y = tube_cy + dy
            if y < inner_y1 or y > inner_y2:
                continue

            # Check if we're in the crack/gap zone
            dist_from_crack = abs(x - crack_center_x)

            if dist_from_crack < crack_width // 2:
                # Inside the broken gap - show dark void
                if abs(dy) <= 1:
                    # Dark interior visible through the break
                    pixels[x, y] = CRACK_DARK
                # Outer edge pixels near crack stay as diffuser (already drawn)
                continue
            elif dist_from_crack < crack_width // 2 + 2:
                # Edge of the break - jagged glass edges
                if abs(dy) <= tube_half_height - 1:
                    # Irregular edge: some pixels are shard, some void
                    if (x + dy) % 3 == 0:
                        color = CRACK_SHARD
                    elif (x + dy) % 3 == 1:
                        color = CRACK_EDGE
                    else:
                        color = TUBE_DEAD_EDGE
                    pixels[x, y] = color
                continue

            # Normal dead tube section (either side of the crack)
            if x < tube_start_x + cap_width or x > tube_end_x - cap_width:
                color = TUBE_CAP_DARK
            elif abs(dy) == tube_half_height:
                color = TUBE_DEAD_EDGE
            elif abs(dy) == tube_half_height - 1:
                color = TUBE_DEAD_EDGE
            else:
                color = TUBE_DEAD

            pixels[x, y] = color

    # Add a couple of tiny glass shard pixels below the crack (fallen debris)
    shard_positions = [
        (crack_center_x - 1, tube_cy + tube_half_height + 1),
        (crack_center_x + 2, tube_cy + tube_half_height + 2),
    ]
    for sx, sy in shard_positions:
        if inner_x1 <= sx <= inner_x2 and inner_y1 <= sy <= inner_y2:
            pixels[sx, sy] = CRACK_SHARD


def draw_fixture_details(img):
    """Add details: center divider bar, mounting clips - more worn than working."""
    pixels = img.load()

    cx = SIZE // 2
    cy = SIZE // 2

    # Center divider bar (same as working version but darker/worn)
    divider_color = (115, 110, 100, 255)  # Darker than working version
    divider_y = cy
    for x in range(FIXTURE_X + 5, FIXTURE_X + FIXTURE_W - 5):
        pixels[x, divider_y] = divider_color

    # A couple of spots where the divider is extra dark (rust/grime)
    rust_spots = [FIXTURE_X + 15, FIXTURE_X + 30, FIXTURE_X + 40]
    for rx in rust_spots:
        if FIXTURE_X + 5 <= rx < FIXTURE_X + FIXTURE_W - 5:
            pixels[rx, divider_y] = HOUSING_GRIME

    # Mounting detail marks (same positions as working version)
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

    # Extra wear: a scratch mark across the housing (diagonal line on frame)
    scratch_color = (95, 90, 80, 255)
    scratch_start_x = FIXTURE_X + 35
    scratch_start_y = FIXTURE_Y + 1
    for i in range(4):
        sx = scratch_start_x + i
        sy = scratch_start_y + (i // 2)
        if (FIXTURE_X <= sx < FIXTURE_X + FIXTURE_W and
                FIXTURE_Y <= sy < FIXTURE_Y + 3):
            pixels[sx, sy] = scratch_color


def generate_broken_fluorescent_light():
    """Main generation function."""
    print("Generating BROKEN fluorescent ceiling light sprite (64x64 RGBA)...")

    # Step 1: Create blank image
    img = create_image()

    # Step 2: Draw subtle dark shadow (instead of glow)
    print("  - Drawing ambient shadow...")
    draw_shadow(img)

    # Step 3: Draw worn metal housing frame
    print("  - Drawing worn metal housing frame...")
    draw = ImageDraw.Draw(img)
    inner_x1, inner_y1, inner_x2, inner_y2 = draw_housing(draw, img)

    # Step 4: Draw dirty diffuser panel
    print("  - Drawing dirty diffuser panel...")
    draw_diffuser(draw, img, inner_x1, inner_y1, inner_x2, inner_y2)

    # Step 5: Draw dead/cracked tubes
    print("  - Drawing dead and cracked tubes...")
    draw_tubes(img, inner_x1, inner_y1, inner_x2, inner_y2)

    # Step 6: Add worn fixture details
    print("  - Adding fixture details and wear marks...")
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
        generate_broken_fluorescent_light()
        print("\nGeneration complete!")
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
