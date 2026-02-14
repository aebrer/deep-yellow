#!/usr/bin/env python3
"""
Barrel Fire Sprite Generator for DEEP YELLOW
Generates a 64x64 PSX-style flaming oil barrel sprite with transparent background.

Context: Ground-level barrel fire on Level -1 (dark snowy forest clearing, tutorial level).
A rusty oil drum with flames licking from the open top. Provides warmth and orange light.
Billboard sprite at Y=1.0, scale 1.5x.

Also generates a 4-frame spritesheet (256x64) with animated flame variations.
"""

from PIL import Image
import random
import math

SIZE = 64

# --- Color Palette (PSX retro, limited) ---

# Barrel body: rusted metal, dark industrial
BARREL = {
    'dark':        (40, 30, 25),      # Darkest rust/shadow
    'rust_dark':   (65, 40, 25),      # Dark rust
    'rust_mid':    (85, 50, 30),      # Mid rust
    'rust_light':  (100, 60, 35),     # Lighter rust spot
    'metal_dark':  (50, 45, 40),      # Dark grey metal
    'metal_mid':   (70, 65, 55),      # Mid grey metal
    'metal_light': (90, 80, 65),      # Light metal highlight
    'band_dark':   (55, 45, 35),      # Barrel band (reinforcing ring) dark
    'band_light':  (80, 70, 55),      # Barrel band highlight
    'rim':         (60, 50, 40),      # Top rim of barrel
    'interior':    (25, 15, 10),      # Dark interior visible at top
}

# Flames: orange/yellow fire matching game's Color(1.0, 0.5, 0.15)
FLAME = {
    'core_white':  (255, 240, 200),   # Hottest core (near-white)
    'core_yellow': (255, 220, 100),   # Bright yellow core
    'mid_orange':  (255, 160, 40),    # Mid-flame orange
    'outer_orange':(255, 120, 25),    # Outer orange (matches game Color(1.0, 0.5, 0.15) ish)
    'tip_red':     (220, 80, 15),     # Flame tips, darker orange-red
    'tip_dark':    (180, 50, 10),     # Outermost wisps
    'ember':       (255, 100, 20),    # Floating ember particles
}

# Glow around the fire (subtle, at base of flames)
GLOW = {
    'hot':   (255, 140, 40, 100),     # Warm glow on barrel rim
    'soft':  (255, 100, 20, 60),      # Softer glow
}


def draw_pixel(pixels, x, y, color, alpha=255):
    """Draw a single pixel with bounds checking."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        if len(color) == 4:
            # RGBA color provided, blend with existing
            r, g, b, a = color
            er, eg, eb, ea = pixels[x, y]
            if ea == 0:
                pixels[x, y] = (r, g, b, a)
            else:
                # Simple alpha blend
                blend = a / 255.0
                nr = int(er * (1 - blend) + r * blend)
                ng = int(eg * (1 - blend) + g * blend)
                nb = int(eb * (1 - blend) + b * blend)
                na = min(255, ea + a)
                pixels[x, y] = (nr, ng, nb, na)
        else:
            pixels[x, y] = color + (alpha,)


def draw_rect(pixels, x1, y1, x2, y2, color, alpha=255):
    """Draw a filled rectangle."""
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            draw_pixel(pixels, x, y, color, alpha)


def draw_barrel(pixels, rng):
    """Draw the rusty oil barrel body (lower ~2/3 of sprite)."""
    # Barrel dimensions - centered, cylindrical shape
    # Barrel occupies roughly y=30 to y=60 (bottom portion)
    barrel_top = 30
    barrel_bottom = 60
    barrel_left = 18
    barrel_right = 45
    barrel_center_x = (barrel_left + barrel_right) // 2
    barrel_width = barrel_right - barrel_left

    # --- Main barrel body ---
    for y in range(barrel_top, barrel_bottom + 1):
        # Slight barrel bulge (wider in the middle) for cylindrical look
        progress = (y - barrel_top) / (barrel_bottom - barrel_top)
        # Parabolic bulge: widest at center
        bulge = 1.0 + 0.08 * (1.0 - (2.0 * progress - 1.0) ** 2)
        half_w = int((barrel_width / 2) * bulge)
        left = barrel_center_x - half_w
        right = barrel_center_x + half_w

        for x in range(left, right + 1):
            # Determine color based on horizontal position (cylindrical shading)
            dx = (x - barrel_center_x) / max(half_w, 1)
            shade = 1.0 - abs(dx) * 0.6  # Darker at edges

            # Base color varies with vertical position for rust variation
            if rng.random() < 0.4:
                base = BARREL['rust_mid']
            elif rng.random() < 0.5:
                base = BARREL['rust_dark']
            else:
                base = BARREL['metal_mid']

            r = int(base[0] * shade)
            g = int(base[1] * shade)
            b = int(base[2] * shade)

            # Edge darkening for silhouette
            if x == left or x == left + 1:
                r, g, b = BARREL['dark']
            elif x == right or x == right - 1:
                r = int(BARREL['dark'][0] * 0.9)
                g = int(BARREL['dark'][1] * 0.9)
                b = int(BARREL['dark'][2] * 0.9)

            draw_pixel(pixels, x, y, (r, g, b))

    # --- Barrel bands (horizontal reinforcing rings) ---
    band_positions = [barrel_top + 3, barrel_top + (barrel_bottom - barrel_top) // 2, barrel_bottom - 4]
    for band_y in band_positions:
        for dy in range(2):  # 2 pixels tall
            y = band_y + dy
            if y > barrel_bottom:
                continue
            progress = (y - barrel_top) / (barrel_bottom - barrel_top)
            bulge = 1.0 + 0.08 * (1.0 - (2.0 * progress - 1.0) ** 2)
            half_w = int((barrel_width / 2) * bulge)
            left = barrel_center_x - half_w
            right = barrel_center_x + half_w

            for x in range(left, right + 1):
                dx = (x - barrel_center_x) / max(half_w, 1)
                if abs(dx) < 0.7:
                    color = BARREL['band_light'] if dy == 0 else BARREL['band_dark']
                else:
                    color = BARREL['band_dark']
                draw_pixel(pixels, x, y, color)

    # --- Top rim / opening ---
    # Elliptical top rim showing the barrel is open
    rim_y = barrel_top
    progress = 0.0
    bulge = 1.0 + 0.08
    half_w = int((barrel_width / 2) * bulge)
    rim_left = barrel_center_x - half_w
    rim_right = barrel_center_x + half_w

    # Rim highlight (top edge)
    for x in range(rim_left, rim_right + 1):
        dx = abs(x - barrel_center_x) / max(half_w, 1)
        if dx < 0.85:
            draw_pixel(pixels, x, rim_y - 1, BARREL['rim'])
            draw_pixel(pixels, x, rim_y, BARREL['metal_light'])

    # Dark interior visible just below rim
    for x in range(rim_left + 2, rim_right - 1):
        dx = abs(x - barrel_center_x) / max(half_w, 1)
        if dx < 0.7:
            draw_pixel(pixels, x, rim_y + 1, BARREL['interior'])

    # --- Rust spots / weathering ---
    for _ in range(25):
        rx = rng.randint(barrel_left - 1, barrel_right + 1)
        ry = rng.randint(barrel_top + 2, barrel_bottom - 1)
        if pixels[rx, ry][3] > 0:  # Only on existing barrel pixels
            rust_colors = [BARREL['rust_light'], BARREL['rust_dark'], BARREL['dark']]
            color = rng.choice(rust_colors)
            draw_pixel(pixels, rx, ry, color)
            # Occasionally make a 2x2 rust patch
            if rng.random() < 0.3:
                draw_pixel(pixels, rx + 1, ry, color)
                draw_pixel(pixels, rx, ry + 1, color)

    # --- Bottom edge (barrel sits on ground) ---
    for x in range(barrel_left + 1, barrel_right):
        draw_pixel(pixels, x, barrel_bottom, BARREL['dark'])
        # Slight ground shadow
        draw_pixel(pixels, x, barrel_bottom + 1, BARREL['dark'], alpha=80)

    return barrel_top, barrel_center_x, half_w


def draw_flames(pixels, barrel_top, barrel_center_x, barrel_half_w, rng, frame=0):
    """Draw flames rising from the barrel top.

    Flames occupy roughly the top third of the sprite (y=2 to y=barrel_top).
    Uses a layered approach: dark outer tips -> orange mid -> yellow/white core.
    """
    flame_base_y = barrel_top - 1  # Where flames emerge from
    flame_top_y = 4                 # How high flames reach (leave a few pixels at top)

    # Define flame tongues - each is a vertical column of fire
    # (center_x_offset, width, height_factor, phase_offset)
    flame_tongues = [
        (-6, 4, 0.65, 0.0),    # Left flame
        (-3, 5, 0.85, 0.3),    # Left-center flame
        (0,  6, 1.0,  0.6),    # Center flame (tallest)
        (4,  5, 0.80, 0.9),    # Right-center flame
        (7,  4, 0.60, 0.2),    # Right flame
        (-8, 3, 0.45, 0.5),    # Far left wisp
        (9,  3, 0.50, 0.7),    # Far right wisp
    ]

    # Frame-based variation for animation
    frame_offsets = [0, 1.5, 3.0, 4.5]
    phase = frame_offsets[frame % 4]

    for tongue_cx_off, tongue_w, height_factor, tongue_phase in flame_tongues:
        tongue_cx = barrel_center_x + tongue_cx_off

        # Animated height variation using sine wave
        anim_factor = 0.85 + 0.15 * math.sin(phase + tongue_phase * math.pi * 2)
        effective_height = int((flame_base_y - flame_top_y) * height_factor * anim_factor)
        tongue_top = flame_base_y - effective_height

        # Animated horizontal sway
        sway = int(1.5 * math.sin(phase * 1.3 + tongue_phase * 5.0))
        tongue_cx += sway

        for y in range(tongue_top, flame_base_y + 1):
            # Progress from tip (0) to base (1)
            progress = (y - tongue_top) / max(effective_height, 1)

            # Width tapers toward tip (narrow at top, wide at base)
            taper = progress ** 0.6  # Slightly concave taper
            current_w = max(1, int(tongue_w * taper))

            # Add jagged edges - random pixel removal for energy
            jag = rng.randint(-1, 1) if progress < 0.7 else 0

            for x in range(tongue_cx - current_w // 2 + jag, tongue_cx + current_w // 2 + 1 + jag):
                # Skip some edge pixels for jagged look
                dx = abs(x - tongue_cx)
                if dx == current_w // 2 and rng.random() < 0.4 and progress < 0.5:
                    continue

                # Color based on distance from center and height
                center_dist = dx / max(current_w // 2, 1)

                if progress > 0.85 and center_dist < 0.4:
                    # Base of flame, near center - hottest
                    color = FLAME['core_white']
                elif progress > 0.6 and center_dist < 0.5:
                    # Mid-low, inner - bright yellow
                    color = FLAME['core_yellow']
                elif progress > 0.3 and center_dist < 0.6:
                    # Mid flame - orange
                    color = FLAME['mid_orange']
                elif progress > 0.15:
                    # Upper mid - outer orange
                    color = FLAME['outer_orange']
                elif progress > 0.05:
                    # Near tip - red-orange
                    color = FLAME['tip_red']
                else:
                    # Very tip - dark tips
                    color = FLAME['tip_dark']

                # Edge pixels are darker/more transparent
                alpha = 255
                if center_dist > 0.7:
                    color = FLAME['tip_red'] if progress > 0.3 else FLAME['tip_dark']
                    alpha = 200

                # Tip transparency fade
                if progress < 0.15:
                    alpha = int(alpha * (progress / 0.15))
                    alpha = max(40, alpha)

                draw_pixel(pixels, x, y, color, alpha)

    # --- Ember / spark particles ---
    num_embers = 5 + frame * 2  # Vary per frame
    for _ in range(num_embers):
        ex = barrel_center_x + rng.randint(-10, 10)
        ey = rng.randint(flame_top_y - 3, flame_base_y - 8)
        # Embers are single bright pixels
        if rng.random() < 0.6:
            ember_color = FLAME['ember']
        else:
            ember_color = FLAME['core_yellow']
        alpha = rng.randint(120, 255)
        draw_pixel(pixels, ex, ey, ember_color, alpha)

    # --- Warm glow on barrel rim ---
    glow_y_start = barrel_top - 2
    glow_y_end = barrel_top + 3
    for y in range(glow_y_start, glow_y_end + 1):
        dist_from_rim = abs(y - barrel_top)
        glow_alpha = max(0, 80 - dist_from_rim * 25)
        for x in range(barrel_center_x - barrel_half_w, barrel_center_x + barrel_half_w + 1):
            dx = abs(x - barrel_center_x) / max(barrel_half_w, 1)
            if dx < 0.8:
                pixel_alpha = int(glow_alpha * (1.0 - dx))
                if pixel_alpha > 10:
                    draw_pixel(pixels, x, y, (255, 140, 40, pixel_alpha))


def add_grain(pixels, rng, intensity=8):
    """Add subtle PSX-style noise to non-transparent pixels."""
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a > 0:
                noise = rng.randint(-intensity, intensity)
                r = max(0, min(255, r + noise))
                g = max(0, min(255, g + noise))
                b = max(0, min(255, b + noise))
                pixels[x, y] = (r, g, b, a)


def generate_frame(seed, frame=0):
    """Generate a single 64x64 barrel fire frame."""
    rng = random.Random(seed + frame * 1000)

    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    pixels = img.load()

    # Draw barrel body (consistent across frames - same seed base)
    barrel_rng = random.Random(seed)  # Same barrel every frame
    barrel_top, barrel_cx, barrel_hw = draw_barrel(pixels, barrel_rng)

    # Draw flames (vary per frame for animation)
    draw_flames(pixels, barrel_top, barrel_cx, barrel_hw, rng, frame=frame)

    # PSX grain
    add_grain(pixels, rng, intensity=6)

    return img


def main():
    print("Generating Barrel Fire sprite (64x64, PSX-style)...")
    print("- Rusty oil drum with flames from open top")
    print("- Dark metal barrel body, orange/yellow flames")
    print("- Transparent background, RGBA")

    SEED = 42

    # --- Single frame (priority output) ---
    single = generate_frame(SEED, frame=0)
    single.save('output.png', 'PNG')
    print(f"  Generated: output.png ({single.size[0]}x{single.size[1]}, {single.mode})")

    # --- 4-frame spritesheet (256x64, bonus) ---
    sheet = Image.new('RGBA', (SIZE * 4, SIZE), (0, 0, 0, 0))
    for i in range(4):
        frame = generate_frame(SEED, frame=i)
        sheet.paste(frame, (i * SIZE, 0))
    sheet.save('output_spritesheet.png', 'PNG')
    print(f"  Generated: output_spritesheet.png ({sheet.size[0]}x{sheet.size[1]}, {sheet.mode})")

    # --- Copy to game assets ---
    import shutil
    dest = '../../../assets/textures/entities/barrel_fire.png'
    shutil.copy('output.png', dest)
    print(f"  Copied to: {dest}")

    print("Done!")


if __name__ == '__main__':
    main()
