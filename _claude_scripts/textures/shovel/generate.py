"""
Shovel Item Texture Generator
Generates a 128x128 pixel-art style shovel for DEEP YELLOW.
"""

from PIL import Image, ImageDraw
import random

SIZE = 128

# Color palette - earthy, worn tones
WOOD_DARK = (101, 67, 33)      # Dark wood
WOOD_MED = (139, 90, 43)        # Medium wood
WOOD_LIGHT = (160, 110, 60)     # Light wood highlight
METAL_DARK = (80, 70, 65)       # Dark metal/rust
METAL_MED = (110, 100, 90)      # Medium metal
METAL_RUST = (160, 90, 50)      # Rust orange
METAL_HIGHLIGHT = (140, 130, 120)  # Metal highlight
SHADOW = (40, 30, 25)           # Shadow color

def create_shovel():
    """Generate the shovel texture."""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Overall composition:
    # - Shovel angled diagonally (lower-left to upper-right)
    # - Wooden handle with grain texture
    # - Metal blade with rust spots
    # - Shadow to add depth

    # Define shovel geometry (diagonal placement)
    blade_bottom_x = 35
    blade_bottom_y = 100
    blade_top_x = 55
    blade_top_y = 70
    blade_width = 30

    handle_start_x = 55
    handle_start_y = 70
    handle_end_x = 95
    handle_end_y = 25
    handle_width = 8

    # 1. Draw shadow first (offset down-right)
    shadow_offset = 3
    # Shadow for blade
    shadow_blade_points = [
        (blade_bottom_x + shadow_offset - blade_width//2, blade_bottom_y + shadow_offset),
        (blade_bottom_x + shadow_offset + blade_width//2, blade_bottom_y + shadow_offset),
        (blade_top_x + shadow_offset + blade_width//3, blade_top_y + shadow_offset),
        (blade_top_x + shadow_offset - blade_width//3, blade_top_y + shadow_offset),
    ]
    draw.polygon(shadow_blade_points, fill=(*SHADOW, 80))

    # Shadow for handle
    draw.line(
        [(handle_start_x + shadow_offset, handle_start_y + shadow_offset),
         (handle_end_x + shadow_offset, handle_end_y + shadow_offset)],
        fill=(*SHADOW, 80),
        width=handle_width
    )

    # 2. Draw metal blade
    blade_points = [
        (blade_bottom_x - blade_width//2, blade_bottom_y),  # Bottom left
        (blade_bottom_x + blade_width//2, blade_bottom_y),  # Bottom right
        (blade_top_x + blade_width//3, blade_top_y),        # Top right
        (blade_top_x - blade_width//3, blade_top_y),        # Top left
    ]

    # Fill blade with base metal color
    draw.polygon(blade_points, fill=METAL_MED)

    # Add rust patches on blade (random spots)
    random.seed(42)  # Consistent rust pattern
    for _ in range(15):
        rust_x = random.randint(blade_bottom_x - blade_width//2, blade_bottom_x + blade_width//2)
        rust_y = random.randint(blade_top_y, blade_bottom_y)
        rust_size = random.randint(2, 5)
        draw.ellipse(
            [rust_x - rust_size, rust_y - rust_size, rust_x + rust_size, rust_y + rust_size],
            fill=METAL_RUST
        )

    # Add dark rust along edges
    for _ in range(8):
        edge_x = random.randint(blade_bottom_x - blade_width//2, blade_bottom_x - blade_width//2 + 4)
        edge_y = random.randint(blade_top_y, blade_bottom_y)
        draw.ellipse(
            [edge_x - 2, edge_y - 2, edge_x + 2, edge_y + 2],
            fill=METAL_DARK
        )

    # Highlight on blade (top edge)
    draw.line(
        [(blade_top_x - blade_width//3 + 2, blade_top_y + 2),
         (blade_top_x + blade_width//3 - 2, blade_top_y + 2)],
        fill=METAL_HIGHLIGHT,
        width=2
    )

    # 3. Draw wooden handle
    # Handle outline/shadow
    draw.line(
        [(handle_start_x - 1, handle_start_y),
         (handle_end_x - 1, handle_end_y)],
        fill=WOOD_DARK,
        width=handle_width + 2
    )

    # Handle base
    draw.line(
        [(handle_start_x, handle_start_y),
         (handle_end_x, handle_end_y)],
        fill=WOOD_MED,
        width=handle_width
    )

    # Wood grain lines (subtle)
    grain_segments = 6
    for i in range(grain_segments):
        t = i / grain_segments
        grain_x = int(handle_start_x + (handle_end_x - handle_start_x) * t)
        grain_y = int(handle_start_y + (handle_end_y - handle_start_y) * t)

        # Perpendicular offset for grain
        dx = handle_end_y - handle_start_y
        dy = -(handle_end_x - handle_start_x)
        length = (dx**2 + dy**2)**0.5
        dx = int(dx / length * 2)
        dy = int(dy / length * 2)

        if i % 2 == 0:
            draw.line(
                [(grain_x + dx, grain_y + dy), (grain_x - dx, grain_y - dy)],
                fill=WOOD_DARK,
                width=1
            )

    # Highlight on handle
    highlight_offset_x = 2
    highlight_offset_y = -1
    draw.line(
        [(handle_start_x + highlight_offset_x, handle_start_y + highlight_offset_y),
         (handle_end_x + highlight_offset_x, handle_end_y + highlight_offset_y)],
        fill=WOOD_LIGHT,
        width=2
    )

    # 4. Add wear marks on handle
    random.seed(123)
    for _ in range(8):
        wear_t = random.uniform(0.2, 0.9)
        wear_x = int(handle_start_x + (handle_end_x - handle_start_x) * wear_t)
        wear_y = int(handle_start_y + (handle_end_y - handle_start_y) * wear_t)
        wear_size = random.randint(1, 3)
        draw.ellipse(
            [wear_x - wear_size, wear_y - wear_size, wear_x + wear_size, wear_y + wear_size],
            fill=WOOD_DARK
        )

    # 5. Add handle grip end (rounded cap)
    grip_radius = handle_width // 2 + 1
    draw.ellipse(
        [handle_end_x - grip_radius, handle_end_y - grip_radius,
         handle_end_x + grip_radius, handle_end_y + grip_radius],
        fill=WOOD_DARK,
        outline=WOOD_LIGHT
    )

    return img


if __name__ == "__main__":
    print("Generating shovel texture...")
    shovel_img = create_shovel()

    output_path = "output.png"
    shovel_img.save(output_path, 'PNG')
    print(f"✓ Shovel texture saved to {output_path}")
    print(f"  Size: {SIZE}x{SIZE}px")
    print(f"  Style: Pixel-art, worn garden shovel")
    print(f"  Colors: Earth tones with rust and wood grain")
