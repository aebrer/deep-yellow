#!/usr/bin/env python3
"""
Bacteria Spawn sprite generator for DEEP YELLOW
Generates a 64x64 PSX-style sprite of a small, spindly bug-rat creature
"""
from PIL import Image, ImageDraw
import random
import math

SIZE = 64

# Dark greenish-black color palette (CORRECTED - more visible green)
BODY_DARK = (35, 50, 35)         # Darkest green-black
BODY_MID = (45, 65, 45)          # Mid green-black
BODY_LIGHT = (55, 80, 55)        # Lighter green-black
BODY_HIGHLIGHT = (80, 120, 70)   # Sickly green accent
HIGHLIGHT_BRIGHT = (100, 140, 90)  # Brighter sickly green
LEG_DARK = (30, 50, 30)          # Dark spindly legs
LEG_HIGHLIGHT = (60, 90, 55)     # Leg highlights

def add_grain(img, intensity=12):
    """Add PSX-style grain/noise to the image"""
    pixels = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a > 0:
                noise = random.randint(-intensity, intensity)
                r = max(0, min(255, r + noise))
                g = max(0, min(255, g + noise))
                b = max(0, min(255, b + noise))
                pixels[x, y] = (r, g, b, a)

def draw_spindly_leg(draw, center_x, center_y, angle, length=26):
    """Draw a thin, spindly leg with multiple segments and organic variation"""
    # Calculate leg segments (2 segments per leg for articulation)
    segment1_len = length * 0.6 + random.uniform(-2, 2)  # Organic variation
    segment2_len = length * 0.4 + random.uniform(-1, 1)

    # First segment - goes outward from body
    end1_x = center_x + math.cos(angle) * segment1_len
    end1_y = center_y + math.sin(angle) * segment1_len

    # Second segment - angles downward/outward with more variation
    angle2 = angle + random.uniform(-0.6, 0.6)  # More organic variation
    end2_x = end1_x + math.cos(angle2) * segment2_len
    end2_y = end1_y + math.sin(angle2) * segment2_len

    # Draw leg segments with slight width variation (1-2 pixels)
    leg_width = random.randint(1, 2)
    draw.line([(center_x, center_y), (end1_x, end1_y)], fill=LEG_DARK + (255,), width=leg_width)
    draw.line([(end1_x, end1_y), (end2_x, end2_y)], fill=LEG_DARK + (255,), width=leg_width)

    # Add sickly green highlight to make legs visible
    offset_x = math.cos(angle + math.pi/2) * 0.5
    offset_y = math.sin(angle + math.pi/2) * 0.5
    draw.line(
        [(center_x + offset_x, center_y + offset_y),
         (end1_x + offset_x, end1_y + offset_y)],
        fill=LEG_HIGHLIGHT + (200,), width=1
    )

def draw_creature():
    """Generate the bacteria spawn sprite"""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center position (slightly lower to show scuttling posture)
    center_x = SIZE // 2
    center_y = SIZE // 2 + 2

    # Draw 8 spindly legs radiating outward (MUCH LONGER to fill canvas)
    num_legs = 8
    for i in range(num_legs):
        angle = (i / num_legs) * 2 * math.pi
        # Legs at different lengths for depth/variety (MUCH LONGER - fills ~60% of canvas)
        leg_length = 24 + random.randint(-3, 3)
        draw_spindly_leg(draw, center_x, center_y, angle, leg_length)

    # Draw larger body (MUCH BIGGER - fills canvas properly)
    body_width = 18  # Was 10, now 80% bigger
    body_height = 24  # Was 14, now 70% bigger
    body_bbox = [
        center_x - body_width//2,
        center_y - body_height//2,
        center_x + body_width//2,
        center_y + body_height//2
    ]

    # Main body (dark greenish-black ellipse)
    draw.ellipse(body_bbox, fill=BODY_DARK + (255,))

    # Add segmentation lines (like insect segments) - using lighter green
    for seg in range(3):
        y_pos = center_y - body_height//2 + (seg + 1) * (body_height // 4)
        draw.line(
            [(center_x - body_width//2 + 2, y_pos),
             (center_x + body_width//2 - 2, y_pos)],
            fill=BODY_LIGHT + (220,), width=1  # Using BODY_LIGHT for visibility
        )

    # Larger highlight on body (sickly green sheen)
    highlight_bbox = [
        center_x - body_width//3,
        center_y - body_height//3,
        center_x + body_width//4,
        center_y - body_height//6
    ]
    draw.ellipse(highlight_bbox, fill=BODY_HIGHLIGHT + (150,))

    # Additional bright sickly green accent
    small_highlight = [
        center_x - 2,
        center_y - body_height//4,
        center_x + 3,
        center_y - body_height//4 + 3
    ]
    draw.ellipse(small_highlight, fill=HIGHLIGHT_BRIGHT + (180,))

    # Larger head area (front of creature)
    head_size = 10  # Was 6, now larger
    head_y = center_y - body_height//2 - 3
    head_bbox = [
        center_x - head_size//2,
        head_y - head_size//2,
        center_x + head_size//2,
        head_y + head_size//2
    ]
    draw.ellipse(head_bbox, fill=BODY_MID + (255,))

    # Tiny eye spots (subtle, unsettling) - dark green-black, not pure black
    eye_offset = 3
    for eye_x in [center_x - eye_offset, center_x + eye_offset]:
        draw.ellipse(
            [eye_x - 1, head_y - 1, eye_x + 1, head_y + 1],
            fill=(15, 25, 15, 255)  # Very dark green-black eyes
        )
        # Add tiny sickly green glint
        draw.point((eye_x, head_y - 1), fill=HIGHLIGHT_BRIGHT + (200,))

    # Add some random spiky hairs/bristles for extra creepiness (more of them)
    for _ in range(10):
        bristle_angle = random.uniform(0, 2 * math.pi)
        bristle_start_r = 8
        bristle_end_r = 12 + random.randint(-2, 2)
        start_x = center_x + math.cos(bristle_angle) * bristle_start_r
        start_y = center_y + math.sin(bristle_angle) * bristle_start_r
        end_x = center_x + math.cos(bristle_angle) * bristle_end_r
        end_y = center_y + math.sin(bristle_angle) * bristle_end_r
        draw.line([(start_x, start_y), (end_x, end_y)], fill=BODY_DARK + (200,), width=1)

    # Apply PSX-style grain (INCREASED intensity for visibility)
    add_grain(img, intensity=15)

    return img

def main():
    print("Generating Bacteria Spawn sprite (64x64, PSX-style)...")
    print("- Dark greenish-black creature with spindly legs")
    print("- Small bug-rat scuttling horror aesthetic")

    img = draw_creature()
    img.save('output.png', 'PNG')

    print("✓ Generated: output.png")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print("  Format: RGBA (transparent background)")

if __name__ == '__main__':
    main()
