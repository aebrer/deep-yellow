#!/usr/bin/env python3
"""
WFC Tileset Pre-Generator for Backrooms Level 0

CORRECT WORKFLOW:
1. Generate interesting 128×128 mazes based on Backrooms lore
   - Agents read Backrooms descriptions for consistency
   - Vary room sizes (narrow hallways + wide rooms)
2. Visualize as PNG images for review
3. Virtuous cycle: generate → visualize → critique → improve
4. Subsample approved mazes into 8×8 tiles (with overlap)
5. Compute edge compatibility algorithmically

Usage:
    # Step 1: Generate and visualize mazes (with virtuous cycle)
    python generate_lvl0_wfc_tileset.py generate-mazes --count 20 --output-dir data/mazes

    # Step 2: Subsample approved mazes into tiles
    python generate_lvl0_wfc_tileset.py subsample-tiles --maze-dir data/mazes --output data/lvl0_wfc_tileset.json
"""

import json
import random
import argparse
import os
from typing import List, Dict, Tuple
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image, ImageDraw
    import numpy as np
except ImportError:
    print("ERROR: PIL and numpy are required. Install with: pip install pillow numpy")
    exit(1)


# Tile constants (matching Godot)
FLOOR = 0
WALL = 1

# Backrooms Level 0 description for context
BACKROOMS_LEVEL_0_DESCRIPTION = """
The Backrooms Level 0 is characterized by:
- Mono-yellow wallpaper with a damp, moldy smell
- Buzzing fluorescent lights overhead
- Damp brownish carpet
- Endless maze of mono-yellow hallways and rooms
- Rooms vary from small closet-sized spaces to larger open areas
- Hallways are typically narrow (1-3 tiles wide)
- Occasional larger rooms (8-20 tiles across)
- No windows, no natural light
- Feeling of infinite repetition and monotony
- Random layout with no logical structure

Key design elements:
- Mix of narrow corridors and open spaces
- Rooms should feel random, not grid-aligned
- Some dead ends, some loops
- Occasional large open areas to break monotony
- Overall ~70% floor, ~30% walls
"""


@dataclass
class Maze128:
    """A 128×128 maze structure"""
    name: str
    grid: np.ndarray  # 128×128 array of FLOOR/WALL

    def to_image(self, cell_size: int = 4) -> Image.Image:
        """Convert maze to PIL Image for visualization"""
        size = 128 * cell_size
        img = Image.new('RGB', (size, size), color='black')
        draw = ImageDraw.Draw(img)

        for y in range(128):
            for x in range(128):
                color = (50, 50, 50) if self.grid[y, x] == WALL else (200, 200, 150)
                x1, y1 = x * cell_size, y * cell_size
                x2, y2 = x1 + cell_size, y1 + cell_size
                draw.rectangle([x1, y1, x2, y2], fill=color)

        return img

    def save_image(self, output_path: str, cell_size: int = 4):
        """Save maze as PNG"""
        img = self.to_image(cell_size)
        img.save(output_path)

    def get_stats(self) -> Dict:
        """Calculate maze statistics"""
        floor_count = np.sum(self.grid == FLOOR)
        wall_count = np.sum(self.grid == WALL)
        total = 128 * 128

        return {
            "floor_pct": floor_count / total * 100,
            "wall_pct": wall_count / total * 100,
            "floor_count": int(floor_count),
            "wall_count": int(wall_count)
        }


class BackroomsMazeGenerator:
    """Generate Backrooms Level 0 style mazes with varied room sizes"""

    def __init__(self, seed: int = 42):
        self.rng = np.random.RandomState(seed)
        self.maze_counter = 0

    def generate_maze(self) -> Maze128:
        """Generate a single 128×128 Backrooms-style maze"""
        grid = np.full((128, 128), WALL, dtype=np.int8)

        # Choose generation strategy (reduced room_focused to prevent too-sparse mazes)
        strategy = self.rng.choice(['room_focused', 'maze_focused', 'hybrid'], p=[0.2, 0.5, 0.3])

        if strategy == 'room_focused':
            # More rooms, fewer maze corridors
            self._generate_varied_rooms(grid, num_rooms=self.rng.randint(10, 18))
            self._connect_rooms_naturally(grid)
            self._add_random_corridors(grid, density=0.1)

        elif strategy == 'maze_focused':
            # Fewer larger rooms, more maze corridors
            self._generate_maze_base(grid)
            self._carve_rooms_in_maze(grid, num_rooms=self.rng.randint(4, 8))

        else:  # hybrid
            # Mix of both approaches
            self._generate_varied_rooms(grid, num_rooms=self.rng.randint(6, 12))
            self._fill_empty_areas_with_maze(grid)

        # Post-processing: target 68-72% floor (sweet spot from approved mazes)
        self._ensure_floor_percentage_range(grid, min_target=0.68, max_target=0.75)

        name = f"maze_{self.maze_counter:03d}"
        self.maze_counter += 1

        return Maze128(name=name, grid=grid)

    def _generate_varied_rooms(self, grid: np.ndarray, num_rooms: int):
        """Generate rooms of varying sizes (Backrooms style)"""
        rooms = []

        for _ in range(num_rooms):
            # Heavily varied room sizes
            size_category = self.rng.choice(['tiny', 'small', 'medium', 'large', 'huge'], p=[0.15, 0.35, 0.30, 0.15, 0.05])

            if size_category == 'tiny':
                width, height = self.rng.randint(3, 6), self.rng.randint(3, 6)
            elif size_category == 'small':
                width, height = self.rng.randint(5, 10), self.rng.randint(5, 10)
            elif size_category == 'medium':
                width, height = self.rng.randint(8, 16), self.rng.randint(8, 16)
            elif size_category == 'large':
                width, height = self.rng.randint(12, 24), self.rng.randint(12, 24)
            else:  # huge
                width, height = self.rng.randint(20, 35), self.rng.randint(20, 35)

            # Random position
            x = self.rng.randint(2, max(3, 128 - width - 2))
            y = self.rng.randint(2, max(3, 128 - height - 2))

            # Carve room
            grid[y:y+height, x:x+width] = FLOOR
            rooms.append((x + width // 2, y + height // 2, width, height))

        self.rooms = rooms

    def _connect_rooms_naturally(self, grid: np.ndarray):
        """Connect rooms with natural-feeling corridors"""
        if not hasattr(self, 'rooms') or len(self.rooms) < 2:
            return

        # Connect sequential rooms
        for i in range(len(self.rooms) - 1):
            x1, y1, _, _ = self.rooms[i]
            x2, y2, _, _ = self.rooms[i + 1]
            self._carve_corridor(grid, x1, y1, x2, y2)

        # Add some extra connections for loops
        extra = min(5, len(self.rooms) // 3)
        for _ in range(extra):
            i, j = self.rng.choice(len(self.rooms), size=2, replace=False)
            x1, y1, _, _ = self.rooms[i]
            x2, y2, _, _ = self.rooms[j]
            self._carve_corridor(grid, x1, y1, x2, y2)

    def _carve_corridor(self, grid: np.ndarray, x1: int, y1: int, x2: int, y2: int):
        """Carve corridor with varied width (Backrooms style: narrow hallways)"""
        # Corridor width (heavily favor narrow)
        width = self.rng.choice([1, 2, 3], p=[0.7, 0.25, 0.05])

        # L-shaped corridor
        if self.rng.random() < 0.5:
            # Horizontal first
            x_start, x_end = sorted([x1, x2])
            for x in range(x_start, x_end + 1):
                for w in range(width):
                    if 0 <= y1 + w < 128 and 0 <= x < 128:
                        grid[y1 + w, x] = FLOOR

            # Then vertical
            y_start, y_end = sorted([y1, y2])
            for y in range(y_start, y_end + 1):
                for w in range(width):
                    if 0 <= y < 128 and 0 <= x2 + w < 128:
                        grid[y, x2 + w] = FLOOR
        else:
            # Vertical first
            y_start, y_end = sorted([y1, y2])
            for y in range(y_start, y_end + 1):
                for w in range(width):
                    if 0 <= y < 128 and 0 <= x1 + w < 128:
                        grid[y, x1 + w] = FLOOR

            # Then horizontal
            x_start, x_end = sorted([x1, x2])
            for x in range(x_start, x_end + 1):
                for w in range(width):
                    if 0 <= y2 + w < 128 and 0 <= x < 128:
                        grid[y2 + w, x] = FLOOR

    def _generate_maze_base(self, grid: np.ndarray):
        """Generate maze using recursive backtracking"""
        visited = set()
        stack = []

        # Start from random position (on even grid for cleaner maze)
        start_x = self.rng.randint(0, 63) * 2
        start_y = self.rng.randint(0, 63) * 2

        stack.append((start_x, start_y))
        visited.add((start_x, start_y))
        grid[start_y, start_x] = FLOOR

        directions = [(0, -2), (0, 2), (-2, 0), (2, 0)]

        while stack:
            x, y = stack[-1]

            # Find unvisited neighbors
            neighbors = []
            for dx, dy in directions:
                nx, ny = x + dx, y + dy
                if 0 <= nx < 128 and 0 <= ny < 128 and (nx, ny) not in visited:
                    neighbors.append((nx, ny, dx, dy))

            if neighbors:
                nx, ny, dx, dy = neighbors[self.rng.randint(len(neighbors))]
                grid[ny, nx] = FLOOR
                grid[y + dy // 2, x + dx // 2] = FLOOR
                visited.add((nx, ny))
                stack.append((nx, ny))
            else:
                stack.pop()

    def _carve_rooms_in_maze(self, grid: np.ndarray, num_rooms: int):
        """Carve rooms into existing maze structure"""
        for _ in range(num_rooms):
            width = self.rng.randint(5, 15)
            height = self.rng.randint(5, 15)

            x = self.rng.randint(2, max(3, 128 - width - 2))
            y = self.rng.randint(2, max(3, 128 - height - 2))

            grid[y:y+height, x:x+width] = FLOOR

    def _add_random_corridors(self, grid: np.ndarray, density: float = 0.1):
        """Add random corridors to increase connectivity"""
        num_corridors = int(128 * 128 * density / 20)

        for _ in range(num_corridors):
            x1 = self.rng.randint(0, 127)
            y1 = self.rng.randint(0, 127)
            x2 = self.rng.randint(0, 127)
            y2 = self.rng.randint(0, 127)

            self._carve_corridor(grid, x1, y1, x2, y2)

    def _fill_empty_areas_with_maze(self, grid: np.ndarray):
        """Fill large wall regions with maze corridors"""
        for y in range(0, 128, 16):
            for x in range(0, 128, 16):
                region = grid[y:min(y+16, 128), x:min(x+16, 128)]
                if np.sum(region == FLOOR) < 20:  # Mostly walls
                    if self.rng.random() < 0.4:
                        self._carve_mini_maze(grid, x, y, 16, 16)

    def _carve_mini_maze(self, grid: np.ndarray, start_x: int, start_y: int, width: int, height: int):
        """Carve a small maze in a region"""
        for _ in range(self.rng.randint(4, 10)):
            x1 = start_x + self.rng.randint(0, width - 1)
            y1 = start_y + self.rng.randint(0, height - 1)
            length = self.rng.randint(2, 6)

            if self.rng.random() < 0.5:
                for dx in range(length):
                    if 0 <= x1 + dx < 128 and 0 <= y1 < 128:
                        grid[y1, x1 + dx] = FLOOR
            else:
                for dy in range(length):
                    if 0 <= x1 < 128 and 0 <= y1 + dy < 128:
                        grid[y1 + dy, x1] = FLOOR

    def _ensure_floor_percentage_range(self, grid: np.ndarray, min_target: float = 0.68, max_target: float = 0.75):
        """Ensure floor percentage is within target range (prevent too sparse or too dense)"""
        floor_count = np.sum(grid == FLOOR)
        total = 128 * 128
        current_pct = floor_count / total

        if current_pct < min_target:
            # Add more floor tiles (too dense with walls)
            needed = int((min_target - current_pct) * total)

            for _ in range(needed):
                x = self.rng.randint(1, 126)
                y = self.rng.randint(1, 126)

                # Carve small corridor
                length = self.rng.randint(2, 5)
                if self.rng.random() < 0.5:
                    for dx in range(length):
                        if 0 <= x + dx < 128:
                            grid[y, x + dx] = FLOOR
                else:
                    for dy in range(length):
                        if 0 <= y + dy < 128:
                            grid[y + dy, x] = FLOOR

        elif current_pct > max_target:
            # Add walls to reduce floor percentage (too sparse)
            needed = int((current_pct - max_target) * total)

            for _ in range(needed):
                x = self.rng.randint(1, 126)
                y = self.rng.randint(1, 126)

                # Add wall chunks to break up overly open areas
                if grid[y, x] == FLOOR:
                    grid[y, x] = WALL
                    # Sometimes add adjacent walls for structure
                    if self.rng.random() < 0.3:
                        for dy, dx in [(0, 1), (1, 0), (0, -1), (-1, 0)]:
                            ny, nx = y + dy, x + dx
                            if 0 <= ny < 128 and 0 <= nx < 128 and grid[ny, nx] == FLOOR:
                                grid[ny, nx] = WALL
                                break


def subsample_maze_to_tiles(maze: Maze128, stride: int = 4) -> List[Dict]:
    """Extract 8×8 tiles from 128×128 maze with overlap

    Args:
        maze: Source maze
        stride: Step size for sampling (4 = 50% overlap, 6 = 25% overlap)

    Returns:
        List of tile dictionaries with pattern and edge info
    """
    tiles = []
    tile_id = 0

    for y in range(0, 128 - 8 + 1, stride):
        for x in range(0, 128 - 8 + 1, stride):
            # Extract 8×8 region
            pattern = maze.grid[y:y+8, x:x+8].tolist()

            # Calculate edge signatures
            north_edge = list(pattern[0])
            south_edge = list(pattern[7])
            east_edge = [row[7] for row in pattern]
            west_edge = [row[0] for row in pattern]

            tiles.append({
                "name": f"{maze.name}_tile_{tile_id:04d}",
                "source_maze": maze.name,
                "source_position": [x, y],
                "pattern": pattern,
                "edges": {
                    "north": north_edge,
                    "south": south_edge,
                    "east": east_edge,
                    "west": west_edge,
                },
                "weight": 1.0
            })
            tile_id += 1

    return tiles


def compute_compatibility_matrix(tiles: List[Dict]) -> Dict[str, List[str]]:
    """Compute tile compatibility based on edge matching (ALGORITHMIC)"""
    compatibility = {}

    # Build edge index for fast lookup
    edge_index = {'north': {}, 'south': {}, 'east': {}, 'west': {}}

    for tile in tiles:
        name = tile["name"]
        for direction in ['north', 'south', 'east', 'west']:
            edge = tuple(tile["edges"][direction])
            if edge not in edge_index[direction]:
                edge_index[direction][edge] = []
            edge_index[direction][edge].append(name)

    # Compute compatibility
    for tile in tiles:
        name = tile["name"]

        # Tiles are compatible if their touching edges match
        north_edge = tuple(tile["edges"]["north"])
        south_edge = tuple(tile["edges"]["south"])
        east_edge = tuple(tile["edges"]["east"])
        west_edge = tuple(tile["edges"]["west"])

        compatibility[f"{name}:north"] = edge_index['south'].get(north_edge, [])
        compatibility[f"{name}:south"] = edge_index['north'].get(south_edge, [])
        compatibility[f"{name}:east"] = edge_index['west'].get(east_edge, [])
        compatibility[f"{name}:west"] = edge_index['east'].get(west_edge, [])

    return compatibility


def generate_mazes_command(args):
    """Step 1: Generate and visualize Backrooms mazes"""
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    generator = BackroomsMazeGenerator(seed=args.seed)

    print(f"=== Generating {args.count} Backrooms Level 0 Mazes ===")
    print(f"Seed: {args.seed}")
    print(f"Output: {output_dir}")
    print()
    print("Design goals (from Backrooms lore):")
    print("  - Mix of narrow hallways (1-3 tiles) and varied rooms")
    print("  - ~70% floor, ~30% walls")
    print("  - Random, non-grid-aligned layout")
    print()

    for i in range(args.count):
        maze = generator.generate_maze()
        stats = maze.get_stats()

        # Save visualization
        img_path = output_dir / f"{maze.name}.png"
        maze.save_image(str(img_path), cell_size=args.cell_size)

        # Save raw data
        data_path = output_dir / f"{maze.name}.npy"
        np.save(str(data_path), maze.grid)

        print(f"  [{i+1:2d}/{args.count}] {maze.name}: {stats['floor_pct']:.1f}% floor, {stats['wall_pct']:.1f}% walls")

    print()
    print("=== Generation Complete ===")
    print(f"Images saved to: {output_dir}")
    print()
    print("NEXT STEPS (Virtuous Cycle):")
    print("1. Review maze images - look for variety in room sizes and interesting layouts")
    print("2. Delete any mazes that look too repetitive or boring")
    print("3. If needed, regenerate with different seeds for more variety")
    print("4. When satisfied, run: python generate_lvl0_wfc_tileset.py subsample-tiles")


def subsample_tiles_command(args):
    """Step 2: Subsample approved mazes into WFC tiles"""
    maze_dir = Path(args.maze_dir)

    if not maze_dir.exists():
        print(f"ERROR: Maze directory not found: {maze_dir}")
        return

    print(f"=== Subsampling Approved Mazes into Tiles ===")
    print(f"Maze directory: {maze_dir}")
    print(f"Stride: {args.stride} ({'50%' if args.stride == 4 else '25%' if args.stride == 6 else 'custom'} overlap)")
    print()

    # Load all approved mazes
    maze_files = sorted(maze_dir.glob("*.npy"))
    if not maze_files:
        print(f"ERROR: No .npy files found in {maze_dir}")
        return

    print(f"Found {len(maze_files)} maze files")

    all_tiles = []
    for maze_file in maze_files:
        maze_name = maze_file.stem
        grid = np.load(str(maze_file))
        maze = Maze128(name=maze_name, grid=grid)

        tiles = subsample_maze_to_tiles(maze, stride=args.stride)
        all_tiles.extend(tiles)

        print(f"  {maze_name}: extracted {len(tiles)} tiles")

    print()
    print(f"Total tiles: {len(all_tiles)}")

    # Compute compatibility
    print("Computing edge compatibility matrix (algorithmic)...")
    compatibility = compute_compatibility_matrix(all_tiles)
    print(f"Compatibility entries: {len(compatibility)}")

    # Export
    output_data = {
        "tiles": all_tiles,
        "compatibility": compatibility,
        "metadata": {
            "tile_count": len(all_tiles),
            "tile_size": 8,
            "stride": args.stride,
            "source_mazes": len(maze_files),
            "generated_by": "generate_lvl0_wfc_tileset.py (subsample mode)"
        }
    }

    with open(args.output, 'w') as f:
        json.dump(output_data, f, indent=2)

    file_size_kb = os.path.getsize(args.output) / 1024
    print(f"Tileset exported: {args.output}")
    print(f"File size: {file_size_kb:.1f} KB")
    print()
    print("=== Ready for Godot Integration! ===")


def main():
    parser = argparse.ArgumentParser(description="Generate WFC tileset for Backrooms Level 0")
    subparsers = parser.add_subparsers(dest='command', required=True)

    # Generate mazes
    gen = subparsers.add_parser('generate-mazes', help='Generate and visualize maze structures')
    gen.add_argument('--count', type=int, default=20, help='Number of mazes to generate')
    gen.add_argument('--seed', type=int, default=42, help='Random seed')
    gen.add_argument('--output-dir', type=str, default='data/mazes', help='Output directory')
    gen.add_argument('--cell-size', type=int, default=4, help='Cell size for PNG visualization')

    # Subsample tiles
    sub = subparsers.add_parser('subsample-tiles', help='Subsample approved mazes into tiles')
    sub.add_argument('--maze-dir', type=str, default='data/mazes', help='Directory with .npy maze files')
    sub.add_argument('--stride', type=int, default=4, help='Sampling stride (4=50%% overlap, 6=25%% overlap)')
    sub.add_argument('--output', type=str, default='data/lvl0_wfc_tileset.json', help='Output JSON file')

    args = parser.parse_args()

    if args.command == 'generate-mazes':
        generate_mazes_command(args)
    elif args.command == 'subsample-tiles':
        subsample_tiles_command(args)


if __name__ == '__main__':
    main()
