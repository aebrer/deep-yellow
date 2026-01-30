#!/usr/bin/env python3
"""
DEBUG_ITEM sprite generator for DEEP YELLOW
Generates a 64x64 PSX-style sprite of a malfunctioning anomaly containment device
"""
from PIL import Image, ImageDraw
import random
import math

SIZE = 64

# Industrial containment device palette
METAL_DARK = (40, 45, 50)          # Dark gunmetal
METAL_MID = (60, 65, 70)           # Mid grey metal
METAL_LIGHT = (90, 95, 100)        # Light metal highlight
METAL_EDGE = (120, 125, 130)       # Edge highlight

# Warning/status lights (malfunctioning)
WARNING_RED = (220, 40, 30)        # Danger red
WARNING_ORANGE = (255, 120, 20)    # Alert orange
HAZARD_YELLOW = (255, 200, 30)     # Caution yellow

# Unstable energy containment
ENERGY_CYAN = (60, 220, 255)       # Unstable cyan energy
ENERGY_PURPLE = (180, 60, 255)     # Chaotic purple energy
ENERGY_SPARK = (255, 255, 255)     # White sparks

# Panel details
PANEL_DARK = (25, 28, 30)          # Dark panel sections
VENT_SLOT = (15, 18, 20)           # Vent/slot darkness

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

def draw_device():
    """Generate the malfunctioning containment device sprite"""
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center position
    center_x = SIZE // 2
    center_y = SIZE // 2

    # Main device body (cylindrical/rectangular containment unit)
    device_width = 32
    device_height = 40
    device_top = center_y - device_height // 2
    device_bottom = center_y + device_height // 2
    device_left = center_x - device_width // 2
    device_right = center_x + device_width // 2

    # Draw main body (dark metal rectangle)
    draw.rectangle(
        [device_left, device_top, device_right, device_bottom],
        fill=METAL_DARK + (255,)
    )

    # Add metal panel sections (horizontal divisions)
    panel_height = device_height // 3
    for i in range(1, 3):
        y_pos = device_top + i * panel_height
        draw.line(
            [(device_left, y_pos), (device_right, y_pos)],
            fill=PANEL_DARK + (255,), width=2
        )

    # Add vertical panel line (asymmetry = malfunction)
    vert_line_x = center_x - 6
    draw.line(
        [(vert_line_x, device_top), (vert_line_x, device_bottom)],
        fill=PANEL_DARK + (255,), width=2
    )

    # Add vent slots (top panel)
    vent_y_start = device_top + 4
    for i in range(4):
        vent_y = vent_y_start + i * 3
        draw.line(
            [(device_left + 4, vent_y), (device_right - 4, vent_y)],
            fill=VENT_SLOT + (255,), width=1
        )

    # Central energy containment chamber (glowing unstable core)
    chamber_size = 14
    chamber_bbox = [
        center_x - chamber_size // 2,
        center_y - chamber_size // 2 + 2,
        center_x + chamber_size // 2,
        center_y + chamber_size // 2 + 2
    ]

    # Draw chamber outer ring (dark)
    draw.ellipse(chamber_bbox, fill=PANEL_DARK + (255,))

    # Unstable energy glow (pulsing colors - cyan/purple mix)
    energy_size = 10
    energy_bbox = [
        center_x - energy_size // 2,
        center_y - energy_size // 2 + 2,
        center_x + energy_size // 2,
        center_y + energy_size // 2 + 2
    ]
    # Random energy color (chaotic!)
    energy_color = random.choice([ENERGY_CYAN, ENERGY_PURPLE])
    draw.ellipse(energy_bbox, fill=energy_color + (200,))

    # Bright core spark
    spark_size = 4
    spark_bbox = [
        center_x - spark_size // 2,
        center_y - spark_size // 2 + 2,
        center_x + spark_size // 2,
        center_y + spark_size // 2 + 2
    ]
    draw.ellipse(spark_bbox, fill=ENERGY_SPARK + (255,))

    # Add erratic energy arcs emanating from core
    num_arcs = random.randint(3, 5)
    for _ in range(num_arcs):
        arc_angle = random.uniform(0, 2 * math.pi)
        arc_length = random.randint(8, 16)
        arc_end_x = center_x + math.cos(arc_angle) * arc_length
        arc_end_y = center_y + 2 + math.sin(arc_angle) * arc_length
        arc_color = random.choice([ENERGY_CYAN, ENERGY_PURPLE])
        draw.line(
            [(center_x, center_y + 2), (arc_end_x, arc_end_y)],
            fill=arc_color + (180,), width=1
        )

    # Warning lights (top section - malfunctioning/flickering)
    light_positions = [
        (device_left + 8, device_top + panel_height // 2),
        (device_right - 8, device_top + panel_height // 2)
    ]

    for light_x, light_y in light_positions:
        # Random light state (on/off/different colors = malfunction)
        if random.random() > 0.3:  # 70% chance of being lit
            light_color = random.choice([WARNING_RED, WARNING_ORANGE, HAZARD_YELLOW])
            draw.ellipse(
                [light_x - 3, light_y - 3, light_x + 3, light_y + 3],
                fill=light_color + (255,)
            )
            # Bright center
            draw.ellipse(
                [light_x - 1, light_y - 1, light_x + 1, light_y + 1],
                fill=ENERGY_SPARK + (255,)
            )

    # Bottom panel indicator lights (smaller, more of them)
    bottom_light_y = device_bottom - 6
    for i in range(5):
        light_x = device_left + 6 + i * 5
        if random.random() > 0.4:  # Random on/off
            indicator_color = random.choice([WARNING_RED, WARNING_ORANGE])
            draw.rectangle(
                [light_x, bottom_light_y, light_x + 2, bottom_light_y + 2],
                fill=indicator_color + (255,)
            )

    # Metal highlights (edges and bevels)
    # Left edge highlight
    draw.line(
        [(device_left, device_top), (device_left, device_bottom)],
        fill=METAL_LIGHT + (200,), width=1
    )
    # Top edge highlight
    draw.line(
        [(device_left, device_top), (device_right, device_top)],
        fill=METAL_LIGHT + (200,), width=1
    )

    # Right edge (darker - shadow)
    draw.line(
        [(device_right, device_top), (device_right, device_bottom)],
        fill=PANEL_DARK + (180,), width=1
    )
    # Bottom edge (darker)
    draw.line(
        [(device_left, device_bottom), (device_right, device_bottom)],
        fill=PANEL_DARK + (180,), width=1
    )

    # Add some asymmetry - damage/malfunction indicators
    # Damaged corner (top right)
    damage_points = [
        (device_right - 2, device_top + 2),
        (device_right, device_top),
        (device_right, device_top + 4)
    ]
    draw.polygon(damage_points, fill=PANEL_DARK + (255,))

    # Spark from damaged area (random)
    if random.random() > 0.5:
        spark_x = device_right - 1
        spark_y = device_top + 3
        draw.ellipse(
            [spark_x - 2, spark_y - 2, spark_x + 2, spark_y + 2],
            fill=HAZARD_YELLOW + (220,)
        )

    # Containment tubes/pipes (small cylinders on sides)
    # Left tube
    tube_width = 4
    tube_height = 12
    tube_left_x = device_left - 5
    tube_y = center_y - tube_height // 2 + 6
    draw.rectangle(
        [tube_left_x, tube_y, tube_left_x + tube_width, tube_y + tube_height],
        fill=METAL_MID + (255,)
    )
    # Tube highlight
    draw.line(
        [(tube_left_x, tube_y), (tube_left_x, tube_y + tube_height)],
        fill=METAL_EDGE + (200,), width=1
    )

    # Right tube (asymmetrical position)
    tube_right_x = device_right + 1
    tube_y2 = center_y - tube_height // 2 - 4
    draw.rectangle(
        [tube_right_x, tube_y2, tube_right_x + tube_width, tube_y2 + tube_height],
        fill=METAL_MID + (255,)
    )
    draw.line(
        [(tube_right_x, tube_y2), (tube_right_x, tube_y2 + tube_height)],
        fill=METAL_EDGE + (200,), width=1
    )

    # Apply PSX-style grain
    add_grain(img, intensity=14)

    return img

def main():
    print("Generating DEBUG_ITEM sprite (64x64, PSX-style)...")
    print("- Malfunctioning anomaly containment device")
    print("- Industrial/SCP aesthetic with unstable energy")

    img = draw_device()
    img.save('output.png', 'PNG')

    print("✓ Generated: output.png")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print("  Format: RGBA (transparent background)")

if __name__ == '__main__':
    main()
