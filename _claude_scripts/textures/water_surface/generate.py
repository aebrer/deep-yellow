#!/usr/bin/env python3
"""
Generate a tileable PSX-style pool water surface texture.
Calm chlorinated water with subtle ripple caustics.
128x128 pixels, seamless via modulo wrapping.
"""

import math
from PIL import Image

# Texture dimensions (must be power of two for clean modulo wrapping)
SIZE = 128

# Base pool water colors (chlorinated blue-green)
BASE_R = 60
BASE_G = 150
BASE_B = 160

# Caustic highlight color (lighter blue-green)
HIGH_R = 120
HIGH_G = 200
HIGH_B = 190

# Shadow/deep color (darker blue)
SHADOW_R = 30
SHADOW_G = 90
SHADOW_B = 120


def fractal_noise(x, y, octaves=4):
    """
    Simple fractal value noise using sine waves.
    All coordinates wrapped with modulo for seamless tiling.
    """
    value = 0.0
    amplitude = 1.0
    frequency = 1.0
    max_value = 0.0

    for i in range(octaves):
        # Use prime-like multipliers to reduce repeating patterns
        fx = frequency * 0.05
        fy = frequency * 0.05

        # Multiple overlapping sine waves for organic look
        v1 = math.sin((x * fx + i * 13.7) + math.cos(y * fy + i * 7.3) * 2.0)
        v2 = math.sin((y * fy + i * 23.1) + math.cos(x * fx + i * 17.9) * 1.5)
        v3 = math.sin((x * fx * 1.7 + y * fy * 0.8) + i * 31.4)

        value += (v1 + v2 + v3) * amplitude
        max_value += 3.0 * amplitude
        amplitude *= 0.5
        frequency *= 2.0

    # Normalize to 0..1
    return (value / max_value + 1.0) * 0.5


def caustic_pattern(x, y):
    """
    Subtle caustic-like light pattern on pool floor.
    Uses wrapped coordinates for seamless tiling.
    """
    scale1 = 0.12
    scale2 = 0.08
    scale3 = 0.18

    # Multiple overlapping wave patterns
    c1 = math.sin(x * scale1) * math.cos(y * scale1 * 1.3)
    c2 = math.sin(y * scale2 + math.cos(x * scale2 * 0.7) * 1.2)
    c3 = math.sin((x + y) * scale3 * 0.8) * math.cos((x - y) * scale3 * 0.6)

    # Sharpen the pattern slightly for caustic look
    combined = (c1 + c2 * 0.7 + c3 * 0.5) / 2.2
    # Add subtle contrast
    combined = combined * combined * math.copysign(1.0, combined)
    return (combined + 1.0) * 0.5


def generate_texture():
    img = Image.new("RGB", (SIZE, SIZE))
    pixels = img.load()

    for py in range(SIZE):
        for px in range(SIZE):
            # Base water variation (very subtle)
            base_noise = fractal_noise(px, py, octaves=3)

            # Caustic highlights (subtle)
            caustic = caustic_pattern(px, py)

            # Large slow ripple (very subtle depth variation)
            ripple = math.sin(px * 0.05 + math.cos(py * 0.04) * 2.0)
            ripple = (ripple + 1.0) * 0.5

            # Combine layers
            # Base water color dominates
            t = base_noise * 0.3 + ripple * 0.2

            # Mix base -> shadow for depth
            r = BASE_R + (SHADOW_R - BASE_R) * t
            g = BASE_G + (SHADOW_G - BASE_G) * t
            b = BASE_B + (SHADOW_B - BASE_B) * t

            # Add subtle caustic highlights (only in bright areas)
            caustic_strength = max(0.0, (caustic - 0.6)) * 0.8
            r += (HIGH_R - r) * caustic_strength
            g += (HIGH_G - g) * caustic_strength
            b += (HIGH_B - b) * caustic_strength

            # PSX-style color quantization (reduce to ~5 bits per channel)
            # This gives the characteristic color-banded look
            r = int(r / 8) * 8
            g = int(g / 8) * 8
            b = int(b / 8) * 8

            # Clamp
            r = max(0, min(255, r))
            g = max(0, min(255, g))
            b = max(0, min(255, b))

            pixels[px, py] = (r, g, b)

    return img


def main():
    print("Generating pool water surface texture...")
    texture = generate_texture()

    output_path = "/home/drew/projects/deep_yellow/_claude_scripts/textures/water_surface/output.png"
    texture.save(output_path)
    print(f"Saved to: {output_path}")
    print(f"Size: {texture.size}")


if __name__ == "__main__":
    main()
