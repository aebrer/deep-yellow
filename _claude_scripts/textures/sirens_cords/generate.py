#!/usr/bin/env python3
"""
Siren's Cords - Item Texture Generator
Generates a 128x128 sprite of preserved vocal cord tissue in a glass vial
"""

from PIL import Image, ImageDraw, ImageFont
import random

# Constants
SIZE = 128
OUTPUT = "output.png"

def create_sirens_cords():
    """Generate the Siren's Cords texture with transparent background"""

    # Create RGBA image with transparent background
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Vial dimensions (centered, vertical orientation)
    vial_left = 35
    vial_right = 93
    vial_top = 15
    vial_bottom = 110
    vial_width = vial_right - vial_left

    # Cork/cap at top
    cork_height = 8
    draw.rectangle(
        [vial_left - 2, vial_top, vial_right + 2, vial_top + cork_height],
        fill=(139, 90, 60, 255),  # Brown cork
        outline=(100, 60, 40, 255),
        width=1
    )

    # Glass vial body - outer edge (slightly dark for glass edge)
    draw.rectangle(
        [vial_left, vial_top + cork_height, vial_right, vial_bottom],
        fill=(240, 245, 250, 180),  # Semi-transparent light blue-white glass
        outline=(180, 190, 200, 200),
        width=2
    )

    # Inner contents area (darker to show depth)
    content_left = vial_left + 4
    content_right = vial_right - 4
    content_top = vial_top + cork_height + 4
    content_bottom = vial_bottom - 4

    # Preservation liquid (slightly yellowish, very transparent)
    draw.rectangle(
        [content_left, content_top, content_right, content_bottom],
        fill=(245, 240, 220, 100)  # Pale yellowish liquid
    )

    # Dried vocal cord tissue (organic, irregular shape)
    tissue_centerX = (content_left + content_right) // 2
    tissue_top = content_top + 10
    tissue_bottom = content_bottom - 15

    # Main tissue mass (pinkish-red, dried appearance)
    tissue_color = (180, 90, 100, 255)  # Dried pinkish-red
    tissue_dark = (140, 60, 70, 255)

    # Draw irregular organic shape for tissue
    random.seed(42)  # Reproducible randomness

    # Create vertical tissue strand with organic variation
    points = []
    num_points = 20
    for i in range(num_points):
        y = tissue_top + (tissue_bottom - tissue_top) * i / (num_points - 1)
        # Organic width variation
        base_width = 8 + 4 * abs((i / num_points) - 0.5)  # Thicker in middle
        wobble = random.randint(-3, 3)
        x = tissue_centerX + wobble
        width_var = random.randint(-2, 2)

        # Left and right edges of tissue
        left_x = int(x - base_width/2 + width_var)
        right_x = int(x + base_width/2 + width_var)

        points.append((left_x, int(y)))
        if i == num_points - 1:
            # Close the shape at bottom
            points.append((right_x, int(y)))

    # Add right side points in reverse
    for i in range(num_points - 2, -1, -1):
        y = tissue_top + (tissue_bottom - tissue_top) * i / (num_points - 1)
        base_width = 8 + 4 * abs((i / num_points) - 0.5)
        wobble = random.randint(-3, 3)
        x = tissue_centerX + wobble
        width_var = random.randint(-2, 2)
        right_x = int(x + base_width/2 + width_var)
        points.append((right_x, int(y)))

    # Draw main tissue shape
    if len(points) > 2:
        draw.polygon(points, fill=tissue_color, outline=tissue_dark)

    # Add texture details to tissue (wrinkles, folds)
    for i in range(5):
        y_pos = tissue_top + 15 + i * 10
        x_offset = random.randint(-2, 2)
        draw.line(
            [tissue_centerX - 6 + x_offset, y_pos,
             tissue_centerX + 6 + x_offset, y_pos],
            fill=tissue_dark,
            width=1
        )

    # Add some darker spots (decay, preservation artifacts)
    for _ in range(8):
        spot_x = tissue_centerX + random.randint(-8, 8)
        spot_y = random.randint(tissue_top + 10, tissue_bottom - 10)
        spot_size = random.randint(1, 3)
        draw.ellipse(
            [spot_x - spot_size, spot_y - spot_size,
             spot_x + spot_size, spot_y + spot_size],
            fill=(120, 50, 60, 200)
        )

    # Glass highlights (to show transparency/glassiness)
    highlight_color = (255, 255, 255, 150)
    draw.line(
        [vial_left + 3, vial_top + cork_height + 5,
         vial_left + 3, vial_bottom - 10],
        fill=highlight_color,
        width=2
    )

    # Small highlight on right edge
    draw.line(
        [vial_right - 2, vial_top + cork_height + 20,
         vial_right - 2, vial_top + cork_height + 45],
        fill=highlight_color,
        width=1
    )

    # Label on vial (small paper label)
    label_top = vial_bottom - 25
    label_bottom = vial_bottom - 10
    label_left = vial_left + 2
    label_right = vial_right - 2

    # Label background (off-white paper)
    draw.rectangle(
        [label_left, label_top, label_right, label_bottom],
        fill=(245, 240, 230, 220),
        outline=(180, 170, 160, 200)
    )

    # Label text (try to load font, fall back to default)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 6)
    except:
        font = ImageFont.load_default()

    # Draw label text
    label_text = "VOCAL"
    text_bbox = draw.textbbox((0, 0), label_text, font=font)
    text_width = text_bbox[2] - text_bbox[0]
    text_x = label_left + (label_right - label_left - text_width) // 2
    text_y = label_top + 2

    draw.text(
        (text_x, text_y),
        label_text,
        fill=(60, 50, 50, 255),
        font=font
    )

    # Bottom of vial (slightly rounded)
    draw.arc(
        [vial_left, vial_bottom - 10, vial_right, vial_bottom + 5],
        start=0,
        end=180,
        fill=(180, 190, 200, 200),
        width=2
    )

    return img

if __name__ == "__main__":
    print("Generating Siren's Cords texture...")

    img = create_sirens_cords()
    img.save(OUTPUT)

    print(f"✓ Generated {OUTPUT} ({SIZE}x{SIZE} RGBA)")
    print(f"  Item sprite: Glass vial with preserved vocal cord tissue")
