#!/usr/bin/env python3
"""
Generate a 64x64 PSX-style pixel art sprite of raw meat wrapped in butcher paper.
"""

from PIL import Image, ImageDraw

SIZE = 64

# PSX-era limited palette (chunky, iconic style)
# Paper colors (off-white/brown butcher paper)
PAPER_LIGHT = (230, 220, 200, 255)
PAPER_MID = (200, 185, 160, 255)
PAPER_DARK = (160, 145, 120, 255)

# Meat colors (pinkish-red raw meat)
MEAT_LIGHT = (220, 140, 140, 255)
MEAT_MID = (200, 100, 100, 255)
MEAT_DARK = (160, 70, 70, 255)
MEAT_MARBLING = (240, 180, 180, 255)  # Fat marbling

# Outline/shadow
OUTLINE = (80, 60, 50, 255)
TRANSPARENT = (0, 0, 0, 0)

def draw_thick_line(draw, x1, y1, x2, y2, color, thickness=2):
    """Draw a thick pixel art line."""
    for i in range(-thickness // 2, thickness // 2 + 1):
        draw.line([(x1 + i, y1), (x2 + i, y2)], fill=color, width=1)
        draw.line([(x1, y1 + i), (x2, y2 + i)], fill=color, width=1)

def main():
    # Create image with transparent background
    img = Image.new('RGBA', (SIZE, SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # Draw wrapped meat slab (angled rectangle with paper wrapping)
    # Main meat body - offset rectangle to show depth

    # Back face of meat slab (darker, partially visible)
    back_polygon = [
        (18, 24),  # top-left back
        (40, 20),  # top-right back
        (42, 42),  # bottom-right back
        (20, 46)   # bottom-left back
    ]
    draw.polygon(back_polygon, fill=MEAT_DARK, outline=OUTLINE)

    # Front face of meat slab (main visible surface)
    front_polygon = [
        (14, 26),  # top-left
        (36, 22),  # top-right
        (38, 44),  # bottom-right
        (16, 48)   # bottom-left
    ]
    draw.polygon(front_polygon, fill=MEAT_MID, outline=OUTLINE)

    # Add some fat marbling (irregular chunky pixels)
    marbling_pixels = [
        (18, 30), (19, 30), (20, 30),
        (24, 34), (25, 34),
        (28, 38), (29, 38), (30, 38),
        (22, 42), (23, 42)
    ]
    for x, y in marbling_pixels:
        draw.point((x, y), fill=MEAT_MARBLING)

    # Add lighter meat highlights (top edge)
    highlight_pixels = [
        (16, 28), (17, 28), (18, 28),
        (20, 26), (21, 26), (22, 26),
        (24, 24), (25, 24)
    ]
    for x, y in highlight_pixels:
        draw.point((x, y), fill=MEAT_LIGHT)

    # Butcher paper wrapping (twisted ends on sides)

    # Left paper wrap
    left_paper = [
        (10, 30),  # outer left
        (14, 28),  # inner left
        (16, 40),  # bottom inner
        (12, 42)   # bottom outer
    ]
    draw.polygon(left_paper, fill=PAPER_MID, outline=OUTLINE)

    # Left paper fold detail
    draw.line([(11, 32), (14, 34)], fill=PAPER_DARK, width=1)
    draw.line([(12, 36), (15, 38)], fill=PAPER_DARK, width=1)

    # Right paper wrap
    right_paper = [
        (36, 24),  # inner right
        (44, 26),  # outer right
        (46, 38),  # bottom outer
        (38, 36)   # bottom inner
    ]
    draw.polygon(right_paper, fill=PAPER_LIGHT, outline=OUTLINE)

    # Right paper fold detail
    draw.line([(40, 28), (43, 30)], fill=PAPER_DARK, width=1)
    draw.line([(41, 32), (44, 34)], fill=PAPER_DARK, width=1)

    # Top paper wrap (twisted closure)
    top_paper = [
        (20, 20),  # left
        (32, 18),  # right
        (34, 24),  # bottom-right
        (22, 26)   # bottom-left
    ]
    draw.polygon(top_paper, fill=PAPER_LIGHT, outline=OUTLINE)

    # Top paper fold lines
    draw.line([(26, 19), (26, 25)], fill=PAPER_DARK, width=1)
    draw.line([(24, 21), (28, 21)], fill=PAPER_MID, width=1)

    # Bottom paper wrap
    bottom_paper = [
        (18, 46),  # top-left
        (36, 42),  # top-right
        (38, 48),  # bottom-right
        (20, 52)   # bottom-left
    ]
    draw.polygon(bottom_paper, fill=PAPER_MID, outline=OUTLINE)

    # Bottom paper fold
    draw.line([(28, 44), (28, 50)], fill=PAPER_DARK, width=1)

    # Save output
    img.save('output.png')
    print("✓ Generated 64x64 PSX-style meat sprite: output.png")
    print(f"  - Palette: {len(set([PAPER_LIGHT, PAPER_MID, PAPER_DARK, MEAT_LIGHT, MEAT_MID, MEAT_DARK, MEAT_MARBLING, OUTLINE]))} colors")
    print("  - Style: Chunky pixel art with transparent background")

if __name__ == '__main__':
    main()
