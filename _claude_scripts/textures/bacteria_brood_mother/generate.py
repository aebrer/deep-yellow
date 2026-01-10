"""
Bacteria Brood Mother Sprite Generator
Creates a 64x64 PSX-style sprite of the towering Kane Pixels Backrooms entity.

Tall, spindly creature with long arm-like limbs reaching to the ground.
Dark greenish-black color palette with subtle sickly green highlights.
"""

from PIL import Image, ImageDraw
import random
import math

# Canvas size
SIZE = 64

# Color palette - VERY dark greenish-black (almost black!)
# EXACT VALUES - DO NOT DEVIATE!
BODY_DARKEST = (12, 18, 14)      # Almost pure black with tiny green tint
BODY_DARK = (18, 28, 20)         # Very dark
BODY_MID = (25, 38, 28)          # Still very dark
HIGHLIGHT = (35, 50, 38)         # Dark green highlight (still very dark!)
HIGHLIGHT_BRIGHT = (42, 60, 45)  # Brightest value (still darker than before)

def add_noise(img, intensity=13):
    """Add PSX-style grain to the image"""
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if pixels[x, y][3] > 0:  # Only noise visible pixels
                r, g, b, a = pixels[x, y]
                noise = random.randint(-intensity, intensity)
                r = max(0, min(255, r + noise))
                g = max(0, min(255, g + noise))
                b = max(0, min(255, b + noise))
                pixels[x, y] = (r, g, b, a)

def draw_spindly_limb(draw, start_x, start_y, end_x, end_y, width_start, width_end, segments=8):
    """Draw a spindly, organic limb with varying width using SOLID SHAPES"""
    # Calculate curve points
    points = []
    for i in range(segments + 1):
        t = i / segments
        # Organic curve - slight bend
        curve_offset = math.sin(t * math.pi) * 2
        x = start_x + (end_x - start_x) * t + curve_offset
        y = start_y + (end_y - start_y) * t
        width = width_start + (width_end - width_start) * t
        points.append((x, y, width))

    # Draw as connected SOLID rectangles/polygons (NOT dots!)
    for i in range(len(points) - 1):
        x1, y1, w1 = points[i]
        x2, y2, w2 = points[i + 1]

        # Use darker colors for the limbs
        color = BODY_DARK if i % 2 == 0 else BODY_DARKEST

        # Draw SOLID polygon connecting this segment to next
        # Create a quadrilateral (trapezoid) for each segment
        left_edge = [(x1 - w1/2, y1), (x2 - w2/2, y2)]
        right_edge = [(x2 + w2/2, y2), (x1 + w1/2, y1)]
        polygon_points = left_edge + right_edge

        draw.polygon(polygon_points, fill=color)

def generate_brood_mother():
    """Generate the Bacteria Brood Mother sprite"""
    # Create transparent canvas
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center position
    center_x = SIZE // 2

    # --- PHASE 1: Long spindly limbs (ground to mid-body) ---
    # These are the iconic long, thin legs/arms that reach the ground

    # Left limb - starts from head area, extends to ground (THICKER for visibility)
    limb_left_top_x = center_x - 6
    limb_left_top_y = 12
    limb_left_bottom_x = center_x - 18
    limb_left_bottom_y = SIZE - 2
    draw_spindly_limb(draw, limb_left_top_x, limb_left_top_y,
                      limb_left_bottom_x, limb_left_bottom_y,
                      width_start=5, width_end=3, segments=12)

    # Right limb - starts from head area, extends to ground (THICKER for visibility)
    limb_right_top_x = center_x + 6
    limb_right_top_y = 12
    limb_right_bottom_x = center_x + 18
    limb_right_bottom_y = SIZE - 2
    draw_spindly_limb(draw, limb_right_top_x, limb_right_top_y,
                      limb_right_bottom_x, limb_right_bottom_y,
                      width_start=5, width_end=3, segments=12)

    # Additional wire-like strands for "tangled organic matter" effect (slightly thicker)
    # Front left strand
    draw_spindly_limb(draw, center_x - 3, 15,
                      center_x - 22, SIZE - 5,
                      width_start=2.5, width_end=2, segments=10)

    # Front right strand
    draw_spindly_limb(draw, center_x + 3, 15,
                      center_x + 22, SIZE - 5,
                      width_start=2.5, width_end=2, segments=10)

    # --- PHASE 2: Small head/upper body ---
    # Head - small, unsettling (slightly larger for visibility)
    head_y = 8
    draw.ellipse(
        [center_x - 6, head_y - 4, center_x + 6, head_y + 7],
        fill=BODY_MID
    )

    # Eye-like highlights (subtle, sickly green)
    draw.ellipse(
        [center_x - 3, head_y, center_x - 1, head_y + 2],
        fill=HIGHLIGHT
    )
    draw.ellipse(
        [center_x + 1, head_y, center_x + 3, head_y + 2],
        fill=HIGHLIGHT
    )

    # --- PHASE 3: Torso/body mass ---
    # Upper torso - thin, elongated (more solid for clearer silhouette)
    torso_top = 14
    torso_bottom = 28
    draw.ellipse(
        [center_x - 8, torso_top, center_x + 8, torso_bottom],
        fill=BODY_DARK
    )

    # Body segments/ridges for organic feel
    for i in range(3):
        y = torso_top + 4 + i * 4
        draw.line(
            [(center_x - 7, y), (center_x + 7, y)],
            fill=BODY_DARKEST,
            width=1
        )

    # Mid-body connection point where limbs meet (larger for connectivity)
    draw.ellipse(
        [center_x - 9, 24, center_x + 9, 32],
        fill=BODY_MID
    )

    # Shoulder connection points where limbs attach (makes form clearer)
    draw.ellipse(
        [center_x - 9, 10, center_x - 5, 16],
        fill=BODY_DARK
    )
    draw.ellipse(
        [center_x + 5, 10, center_x + 9, 16],
        fill=BODY_DARK
    )

    # --- PHASE 4: Organic details ---
    # Add vine-like details across the body
    for _ in range(6):
        x = random.randint(center_x - 6, center_x + 6)
        y_start = random.randint(15, 25)
        y_end = y_start + random.randint(3, 8)
        draw.line(
            [(x, y_start), (x, y_end)],
            fill=BODY_DARKEST,
            width=1
        )

    # Subtle highlights on upper body (sickly green)
    for _ in range(4):
        x = random.randint(center_x - 5, center_x + 5)
        y = random.randint(16, 26)
        draw.ellipse(
            [x - 1, y - 1, x + 1, y + 1],
            fill=HIGHLIGHT
        )

    # Brighter accent highlights (very sparse)
    for _ in range(2):
        x = random.randint(center_x - 4, center_x + 4)
        y = random.randint(18, 24)
        draw.point((x, y), fill=HIGHLIGHT_BRIGHT)

    # --- PHASE 5: PSX grain ---
    add_noise(img, intensity=13)

    return img

def main():
    """Generate and save the Brood Mother sprite"""
    print("Generating Bacteria Brood Mother sprite...")

    img = generate_brood_mother()

    output_path = "output.png"
    img.save(output_path, "PNG")

    print(f"✓ Brood Mother sprite saved to {output_path}")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print(f"  Style: PSX-aesthetic with dark greenish-black palette")
    print(f"  Features: Tall spindly limbs, small head, organic vine-like body")

if __name__ == "__main__":
    main()
