#!/usr/bin/env python3
"""
Backrooms Level 0 Closed Door Texture Generator (Iteration 2)

Generates a 128x128 tileable texture depicting a worn office door set into
yellow wallpaper. The door panel is a brownish/tan wood color that reads as
clearly distinct from the surrounding yellow wallpaper frame.

Revision notes (from critic feedback on iteration 1):
- FIX horizontal tiling: wallpaper strips at left/right edges must tile seamlessly.
  The wallpaper source is already 128x128 tileable, so we sample with modulo and
  ensure the frame trim + shadow gaps are symmetric and continuous at tile edges.
- FIX vertical tiling: wood grain, recessed panels, and grime must all use modulo
  wrapping so the door surface is a continuous vertical loop.
- ADD more weathering: water stains, discoloration patches, scuff marks, uneven
  darkening near edges. Decades of neglect in the Backrooms.
- IMPROVE handle: slightly larger backplate, more defined lever with better shading.

Since this tiles as a GridMap wall (2x4x2 box), the door is centered and
the surrounding frame uses colors sampled from the existing wallpaper texture.
"""

import numpy as np
from PIL import Image
import random
from math import sqrt, sin, cos, pi

# Configuration
SIZE = 128
OUTPUT_PATH = "output.png"
TILED_PATH = "output_tiled_2x2.png"
WALLPAPER_PATH = "/home/drew/projects/deep_yellow/assets/levels/level_00/textures/wallpaper_yellow.png"

# Door panel colors (warm brown wood, distinct from yellow wallpaper)
DOOR_BASE = np.array([135, 105, 72], dtype=np.float64)       # Mid brown wood
DOOR_DARK = np.array([95, 72, 48], dtype=np.float64)         # Dark wood grain
DOOR_LIGHT = np.array([165, 135, 95], dtype=np.float64)      # Light wood highlight

# Frame/trim colors (darker than wallpaper, lighter than door)
FRAME_COLOR = np.array([140, 120, 80], dtype=np.float64)     # Muted brownish-gold frame trim
FRAME_SHADOW = np.array([100, 85, 55], dtype=np.float64)     # Shadow side of frame

# Door handle colors (metallic)
HANDLE_COLOR = np.array([160, 155, 140], dtype=np.float64)   # Brushed metal
HANDLE_DARK = np.array([90, 85, 75], dtype=np.float64)       # Handle shadow
HANDLE_HIGHLIGHT = np.array([200, 195, 180], dtype=np.float64)  # Handle shine

# Wallpaper border colors (fallback if texture not found)
WALLPAPER_BASE = np.array([169, 154, 118], dtype=np.float64)


def load_wallpaper():
    """
    Load the wallpaper texture. Returns a numpy array (float64, RGB) or None.
    The wallpaper is already 128x128 and tileable.
    """
    try:
        img = Image.open(WALLPAPER_PATH)
        return np.array(img)[:, :, :3].astype(np.float64)
    except FileNotFoundError:
        print(f"Warning: Wallpaper not found at {WALLPAPER_PATH}, using procedural fallback")
        return None


def create_base_wallpaper_frame(wallpaper_arr):
    """
    Create the base image filled with wallpaper for the frame area.
    Uses modulo wrapping to sample the wallpaper, ensuring seamless tiling.
    The entire image starts as wallpaper, then the door is painted over the center.
    """
    img = np.zeros((SIZE, SIZE, 3), dtype=np.float64)

    if wallpaper_arr is not None:
        wp_h, wp_w = wallpaper_arr.shape[:2]
        for y in range(SIZE):
            for x in range(SIZE):
                img[y % SIZE, x % SIZE] = wallpaper_arr[y % wp_h, x % wp_w]
    else:
        # Procedural fallback
        for y in range(SIZE):
            for x in range(SIZE):
                noise = random.uniform(-10, 10)
                img[y % SIZE, x % SIZE] = WALLPAPER_BASE + noise

    return img


def draw_door_panel(img):
    """
    Draw the main door panel in the center of the texture.

    Door layout (128px wide):
    - Left wallpaper border: ~8px
    - Left frame trim: ~3px
    - Door panel: ~106px
    - Right frame trim: ~3px
    - Right wallpaper border: ~8px

    Vertically the door spans the full height and tiles seamlessly.
    ALL grain patterns use modulo coordinates so they wrap vertically.
    """
    frame_width = 8
    trim_width = 3
    door_left = frame_width + trim_width
    door_right = SIZE - frame_width - trim_width

    # Draw the door panel wood base with wrapping grain
    for y in range(SIZE):
        for x in range(door_left, door_right):
            # Use modulo-friendly grain: sin functions are inherently periodic,
            # but we need the period to divide SIZE evenly for vertical tiling.
            # sin with period SIZE: sin(2*pi*y/SIZE * N) where N is number of repeats
            grain_offset = sin(2 * pi * y / SIZE * 3 + x * 0.02) * 8
            grain_fine = sin(2 * pi * y / SIZE * 12 + x * 0.05) * 3
            vert_variation = sin(x * 0.1) * 5

            color = DOOR_BASE + grain_offset + grain_fine + vert_variation
            img[y % SIZE, x % SIZE] = color

    return img, door_left, door_right


def add_wood_grain(img, door_left, door_right):
    """
    Add subtle horizontal wood grain lines across the door panel.
    These are thin, slightly darker or lighter streaks.
    All grain lines wrap vertically using modulo.
    """
    num_grain_lines = random.randint(18, 28)
    for _ in range(num_grain_lines):
        y_pos = random.randint(0, SIZE - 1)
        thickness = random.randint(1, 2)
        intensity = random.uniform(0.06, 0.18)
        is_dark = random.random() < 0.7

        target = DOOR_DARK if is_dark else DOOR_LIGHT

        # Grain line with slight waviness -- wave uses tiling-safe frequency
        wave_freq = random.uniform(0.02, 0.08)
        wave_amp = random.uniform(0, 2)

        for dy in range(thickness):
            for x in range(door_left, door_right):
                y = (y_pos + dy + int(sin(x * wave_freq) * wave_amp)) % SIZE
                img[y, x % SIZE] = img[y, x % SIZE] * (1 - intensity) + target * intensity

    return img


def draw_frame_trim(img, door_left, door_right):
    """
    Draw the raised frame trim between the wallpaper and the door panel.
    Creates a 3D beveled look. The trim runs the full height and is
    symmetric so that the left edge of one tile matches the right edge
    of the adjacent tile (wallpaper is continuous across tile boundaries).
    """
    frame_width_px = 8
    trim_width_px = 3

    # Left trim (light on outer edge, dark on inner edge = raised bevel)
    for y in range(SIZE):
        for i in range(trim_width_px):
            x = (frame_width_px + i) % SIZE
            t = i / trim_width_px
            color = FRAME_COLOR * (1 - t) + FRAME_SHADOW * t
            noise = random.uniform(-5, 5)
            img[y % SIZE, x] = color + noise

    # Right trim (dark on inner edge, light on outer edge)
    for y in range(SIZE):
        for i in range(trim_width_px):
            x = (SIZE - frame_width_px - trim_width_px + i) % SIZE
            t = i / trim_width_px
            color = FRAME_SHADOW * (1 - t) + FRAME_COLOR * t
            noise = random.uniform(-5, 5)
            img[y % SIZE, x] = color + noise

    # Thin dark line at junction between trim and wallpaper (shadow gap)
    # These are on the INNER side of the wallpaper strip, so they don't
    # affect the tile edges (x=0..7 and x=120..127 are pure wallpaper).
    for y in range(SIZE):
        # Left shadow gap (between wallpaper and left trim)
        x_left = frame_width_px % SIZE
        img[y % SIZE, x_left] = img[y % SIZE, x_left] * 0.7
        # Right shadow gap (between right trim and wallpaper)
        x_right = (SIZE - frame_width_px - 1) % SIZE
        img[y % SIZE, x_right] = img[y % SIZE, x_right] * 0.7

    return img


def draw_recessed_panels(img, door_left, door_right):
    """
    Draw two recessed rectangular panels on the door face. These give
    the door visual depth and make it unmistakably a door.

    The panels are positioned to leave a gap at top and bottom that
    tiles seamlessly (the gap area is just flat wood grain).
    We use a slightly larger gap zone at top/bottom to avoid the panel
    bevels landing right at the tile boundary.
    """
    panel_inset = 8
    panel_gap = 6
    panel_left = door_left + panel_inset
    panel_right = door_right - panel_inset
    bevel = 2

    # Panels positioned with margin from tile edges for clean vertical tiling
    margin = 10  # Gap from tile edge so bevel doesn't sit at y=0 or y=127
    upper_top = margin
    upper_bottom = SIZE // 2 - panel_gap // 2
    lower_top = SIZE // 2 + panel_gap // 2
    lower_bottom = SIZE - margin

    panels = [
        (upper_top, upper_bottom, panel_left, panel_right),
        (lower_top, lower_bottom, panel_left, panel_right),
    ]

    for (ptop, pbottom, pleft, pright) in panels:
        # Darken the recessed panel area slightly
        for y in range(ptop, pbottom):
            for x in range(pleft, pright):
                img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * 0.92

        # Top bevel (shadow - panel is recessed)
        for y in range(ptop, ptop + bevel):
            for x in range(pleft, pright):
                img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * 0.78

        # Bottom bevel (highlight)
        for y in range(pbottom - bevel, pbottom):
            for x in range(pleft, pright):
                img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * 1.08

        # Left bevel (shadow)
        for y in range(ptop, pbottom):
            for x in range(pleft, pleft + bevel):
                img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * 0.80

        # Right bevel (highlight)
        for y in range(ptop, pbottom):
            for x in range(pright - bevel, pright):
                img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * 1.06

    return img


def draw_door_handle(img, door_left, door_right):
    """
    Draw a more defined door handle on the right side of the door.
    Larger backplate, thicker lever, better metallic shading.
    Classic lever-style office door handle.
    """
    handle_center_x = door_right - 18
    handle_center_y = SIZE // 2

    # --- Backplate (larger, rounded-corner rectangle) ---
    bp_width = 10
    bp_height = 26
    bp_left = handle_center_x - bp_width // 2
    bp_right = handle_center_x + bp_width // 2
    bp_top = handle_center_y - bp_height // 2
    bp_bottom = handle_center_y + bp_height // 2

    for y in range(bp_top, bp_bottom):
        for x in range(bp_left, bp_right):
            yy = y % SIZE
            xx = x % SIZE
            # Rounded corners: skip corner pixels
            dy = min(y - bp_top, bp_bottom - 1 - y)
            dx = min(x - bp_left, bp_right - 1 - x)
            if dy == 0 and dx == 0:
                continue  # Skip exact corners for rounded look
            # Metallic gradient on backplate
            t = (y - bp_top) / max(1, bp_height - 1)
            base = HANDLE_DARK * 0.9
            sheen = base * (1.0 + 0.15 * sin(t * pi))
            img[yy, xx] = sheen

    # Backplate edge highlight (top)
    for x in range(bp_left + 1, bp_right - 1):
        img[bp_top % SIZE, x % SIZE] = HANDLE_COLOR * 0.85

    # Backplate edge shadow (bottom)
    for x in range(bp_left + 1, bp_right - 1):
        img[(bp_bottom - 1) % SIZE, x % SIZE] = HANDLE_DARK * 0.7

    # --- Lever handle (horizontal bar, slightly larger) ---
    lever_width = 18
    lever_height = 5
    lever_left = handle_center_x - lever_width // 2 + 3
    lever_right = handle_center_x + lever_width // 2 + 3
    lever_top = handle_center_y - lever_height // 2
    lever_bottom = handle_center_y + lever_height // 2

    for y in range(lever_top, lever_bottom):
        for x in range(lever_left, lever_right):
            yy = y % SIZE
            xx = x % SIZE
            # Metallic gradient: bright top, darker bottom
            t = (y - lever_top) / max(1, lever_height - 1)
            color = HANDLE_HIGHLIGHT * (1 - t * 0.5) + HANDLE_COLOR * (t * 0.5)
            # Slight horizontal gradient too (brighter toward tip)
            tx = (x - lever_left) / max(1, lever_width - 1)
            color = color * (0.9 + tx * 0.15)
            img[yy, xx] = color

    # Lever top highlight line
    for x in range(lever_left, lever_right):
        img[lever_top % SIZE, x % SIZE] = HANDLE_HIGHLIGHT * 1.05

    # Lever bottom shadow line
    for x in range(lever_left + 1, lever_right - 1):
        img[lever_bottom % SIZE, x % SIZE] = HANDLE_DARK * 0.85

    # Shadow cast below lever (soft)
    for dy in range(1, 3):
        for x in range(lever_left + 1, lever_right):
            yy = (lever_bottom + dy) % SIZE
            xx = x % SIZE
            shadow_strength = 0.88 + dy * 0.04
            img[yy, xx] = img[yy, xx] * shadow_strength

    # --- Lever return/base (round nub where lever meets backplate) ---
    nub_cx = handle_center_x
    nub_cy = handle_center_y
    nub_r = 3
    for dy in range(-nub_r, nub_r + 1):
        for dx in range(-nub_r, nub_r + 1):
            if dx * dx + dy * dy <= nub_r * nub_r:
                yy = (nub_cy + dy) % SIZE
                xx = (nub_cx + dx) % SIZE
                dist = sqrt(dx * dx + dy * dy) / nub_r
                # Bright center, dark edges = convex metallic nub
                color = HANDLE_HIGHLIGHT * (1 - dist * 0.5) + HANDLE_COLOR * (dist * 0.5)
                img[yy, xx] = color

    # --- Keyhole: small dark circle below handle ---
    kh_y = handle_center_y + 14
    kh_x = handle_center_x
    for dy in range(-2, 3):
        for dx in range(-1, 2):
            if abs(dy) + abs(dx) <= 2:
                yy = (kh_y + dy) % SIZE
                xx = (kh_x + dx) % SIZE
                img[yy, xx] = np.array([35, 30, 25], dtype=np.float64)
    # Keyhole highlight (small bright pixel at top)
    img[(kh_y - 2) % SIZE, kh_x % SIZE] = HANDLE_COLOR * 0.6

    return img


def add_water_stains(img, door_left, door_right):
    """
    Add water stain / discoloration patches to the door surface.
    These are irregular darker or yellowish patches that look like
    decades of moisture damage in the Backrooms' humid environment.
    All coordinates use modulo wrapping for seamless tiling.
    """
    num_stains = random.randint(6, 10)
    for _ in range(num_stains):
        # Random center on the door surface
        cx = random.randint(door_left + 5, door_right - 5)
        cy = random.randint(0, SIZE - 1)
        radius = random.randint(6, 18)
        # Stain color shift: slightly yellowed/darkened
        stain_type = random.choice(["dark", "yellow", "brown"])

        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = sqrt(dx * dx + dy * dy)
                if dist > radius:
                    continue
                # Falloff: stronger at center, fading at edges
                falloff = 1.0 - (dist / radius)
                falloff = falloff * falloff  # Quadratic falloff for softer edges
                strength = falloff * random.uniform(0.08, 0.18)

                yy = (cy + dy) % SIZE
                xx = (cx + dx) % SIZE

                # Only apply to door area
                if xx < door_left or xx >= door_right:
                    continue

                if stain_type == "dark":
                    img[yy, xx] = img[yy, xx] * (1.0 - strength * 0.4)
                elif stain_type == "yellow":
                    # Shift toward yellow
                    shift = np.array([5, 3, -8], dtype=np.float64) * strength
                    img[yy, xx] = img[yy, xx] + shift
                else:  # brown
                    # Shift toward darker brown
                    shift = np.array([-8, -5, -3], dtype=np.float64) * strength
                    img[yy, xx] = img[yy, xx] + shift

    return img


def add_edge_darkening(img, door_left, door_right):
    """
    Add darkening near the frame edges (where grime accumulates where
    the door meets the frame). Uses smooth gradients that wrap seamlessly.
    """
    # Darken near left and right edges of door (grime at frame junction)
    edge_zone = 6
    for y in range(SIZE):
        for x in range(door_left, door_left + edge_zone):
            t = 1.0 - ((x - door_left) / edge_zone)
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * (1.0 - t * 0.18)
        for x in range(door_right - edge_zone, door_right):
            t = (x - (door_right - edge_zone)) / edge_zone
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * (1.0 - t * 0.18)

    # Vertical edge darkening that wraps seamlessly using periodic function
    # Use cos so that the darkening is symmetric at y=0 and y=SIZE
    for y in range(SIZE):
        for x in range(door_left, door_right):
            # Periodic darkening: darker at y=0/SIZE boundary, lighter in middle
            # This creates a subtle banding that tiles perfectly
            vert_dark = 0.04 * (1.0 + cos(2 * pi * y / SIZE)) * 0.5
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * (1.0 - vert_dark)

    return img


def add_scuff_marks(img, door_left, door_right):
    """
    Add visible scuff marks, scratches, and wear marks across the door.
    More numerous and varied than iteration 1.
    """
    # --- Larger scuff patches (shoe marks, bumps) ---
    num_scuffs = random.randint(18, 30)
    for _ in range(num_scuffs):
        sx = random.randint(door_left + 3, door_right - 3)
        sy = random.randint(0, SIZE - 1)
        scuff_len = random.randint(3, 12)
        scuff_width = random.randint(1, 3)
        angle = random.uniform(-0.5, 0.5)
        darken = random.uniform(0.80, 0.93)

        for i in range(scuff_len):
            for w in range(scuff_width):
                px = (sx + int(i * cos(angle))) % SIZE
                py = (sy + int(i * sin(angle)) + w) % SIZE
                if door_left <= px < door_right:
                    img[py, px] = img[py, px] * darken

    # --- Fine scratches (thin single-pixel lines) ---
    num_scratches = random.randint(8, 15)
    for _ in range(num_scratches):
        sx = random.randint(door_left + 5, door_right - 5)
        sy = random.randint(0, SIZE - 1)
        length = random.randint(5, 20)
        angle = random.uniform(-pi / 6, pi / 6)
        # Scratches are slightly lighter (exposed wood underneath)
        lighten = random.uniform(1.04, 1.12)

        for i in range(length):
            px = (sx + int(i * cos(angle))) % SIZE
            py = (sy + int(i * sin(angle))) % SIZE
            if door_left <= px < door_right:
                img[py, px] = img[py, px] * lighten

    return img


def add_discoloration_patches(img, door_left, door_right):
    """
    Add large, subtle discoloration patches across the door surface.
    These simulate decades of uneven aging, UV exposure, and moisture.
    Uses very large, soft blobs for organic-looking wear.
    """
    num_patches = random.randint(4, 7)
    for _ in range(num_patches):
        cx = random.randint(door_left, door_right)
        cy = random.randint(0, SIZE - 1)
        radius = random.randint(15, 35)
        # Random color shift
        r_shift = random.uniform(-12, 8)
        g_shift = random.uniform(-10, 6)
        b_shift = random.uniform(-15, 4)
        shift = np.array([r_shift, g_shift, b_shift], dtype=np.float64)

        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = sqrt(dx * dx + dy * dy)
                if dist > radius:
                    continue
                falloff = 1.0 - (dist / radius)
                falloff = falloff * falloff * falloff  # Cubic for very soft edges
                strength = falloff * 0.5

                yy = (cy + dy) % SIZE
                xx = (cx + dx) % SIZE
                if xx < door_left or xx >= door_right:
                    continue

                img[yy, xx] = img[yy, xx] + shift * strength

    return img


def add_grime_near_handle(img, door_left, door_right):
    """
    Add extra grime/darkening near the door handle area where hands
    have touched for decades. A dark, greasy-looking patch.
    """
    handle_cx = door_right - 18
    handle_cy = SIZE // 2
    grime_radius = 20

    for dy in range(-grime_radius, grime_radius + 1):
        for dx in range(-grime_radius, grime_radius + 1):
            dist = sqrt(dx * dx + dy * dy)
            if dist > grime_radius:
                continue
            falloff = 1.0 - (dist / grime_radius)
            falloff = falloff * falloff
            darken = 1.0 - falloff * 0.12

            yy = (handle_cy + dy) % SIZE
            xx = (handle_cx + dx) % SIZE
            if xx < door_left or xx >= door_right:
                continue
            img[yy, xx] = img[yy, xx] * darken

    return img


def add_overall_noise(img):
    """
    Add fine pixel-level noise across the entire texture for PSX grittiness.
    Uses modulo wrapping for all operations.
    """
    noise = np.random.randn(SIZE, SIZE, 3) * 4.5
    img += noise

    # Subtle dithering pattern (PSX-like)
    for y in range(SIZE):
        for x in range(SIZE):
            if (x + y) % 2 == 0:
                img[y % SIZE, x % SIZE] += 1.5
            else:
                img[y % SIZE, x % SIZE] -= 1.5

    return img


def add_wallpaper_frame_grime(img, door_left):
    """
    Add subtle grime to the wallpaper frame strips (left/right borders).
    This must also tile seamlessly, so we use periodic vertical functions.
    """
    frame_width = 8  # Wallpaper border on each side

    for y in range(SIZE):
        # Periodic vertical grime on wallpaper strips
        grime = 0.03 * (1.0 + sin(2 * pi * y / SIZE * 2)) * 0.5
        grime += 0.02 * (1.0 + sin(2 * pi * y / SIZE * 5 + 1.7)) * 0.5

        # Left wallpaper strip
        for x in range(0, frame_width):
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * (1.0 - grime)

        # Right wallpaper strip
        for x in range(SIZE - frame_width, SIZE):
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * (1.0 - grime)

    return img


def generate_door_texture():
    """
    Generate the complete closed door texture with all fixes applied.
    """
    print("Generating Backrooms closed door texture (iteration 2)...")

    # Load wallpaper for frame reference
    print("  Loading wallpaper texture...")
    wallpaper = load_wallpaper()

    # Step 1: Create base with wallpaper frame
    print("  Creating wallpaper frame base...")
    img = create_base_wallpaper_frame(wallpaper)

    # Step 2: Draw door panel (wood) with tiling-safe grain
    print("  Drawing door panel...")
    img, door_left, door_right = draw_door_panel(img)

    # Step 3: Add wood grain detail (wraps vertically)
    print("  Adding wood grain...")
    img = add_wood_grain(img, door_left, door_right)

    # Step 4: Draw frame trim between wallpaper and door
    print("  Drawing frame trim...")
    img = draw_frame_trim(img, door_left, door_right)

    # Step 5: Draw recessed panels on door face
    print("  Drawing recessed panels...")
    img = draw_recessed_panels(img, door_left, door_right)

    # Step 6: Draw door handle (improved size and definition)
    print("  Drawing door handle...")
    img = draw_door_handle(img, door_left, door_right)

    # Step 7: Weathering — water stains
    print("  Adding water stains...")
    img = add_water_stains(img, door_left, door_right)

    # Step 8: Weathering — edge darkening (tiling-safe)
    print("  Adding edge darkening...")
    img = add_edge_darkening(img, door_left, door_right)

    # Step 9: Weathering — scuff marks and scratches
    print("  Adding scuff marks and scratches...")
    img = add_scuff_marks(img, door_left, door_right)

    # Step 10: Weathering — discoloration patches
    print("  Adding discoloration patches...")
    img = add_discoloration_patches(img, door_left, door_right)

    # Step 11: Weathering — grime near handle
    print("  Adding grime near handle...")
    img = add_grime_near_handle(img, door_left, door_right)

    # Step 12: Grime on wallpaper frame strips
    print("  Adding wallpaper frame grime...")
    img = add_wallpaper_frame_grime(img, door_left)

    # Step 13: Overall PSX noise
    print("  Adding PSX noise...")
    img = add_overall_noise(img)

    # Clamp to valid range
    print("  Clamping values...")
    img = np.clip(img, 0, 255).astype(np.uint8)

    # Convert to PIL Image and save
    result = Image.fromarray(img, mode='RGB')
    result.save(OUTPUT_PATH)
    print(f"  Saved to {OUTPUT_PATH}")
    print(f"  Size: {result.size[0]}x{result.size[1]}, Mode: {result.mode}")

    return result


def generate_tiled_preview(img_path):
    """
    Create a 2x2 tiled version to visually verify seamlessness.
    """
    img = Image.open(img_path)
    width, height = img.size

    tiled = Image.new('RGB', (width * 2, height * 2))
    tiled.paste(img, (0, 0))
    tiled.paste(img, (width, 0))
    tiled.paste(img, (0, height))
    tiled.paste(img, (width, height))

    tiled.save(TILED_PATH)
    print(f"  Saved 2x2 tiled version to {TILED_PATH} for seam verification")

    return tiled


if __name__ == "__main__":
    # Fixed seed for reproducibility
    np.random.seed(42)
    random.seed(42)

    generate_door_texture()

    # Verify output
    img = Image.open(OUTPUT_PATH)
    print(f"\nVerified: {img.size[0]}x{img.size[1]} pixels, {img.mode} mode")

    # Generate tiled preview
    print("\nGenerating 2x2 tiled preview...")
    generate_tiled_preview(OUTPUT_PATH)

    print("\nDone!")
