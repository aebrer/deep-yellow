#!/usr/bin/env python3
"""
Backrooms Level 0 Open Door Threshold Texture Generator

Generates a 128x128 tileable floor texture depicting a door threshold/track
on brown carpet. This is a FLOOR tile viewed from above -- when a door opens,
the wall tile swaps to this floor tile showing where the door used to be.

Visual elements:
- Base: brown carpet (loaded from existing asset)
- A thin metallic door track/strip running horizontally across the middle
- Worn/discolored carpet around the track (more foot traffic here)
- Scuff marks from the door sliding along the track
- Subtle dust/debris accumulation along the track edges
- PSX aesthetic: grungy, low-fi

The track runs horizontally (left-right) so it tiles seamlessly in that
direction. Vertically, the carpet above and below the track blends back
into normal carpet for seamless vertical tiling too.
"""

import numpy as np
from PIL import Image
import random
from math import sqrt, sin, cos, pi

# Configuration
SIZE = 128
OUTPUT_PATH = "output.png"
TILED_PATH = "output_tiled_2x2.png"
CARPET_PATH = "/home/drew/projects/deep_yellow/assets/levels/level_00/textures/carpet_brown.png"

# Door track colors (brushed aluminum / chrome strip)
TRACK_BASE = np.array([145, 140, 130], dtype=np.float64)      # Brushed metal base
TRACK_HIGHLIGHT = np.array([175, 170, 158], dtype=np.float64)  # Metal highlight
TRACK_SHADOW = np.array([95, 90, 82], dtype=np.float64)        # Metal shadow
TRACK_GROOVE = np.array([55, 52, 48], dtype=np.float64)        # Dark groove/slot

# Wear zone colors (shifts applied to carpet)
WEAR_DARKEN = 0.82    # How much to darken worn carpet
WEAR_YELLOW_SHIFT = np.array([4, 2, -6], dtype=np.float64)  # Yellowing from age


def load_carpet():
    """
    Load the base brown carpet texture. Returns a numpy array (float64, RGB).
    The carpet is already 128x128 and tileable.
    """
    try:
        img = Image.open(CARPET_PATH).convert('RGB')
        arr = np.array(img).astype(np.float64)
        print(f"  Loaded carpet: {img.size[0]}x{img.size[1]}, mode={img.mode}")
        return arr
    except FileNotFoundError:
        print(f"  WARNING: Carpet not found at {CARPET_PATH}, generating procedural fallback")
        # Procedural brown carpet fallback
        arr = np.zeros((SIZE, SIZE, 3), dtype=np.float64)
        for y in range(SIZE):
            for x in range(SIZE):
                base = np.array([115, 92, 64], dtype=np.float64)
                noise = np.random.randn(3) * 8
                arr[y, x] = base + noise
        return arr


def add_wear_zone(img, carpet_base):
    """
    Add a worn/discolored zone around the door track area. Carpet near the
    threshold gets more foot traffic, so it's more matted, darker, and
    slightly discolored compared to the surrounding carpet.

    The wear zone is strongest right next to the track and fades out
    toward the top and bottom edges using a smooth falloff, so it tiles
    seamlessly vertically (the edges match normal carpet).
    """
    track_center_y = SIZE // 2
    # Wear zone extends ~30px above and below the track center
    wear_radius = 30

    for y in range(SIZE):
        # Distance from the track center (in tile-wrapped space)
        dist = abs(y - track_center_y)
        # Handle wrapping: also check distance via the wrap-around path
        dist_wrapped = SIZE - dist
        dist = min(dist, dist_wrapped)

        if dist >= wear_radius:
            continue

        # Smooth falloff: strongest near track, fading to zero at edge
        # Using cosine falloff for smooth blending
        t = dist / wear_radius
        strength = 0.5 * (1.0 + cos(pi * t))  # 1.0 at center, 0.0 at edge

        for x in range(SIZE):
            # Darken the carpet
            darken_factor = 1.0 - (1.0 - WEAR_DARKEN) * strength
            img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * darken_factor

            # Add slight yellowing/discoloration
            img[y % SIZE, x % SIZE] += WEAR_YELLOW_SHIFT * strength * 0.4

            # Reduce carpet texture variation (matted/flattened carpet)
            # Blend slightly toward the local average to simulate matting
            carpet_val = carpet_base[y % SIZE, x % SIZE]
            local_avg = np.mean(carpet_val)
            flatten_strength = strength * 0.15
            for c in range(3):
                diff = img[y % SIZE, x % SIZE, c] - local_avg
                img[y % SIZE, x % SIZE, c] -= diff * flatten_strength

    return img


def draw_door_track(img):
    """
    Draw a thin metallic door track/strip running horizontally across the
    middle of the tile. This is the rail that the door slides along.

    Track anatomy (from top to bottom):
    - 1px: shadow line (carpet shadow cast by track)
    - 1px: track top bevel (highlight)
    - 1px: track surface (brushed metal)
    - 1px: groove/slot (dark center line where door slides)
    - 1px: track surface (brushed metal)
    - 1px: track bottom bevel (shadow)
    - 1px: shadow line (carpet shadow cast by track)

    Total: 7px tall, centered vertically.
    The track runs the full width for seamless horizontal tiling.
    """
    track_top = SIZE // 2 - 3  # 7px tall, centered

    for x in range(SIZE):
        # Horizontal variation for brushed metal look
        # Use periodic function so it tiles horizontally
        brush_var = sin(2 * pi * x / SIZE * 16) * 3 + sin(2 * pi * x / SIZE * 7) * 2
        spot_var = random.uniform(-2, 2)  # Per-pixel noise

        # Row 0: Top shadow on carpet (track casts shadow on carpet above)
        y = track_top
        shadow_strength = 0.75 + random.uniform(-0.05, 0.05)
        img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * shadow_strength

        # Row 1: Track top bevel (highlight - light catches the top edge)
        y = track_top + 1
        color = TRACK_HIGHLIGHT + brush_var + spot_var
        img[y % SIZE, x % SIZE] = color

        # Row 2: Track upper surface (brushed metal)
        y = track_top + 2
        color = TRACK_BASE + brush_var * 0.8 + spot_var
        img[y % SIZE, x % SIZE] = color

        # Row 3: Center groove/slot (dark line where door panel slides)
        y = track_top + 3
        groove_depth = random.uniform(-3, 3)
        color = TRACK_GROOVE + groove_depth
        img[y % SIZE, x % SIZE] = color

        # Row 4: Track lower surface (brushed metal, slightly darker)
        y = track_top + 4
        color = TRACK_BASE * 0.92 + brush_var * 0.6 + spot_var
        img[y % SIZE, x % SIZE] = color

        # Row 5: Track bottom bevel (shadow edge)
        y = track_top + 5
        color = TRACK_SHADOW + brush_var * 0.5 + spot_var
        img[y % SIZE, x % SIZE] = color

        # Row 6: Bottom shadow on carpet (track casts shadow on carpet below)
        y = track_top + 6
        shadow_strength = 0.70 + random.uniform(-0.05, 0.05)
        img[y % SIZE, x % SIZE] = img[y % SIZE, x % SIZE] * shadow_strength

    return img, track_top


def add_track_grime(img, track_top):
    """
    Add dust, grime, and debris accumulation along the track edges.
    Dirt collects in the gap between the track and the carpet.
    Uses modulo wrapping for all coordinates.
    """
    track_height = 7

    for x in range(SIZE):
        # Dust specks along the top edge of the track
        if random.random() < 0.35:
            y = (track_top - 1) % SIZE
            dust_color = np.array([90, 82, 60], dtype=np.float64) + random.uniform(-10, 10)
            blend = random.uniform(0.15, 0.35)
            img[y, x % SIZE] = img[y, x % SIZE] * (1 - blend) + dust_color * blend

        # Dust specks along the bottom edge of the track
        if random.random() < 0.35:
            y = (track_top + track_height) % SIZE
            dust_color = np.array([90, 82, 60], dtype=np.float64) + random.uniform(-10, 10)
            blend = random.uniform(0.15, 0.35)
            img[y, x % SIZE] = img[y, x % SIZE] * (1 - blend) + dust_color * blend

        # Occasional darker grime/crud in the groove itself
        if random.random() < 0.2:
            y = (track_top + 3) % SIZE  # The groove row
            img[y, x % SIZE] = img[y, x % SIZE] * random.uniform(0.7, 0.9)

    # Clumps of lint/dust near the track (small irregular spots)
    num_clumps = random.randint(8, 14)
    for _ in range(num_clumps):
        cx = random.randint(0, SIZE - 1)
        # Position clumps near the track edges (above or below)
        if random.random() < 0.5:
            cy = (track_top - random.randint(1, 4)) % SIZE
        else:
            cy = (track_top + track_height + random.randint(0, 3)) % SIZE

        clump_size = random.randint(1, 3)
        for dy in range(-clump_size, clump_size + 1):
            for dx in range(-clump_size, clump_size + 1):
                if abs(dy) + abs(dx) > clump_size + 1:
                    continue
                if random.random() < 0.4:
                    continue
                yy = (cy + dy) % SIZE
                xx = (cx + dx) % SIZE
                darken = random.uniform(0.82, 0.92)
                img[yy, xx] = img[yy, xx] * darken

    return img


def add_door_scuff_marks(img, track_top):
    """
    Add scuff marks from the door sliding. These are subtle arc-shaped
    or straight marks on the carpet near the track, where the bottom
    edge of the door has scraped the carpet over many openings/closings.

    Scuffs are primarily on one side of the track (the side the door
    swings toward) and run roughly parallel to the track.
    """
    track_center_y = track_top + 3

    # Main scuff zone: carpet on the side where door swings open
    # (above the track in our case, since door opens "away")
    num_scuffs = random.randint(12, 20)
    for _ in range(num_scuffs):
        # Scuffs are short horizontal-ish marks
        sx = random.randint(0, SIZE - 1)
        # Position scuffs a few pixels from the track
        sy = (track_center_y + random.choice([-1, 1]) * random.randint(5, 18)) % SIZE

        scuff_len = random.randint(6, 22)
        scuff_angle = random.uniform(-0.15, 0.15)  # Nearly horizontal
        darken = random.uniform(0.82, 0.92)

        for i in range(scuff_len):
            px = (sx + int(i * cos(scuff_angle))) % SIZE
            py = (sy + int(i * sin(scuff_angle))) % SIZE
            img[py, px] = img[py, px] * darken
            # Some scuffs are 2px wide
            if random.random() < 0.4:
                py2 = (py + 1) % SIZE
                img[py2, px] = img[py2, px] * (darken * 1.03)

    # A few prominent arc-shaped scuffs (door bottom dragging on carpet)
    num_arcs = random.randint(2, 4)
    for _ in range(num_arcs):
        arc_start_x = random.randint(0, SIZE - 1)
        arc_y_base = (track_center_y + random.choice([-1, 1]) * random.randint(8, 20)) % SIZE
        arc_len = random.randint(15, 40)
        arc_curve = random.uniform(0.03, 0.08)  # Slight curve
        darken = random.uniform(0.78, 0.88)

        for i in range(arc_len):
            px = (arc_start_x + i) % SIZE
            # Gentle parabolic arc
            arc_offset = int(arc_curve * (i - arc_len / 2) ** 2 - arc_curve * (arc_len / 2) ** 2)
            py = (arc_y_base + arc_offset) % SIZE
            img[py, px] = img[py, px] * darken

    return img


def add_track_scratches(img, track_top):
    """
    Add fine scratches on the metal track surface itself. These run
    horizontally (parallel to the track) from the door sliding back
    and forth. Scratches are lighter lines on the metal.
    """
    track_surface_rows = [track_top + 1, track_top + 2, track_top + 4, track_top + 5]

    num_scratches = random.randint(8, 15)
    for _ in range(num_scratches):
        row = random.choice(track_surface_rows)
        start_x = random.randint(0, SIZE - 1)
        length = random.randint(8, 45)
        lighten = random.uniform(1.04, 1.14)

        for i in range(length):
            x = (start_x + i) % SIZE
            y = row % SIZE
            img[y, x] = img[y, x] * lighten

    # A few deeper scratches (darker)
    num_deep = random.randint(3, 6)
    for _ in range(num_deep):
        row = random.choice(track_surface_rows)
        start_x = random.randint(0, SIZE - 1)
        length = random.randint(5, 20)
        darken = random.uniform(0.85, 0.93)

        for i in range(length):
            x = (start_x + i) % SIZE
            y = row % SIZE
            img[y, x] = img[y, x] * darken

    return img


def add_track_wear_spots(img, track_top):
    """
    Add worn/polished spots on the track where it gets the most contact.
    These are brighter patches where the metal has been polished smooth
    by repeated door sliding.
    """
    num_spots = random.randint(4, 8)
    track_surface_rows = [track_top + 2, track_top + 4]  # The main surface rows

    for _ in range(num_spots):
        cx = random.randint(0, SIZE - 1)
        row = random.choice(track_surface_rows)
        spot_width = random.randint(6, 18)

        for dx in range(-spot_width // 2, spot_width // 2 + 1):
            x = (cx + dx) % SIZE
            # Smooth falloff from center
            t = abs(dx) / (spot_width / 2)
            brighten = 1.0 + (1.0 - t) * random.uniform(0.06, 0.12)
            img[row % SIZE, x] = img[row % SIZE, x] * brighten

    return img


def add_carpet_stain_near_track(img, track_top):
    """
    Add a couple of subtle stains/discoloration patches near the threshold.
    Doorways accumulate stains from foot traffic, spills, etc.
    All coordinates use modulo wrapping.
    """
    track_center_y = track_top + 3
    num_stains = random.randint(3, 6)

    for _ in range(num_stains):
        cx = random.randint(0, SIZE - 1)
        # Stains cluster near the track
        cy = (track_center_y + random.choice([-1, 1]) * random.randint(8, 25)) % SIZE
        radius = random.randint(5, 14)

        stain_type = random.choice(["dark", "yellow"])

        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                dist = sqrt(dx * dx + dy * dy)
                if dist > radius:
                    continue

                falloff = 1.0 - (dist / radius)
                falloff = falloff * falloff  # Quadratic falloff
                strength = falloff * random.uniform(0.06, 0.14)

                yy = (cy + dy) % SIZE
                xx = (cx + dx) % SIZE

                if stain_type == "dark":
                    img[yy, xx] = img[yy, xx] * (1.0 - strength * 0.3)
                else:
                    shift = np.array([3, 1, -5], dtype=np.float64) * strength
                    img[yy, xx] = img[yy, xx] + shift

    return img


def add_psx_noise(img):
    """
    Add fine pixel-level noise across the entire texture for PSX grittiness.
    Plus a subtle dither pattern.
    """
    # Per-pixel gaussian noise
    noise = np.random.randn(SIZE, SIZE, 3) * 3.0
    img += noise

    # Subtle checkerboard dither (PSX-like)
    for y in range(SIZE):
        for x in range(SIZE):
            if (x + y) % 2 == 0:
                img[y % SIZE, x % SIZE] += 1.0
            else:
                img[y % SIZE, x % SIZE] -= 1.0

    return img


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
    print(f"  Saved 2x2 tiled preview to {TILED_PATH}")


def generate_door_threshold():
    """
    Generate the complete open door threshold floor texture.
    """
    print("Generating Backrooms open door threshold texture...")

    # Step 1: Load base carpet
    print("  Loading carpet texture...")
    carpet = load_carpet()
    img = carpet.copy()

    # Step 2: Add wear zone around the threshold area
    print("  Adding carpet wear zone...")
    img = add_wear_zone(img, carpet)

    # Step 3: Add carpet stains near the threshold
    print("  Adding carpet stains near threshold...")
    img = add_carpet_stain_near_track(img, SIZE // 2 - 3)

    # Step 4: Add door scuff marks on the carpet
    print("  Adding door scuff marks...")
    img = add_door_scuff_marks(img, SIZE // 2 - 3)

    # Step 5: Draw the metallic door track
    print("  Drawing metallic door track...")
    img, track_top = draw_door_track(img)

    # Step 6: Add grime along the track edges
    print("  Adding track edge grime...")
    img = add_track_grime(img, track_top)

    # Step 7: Add scratches on the track metal
    print("  Adding track scratches...")
    img = add_track_scratches(img, track_top)

    # Step 8: Add polished wear spots on the track
    print("  Adding track wear spots...")
    img = add_track_wear_spots(img, track_top)

    # Step 9: PSX noise and dither
    print("  Adding PSX noise...")
    img = add_psx_noise(img)

    # Clamp to valid range
    print("  Clamping values...")
    img = np.clip(img, 0, 255).astype(np.uint8)

    # Save
    result = Image.fromarray(img, mode='RGB')
    result.save(OUTPUT_PATH)
    print(f"  Saved to {OUTPUT_PATH}")
    print(f"  Size: {result.size[0]}x{result.size[1]}, Mode: {result.mode}")

    return result


if __name__ == "__main__":
    # Fixed seed for reproducibility
    np.random.seed(42)
    random.seed(42)

    generate_door_threshold()

    # Verify output
    img = Image.open(OUTPUT_PATH)
    print(f"\nVerified: {img.size[0]}x{img.size[1]} pixels, {img.mode} mode")

    # Generate tiled preview
    print("\nGenerating 2x2 tiled preview...")
    generate_tiled_preview(OUTPUT_PATH)

    print("\nDone!")
