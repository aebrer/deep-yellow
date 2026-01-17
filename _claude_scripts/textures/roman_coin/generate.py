"""
Roman Coin Texture Generator
Creates a 64x64 PSX-style ancient bronze coin with verdigris patina.
"""

from PIL import Image, ImageDraw
import numpy as np
import random

# Set seed for reproducibility
random.seed(42)
np.random.seed(42)

SIZE = 64
CENTER = SIZE // 2

# PSX-style color palette
BRONZE_DARK = (101, 67, 33)      # Deep bronze
BRONZE_MID = (138, 91, 51)       # Medium bronze
BRONZE_LIGHT = (184, 134, 89)    # Light bronze/copper
BRONZE_HIGHLIGHT = (205, 164, 115)  # Golden highlight
VERDIGRIS_DARK = (52, 78, 65)    # Dark green patina
VERDIGRIS_LIGHT = (82, 121, 96)  # Light green patina
SHADOW = (45, 30, 15)            # Deep shadow in recesses
BACKGROUND = (0, 0, 0, 0)        # Transparent

def create_base_coin():
    """Create base circular coin shape with gradient"""
    img = Image.new('RGBA', (SIZE, SIZE), BACKGROUND)
    img_array = np.array(img)

    # Draw circular coin
    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - CENTER
            dy = y - CENTER
            dist = np.sqrt(dx**2 + dy**2)

            # Coin radius slightly smaller than half to leave edge padding
            coin_radius = 28

            if dist <= coin_radius:
                # Radial gradient for depth
                gradient = 1.0 - (dist / coin_radius) * 0.3

                # Base bronze color with gradient
                if dist < coin_radius - 2:
                    # Interior of coin - bronze
                    base_color = BRONZE_MID
                    r = int(base_color[0] * gradient)
                    g = int(base_color[1] * gradient)
                    b = int(base_color[2] * gradient)
                    img_array[y, x] = [r, g, b, 255]
                else:
                    # Edge of coin - darker
                    img_array[y, x] = [*BRONZE_DARK, 255]

    return Image.fromarray(img_array)

def add_emperor_profile(img):
    """Add simplified emperor profile relief"""
    img_array = np.array(img)
    draw = ImageDraw.Draw(img)

    # Profile facing right - simplified geometric shapes
    # Head circle (offset to left side of coin)
    head_x = CENTER - 6
    head_y = CENTER - 2
    head_radius = 10

    # Add relief by brightening areas
    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - head_x
            dy = y - head_y
            dist = np.sqrt(dx**2 + dy**2)

            # Head area - raised relief
            if dist <= head_radius:
                if img_array[y, x, 3] > 0:  # Only on coin area
                    # Brighten for raised relief
                    img_array[y, x, 0] = min(255, int(img_array[y, x, 0] * 1.15))
                    img_array[y, x, 1] = min(255, int(img_array[y, x, 1] * 1.15))
                    img_array[y, x, 2] = min(255, int(img_array[y, x, 2] * 1.15))

    # Nose (triangular protrusion)
    nose_points = [
        (head_x + 8, head_y - 1),
        (head_x + 11, head_y + 2),
        (head_x + 8, head_y + 3)
    ]
    for px, py in nose_points:
        if 0 <= px < SIZE and 0 <= py < SIZE and img_array[py, px, 3] > 0:
            img_array[py, px, 0] = min(255, int(img_array[py, px, 0] * 1.2))
            img_array[py, px, 1] = min(255, int(img_array[py, px, 1] * 1.2))
            img_array[py, px, 2] = min(255, int(img_array[py, px, 2] * 1.2))

    # Laurel wreath outline (back of head)
    wreath_x = head_x - 7
    wreath_y = head_y
    wreath_radius = 8

    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - wreath_x
            dy = y - wreath_y
            dist = np.sqrt(dx**2 + dy**2)

            # Ring pattern for wreath
            if 6 <= dist <= 8 and img_array[y, x, 3] > 0:
                img_array[y, x, 0] = min(255, int(img_array[y, x, 0] * 1.1))
                img_array[y, x, 1] = min(255, int(img_array[y, x, 1] * 1.1))
                img_array[y, x, 2] = min(255, int(img_array[y, x, 2] * 1.1))

    return Image.fromarray(img_array)

def add_weathering(img):
    """Add wear, scratches, and worn areas"""
    img_array = np.array(img)

    # Random wear spots - darken areas
    for _ in range(25):
        wx = random.randint(CENTER - 20, CENTER + 20)
        wy = random.randint(CENTER - 20, CENTER + 20)
        wear_radius = random.randint(2, 5)

        for y in range(max(0, wy - wear_radius), min(SIZE, wy + wear_radius)):
            for x in range(max(0, wx - wear_radius), min(SIZE, wx + wear_radius)):
                if img_array[y, x, 3] > 0:  # Only on coin
                    dist = np.sqrt((x - wx)**2 + (y - wy)**2)
                    if dist <= wear_radius:
                        # Darken for wear
                        factor = 0.85
                        img_array[y, x, 0] = int(img_array[y, x, 0] * factor)
                        img_array[y, x, 1] = int(img_array[y, x, 1] * factor)
                        img_array[y, x, 2] = int(img_array[y, x, 2] * factor)

    # Scratches - thin dark lines
    for _ in range(8):
        sx = random.randint(CENTER - 25, CENTER + 25)
        sy = random.randint(CENTER - 25, CENTER + 25)
        length = random.randint(5, 12)
        angle = random.random() * 2 * np.pi

        for i in range(length):
            px = int(sx + i * np.cos(angle))
            py = int(sy + i * np.sin(angle))

            if 0 <= px < SIZE and 0 <= py < SIZE and img_array[py, px, 3] > 0:
                img_array[py, px] = [*SHADOW, 255]

    return Image.fromarray(img_array)

def add_verdigris(img):
    """Add green patina spots typical of aged bronze"""
    img_array = np.array(img)

    # Larger verdigris patches
    for _ in range(6):
        vx = random.randint(CENTER - 22, CENTER + 22)
        vy = random.randint(CENTER - 22, CENTER + 22)
        v_radius = random.randint(3, 7)

        for y in range(max(0, vy - v_radius), min(SIZE, vy + v_radius)):
            for x in range(max(0, vx - v_radius), min(SIZE, vx + v_radius)):
                if img_array[y, x, 3] > 0:  # Only on coin
                    dist = np.sqrt((x - vx)**2 + (y - vy)**2)
                    if dist <= v_radius:
                        # Blend verdigris with existing color
                        blend = 1.0 - (dist / v_radius) * 0.5
                        use_dark = random.random() < 0.5
                        v_color = VERDIGRIS_DARK if use_dark else VERDIGRIS_LIGHT

                        img_array[y, x, 0] = int(img_array[y, x, 0] * (1 - blend) + v_color[0] * blend)
                        img_array[y, x, 1] = int(img_array[y, x, 1] * (1 - blend) + v_color[1] * blend)
                        img_array[y, x, 2] = int(img_array[y, x, 2] * (1 - blend) + v_color[2] * blend)

    # Smaller verdigris spots
    for _ in range(15):
        vx = random.randint(CENTER - 25, CENTER + 25)
        vy = random.randint(CENTER - 25, CENTER + 25)

        if 0 <= vx < SIZE and 0 <= vy < SIZE and img_array[vy, vx, 3] > 0:
            v_color = VERDIGRIS_DARK if random.random() < 0.6 else VERDIGRIS_LIGHT
            img_array[vy, vx] = [*v_color, 255]

    return Image.fromarray(img_array)

def add_psx_grain(img):
    """Add PSX-style grain/noise for authentic retro look"""
    img_array = np.array(img, dtype=np.int16)  # Use int16 to avoid overflow

    # Subtle noise across entire coin
    for y in range(SIZE):
        for x in range(SIZE):
            if img_array[y, x, 3] > 0:  # Only on coin
                noise = random.randint(-8, 8)
                img_array[y, x, 0] = np.clip(img_array[y, x, 0] + noise, 0, 255)
                img_array[y, x, 1] = np.clip(img_array[y, x, 1] + noise, 0, 255)
                img_array[y, x, 2] = np.clip(img_array[y, x, 2] + noise, 0, 255)

    return Image.fromarray(img_array.astype(np.uint8))

def add_highlights(img):
    """Add golden highlights on raised areas"""
    img_array = np.array(img)

    # Highlights on upper-left (simulating light source)
    for _ in range(12):
        hx = random.randint(CENTER - 15, CENTER + 5)
        hy = random.randint(CENTER - 15, CENTER + 5)
        h_radius = random.randint(1, 3)

        for y in range(max(0, hy - h_radius), min(SIZE, hy + h_radius)):
            for x in range(max(0, hx - h_radius), min(SIZE, hx + h_radius)):
                if img_array[y, x, 3] > 0:
                    dist = np.sqrt((x - hx)**2 + (y - hy)**2)
                    if dist <= h_radius:
                        # Only add highlights to bronze areas (not verdigris)
                        r, g, b = img_array[y, x, :3]
                        # Check if it's bronze-ish (more red/orange than green)
                        if r > g and (r + b) > (g * 1.5):
                            blend = 0.3 * (1.0 - dist / h_radius)
                            img_array[y, x, 0] = int(r * (1 - blend) + BRONZE_HIGHLIGHT[0] * blend)
                            img_array[y, x, 1] = int(g * (1 - blend) + BRONZE_HIGHLIGHT[1] * blend)
                            img_array[y, x, 2] = int(b * (1 - blend) + BRONZE_HIGHLIGHT[2] * blend)

    return Image.fromarray(img_array)

def main():
    """Generate complete Roman coin texture"""
    print("Generating Roman coin texture...")

    # Build texture in layers
    img = create_base_coin()
    print("  ✓ Base coin shape created")

    img = add_emperor_profile(img)
    print("  ✓ Emperor profile relief added")

    img = add_weathering(img)
    print("  ✓ Weathering applied")

    img = add_verdigris(img)
    print("  ✓ Verdigris patina added")

    img = add_highlights(img)
    print("  ✓ Highlights added")

    img = add_psx_grain(img)
    print("  ✓ PSX grain applied")

    # Save output
    output_path = 'output.png'
    img.save(output_path)
    print(f"\n✓ Roman coin texture saved to {output_path}")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print(f"  Style: PSX-era ancient bronze with verdigris")

if __name__ == '__main__':
    main()
