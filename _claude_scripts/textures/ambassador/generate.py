#!/usr/bin/env python3
"""
Generate a PSX-style entity sprite texture for the "Ambassador" entity.
Tall, slender, elusive silhouette with pale white-blue ethereal appearance.
"""

from PIL import Image, ImageDraw

# Canvas settings
SIZE = 64
BG = (0, 0, 0, 0)  # Transparent

# PSX-style limited palette (pale white-blue ethereal)
COLORS = {
    "core": (220, 235, 255, 255),      # Bright white-blue core
    "mid": (180, 210, 240, 255),       # Mid ethereal blue
    "shadow": (120, 160, 200, 255),    # Deeper blue shadow
    "edge": (80, 120, 160, 255),       # Dark edge definition
    "fade1": (200, 225, 250, 180),     # Semi-transparent fade
    "fade2": (160, 200, 230, 100),     # More transparent fade
    "fade3": (140, 180, 220, 60),      # Ghostly outer fade
    "fade4": (120, 160, 200, 30),      # Very faint outer glow
}

def draw_pixel(img, x, y, color):
    """Draw a single pixel if in bounds."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        img.putpixel((x, y), color)

def draw_rect(img, x1, y1, x2, y2, color):
    """Draw a filled rectangle."""
    for y in range(max(0, y1), min(SIZE, y2 + 1)):
        for x in range(max(0, x1), min(SIZE, x2 + 1)):
            img.putpixel((x, y), color)

def draw_line(img, x1, y1, x2, y2, color):
    """Bresenham-ish line."""
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx - dy
    while True:
        draw_pixel(img, x1, y1, color)
        if x1 == x2 and y1 == y2:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x1 += sx
        if e2 < dx:
            err += dx
            y1 += sy

def draw_triangle(img, x1, y1, x2, y2, x3, y3, color):
    """Draw a filled triangle (simple scanline)."""
    pts = sorted([(x1, y1), (x2, y2), (x3, y3)], key=lambda p: p[1])
    (x_a, y_a), (x_b, y_b), (x_c, y_c) = pts

    def interpolate(y0, y1, x0, x1, y):
        if y1 == y0:
            return x0
        return x0 + (x1 - x0) * (y - y0) / (y1 - y0)

    for y in range(max(0, int(y_a)), min(SIZE, int(y_c) + 1)):
        x_left = None
        x_right = None
        if y_a <= y <= y_b and y_b != y_a:
            x_left = interpolate(y_a, y_b, x_a, x_b, y)
        elif y_b <= y <= y_c and y_c != y_b:
            x_left = interpolate(y_b, y_c, x_b, x_c, y)
        if y_a <= y <= y_c and y_c != y_a:
            x_right = interpolate(y_a, y_c, x_a, x_c, y)

        if x_left is not None and x_right is not None:
            xl, xr = sorted([x_left, x_right])
            for x in range(max(0, int(xl)), min(SIZE, int(xr) + 1)):
                draw_pixel(img, x, y, color)

def main():
    img = Image.new("RGBA", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)

    cx = SIZE // 2  # 32

    # === BODY: tall slender tapered form ===
    # Main torso - tall triangle/trapezoid
    draw_triangle(img, cx, 4, cx - 6, 28, cx + 6, 28, COLORS["fade4"])
    draw_triangle(img, cx, 6, cx - 5, 26, cx + 5, 26, COLORS["fade3"])
    draw_triangle(img, cx, 8, cx - 4, 24, cx + 4, 24, COLORS["fade2"])
    draw_triangle(img, cx, 10, cx - 3, 22, cx + 3, 22, COLORS["fade1"])
    draw_triangle(img, cx, 12, cx - 2, 20, cx + 2, 20, COLORS["shadow"])
    draw_triangle(img, cx, 14, cx - 1, 18, cx + 1, 18, COLORS["mid"])
    draw_rect(img, cx - 1, 14, cx + 1, 20, COLORS["core"])

    # === HEAD: elongated, featureless ===
    # Head is an elongated oval/rectangle, slightly larger than neck
    draw_rect(img, cx - 4, 2, cx + 4, 10, COLORS["fade4"])
    draw_rect(img, cx - 3, 3, cx + 3, 9, COLORS["fade3"])
    draw_rect(img, cx - 2, 4, cx + 2, 8, COLORS["fade2"])
    draw_rect(img, cx - 1, 5, cx + 1, 7, COLORS["mid"])
    draw_pixel(img, cx, 6, COLORS["core"])

    # === SHOULDERS / CLOAK ===
    # Slight shoulder bumps, then flowing down
    draw_triangle(img, cx - 7, 24, cx - 12, 44, cx - 3, 26, COLORS["fade3"])
    draw_triangle(img, cx + 7, 24, cx + 12, 44, cx + 3, 26, COLORS["fade3"])
    draw_triangle(img, cx - 5, 24, cx - 9, 40, cx - 2, 26, COLORS["fade2"])
    draw_triangle(img, cx + 5, 24, cx + 9, 40, cx + 2, 26, COLORS["fade2"])
    draw_triangle(img, cx - 3, 24, cx - 5, 36, cx - 1, 26, COLORS["fade1"])
    draw_triangle(img, cx + 3, 24, cx + 5, 36, cx + 1, 26, COLORS["fade1"])

    # === LOWER BODY / LEGS (merged, ghostly) ===
    # Flows down to points, no distinct legs
    draw_triangle(img, cx - 2, 36, cx - 8, 58, cx, 40, COLORS["fade3"])
    draw_triangle(img, cx + 2, 36, cx + 8, 58, cx, 40, COLORS["fade3"])
    draw_triangle(img, cx - 1, 38, cx - 5, 54, cx, 42, COLORS["fade2"])
    draw_triangle(img, cx + 1, 38, cx + 5, 54, cx, 42, COLORS["fade2"])
    draw_line(img, cx, 38, cx, 56, COLORS["fade1"])
    draw_line(img, cx - 1, 40, cx - 3, 52, COLORS["fade1"])
    draw_line(img, cx + 1, 40, cx + 3, 52, COLORS["fade1"])

    # === ARMS: long, thin, hanging down ===
    # Left arm
    draw_line(img, cx - 6, 22, cx - 10, 42, COLORS["fade3"])
    draw_line(img, cx - 7, 22, cx - 11, 42, COLORS["fade2"])
    draw_line(img, cx - 8, 22, cx - 12, 42, COLORS["fade3"])
    # Left hand taper
    draw_triangle(img, cx - 10, 42, cx - 13, 50, cx - 8, 44, COLORS["fade2"])
    draw_triangle(img, cx - 11, 42, cx - 14, 48, cx - 9, 44, COLORS["fade3"])

    # Right arm
    draw_line(img, cx + 6, 22, cx + 10, 42, COLORS["fade3"])
    draw_line(img, cx + 7, 22, cx + 11, 42, COLORS["fade2"])
    draw_line(img, cx + 8, 22, cx + 12, 42, COLORS["fade3"])
    # Right hand taper
    draw_triangle(img, cx + 10, 42, cx + 13, 50, cx + 8, 44, COLORS["fade2"])
    draw_triangle(img, cx + 11, 42, cx + 14, 48, cx + 9, 44, COLORS["fade3"])

    # === OUTER GLOW / AURA (subtle ethereal haze) ===
    # Sparse pixels around the figure for ghostly effect
    glow_pixels = [
        (cx - 10, 8, COLORS["fade4"]), (cx + 10, 8, COLORS["fade4"]),
        (cx - 14, 20, COLORS["fade4"]), (cx + 14, 20, COLORS["fade4"]),
        (cx - 16, 34, COLORS["fade4"]), (cx + 16, 34, COLORS["fade4"]),
        (cx - 12, 48, COLORS["fade4"]), (cx + 12, 48, COLORS["fade4"]),
        (cx - 6, 56, COLORS["fade4"]), (cx + 6, 56, COLORS["fade4"]),
        (cx, 0, COLORS["fade4"]), (cx, 62, COLORS["fade4"]),
        (cx - 8, 14, COLORS["fade3"]), (cx + 8, 14, COLORS["fade3"]),
        (cx - 10, 30, COLORS["fade3"]), (cx + 10, 30, COLORS["fade3"]),
        (cx - 8, 46, COLORS["fade3"]), (cx + 8, 46, COLORS["fade3"]),
    ]
    for gx, gy, gc in glow_pixels:
        draw_pixel(img, gx, gy, gc)

    # === FACE AREA: subtle hint of features (elusive, not clear) ===
    # Very faint vertical line suggesting a faceless mask
    draw_line(img, cx, 4, cx, 9, COLORS["mid"])
    draw_pixel(img, cx - 1, 6, COLORS["fade1"])
    draw_pixel(img, cx + 1, 6, COLORS["fade1"])
    draw_pixel(img, cx - 2, 7, COLORS["fade2"])
    draw_pixel(img, cx + 2, 7, COLORS["fade2"])

    # === FINAL CENTER HIGHLIGHT ===
    # Vertical core highlight for ethereal feel
    for y in range(12, 48):
        if y % 3 == 0:
            draw_pixel(img, cx, y, COLORS["core"])
        elif y % 3 == 1:
            draw_pixel(img, cx, y, COLORS["mid"])

    img.save("/home/drew/projects/deep_yellow/_claude_scripts/textures/ambassador/output.png")
    print("Saved output.png (64x64 RGBA)")


if __name__ == "__main__":
    main()
