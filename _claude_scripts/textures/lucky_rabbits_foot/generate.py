#!/usr/bin/env python3
"""
Generate a PSX-style Lucky Rabbit's Foot texture (64x64).

A severed rabbit's HIND foot with matted greyish-brown fur on a tarnished brass chain.
Rabbit hind feet are LONG and narrow with visible toes at the bottom.
Creepy lucky charm aesthetic with PSX-era grainy pixel art style.
"""

import numpy as np
from PIL import Image, ImageDraw
import random

# Set seed for reproducibility
random.seed(42)
np.random.seed(42)

SIZE = 64

# PSX-style color palette
# Matted greyish-brown fur
FUR_BASE = (110, 95, 80)
FUR_DARK = (70, 60, 50)
FUR_LIGHT = (140, 125, 105)
FUR_HIGHLIGHT = (160, 145, 120)

# Tarnished brass chain
BRASS_DARK = (120, 100, 50)
BRASS_MID = (150, 130, 70)
BRASS_LIGHT = (180, 160, 90)

# Paw pad (slightly pinkish-grey, dried)
PAD_DARK = (90, 75, 75)
PAD_MID = (110, 95, 95)
PAD_LIGHT = (130, 110, 110)

# Outline/shadows
DARK_OUTLINE = (40, 35, 30)
SHADOW = (50, 45, 40)

# Background (transparent)
BG = (0, 0, 0, 0)

def add_psx_grain(img_array, intensity=0.15):
    """Add PSX-style grain/noise to the image."""
    noise = np.random.randint(-int(intensity * 255), int(intensity * 255),
                               (SIZE, SIZE, 3), dtype=np.int16)
    img_array[:, :, :3] = np.clip(img_array[:, :, :3].astype(np.int16) + noise, 0, 255).astype(np.uint8)

# Create image with alpha channel
img = Image.new('RGBA', (SIZE, SIZE), BG)
draw = ImageDraw.Draw(img)

# --- CHAIN (top of image) ---
chain_x = SIZE // 2
chain_y_start = 6

# Keyring at top (circular loop)
ring_radius = 4
for i in range(2):
    draw.ellipse([chain_x - ring_radius - i, chain_y_start - ring_radius - i,
                  chain_x + ring_radius + i, chain_y_start + ring_radius + i],
                 outline=BRASS_DARK)
draw.ellipse([chain_x - ring_radius + 1, chain_y_start - ring_radius + 1,
              chain_x + ring_radius - 1, chain_y_start + ring_radius - 1],
             outline=BRASS_MID)

# Chain links (simple vertical links)
link_positions = [12, 16, 20]
for link_y in link_positions:
    # Outline
    draw.ellipse([chain_x - 3, link_y - 2, chain_x + 3, link_y + 2], outline=BRASS_DARK)
    # Fill
    draw.ellipse([chain_x - 2, link_y - 1, chain_x + 2, link_y + 1], fill=BRASS_MID)
    # Highlight
    draw.point([(chain_x - 1, link_y)], fill=BRASS_LIGHT)

# --- RABBIT'S HIND FOOT (elongated shape) ---
# Hind feet are LONG - much longer than they are wide
# Shape: narrower at ankle (top), wider/thicker in middle, toes at bottom

# Build foot shape pixel by pixel for proper elongated anatomy
img_array = np.array(img)

# Foot dimensions - ELONGATED vertically
foot_top_y = 24  # Where ankle/cut area starts
foot_bottom_y = 58  # Where toes end
foot_center_x = SIZE // 2

# Create foot silhouette (elongated with proper width variation)
for y in range(foot_top_y, foot_bottom_y + 1):
    # Progress along foot (0.0 = ankle, 1.0 = toes)
    t = (y - foot_top_y) / (foot_bottom_y - foot_top_y)

    # Width variation (narrower at ankle, wider in middle, narrower at toes)
    if t < 0.3:  # Ankle area - narrow
        width = 6 + int(8 * (t / 0.3))
    elif t < 0.7:  # Main body - wider
        width = 14
    else:  # Toe area - narrowing
        width = 14 - int(6 * ((t - 0.7) / 0.3))

    # Draw horizontal line for this slice of the foot
    for x in range(foot_center_x - width, foot_center_x + width + 1):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            # Outline at edges
            if x == foot_center_x - width or x == foot_center_x + width:
                img_array[y, x] = (*DARK_OUTLINE, 255)
            else:
                img_array[y, x] = (*FUR_BASE, 255)

# --- TOES (4 small bumps at bottom) ---
# Rabbit hind feet have 4 toes with small claws
toe_y = foot_bottom_y - 4
toe_positions = [
    foot_center_x - 8,
    foot_center_x - 3,
    foot_center_x + 3,
    foot_center_x + 8
]

for toe_x in toe_positions:
    # Toe bump (small oval)
    for dy in range(-3, 4):
        for dx in range(-2, 3):
            x = toe_x + dx
            y = toe_y + dy
            if 0 <= x < SIZE and 0 <= y < SIZE:
                # Ellipse check
                if (dx/2.5)**2 + (dy/3.5)**2 <= 1.0:
                    if dy == -3 or dx == -2 or dx == 2:  # Outline
                        img_array[y, x] = (*SHADOW, 255)
                    else:
                        img_array[y, x] = (*FUR_DARK, 255)
                        # Small highlight
                        if dx == -1 and dy == -1:
                            img_array[y, x] = (*FUR_LIGHT, 255)

# Claws (tiny dark points extending from toes)
img = Image.fromarray(img_array)
draw = ImageDraw.Draw(img)
for toe_x in toe_positions:
    claw_y = toe_y + 4
    draw.line([(toe_x, claw_y), (toe_x, claw_y + 2)], fill=DARK_OUTLINE)

# --- PAW PAD (bottom center, between toes) ---
pad_x = foot_center_x
pad_y = foot_bottom_y - 8

# Larger main pad
img_array = np.array(img)
for dy in range(-4, 5):
    for dx in range(-6, 7):
        x = pad_x + dx
        y = pad_y + dy
        if 0 <= x < SIZE and 0 <= y < SIZE:
            # Oval shape
            if (dx/6.5)**2 + (dy/4.5)**2 <= 1.0:
                if (dx/6.5)**2 + (dy/4.5)**2 > 0.85:  # Outline
                    img_array[y, x] = (*DARK_OUTLINE, 255)
                elif (dx/6.5)**2 + (dy/4.5)**2 > 0.5:  # Mid tone
                    img_array[y, x] = (*PAD_MID, 255)
                else:  # Center
                    img_array[y, x] = (*PAD_DARK, 255)
                    if dx == -2 and dy == -1:  # Highlight
                        img_array[y, x] = (*PAD_LIGHT, 255)

# --- FUR TEXTURE (matted clumps/strands) ---
# Add visible fur texture with matted appearance

# Random matted fur patches (darker/lighter streaks)
for _ in range(60):
    x = random.randint(foot_center_x - 14, foot_center_x + 14)
    y = random.randint(foot_top_y + 2, foot_bottom_y - 10)

    if 0 <= x < SIZE and 0 <= y < SIZE:
        # Only modify if it's part of the fur (not transparent, not pad)
        if img_array[y, x, 3] > 0 and not (PAD_DARK[0] - 10 < img_array[y, x, 0] < PAD_LIGHT[0] + 10):
            # Matted clumps (small vertical streaks)
            streak_length = random.randint(2, 4)
            color = FUR_DARK if random.random() > 0.5 else FUR_LIGHT
            for dy in range(streak_length):
                if 0 <= y + dy < SIZE:
                    img_array[y + dy, x] = (*color, 255)

# Highlight along left edge (PSX lighting)
for y in range(foot_top_y + 5, foot_bottom_y - 5):
    x = foot_center_x - 10
    if 0 <= x < SIZE and 0 <= y < SIZE:
        if img_array[y, x, 3] > 0:  # Only if not transparent
            # Check it's fur, not pad
            if not (PAD_DARK[0] - 10 < img_array[y, x, 0] < PAD_LIGHT[0] + 10):
                img_array[y, x, :3] = FUR_HIGHLIGHT

# Shadow along right edge
for y in range(foot_top_y + 5, foot_bottom_y - 5):
    x = foot_center_x + 10
    if 0 <= x < SIZE and 0 <= y < SIZE:
        if img_array[y, x, 3] > 0:
            if not (PAD_DARK[0] - 10 < img_array[y, x, 0] < PAD_LIGHT[0] + 10):
                img_array[y, x, :3] = FUR_DARK

# --- SEVERED ANKLE (top of foot) ---
# Add cut/severed appearance at top where chain attaches
for y in range(foot_top_y, foot_top_y + 3):
    for x in range(foot_center_x - 6, foot_center_x + 7):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            if img_array[y, x, 3] > 0:
                # Darker, bloodied edge
                img_array[y, x, :3] = (60, 45, 40)
                # Some lighter spots for texture
                if random.random() > 0.7:
                    img_array[y, x, :3] = (80, 60, 55)

# --- PSX GRAIN ---
add_psx_grain(img_array, intensity=0.12)

# Convert back to image
img = Image.fromarray(img_array)

# Save output
output_path = 'output.png'
img.save(output_path)
print(f"✓ Generated Lucky Rabbit's Foot texture: {output_path}")
print(f"  Size: {SIZE}x{SIZE}")
print(f"  Style: PSX-era pixel art with grain")
print(f"  Features: ELONGATED hind foot with visible toes, matted fur, brass chain")
print(f"  Anatomy: Narrow at ankle, wider in middle, 4 toes with claws at bottom")
