#!/usr/bin/env python3
"""
Generate a 64x64 ominous pit/hole texture for Backrooms exit stairs.
PSX-style low-fi pixel art aesthetic with transparent background.
"""

from PIL import Image, ImageDraw
import math

# Configuration
SIZE = 64
OUTPUT_PATH = "output.png"

# Color palette (PSX-style limited colors)
GROUND_DARK = (40, 35, 30)      # Dark brown-gray ground
GROUND_MID = (55, 48, 42)       # Mid-tone ground
GROUND_LIGHT = (70, 62, 55)     # Lighter ground edges
CRACK_COLOR = (20, 18, 15)      # Dark cracks
PIT_EDGE = (25, 22, 20)         # Pit outer edge
PIT_DARK = (12, 10, 8)          # Pit inner
PIT_BLACK = (0, 0, 0)           # Pure black center

def create_exit_hole():
    """Generate the ominous pit texture."""
    # Create RGBA image (transparent background)
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    center_x = SIZE // 2
    center_y = SIZE // 2

    # Draw ground circle (the damaged area around the pit)
    ground_radius = 30
    draw.ellipse(
        [center_x - ground_radius, center_y - ground_radius,
         center_x + ground_radius, center_y + ground_radius],
        fill=GROUND_MID + (255,)
    )

    # Add some texture to the ground (pixel-level noise and cracks)
    pixels = img.load()

    # Ground texture - subtle variation
    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx**2 + dy**2)

            # Only modify pixels within ground radius
            if dist <= ground_radius and dist > 15:
                current = pixels[x, y]
                if current[3] > 0:  # If not transparent
                    # Add subtle variation to ground color
                    if (x + y) % 3 == 0:
                        pixels[x, y] = GROUND_LIGHT + (255,)
                    elif (x * 3 + y * 2) % 5 == 0:
                        pixels[x, y] = GROUND_DARK + (255,)

    # Draw radial cracks emanating from pit
    num_cracks = 8
    for i in range(num_cracks):
        angle = (i / num_cracks) * 2 * math.pi
        # Cracks extend outward from pit edge
        start_r = 16
        end_r = ground_radius - 2

        for r in range(int(start_r), int(end_r), 2):
            # Add some wobble to cracks
            wobble = math.sin(r * 0.3 + i) * 1.5
            x = int(center_x + math.cos(angle) * r + wobble)
            y = int(center_y + math.sin(angle) * r + wobble)

            if 0 <= x < SIZE and 0 <= y < SIZE:
                # Draw crack pixel and neighbor for thickness
                pixels[x, y] = CRACK_COLOR + (255,)
                if x + 1 < SIZE:
                    pixels[x + 1, y] = CRACK_COLOR + (200,)

    # Draw the pit itself (concentric darkening circles)
    # Outer pit edge
    pit_radius_outer = 15
    draw.ellipse(
        [center_x - pit_radius_outer, center_y - pit_radius_outer,
         center_x + pit_radius_outer, center_y + pit_radius_outer],
        fill=PIT_EDGE + (255,)
    )

    # Mid pit
    pit_radius_mid = 11
    draw.ellipse(
        [center_x - pit_radius_mid, center_y - pit_radius_mid,
         center_x + pit_radius_mid, center_y + pit_radius_mid],
        fill=PIT_DARK + (255,)
    )

    # Inner pit (pure black abyss)
    pit_radius_inner = 7
    draw.ellipse(
        [center_x - pit_radius_inner, center_y - pit_radius_inner,
         center_x + pit_radius_inner, center_y + pit_radius_inner],
        fill=PIT_BLACK + (255,)
    )

    # Add some depth detail to pit edge (rough/jagged edge effect)
    for angle_deg in range(0, 360, 15):
        angle = math.radians(angle_deg)
        # Vary the radius slightly for each point
        r_var = pit_radius_outer + (1 if angle_deg % 30 == 0 else -1)
        x = int(center_x + math.cos(angle) * r_var)
        y = int(center_y + math.sin(angle) * r_var)

        if 0 <= x < SIZE and 0 <= y < SIZE:
            pixels[x, y] = CRACK_COLOR + (255,)

    # Add subtle shadow gradient around pit edge (darkening effect)
    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx**2 + dy**2)

            # Shadow ring around pit
            if 15 < dist < 20:
                current = pixels[x, y]
                if current[3] > 0:  # If not transparent
                    # Darken pixels near pit edge
                    factor = 0.7
                    r = int(current[0] * factor)
                    g = int(current[1] * factor)
                    b = int(current[2] * factor)
                    pixels[x, y] = (r, g, b, current[3])

    return img

def main():
    """Generate and save the exit hole texture."""
    print(f"Generating {SIZE}x{SIZE} exit hole texture...")

    img = create_exit_hole()

    # Save PNG
    img.save(OUTPUT_PATH, 'PNG')
    print(f"✓ Saved texture to: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print(f"  Format: RGBA PNG (transparent background)")
    print(f"  Style: Ominous pit with dark center, cracked ground")

if __name__ == "__main__":
    main()
