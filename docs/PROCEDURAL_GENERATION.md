# Procedural Generation System Design

**Last Updated**: 2025-11-09

---

## Overview

This document outlines the procedural generation system for Backrooms Power Crawl's infinite maze world. The system uses a chunk-based "island of mazes" approach inspired by Binding of Isaac's chunked generation and Minecraft's infinite world streaming, while maintaining the classic Backrooms Level 0 aesthetic of endless yellow hallways and fluorescent monotony.

### Core Concept: Island of Mazes

Unlike traditional dungeon generators that create "islands of rooms" (discrete rooms connected by hallways), this system creates **self-contained maze "islands"** where:
- Each island is a complete Backrooms-style maze (hallways + occasional rooms)
- Islands are generated chunk-by-chunk as the player explores
- Islands can connect to adjacent islands via portals/doorways
- Entities can wander between connected islands
- Potentially infinite generation without memory constraints

---

## 1. Chunk System Architecture

### 1.1 Chunk Structure

```
Chunk
├── Position: Vector2i (chunk coordinates, not tile coordinates)
├── Size: 32x32 tiles (configurable constant)
├── Data: Array[Array[int]] (tile types)
├── State: Enum (UNGENERATED, GENERATING, LOADED, UNLOADING)
├── Island ID: int (which maze island this chunk belongs to)
├── Entity List: Array[EntityID] (entities currently in this chunk)
├── Last Access Time: float (for unloading priority)
└── Connections: Array[Vector2i] (connected chunk positions)
```

**Why 32x32 tiles per chunk?**
- **Performance**: Current render distance is ~20 tiles. 32x32 chunks means ~6-9 chunks visible at once
- **Generation Speed**: Small enough to generate quickly (within a frame budget)
- **Memory**: ~1KB per chunk for tile data (32x32 bytes), ~50KB for 50 loaded chunks
- **Grid alignment**: 32 is a power of 2, making coordinate math simple
- **Scalability**: Can adjust if needed based on testing

### 1.2 Chunk Loading Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                   CHUNK LOADING ZONES                        │
│                                                              │
│   ┌──────────────────────────────────────┐                  │
│   │  UNLOAD ZONE (8+ chunks away)        │                  │
│   │  ┌────────────────────────────┐      │                  │
│   │  │ GENERATION ZONE (4-7 away) │      │                  │
│   │  │  ┌──────────────────┐      │      │                  │
│   │  │  │ ACTIVE ZONE (0-3)│      │      │                  │
│   │  │  │                  │      │      │                  │
│   │  │  │     [PLAYER]     │      │      │                  │
│   │  │  │                  │      │      │                  │
│   │  │  └──────────────────┘      │      │                  │
│   │  └────────────────────────────┘      │                  │
│   └──────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

**Zone Definitions:**
- **Active Zone (0-3 chunks)**: Fully loaded, entities active, physics simulated
- **Generation Zone (4-7 chunks)**: Queued for async generation, no entities yet
- **Unload Zone (8+ chunks)**: Candidates for unloading to free memory

**Loading Thresholds:**
```gdscript
const ACTIVE_RADIUS := 3        # Chunks to keep fully loaded
const GENERATION_RADIUS := 7    # Chunks to pre-generate
const UNLOAD_RADIUS := 8        # Chunks to unload
const MAX_LOADED_CHUNKS := 100  # Hard limit to prevent memory issues
```

### 1.3 Chunk State Machine

```
UNGENERATED
    ├─ player enters generation zone → GENERATING
    
GENERATING (async)
    ├─ generation complete → LOADED
    └─ generation failed → UNGENERATED
    
LOADED
    ├─ player exits unload zone → UNLOADING
    └─ player in active zone → (stay LOADED)
    
UNLOADING
    ├─ unload complete → UNGENERATED
    └─ player re-enters active zone → LOADED
```

### 1.4 World Coordinate System

```gdscript
# Convert between coordinate systems

# Tile position → Chunk position
func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
    return Vector2i(
        floori(float(tile_pos.x) / CHUNK_SIZE),
        floori(float(tile_pos.y) / CHUNK_SIZE)
    )

# Chunk position → World tile position (chunk origin)
func chunk_to_world(chunk_pos: Vector2i) -> Vector2i:
    return chunk_pos * CHUNK_SIZE

# Tile position → Local chunk position (0-31)
func tile_to_local(tile_pos: Vector2i) -> Vector2i:
    return Vector2i(
        posmod(tile_pos.x, CHUNK_SIZE),
        posmod(tile_pos.y, CHUNK_SIZE)
    )
```

**Example:**
- Player at tile (100, 50)
- Chunk position: (3, 1) → (100/32 = 3.125, 50/32 = 1.5625)
- Local position: (4, 18) → (100 % 32 = 4, 50 % 32 = 18)
- World origin: (96, 32) → (3 * 32, 1 * 32)

---

## 2. Maze Generation Algorithm

### 2.1 Algorithm Choice: Modified Recursive Backtracking

**Why Recursive Backtracking?**
- ✅ **Long corridors**: Backrooms aesthetic requires long, monotonous hallways
- ✅ **Low branching**: Reduces complexity, creates tension from limited paths
- ✅ **Simple implementation**: Easy to understand and debug
- ✅ **Fast generation**: Θ(h × w) average time complexity
- ❌ **Memory intensive**: Requires stack for full maze (mitigated by small chunk size)

**Why NOT Eller's Algorithm?**
- Eller's is optimized for infinite *row-by-row* generation
- We need *chunk-by-chunk* generation with island connectivity
- Harder to control corridor length and branching factor
- Complexity doesn't justify benefits for 32x32 chunks

### 2.2 Chunk-Aware Recursive Backtracking

```gdscript
class_name ChunkMazeGenerator

const TILE_WALL := 1
const TILE_FLOOR := 0
const TILE_DOOR := 2  # Connection to adjacent chunk/island

# Generate maze within a single chunk
func generate_chunk_maze(chunk_pos: Vector2i, island_id: int, seed_value: int, border_connections: Dictionary) -> Array[Array]:
    var rng := RandomNumberGenerator.new()
    rng.seed = _chunk_seed(chunk_pos, seed_value)
    
    # Initialize grid (all walls)
    var data := _init_grid(CHUNK_SIZE, TILE_WALL)
    
    # Carve maze using recursive backtracking
    var stack: Array[Vector2i] = []
    var start_pos := _get_start_position(border_connections)
    stack.push_back(start_pos)
    data[start_pos.y][start_pos.x] = TILE_FLOOR
    
    while stack.size() > 0:
        var current := stack.back()
        var neighbors := _get_unvisited_neighbors(current, data, rng)
        
        if neighbors.size() > 0:
            # Choose random unvisited neighbor
            var next := neighbors[rng.randi() % neighbors.size()]
            
            # Carve path between current and next
            _carve_path(data, current, next)
            data[next.y][next.x] = TILE_FLOOR
            
            stack.push_back(next)
        else:
            # Backtrack
            stack.pop_back()
    
    # Add border connections (doors to adjacent chunks)
    _add_border_connections(data, border_connections)
    
    # Occasionally place rooms
    _place_rooms(data, rng, chunk_pos, island_id)
    
    return data

# Get unvisited neighbors (2 cells away to create corridors)
func _get_unvisited_neighbors(pos: Vector2i, data: Array, rng: RandomNumberGenerator) -> Array[Vector2i]:
    var neighbors: Array[Vector2i] = []
    var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
    
    # Shuffle for randomness
    directions.shuffle()
    
    for dir in directions:
        var next := pos + dir * 2  # 2 cells away
        if _is_in_bounds(next) and data[next.y][next.x] == TILE_WALL:
            # Check if next cell hasn't been carved yet
            neighbors.append(next)
    
    return neighbors

# Carve path (set current, between, and next to floor)
func _carve_path(data: Array, current: Vector2i, next: Vector2i) -> void:
    var between := (current + next) / 2
    data[between.y][between.x] = TILE_FLOOR
```

### 2.3 Chunk Seed Generation (Deterministic)

```gdscript
# Generate consistent seed for any chunk position
func _chunk_seed(chunk_pos: Vector2i, world_seed: int) -> int:
    # FNV-1a hash for deterministic chunk seeds
    var hash := 2166136261  # FNV offset basis
    
    # Hash world seed
    hash = (hash ^ world_seed) * 16777619
    
    # Hash chunk X
    hash = (hash ^ chunk_pos.x) * 16777619
    
    # Hash chunk Y
    hash = (hash ^ chunk_pos.y) * 16777619
    
    return hash
```

**Why FNV-1a Hash?**
- Fast to compute
- Good distribution (avoids correlation between nearby chunks)
- Deterministic (same chunk_pos + world_seed = same maze every time)
- No need to store chunk data between sessions (can regenerate on load)

### 2.4 Backrooms-Specific Enhancements

```gdscript
# Place occasional rooms to break monotony
func _place_rooms(data: Array, rng: RandomNumberGenerator, chunk_pos: Vector2i, island_id: int) -> void:
    # 20% chance of a room in this chunk
    if rng.randf() > 0.2:
        return
    
    # Room size: 4x4 to 8x8
    var room_size := Vector2i(
        rng.randi_range(4, 8),
        rng.randi_range(4, 8)
    )
    
    # Random position (not on edges)
    var room_pos := Vector2i(
        rng.randi_range(2, CHUNK_SIZE - room_size.x - 2),
        rng.randi_range(2, CHUNK_SIZE - room_size.y - 2)
    )
    
    # Carve room
    for y in range(room_size.y):
        for x in range(room_size.x):
            data[room_pos.y + y][room_pos.x + x] = TILE_FLOOR
    
    # Ensure connection to maze (find nearest hallway)
    _connect_room_to_maze(data, room_pos, room_size)

# Add visual variety while maintaining monotony
func _add_decorative_elements(data: Array, rng: RandomNumberGenerator) -> void:
    # Occasional dead-end pillars
    # Random wall thickness variations
    # Light fixture positions (stored in chunk metadata)
    pass
```

---

## 3. Island System (Multi-Maze Connectivity)

### 3.1 Island Structure

```gdscript
class_name MazeIsland extends RefCounted

var island_id: int
var chunk_positions: Array[Vector2i] = []  # All chunks in this island
var connections: Array[IslandConnection] = []  # Connections to other islands
var difficulty_tier: int = 0  # Affects entity spawning, hazards
var theme_variant: String = "classic_yellow"  # Visual variation

class IslandConnection:
    var from_island: int
    var to_island: int
    var from_chunk: Vector2i
    var to_chunk: Vector2i
    var door_position: Vector2i  # Tile position of connection door
```

### 3.2 Island Generation Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                   ISLAND LAYOUT                              │
│                                                              │
│   Island A (9 chunks)     Island B (12 chunks)              │
│   ┌───┬───┬───┐          ┌───┬───┬───┬───┐                 │
│   │   │   │   │          │   │   │   │   │                 │
│   ├───┼───┼───┤          ├───┼───┼───┼───┤                 │
│   │   │[P]│   │══════════│   │   │   │   │                 │
│   ├───┼───┼───┤  (door)  ├───┼───┼───┼───┤                 │
│   │   │   │   │          │   │   │   │   │                 │
│   └───┴───┴───┘          └───┴───┴───┴───┘                 │
│                                                              │
│   Island C (6 chunks)                                        │
│   ┌───┬───┬───┐                                             │
│   │   │   │   │                                             │
│   ├───┼───┼───┤                                             │
│   │   │   │   │                                             │
│   └───┴───┴───┘                                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Island Size:**
- Minimum: 4 chunks (2x2)
- Maximum: 16 chunks (4x4)
- Average: 9 chunks (3x3)

**Island Spacing:**
- 1-3 chunks of "void" between islands (initially)
- Void can be bridged later via exploration/progression

### 3.3 Island Connection Algorithm

```gdscript
class_name IslandManager extends Node

var islands: Dictionary = {}  # island_id -> MazeIsland
var chunk_to_island: Dictionary = {}  # chunk_pos -> island_id
var next_island_id := 0

func generate_island(center_chunk: Vector2i, world_seed: int) -> MazeIsland:
    var island := MazeIsland.new()
    island.island_id = next_island_id
    next_island_id += 1
    
    # Determine island size based on seed + position
    var rng := RandomNumberGenerator.new()
    rng.seed = _chunk_seed(center_chunk, world_seed)
    var size := Vector2i(
        rng.randi_range(2, 4),  # Width: 2-4 chunks
        rng.randi_range(2, 4)   # Height: 2-4 chunks
    )
    
    # Populate chunks
    for y in range(size.y):
        for x in range(size.x):
            var chunk_pos := center_chunk + Vector2i(x, y)
            island.chunk_positions.append(chunk_pos)
            chunk_to_island[chunk_pos] = island.island_id
    
    # Check for potential connections to adjacent islands
    _generate_island_connections(island)
    
    islands[island.island_id] = island
    return island

func _generate_island_connections(island: MazeIsland) -> void:
    # Check border chunks for adjacent islands
    var border_chunks := _get_border_chunks(island)
    
    for chunk_pos in border_chunks:
        var adjacent_chunks := [
            chunk_pos + Vector2i.UP,
            chunk_pos + Vector2i.DOWN,
            chunk_pos + Vector2i.LEFT,
            chunk_pos + Vector2i.RIGHT
        ]
        
        for adj_pos in adjacent_chunks:
            if adj_pos in chunk_to_island:
                var other_island_id: int = chunk_to_island[adj_pos]
                if other_island_id != island.island_id:
                    # Create connection
                    _create_connection(island.island_id, other_island_id, chunk_pos, adj_pos)
```

### 3.4 Connection Door Placement

```gdscript
# Place a door between two chunks on adjacent islands
func _create_connection(from_island: int, to_island: int, from_chunk: Vector2i, to_chunk: Vector2i) -> void:
    var connection := MazeIsland.IslandConnection.new()
    connection.from_island = from_island
    connection.to_island = to_island
    connection.from_chunk = from_chunk
    connection.to_chunk = to_chunk
    
    # Determine door position (on chunk border)
    var direction := to_chunk - from_chunk
    if direction.x > 0:  # East door
        connection.door_position = Vector2i(CHUNK_SIZE - 1, CHUNK_SIZE / 2)
    elif direction.x < 0:  # West door
        connection.door_position = Vector2i(0, CHUNK_SIZE / 2)
    elif direction.y > 0:  # South door
        connection.door_position = Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE - 1)
    else:  # North door
        connection.door_position = Vector2i(CHUNK_SIZE / 2, 0)
    
    islands[from_island].connections.append(connection)
    islands[to_island].connections.append(connection)
    
    # Mark door in chunk data (TILE_DOOR)
    # This is done during chunk generation when border_connections are checked
```

---

## 4. Data Structures

### 4.1 ChunkManager (Singleton)

```gdscript
class_name ChunkManager extends Node
## Manages chunk loading, unloading, and generation

# Chunk storage
var loaded_chunks: Dictionary = {}  # Vector2i -> Chunk
var generating_chunks: Array[Vector2i] = []  # Async generation queue

# Configuration
const CHUNK_SIZE := 32
const ACTIVE_RADIUS := 3
const GENERATION_RADIUS := 7
const UNLOAD_RADIUS := 8
const MAX_LOADED_CHUNKS := 100

# World settings
var world_seed: int = 0

# Generation
var generator: ChunkMazeGenerator
var island_manager: IslandManager

func _ready() -> void:
    generator = ChunkMazeGenerator.new()
    island_manager = IslandManager.new()
    add_child(island_manager)

func _process(delta: float) -> void:
    # Update chunks based on player position
    _update_chunks_around_player()
    
    # Process generation queue
    _process_generation_queue()
    
    # Unload distant chunks
    _unload_distant_chunks()

func _update_chunks_around_player() -> void:
    var player_tile := PlayerManager.get_position()  # From player singleton
    var player_chunk := tile_to_chunk(player_tile)
    
    # Load/generate chunks in radius
    for y in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
        for x in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
            var chunk_pos := player_chunk + Vector2i(x, y)
            var distance := player_chunk.distance_to(chunk_pos)
            
            if distance <= GENERATION_RADIUS and chunk_pos not in loaded_chunks:
                _queue_chunk_generation(chunk_pos)

func _queue_chunk_generation(chunk_pos: Vector2i) -> void:
    if chunk_pos in generating_chunks:
        return  # Already queued
    
    generating_chunks.append(chunk_pos)

func _process_generation_queue() -> void:
    # Generate 1 chunk per frame to avoid frame drops
    if generating_chunks.size() == 0:
        return
    
    var chunk_pos := generating_chunks.pop_front()
    var chunk := _generate_chunk(chunk_pos)
    loaded_chunks[chunk_pos] = chunk
    
    # Update render (delegate to Grid)
    Grid.load_chunk(chunk)

func _generate_chunk(chunk_pos: Vector2i) -> Chunk:
    # Determine which island this chunk belongs to
    var island_id: int
    if chunk_pos in island_manager.chunk_to_island:
        island_id = island_manager.chunk_to_island[chunk_pos]
    else:
        # Generate new island
        var island := island_manager.generate_island(chunk_pos, world_seed)
        island_id = island.island_id
    
    # Get border connections from island manager
    var border_connections := island_manager.get_chunk_connections(chunk_pos)
    
    # Generate maze data
    var data := generator.generate_chunk_maze(chunk_pos, island_id, world_seed, border_connections)
    
    # Create chunk object
    var chunk := Chunk.new()
    chunk.position = chunk_pos
    chunk.data = data
    chunk.island_id = island_id
    chunk.state = Chunk.State.LOADED
    chunk.last_access_time = Time.get_ticks_msec()
    
    return chunk

func _unload_distant_chunks() -> void:
    if loaded_chunks.size() <= MAX_LOADED_CHUNKS:
        return
    
    var player_chunk := tile_to_chunk(PlayerManager.get_position())
    var chunks_to_unload: Array[Vector2i] = []
    
    for chunk_pos in loaded_chunks.keys():
        var distance := player_chunk.distance_to(chunk_pos)
        if distance > UNLOAD_RADIUS:
            chunks_to_unload.append(chunk_pos)
    
    # Unload oldest chunks first
    chunks_to_unload.sort_custom(func(a, b): 
        return loaded_chunks[a].last_access_time < loaded_chunks[b].last_access_time
    )
    
    for chunk_pos in chunks_to_unload:
        _unload_chunk(chunk_pos)
        
        # Stop if we're back under limit
        if loaded_chunks.size() <= MAX_LOADED_CHUNKS * 0.8:
            break

func _unload_chunk(chunk_pos: Vector2i) -> void:
    var chunk: Chunk = loaded_chunks[chunk_pos]
    
    # TODO: Save chunk state if modified (entities killed, items picked up, etc.)
    
    # Remove from render
    Grid.unload_chunk(chunk)
    
    # Remove from memory
    loaded_chunks.erase(chunk_pos)
```

### 4.2 Chunk Class

```gdscript
class_name Chunk extends RefCounted
## Represents a single chunk of the world

enum State {
    UNGENERATED,
    GENERATING,
    LOADED,
    UNLOADING
}

var position: Vector2i
var data: Array[Array]  # CHUNK_SIZE x CHUNK_SIZE tile types
var state: State = State.UNGENERATED
var island_id: int = -1
var entities: Array[int] = []  # Entity IDs in this chunk
var last_access_time: float = 0.0
var connections: Array[Vector2i] = []  # Connected chunk positions
var metadata: Dictionary = {}  # Light positions, decorations, etc.

func get_tile(local_pos: Vector2i) -> int:
    if local_pos.x < 0 or local_pos.x >= data[0].size():
        return -1
    if local_pos.y < 0 or local_pos.y >= data.size():
        return -1
    return data[local_pos.y][local_pos.x]

func set_tile(local_pos: Vector2i, tile_type: int) -> void:
    if local_pos.x < 0 or local_pos.x >= data[0].size():
        return
    if local_pos.y < 0 or local_pos.y >= data.size():
        return
    data[local_pos.y][local_pos.x] = tile_type
```

### 4.3 Spatial Hash for Entity Queries

```gdscript
class_name EntitySpatialHash extends Node
## Efficient entity location queries

var entity_positions: Dictionary = {}  # entity_id -> Vector2i (tile pos)
var chunk_entities: Dictionary = {}    # Vector2i (chunk pos) -> Array[entity_id]

func add_entity(entity_id: int, tile_pos: Vector2i) -> void:
    entity_positions[entity_id] = tile_pos
    
    var chunk_pos := ChunkManager.tile_to_chunk(tile_pos)
    if chunk_pos not in chunk_entities:
        chunk_entities[chunk_pos] = []
    chunk_entities[chunk_pos].append(entity_id)

func move_entity(entity_id: int, new_tile_pos: Vector2i) -> void:
    # Remove from old chunk
    var old_tile_pos: Vector2i = entity_positions.get(entity_id, Vector2i(-1, -1))
    if old_tile_pos != Vector2i(-1, -1):
        var old_chunk := ChunkManager.tile_to_chunk(old_tile_pos)
        if old_chunk in chunk_entities:
            chunk_entities[old_chunk].erase(entity_id)
    
    # Add to new chunk
    add_entity(entity_id, new_tile_pos)

func get_entities_in_radius(center: Vector2i, radius: int) -> Array[int]:
    var results: Array[int] = []
    var center_chunk := ChunkManager.tile_to_chunk(center)
    
    # Check all chunks that could contain entities in radius
    var chunk_radius := ceili(float(radius) / ChunkManager.CHUNK_SIZE)
    
    for y in range(-chunk_radius, chunk_radius + 1):
        for x in range(-chunk_radius, chunk_radius + 1):
            var chunk_pos := center_chunk + Vector2i(x, y)
            if chunk_pos in chunk_entities:
                for entity_id in chunk_entities[chunk_pos]:
                    var entity_pos: Vector2i = entity_positions[entity_id]
                    if center.distance_to(entity_pos) <= radius:
                        results.append(entity_id)
    
    return results
```

---

## 5. Entity Integration

### 5.1 Entity Spawning Distribution

```gdscript
class_name EntitySpawner extends Node

func spawn_entities_in_chunk(chunk: Chunk) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = ChunkManager._chunk_seed(chunk.position, ChunkManager.world_seed) + 12345
    
    # Get island difficulty tier
    var island: MazeIsland = ChunkManager.island_manager.islands[chunk.island_id]
    var difficulty := island.difficulty_tier
    
    # Spawn density increases with difficulty
    var spawn_count := rng.randi_range(1 + difficulty, 5 + difficulty * 2)
    
    for i in range(spawn_count):
        var spawn_pos := _find_valid_spawn_position(chunk, rng)
        if spawn_pos == Vector2i(-1, -1):
            continue  # No valid position
        
        var entity_type := _choose_entity_type(difficulty, rng)
        var entity := EntityFactory.create_entity(entity_type, spawn_pos)
        
        # Register with spatial hash
        EntitySpatialHash.add_entity(entity.id, spawn_pos)
        chunk.entities.append(entity.id)

func _find_valid_spawn_position(chunk: Chunk, rng: RandomNumberGenerator) -> Vector2i:
    # Try random floor tiles
    for attempt in range(20):
        var local_x := rng.randi_range(0, ChunkManager.CHUNK_SIZE - 1)
        var local_y := rng.randi_range(0, ChunkManager.CHUNK_SIZE - 1)
        
        if chunk.data[local_y][local_x] == ChunkMazeGenerator.TILE_FLOOR:
            # Convert to world position
            var world_pos := ChunkManager.chunk_to_world(chunk.position)
            return world_pos + Vector2i(local_x, local_y)
    
    return Vector2i(-1, -1)  # Failed to find position
```

### 5.2 Multi-Island Pathfinding

```gdscript
class_name CrossIslandPathfinder

# A* pathfinding that can traverse island connections
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
    # Check if start and goal are on same island
    var start_chunk := ChunkManager.tile_to_chunk(start)
    var goal_chunk := ChunkManager.tile_to_chunk(goal)
    
    var start_island := ChunkManager.island_manager.chunk_to_island.get(start_chunk, -1)
    var goal_island := ChunkManager.island_manager.chunk_to_island.get(goal_chunk, -1)
    
    if start_island == goal_island:
        # Simple A* within island
        return _astar_pathfind(start, goal)
    else:
        # Multi-island pathfinding
        return _multi_island_pathfind(start, goal, start_island, goal_island)

func _multi_island_pathfind(start: Vector2i, goal: Vector2i, start_island: int, goal_island: int) -> Array[Vector2i]:
    # 1. Find island-to-island path using island graph
    var island_path := _find_island_path(start_island, goal_island)
    
    if island_path.size() == 0:
        return []  # No path between islands
    
    # 2. Path through each island segment
    var full_path: Array[Vector2i] = []
    var current_pos := start
    
    for i in range(island_path.size() - 1):
        var from_island: int = island_path[i]
        var to_island: int = island_path[i + 1]
        
        # Find connection door
        var connection := _find_connection(from_island, to_island)
        var door_pos := connection.door_position
        
        # Path from current_pos to door
        var segment := _astar_pathfind(current_pos, door_pos)
        full_path.append_array(segment)
        
        current_pos = door_pos
    
    # Final segment to goal
    var final_segment := _astar_pathfind(current_pos, goal)
    full_path.append_array(final_segment)
    
    return full_path
```

---

## 6. Performance Optimization

### 6.1 Memory Budget

```
Target: 50 loaded chunks max
├── Tile data: 50 chunks × 1KB = 50KB
├── Entity data: ~200 entities × 100 bytes = 20KB
├── Spatial hash: ~5KB
└── Total: ~75KB (negligible for modern systems)
```

### 6.2 Generation Performance

```gdscript
# Time budget per frame: 16.67ms (60fps) → allocate 2ms for generation
const GENERATION_TIME_BUDGET_MS := 2.0

func _process_generation_queue_with_budget() -> void:
    var start_time := Time.get_ticks_msec()
    
    while generating_chunks.size() > 0:
        var chunk_pos := generating_chunks.pop_front()
        var chunk := _generate_chunk(chunk_pos)
        loaded_chunks[chunk_pos] = chunk
        Grid.load_chunk(chunk)
        
        # Check time budget
        var elapsed := Time.get_ticks_msec() - start_time
        if elapsed >= GENERATION_TIME_BUDGET_MS:
            break  # Continue next frame
```

### 6.3 Render Optimization (Building on Current System)

```gdscript
# Current Grid system already has viewport culling
# Extend it to work with chunks

func load_chunk(chunk: Chunk) -> void:
    var world_origin := ChunkManager.chunk_to_world(chunk.position)
    
    for y in range(ChunkManager.CHUNK_SIZE):
        for x in range(ChunkManager.CHUNK_SIZE):
            var tile_pos := world_origin + Vector2i(x, y)
            var tile_type: int = chunk.data[y][x]
            
            # Only render if in viewport
            if _is_in_viewport(tile_pos):
                _create_tile(tile_pos, tile_type)

func unload_chunk(chunk: Chunk) -> void:
    var world_origin := ChunkManager.chunk_to_world(chunk.position)
    
    for y in range(ChunkManager.CHUNK_SIZE):
        for x in range(ChunkManager.CHUNK_SIZE):
            var tile_pos := world_origin + Vector2i(x, y)
            
            if tile_pos in rendered_tiles:
                rendered_tiles[tile_pos].queue_free()
                rendered_tiles.erase(tile_pos)
```

---

## 7. Backrooms Aesthetic Integration

### 7.1 Visual Theming

```gdscript
# Chunk metadata includes visual variation within monotony
class ChunkMetadata:
    var light_positions: Array[Vector2i] = []
    var light_flicker_patterns: Array[float] = []
    var wall_tint_variation: float = 0.0  # Slight hue shift
    var ceiling_height: float = 8.0  # Occasional variation
    var carpet_wear_level: float = 0.5  # Texture variation

func _generate_chunk_aesthetics(chunk: Chunk, rng: RandomNumberGenerator) -> void:
    var metadata := ChunkMetadata.new()
    
    # Place lights on ceiling (every 4-6 tiles)
    for y in range(0, ChunkManager.CHUNK_SIZE, rng.randi_range(4, 6)):
        for x in range(0, ChunkManager.CHUNK_SIZE, rng.randi_range(4, 6)):
            if chunk.data[y][x] == ChunkMazeGenerator.TILE_FLOOR:
                metadata.light_positions.append(Vector2i(x, y))
                metadata.light_flicker_patterns.append(rng.randf_range(0.8, 1.0))
    
    # Subtle wall color variation (still yellow, but not identical)
    metadata.wall_tint_variation = rng.randf_range(-0.05, 0.05)
    
    # Occasional ceiling height variation
    if rng.randf() < 0.1:
        metadata.ceiling_height = rng.randf_range(6.0, 10.0)
    
    chunk.metadata["aesthetics"] = metadata
```

### 7.2 Liminal Space Design Principles

```gdscript
# Enforce Backrooms aesthetic rules during generation

# Rule 1: Long, straight corridors (low branching)
const MIN_CORRIDOR_LENGTH := 8
const MAX_BRANCHING_FACTOR := 0.3  # 30% chance of branch

# Rule 2: Occasional rooms for contrast
const ROOM_CHANCE := 0.2  # 20% chance per chunk
const ROOM_SIZE_RANGE := Vector2i(4, 8)

# Rule 3: Mostly empty (sparse entity placement)
const ENTITY_DENSITY_LOW := 0.1  # Entities per tile
const ENTITY_DENSITY_HIGH := 0.3  # In high-difficulty islands

# Rule 4: Monotonous but not identical
const WALL_COLOR_BASE := Color(0.84, 0.81, 0.58)  # Classic yellow
const WALL_COLOR_VARIATION := 0.05  # Slight variation
const LIGHT_COLOR_BASE := Color(1.0, 0.95, 0.8)  # Fluorescent white
```

---

## 8. Phased Implementation Plan

### Phase 1: Core Chunk System (Week 1)
**Goal**: Replace static 128x128 grid with dynamic chunk loading

1. **Implement ChunkManager singleton**
   - Chunk loading/unloading based on player position
   - Simple placeholder maze (just walls on edges)
   - Coordinate conversion utilities

2. **Extend Grid class for chunk rendering**
   - `load_chunk()` and `unload_chunk()` methods
   - Update `render_around_position()` to work with chunks

3. **Test with player movement**
   - Verify chunks load as player moves
   - Verify chunks unload when player leaves
   - Monitor memory usage

**Success Criteria:**
- Player can walk indefinitely in any direction
- Chunks load/unload smoothly without frame drops
- Memory stays under 100KB for 50 chunks

---

### Phase 2: Maze Generation (Week 2)
**Goal**: Generate actual Backrooms-style mazes in each chunk

1. **Implement ChunkMazeGenerator**
   - Recursive backtracking algorithm
   - Chunk seed generation (FNV hash)
   - Border connection handling

2. **Test maze quality**
   - Verify long corridors
   - Check for completeness (no unreachable areas)
   - Validate determinism (same seed = same maze)

3. **Add room placement**
   - Random room generation
   - Room-to-corridor connection

**Success Criteria:**
- Every chunk generates a unique, walkable maze
- Corridors are long and low-branching
- Occasional rooms break monotony
- Regenerating same chunk produces identical maze

---

### Phase 3: Island System (Week 3)
**Goal**: Group chunks into maze islands with connections

1. **Implement IslandManager**
   - Island generation and size determination
   - Chunk-to-island mapping
   - Island connection detection

2. **Implement island connections**
   - Door placement between islands
   - Connection metadata in chunks
   - Visual distinction for doors

3. **Test island traversal**
   - Walk from one island to another
   - Verify doors align correctly
   - Check connection pathfinding

**Success Criteria:**
- Multiple distinct islands generate
- Islands connect via doors
- Player can traverse between islands
- Islands have visual identity

---

### Phase 4: Entity Integration (Week 4)
**Goal**: Spawn entities in chunks and enable cross-island movement

1. **Implement EntitySpatialHash**
   - Entity position tracking
   - Chunk-based entity queries
   - Entity movement updates

2. **Implement EntitySpawner**
   - Spawn entities when chunk loads
   - Remove entities when chunk unloads
   - Difficulty-based spawn density

3. **Update entity AI for chunks**
   - Check entity chunk on movement
   - Update spatial hash on move
   - Cross-island pathfinding

**Success Criteria:**
- Entities spawn in loaded chunks
- Entities are removed when chunks unload
- Entity pathfinding works across islands
- `get_entities_in_radius()` is performant

---

### Phase 5: Aesthetic & Polish (Week 5)
**Goal**: Add Backrooms visual theming and atmospheric details

1. **Chunk aesthetic metadata**
   - Light placement and flicker
   - Wall color variation
   - Ceiling height variation

2. **Visual enhancements**
   - Update tile rendering with color variation
   - Add decorative elements
   - Implement corruption shaders (future)

3. **Performance optimization**
   - Profile generation time
   - Optimize spatial hash queries
   - Tune chunk loading parameters

**Success Criteria:**
- Chunks feel like Backrooms (monotonous but unsettling)
- No frame drops during generation
- Visual variety without breaking aesthetic

---

### Phase 6: Persistence & Save System (Future)
**Goal**: Save modified chunks and world state

1. **Chunk modification tracking**
   - Mark chunks as "modified" if player changes them
   - Track killed entities, picked up items, etc.

2. **Save/load system**
   - Serialize modified chunks to disk
   - Load modified chunks instead of regenerating
   - Clear old save data when starting new run

3. **World seed management**
   - Save seed with game state
   - Allow seed input for consistent worlds

---

## 9. Code Examples

### Example: Full Chunk Generation Flow

```gdscript
# User code (called when player moves)
func on_player_moved(new_tile_pos: Vector2i) -> void:
    ChunkManager.update_chunks_around_player(new_tile_pos)

# ChunkManager._process()
func _process(delta: float) -> void:
    var player_chunk := tile_to_chunk(PlayerManager.get_position())
    
    # Queue generation for chunks in radius
    for y in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
        for x in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
            var chunk_pos := player_chunk + Vector2i(x, y)
            if chunk_pos.distance_to(player_chunk) <= GENERATION_RADIUS:
                if chunk_pos not in loaded_chunks and chunk_pos not in generating_chunks:
                    generating_chunks.append(chunk_pos)
    
    # Generate one chunk per frame
    if generating_chunks.size() > 0:
        var chunk_pos := generating_chunks.pop_front()
        var chunk := _generate_chunk(chunk_pos)
        loaded_chunks[chunk_pos] = chunk
        Grid.load_chunk(chunk)
        
        # Spawn entities
        EntitySpawner.spawn_entities_in_chunk(chunk)

# ChunkMazeGenerator.generate_chunk_maze()
func generate_chunk_maze(chunk_pos: Vector2i, island_id: int, seed_value: int, border_connections: Dictionary) -> Array[Array]:
    var rng := RandomNumberGenerator.new()
    rng.seed = _chunk_seed(chunk_pos, seed_value)
    
    # 1. Initialize grid (all walls)
    var data := []
    for y in range(CHUNK_SIZE):
        var row := []
        for x in range(CHUNK_SIZE):
            row.append(TILE_WALL)
        data.append(row)
    
    # 2. Carve maze using recursive backtracking
    var stack: Array[Vector2i] = []
    var start := Vector2i(1, 1)  # Start in corner
    stack.push_back(start)
    data[start.y][start.x] = TILE_FLOOR
    
    while stack.size() > 0:
        var current := stack.back()
        var neighbors := _get_unvisited_neighbors(current, data)
        
        if neighbors.size() > 0:
            var next := neighbors[rng.randi() % neighbors.size()]
            var between := (current + next) / 2
            
            data[next.y][next.x] = TILE_FLOOR
            data[between.y][between.x] = TILE_FLOOR
            
            stack.push_back(next)
        else:
            stack.pop_back()
    
    # 3. Add border connections (doors)
    for connection in border_connections.values():
        var door_pos: Vector2i = connection.door_position
        data[door_pos.y][door_pos.x] = TILE_DOOR
    
    # 4. Occasional rooms
    if rng.randf() < 0.2:
        _carve_room(data, rng)
    
    return data
```

### Example: Entity Query for Combat

```gdscript
# Find all entities within attack range
func get_targets_in_range(attacker_pos: Vector2i, range: int) -> Array[Entity]:
    var entity_ids := EntitySpatialHash.get_entities_in_radius(attacker_pos, range)
    
    var targets: Array[Entity] = []
    for entity_id in entity_ids:
        var entity := EntityManager.get_entity(entity_id)
        if entity and entity.is_hostile():
            targets.append(entity)
    
    return targets
```

### Example: Cross-Island Pathfinding

```gdscript
# AI entity wants to chase player across islands
func chase_player() -> void:
    var entity_pos := self.grid_position
    var player_pos := PlayerManager.get_position()
    
    var path := CrossIslandPathfinder.find_path(entity_pos, player_pos)
    
    if path.size() > 1:
        var next_step := path[1]  # path[0] is current position
        move_to(next_step)
```

---

## 10. Diagrams

### Chunk Layout Diagram

```
World Coordinates (tile positions):
    
    0        32       64       96      128
    ├────────┼────────┼────────┼────────┤
 0  │ (0,0)  │ (1,0)  │ (2,0)  │ (3,0)  │
    │ Chunk  │ Chunk  │ Chunk  │ Chunk  │
    ├────────┼────────┼────────┼────────┤
32  │ (0,1)  │ (1,1)  │ (2,1)  │ (3,1)  │
    │ Chunk  │ Chunk  │ Chunk  │ Chunk  │
    ├────────┼────────┼────────┼────────┤
64  │ (0,2)  │ (1,2)  │ (2,2)  │ (3,2)  │
    │ Chunk  │ Chunk  │ Chunk  │ Chunk  │
    ├────────┼────────┼────────┼────────┤
96  │ (0,3)  │ (1,3)  │ (2,3)  │ (3,3)  │
    │ Chunk  │ Chunk  │ Chunk  │ Chunk  │
    └────────┴────────┴────────┴────────┘

Each chunk: 32x32 tiles
Chunk (1,1) contains tiles (32,32) to (63,63)
```

### Maze Pattern Example (Single Chunk)

```
32x32 Chunk Interior (█ = wall, · = floor, ═ = door to adjacent chunk):

█████████████████████████████████
█··········█············█·······█
█·█████████·████████████·████████
█·█·········█···········█·······█
█·█·█████████·█████████·████·████
█·█·█·······█·█·········█····█··█
█·█·█·█████·█·█·█████████·██·█·██
█·█···█·····█···█·······█·█··█·█═ ← Door to chunk (2,1)
█·█████·█████████·█████·█·█·██·██
█·······█·········█·····█···█···█
█·███████·█████████·█████████·█·█
█·█·······█·········█·········█·█
█·█·███████·█████████·█████████·█
█···█·······█·········█·········█
█████·███████·█████████·█████████
█·····█·······█·········█·······█
█·█████·█████·█·█████████·█████·█
█·█·····█·····█·█·········█·····█
█·█·█████·█████·█·█████████·███·█
█·█·█·····█·····█·█·········█···█
█·█·█·█████·█████·█·█████████·███
█·█·█·█·····█·····█·█·········█·█
█·█·█·█·█████·█████·█·█████████·█
█·█···█·█·····█·····█·█·········█
█·█████·█·█████·█████·█·█████████
█·······█·······█·····█·········█
█·███████·███████·█████·███████·█
█·█·······█·······█·····█·······█
█·█·█████·█·█████·█·█████·█████·█
█·█·█·····█·█·····█·█·····█·····█
█·█·█·█████·█·█████·█·█████·█████
█···█···················█·······█
█████████████████████████████████

Note: Long corridors, low branching, occasional wider areas
```

### Island Connection Diagram

```
Island A (3x3 chunks)          Island B (2x4 chunks)
┌─────┬─────┬─────┐           ┌─────┬─────┐
│     │     │     │           │     │     │
│     │     │     │           │     │     │
├─────┼─────┼─────┤           ├─────┼─────┤
│     │     │     │           │     │     │
│     │  P  │     │═══════════│     │     │ ← Door connection
├─────┼─────┼─────┤   (door)  ├─────┼─────┤
│     │     │     │           │     │     │
│     │     │     │           │     │     │
└─────┴─────┴─────┘           ├─────┼─────┤
                               │     │     │
                               │     │     │
                               └─────┴─────┘

Island C (2x2 chunks)
┌─────┬─────┐
│     │     │
│     │     │
├─────┼─────┤
│     │     │
│     │     │
└─────┴─────┘

Islands A and B are connected (entities can path between them)
Island C is isolated (requires progression/discovery to connect)
```

---

## 11. Future Enhancements

### Dynamic Island Connection
- Islands start isolated, player discovers connection items/abilities
- "Noclipping" mechanic to phase through walls and access new islands

### Island Themes
- Islands have visual/gameplay variations
- "Office" island: classic yellow, low difficulty
- "Industrial" island: darker, hazards, higher difficulty
- "Corrupted" island: glitch effects, reality-bending

### Procedural Lore
- Generate SCP-style "incident reports" based on island seed
- Discovered documents reference specific room layouts
- Knowledge database entries reference actual generated features

### Advanced Physics Integration
- Liquid spreading across chunk boundaries
- Temperature gradients between islands
- Fire propagation (chunk-aware)

---

## Conclusion

This chunk-based "island of mazes" system provides:
- **Infinite exploration** without memory constraints
- **Backrooms aesthetic** with long corridors and monotonous yellow hallways
- **Island structure** for varied difficulty and themed areas
- **Performance** via lazy loading and spatial hashing
- **Determinism** via seed-based generation
- **Extensibility** for future features (persistence, themes, progression)

The system builds on the existing turn-based, grid-based architecture while enabling limitless procedural generation. Each component (ChunkManager, MazeGenerator, IslandManager) is modular and testable, following the project's deliberate, quality-focused development philosophy.

---

**Ready for Phase 1 implementation. Test chunk loading before proceeding to maze generation.**
