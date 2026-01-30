#!/usr/bin/env python3
"""
Generate a tileable wall hole texture for DEEP YELLOW.
Shows yellow wallpaper with a BOTTOM-OPENING CRAWL HOLE - like a rabbit hole
or crawl space at floor level. Human-sized, dark void inside, ragged edges.
"""

import numpy as np
from PIL import Image
import random

# Constants
SIZE = 128
BASE_WALLPAPER_PATH = "../../../assets/levels/level_00/textures/wallpaper_yellow.png"
OUTPUT_PATH = "output.png"

# Hole parameters - bottom opening (WIDE at bottom, NARROW at top)
HOLE_HEIGHT = 50  # How far up from bottom the hole extends
HOLE_WIDTH_BOTTOM = 105  # Width at the very bottom (wide - broken from floor up)
HOLE_WIDTH_TOP = 50  # Width at top of hole (narrows significantly as damage tapers)

# Colors
VOID_COLOR = (5, 4, 3)               # Near-black void - very dark
VOID_INNER = (2, 2, 2)               # Even darker inside
PLASTER_LIGHT = (180, 175, 160)      # Light plaster/drywall
PLASTER_MID = (120, 115, 105)        # Mid-tone plaster
PLASTER_DARK = (60, 58, 52)          # Dark plaster/shadow
TORN_EDGE_DARK = (140, 130, 90)      # Darker torn wallpaper edge

# Interior debris colors
WOOD_STUD = (110, 85, 60)            # Exposed wooden stud
WOOD_STUD_SHADOW = (45, 35, 25)      # Shadow on wood
DRYWALL_CHUNK = (160, 155, 145)      # Broken drywall pieces
INSULATION_PINK = (180, 140, 120)    # Pink fiberglass insulation
INSULATION_YELLOW = (160, 150, 100)  # Yellow/tan insulation
DUST = (80, 75, 65)                  # Dust and grime

def load_base_wallpaper():
    """Load the existing wallpaper texture."""
    img = Image.open(BASE_WALLPAPER_PATH).convert('RGB')
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.array(img, dtype=np.uint8)

def create_crawl_hole_mask(size):
    """
    Create a bottom-opening crawl hole mask.
    Returns a mask where 0.0 = inside hole (void), 1.0 = outside hole (wallpaper).
    """
    mask = np.ones((size, size), dtype=np.float32)

    # Set random seed for consistent raggedness
    np.random.seed(42)

    # Generate ragged top edge using noise
    ragged_edge = np.zeros(size, dtype=np.float32)
    for x in range(size):
        # Base curve - arch shape that's wider at bottom
        # Width varies with height
        progress = 1.0  # Start at bottom
        base_y = HOLE_HEIGHT

        # Add raggedness
        raggedness = np.random.randn() * 3.0
        ragged_edge[x] = base_y + raggedness

    # Smooth the ragged edge slightly
    from scipy.ndimage import gaussian_filter1d
    ragged_edge = gaussian_filter1d(ragged_edge, sigma=2.0)

    # Create the hole mask
    for y in range(size):
        for x in range(size):
            # Distance from bottom
            from_bottom = size - y

            # Calculate hole width at this height
            if from_bottom <= HOLE_HEIGHT:
                height_progress = from_bottom / HOLE_HEIGHT  # 0.0 at bottom, 1.0 at top of hole
                # Width interpolates from WIDE at bottom to NARROW at top
                # When from_bottom is small (near floor): width = HOLE_WIDTH_BOTTOM
                # When from_bottom approaches HOLE_HEIGHT (top of hole): width = HOLE_WIDTH_TOP
                hole_width = HOLE_WIDTH_BOTTOM + (HOLE_WIDTH_TOP - HOLE_WIDTH_BOTTOM) * height_progress

                # Center X position
                center_x = size / 2.0
                left_edge = center_x - hole_width / 2.0
                right_edge = center_x + hole_width / 2.0

                # Add raggedness to edges
                edge_raggedness = np.random.randn() * 2.0

                # Check if pixel is inside the hole
                if x > left_edge + edge_raggedness and x < right_edge - edge_raggedness:
                    # Inside the hole horizontally

                    # Check vertical position with ragged top edge
                    ragged_top = ragged_edge[x]

                    if from_bottom < ragged_top:
                        # Inside hole - check for transition zone at edges
                        dist_to_left = x - (left_edge + edge_raggedness)
                        dist_to_right = (right_edge - edge_raggedness) - x
                        dist_to_top = ragged_top - from_bottom

                        # Find minimum distance to any edge
                        min_dist = min(dist_to_left, dist_to_right, dist_to_top)

                        if min_dist < 3.0:
                            # Transition zone - blend
                            mask[y, x] = min_dist / 3.0
                        else:
                            # Fully inside hole
                            mask[y, x] = 0.0

    return mask, ragged_edge

def render_hole_interior(base_array, hole_mask):
    """
    Render the hole interior with visible debris and wall internals.
    Shows wooden studs, drywall chunks, insulation, dust - not just darkness.
    """
    result = base_array.copy()
    np.random.seed(50)  # Consistent debris placement

    # Pre-generate interior features
    # Wooden stud positions (vertical supports, typically 16" apart = ~20-25px in our scale)
    stud_positions = [40, 64, 88]  # Three vertical studs visible

    for y in range(SIZE):
        for x in range(SIZE):
            if hole_mask[y, x] < 1.0:
                # Inside or at edge of hole
                from_bottom = SIZE - y

                # Base dark background
                base_color = list(VOID_COLOR)

                # Add depth gradient - darker toward bottom and center
                depth_factor = from_bottom / HOLE_HEIGHT  # 0 at top, 1 at bottom
                center_x = SIZE / 2.0
                dist_from_center = abs(x - center_x) / (SIZE / 2.0)
                darkness = 1.0 - (depth_factor * 0.3 + (1.0 - dist_from_center) * 0.2)

                # Wooden studs (vertical lines with width ~3-5px)
                for stud_x in stud_positions:
                    dist_to_stud = abs(x - stud_x)
                    if dist_to_stud < 3:
                        # On a stud
                        stud_strength = 1.0 - (dist_to_stud / 3.0)
                        # Studs are darker at edges (shadow), lighter in center
                        if dist_to_stud < 1:
                            base_color = [int(WOOD_STUD[c] * darkness * 0.6) for c in range(3)]
                        else:
                            wood_color = [int(WOOD_STUD_SHADOW[c] * darkness * 0.4) for c in range(3)]
                            base_color = [
                                int(base_color[c] * (1 - stud_strength) + wood_color[c] * stud_strength)
                                for c in range(3)
                            ]

                # Drywall chunks (random scattered pieces)
                chunk_noise = np.random.rand()
                if chunk_noise < 0.15:  # 15% chance of drywall chunk
                    chunk_brightness = 0.5 + np.random.rand() * 0.3
                    base_color = [
                        int(DRYWALL_CHUNK[c] * darkness * chunk_brightness)
                        for c in range(3)
                    ]

                # Insulation wisps (random patches, especially near edges)
                insulation_noise = np.random.rand()
                if insulation_noise < 0.08:  # 8% chance of insulation
                    insulation_color = INSULATION_PINK if np.random.rand() < 0.6 else INSULATION_YELLOW
                    insulation_brightness = 0.4 + np.random.rand() * 0.3
                    base_color = [
                        int(insulation_color[c] * darkness * insulation_brightness)
                        for c in range(3)
                    ]

                # Dust/grime (subtle overlay)
                dust_noise = np.random.rand()
                if dust_noise < 0.2:  # 20% chance of dust
                    dust_strength = 0.3
                    base_color = [
                        int(base_color[c] * (1 - dust_strength) + DUST[c] * darkness * 0.5 * dust_strength)
                        for c in range(3)
                    ]

                # Extra darkness at very bottom (deep shadow)
                if from_bottom < 8:
                    bottom_shadow = 1.0 - (from_bottom / 8.0)
                    base_color = [int(c * (1.0 - bottom_shadow * 0.7)) for c in base_color]

                # Blend between interior and wallpaper based on mask
                blend = hole_mask[y, x]
                for c in range(3):
                    result[y, x, c] = int(
                        base_color[c] * (1.0 - blend) +
                        base_array[y, x, c] * blend
                    )

    return result

def add_plaster_debris(img_array, hole_mask, ragged_edge):
    """Add plaster/drywall chunks around the ragged top edge."""
    np.random.seed(43)

    for y in range(SIZE):
        for x in range(SIZE):
            from_bottom = SIZE - y

            # Only add plaster near the ragged top edge
            if from_bottom > 0 and from_bottom <= HOLE_HEIGHT + 15:
                ragged_top = ragged_edge[x]
                dist_to_edge = abs(from_bottom - ragged_top)

                # Plaster visible in a zone above the hole edge
                if dist_to_edge < 8 and from_bottom > ragged_top:
                    # Random plaster chunks
                    if random.random() < 0.3:
                        plaster_choice = random.random()

                        if plaster_choice < 0.3:
                            plaster_color = PLASTER_LIGHT
                        elif plaster_choice < 0.7:
                            plaster_color = PLASTER_MID
                        else:
                            plaster_color = PLASTER_DARK

                        # Blend plaster
                        plaster_strength = 0.4 * (1.0 - dist_to_edge / 8.0)
                        for c in range(3):
                            img_array[y, x, c] = int(
                                img_array[y, x, c] * (1.0 - plaster_strength) +
                                plaster_color[c] * plaster_strength
                            )

def add_torn_wallpaper_edges(img_array, hole_mask, ragged_edge):
    """Darken and damage wallpaper at the torn edges."""
    for y in range(SIZE):
        for x in range(SIZE):
            from_bottom = SIZE - y

            if from_bottom > 0 and from_bottom <= HOLE_HEIGHT + 10:
                ragged_top = ragged_edge[x]
                dist_to_edge = abs(from_bottom - ragged_top)

                # Torn edge zone - just above the hole
                if dist_to_edge < 5 and from_bottom > ragged_top:
                    edge_strength = 0.5 * (1.0 - dist_to_edge / 5.0)
                    for c in range(3):
                        img_array[y, x, c] = int(
                            img_array[y, x, c] * (1.0 - edge_strength) +
                            TORN_EDGE_DARK[c] * edge_strength
                        )

def add_subtle_cracks(img_array, ragged_edge):
    """Add subtle vertical cracks radiating from the hole edges."""
    np.random.seed(44)

    # Pick a few random X positions for cracks
    num_cracks = 5
    crack_positions = np.random.choice(range(20, SIZE - 20), num_cracks, replace=False)

    for crack_x in crack_positions:
        ragged_top = ragged_edge[crack_x]
        start_y = SIZE - int(ragged_top)

        # Crack extends upward
        crack_length = random.randint(10, 25)

        for offset in range(crack_length):
            y = start_y - offset
            if y < 0 or y >= SIZE:
                continue

            # Slight horizontal wandering
            x_wander = int(np.random.randn() * 0.5)
            x = crack_x + x_wander

            if x < 0 or x >= SIZE:
                continue

            # Darken slightly
            fade = 1.0 - (offset / crack_length) * 0.3
            for c in range(3):
                img_array[y, x, c] = int(img_array[y, x, c] * fade)

def main():
    print("Loading base wallpaper...")
    base_wallpaper = load_base_wallpaper()

    print("Creating bottom-opening crawl hole mask...")
    hole_mask, ragged_edge = create_crawl_hole_mask(SIZE)

    print("Rendering hole interior with debris (studs, drywall, insulation)...")
    result = render_hole_interior(base_wallpaper, hole_mask)

    print("Adding plaster debris around edges...")
    add_plaster_debris(result, hole_mask, ragged_edge)

    print("Adding torn wallpaper edges...")
    add_torn_wallpaper_edges(result, hole_mask, ragged_edge)

    print("Adding subtle cracks...")
    add_subtle_cracks(result, ragged_edge)

    print("Adding final grain/noise...")
    noise = np.random.randint(-4, 5, (SIZE, SIZE, 3), dtype=np.int16)
    result = np.clip(result.astype(np.int16) + noise, 0, 255).astype(np.uint8)

    print(f"Saving to {OUTPUT_PATH}...")
    output_img = Image.fromarray(result, mode='RGB')
    output_img.save(OUTPUT_PATH)

    print(f"✓ Wall hole texture generated successfully!")
    print(f"  Size: {SIZE}×{SIZE}")
    print(f"  Hole type: Bottom-opening crawl space (human-sized)")
    print(f"  Hole height: ~{HOLE_HEIGHT}px from bottom")
    print(f"  Hole shape: WIDE at bottom ({HOLE_WIDTH_BOTTOM}px) → NARROW at top ({HOLE_WIDTH_TOP}px)")
    print(f"  Interior: Wooden studs, drywall chunks, insulation, dust, debris")
    print(f"  Features: Ragged edges, plaster debris, torn wallpaper, depth shading")
    print(f"  Output: {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
