#!/usr/bin/env python3
"""
Generates a tileable ceiling hole texture for DEEP YELLOW.
Takes the existing acoustic ceiling texture and adds a broken/missing section
revealing dark void and hints of infrastructure above.
"""

from PIL import Image, ImageDraw
import numpy as np
import random

# Configuration
SIZE = 128
INPUT_PATH = "../../../assets/levels/level_00/textures/ceiling_acoustic.png"
OUTPUT_PATH = "output.png"

# Seed for reproducibility
random.seed(42)
np.random.seed(42)

def add_noise(img_array, intensity=5):
    """Add subtle grain/noise to the image."""
    noise = np.random.randint(-intensity, intensity + 1, img_array.shape, dtype=np.int16)
    noisy = np.clip(img_array.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    return noisy

def create_irregular_hole_mask(size, center_x, center_y, width, height):
    """Create an irregular hole mask with VERY jagged/broken edges using noise."""
    mask = np.zeros((size, size), dtype=np.float32)

    half_w = width // 2
    half_h = height // 2

    # Generate Perlin-like noise for organic edge variation
    noise_scale = 8.0  # Controls edge raggedness

    for y in range(size):
        for x in range(size):
            # Distance from center (elliptical)
            dx = (x - center_x) / half_w
            dy = (y - center_y) / half_h
            dist = np.sqrt(dx**2 + dy**2)

            # Add noise to the distance threshold to create ragged edges
            angle = np.arctan2(dy, dx)
            # Multi-octave noise for varied edge detail
            noise1 = np.sin(angle * 5 + np.sin(angle * 3) * 0.5) * 0.15
            noise2 = np.sin(angle * 11 + np.cos(angle * 7) * 0.3) * 0.08
            noise3 = random.random() * 0.05  # Add some pure randomness

            threshold = 1.0 + noise1 + noise2 + noise3

            if dist < threshold:
                # Inside the hole - but add some interior gaps for broken chunks
                if random.random() > 0.03:  # 97% solid, 3% interior gaps
                    mask[y, x] = 1.0

    # Add chunky broken pieces hanging from edges
    num_chunks = random.randint(15, 25)
    for _ in range(num_chunks):
        # Place chunks near the edge
        angle = random.uniform(0, 2 * np.pi)
        edge_dist = random.uniform(0.9, 1.3)  # Just inside or outside edge

        chunk_x = int(center_x + np.cos(angle) * half_w * edge_dist)
        chunk_y = int(center_y + np.sin(angle) * half_h * edge_dist)

        if 0 <= chunk_x < size and 0 <= chunk_y < size:
            # Irregular chunk shape
            chunk_size = random.randint(2, 6)
            for dy in range(-chunk_size, chunk_size + 1):
                for dx in range(-chunk_size, chunk_size + 1):
                    px = chunk_x + dx
                    py = chunk_y + dy
                    if 0 <= px < size and 0 <= py < size:
                        # Irregular chunk shape (not circular)
                        chunk_dist = abs(dx) + abs(dy) * random.uniform(0.7, 1.3)
                        if chunk_dist < chunk_size and random.random() > 0.3:
                            mask[py, px] = 1.0

    # Convert to uint8
    return (mask * 255).astype(np.uint8)

def create_void_texture(size):
    """Create dark void texture with depth gradient and infrastructure hints."""
    # Create depth gradient - darker at center, slightly lighter at edges
    void = np.zeros((size, size, 3), dtype=np.uint8)

    center_x, center_y = size // 2, size // 2
    max_dist = np.sqrt(2) * size / 2

    for y in range(size):
        for x in range(size):
            # Distance from center for radial gradient
            dist = np.sqrt((x - center_x)**2 + (y - center_y)**2)
            # Normalized distance 0-1
            norm_dist = dist / max_dist

            # Very dark at center, slightly lighter at edges (for depth illusion)
            # Center: ~[8, 8, 12], Edges: ~[22, 22, 28]
            brightness = 8 + int(norm_dist * 14)
            void[y, x] = [brightness, brightness, brightness + 4]

    # Add pipe/beam structures (dark grey lines on near-black)
    num_pipes = random.randint(3, 5)
    for _ in range(num_pipes):
        pipe_color = random.randint(30, 50)

        if random.random() > 0.5:
            # Horizontal pipe/beam
            y = random.randint(15, size - 15)
            thickness = random.randint(2, 5)

            for dy in range(-thickness, thickness + 1):
                py = y + dy
                if 0 <= py < size:
                    for x in range(size):
                        # Add some variation along the pipe
                        var = int(np.sin(x * 0.3) * 3)
                        void[py, x] = np.clip([pipe_color + var, pipe_color + var, pipe_color + var + 5], 0, 255)
        else:
            # Vertical pipe/beam
            x = random.randint(15, size - 15)
            thickness = random.randint(2, 5)

            for dx in range(-thickness, thickness + 1):
                px = x + dx
                if 0 <= px < size:
                    for y in range(size):
                        # Add some variation along the pipe
                        var = int(np.sin(y * 0.3) * 3)
                        void[y, px] = np.clip([pipe_color + var, pipe_color + var, pipe_color + var + 5], 0, 255)

    # Add subtle cross-beams or structural elements
    num_cross = random.randint(1, 3)
    for _ in range(num_cross):
        # Diagonal or angled structural element
        start_x = random.randint(10, size - 10)
        start_y = random.randint(10, size - 10)
        angle = random.uniform(0, 2 * np.pi)
        length = random.randint(20, 50)
        thickness = random.randint(1, 3)
        color = random.randint(25, 45)

        for i in range(length):
            x = int(start_x + np.cos(angle) * i)
            y = int(start_y + np.sin(angle) * i)

            for dy in range(-thickness, thickness + 1):
                for dx in range(-thickness, thickness + 1):
                    px, py = x + dx, y + dy
                    if 0 <= px < size and 0 <= py < size:
                        void[py, px] = [color, color, color + 5]

    # Add subtle noise for texture
    void = add_noise(void, intensity=4)

    return void

def create_crumbled_edge_shadow(img_array, mask):
    """Add shadow/darkening around the hole edges to show depth."""
    size = mask.shape[0]

    # Create distance transform from hole edge
    from scipy import ndimage

    # Find edges of the hole
    edges = ndimage.binary_dilation(mask > 0) & ~(mask > 0)

    # Create shadow gradient (darker near edge, fades out)
    shadow_distance = 8  # pixels
    shadow = np.zeros((size, size), dtype=np.float32)

    for y in range(size):
        for x in range(size):
            if edges[y, x]:
                # Paint shadow outward from edges
                for dy in range(-shadow_distance, shadow_distance + 1):
                    for dx in range(-shadow_distance, shadow_distance + 1):
                        py = y + dy
                        px = x + dx

                        if 0 <= py < size and 0 <= px < size and mask[py, px] == 0:
                            dist = np.sqrt(dx**2 + dy**2)
                            if dist <= shadow_distance:
                                # Shadow intensity falls off with distance
                                intensity = 1.0 - (dist / shadow_distance)
                                shadow[py, px] = max(shadow[py, px], intensity * 0.4)

    # Apply shadow to image
    for c in range(3):
        img_array[:, :, c] = np.clip(
            img_array[:, :, c].astype(np.float32) * (1.0 - shadow),
            0, 255
        ).astype(np.uint8)

    return img_array

def main():
    print("Loading base ceiling texture...")
    base_img = Image.open(INPUT_PATH)

    # Ensure it's the right size
    if base_img.size != (SIZE, SIZE):
        print(f"Resizing base texture from {base_img.size} to {SIZE}x{SIZE}")
        base_img = base_img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    # Convert to RGB if needed
    if base_img.mode != 'RGB':
        base_img = base_img.convert('RGB')

    base_array = np.array(base_img)

    print("Creating irregular hole mask...")
    # Create hole roughly centered, but not touching edges (for tiling)
    hole_center_x = SIZE // 2 + random.randint(-10, 10)
    hole_center_y = SIZE // 2 + random.randint(-10, 10)
    hole_width = random.randint(40, 55)
    hole_height = random.randint(35, 50)

    hole_mask = create_irregular_hole_mask(SIZE, hole_center_x, hole_center_y, hole_width, hole_height)

    print("Generating void texture...")
    void_texture = create_void_texture(SIZE)

    print("Compositing hole into ceiling...")
    # Start with base ceiling
    result = base_array.copy()

    # Add shadow around hole edges first
    result = create_crumbled_edge_shadow(result, hole_mask)

    # Replace hole region with void
    for y in range(SIZE):
        for x in range(SIZE):
            if hole_mask[y, x] > 0:
                # Blend void texture in
                result[y, x] = void_texture[y, x]

    # Add prominent crumbled edges - partially hanging ceiling tile fragments
    edge_mask = ndimage.binary_dilation(hole_mask > 0) & ~(hole_mask > 0)

    # Find edge pixels
    edge_pixels = [(y, x) for y in range(SIZE) for x in range(SIZE) if edge_mask[y, x]]

    # Create hanging fragment clusters
    num_fragments = random.randint(8, 15)
    for _ in range(num_fragments):
        if not edge_pixels:
            break

        # Pick a random edge pixel
        seed_y, seed_x = random.choice(edge_pixels)

        # Create irregular fragment hanging from this edge
        fragment_size = random.randint(3, 8)

        for dy in range(fragment_size):
            for dx in range(-fragment_size // 2, fragment_size // 2 + 1):
                px = seed_x + dx + random.randint(-1, 1)  # Irregular shape
                py = seed_y + dy + random.randint(-1, 1)

                if 0 <= px < SIZE and 0 <= py < SIZE:
                    # Random chance to include pixel (creates ragged fragment)
                    if random.random() > 0.3:
                        # Darken significantly - exposed backing/shadow
                        result[py, px] = (result[py, px] * random.uniform(0.4, 0.7)).astype(np.uint8)

    # Add shadow/darkening around all edges
    for y in range(SIZE):
        for x in range(SIZE):
            if edge_mask[y, x]:
                # Edges are darker (exposed backing material/shadow)
                result[y, x] = (result[y, x] * random.uniform(0.5, 0.8)).astype(np.uint8)

    print("Saving output...")
    output_img = Image.fromarray(result)
    output_img.save(OUTPUT_PATH)

    print(f"✓ Generated ceiling hole texture: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}x{SIZE} pixels")
    print(f"  Hole size: ~{hole_width}x{hole_height} pixels")
    print(f"  Tileable: Yes (hole kept away from edges)")

if __name__ == "__main__":
    # Import scipy if available, fallback to simpler shadow otherwise
    try:
        from scipy import ndimage
    except ImportError:
        print("Warning: scipy not available, installing...")
        import subprocess
        subprocess.check_call(["pip", "install", "scipy"])
        from scipy import ndimage

    main()
