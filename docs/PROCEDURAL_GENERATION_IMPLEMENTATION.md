# Procedural Generation Implementation Plan

**Project**: Backrooms Power Crawl
**Feature**: Level 0 Procedural Generation with Corruption System
**Status**: Planning Complete, Ready for Implementation
**Created**: 2025-01-14
**Branch**: `feature/procedural-generation`

---

## Overview

This document outlines the implementation of the procedural generation system for Backrooms Power Crawl. The system uses a chunk-based architecture with probabilistic entity spawning and a corruption escalation mechanic.

### Key Design Principles

1. **Chunk-Based Architecture**: 128×128 tile chunks divided into 64 sub-chunks (16×16 each)
2. **Probabilistic Everything**: All entities (enemies, NPCs, structures, exits, items) spawn based on probability rolls
3. **Corruption Escalation**: Per-level corruption increases as chunks load, modifying spawn probabilities
4. **Exit Forcing Mechanic**: Exits become MORE common with corruption, forcing player to eventually move on
5. **Per-Level Configuration**: Each Backrooms level has distinct generation rules and entity pools
6. **Within-Run Persistence**: Chunks persist in memory for the current run only

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│               CHUNK & ENTITY SPAWNING SYSTEM                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  CHUNK STRUCTURE:                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Chunk (128×128 tiles)                                │  │
│  │ ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐  │  │
│  │ │16×16│16×16│16×16│16×16│16×16│16×16│16×16│16×16│  │  │
│  │ ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤  │  │
│  │ │16×16│16×16│16×16│16×16│16×16│16×16│16×16│16×16│  │  │
│  │ ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤  │  │
│  │ │16×16│16×16│16×16│16×16│16×16│16×16│16×16│16×16│  │  │
│  │ ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤  │  │
│  │ │ ... │ ... │ ... │ ... │ ... │ ... │ ... │ ... │  │  │
│  │ └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘  │  │
│  │ Total: 64 sub-chunks per chunk (8×8 grid)           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  CORRUPTION SYSTEM:                                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ CorruptionTracker                                    │  │
│  │ - Per-level corruption value                         │  │
│  │ - Increases by N per chunk loaded                    │  │
│  │ - Modifies entity spawn probabilities                │  │
│  │                                                       │  │
│  │ Formula:                                             │  │
│  │ final_prob = base_prob × (1 + corruption × mult)    │  │
│  │                                                       │  │
│  │ Example (Enemy - gets MORE common):                  │  │
│  │ - base=0.05, mult=1.5, corruption=5                  │  │
│  │   → final = 0.05 × (1 + 5×1.5) = 0.425 (42.5%)      │  │
│  │                                                       │  │
│  │ Example (Exit - gets MORE common, forces exit):      │  │
│  │ - base=0.001, mult=2.0, corruption=5                 │  │
│  │   → final = 0.001 × (1 + 5×2.0) = 0.011 (1.1%)      │  │
│  │                                                       │  │
│  │ Example (Item - gets LESS common):                   │  │
│  │ - base=0.05, mult=-0.3, corruption=5                 │  │
│  │   → final = 0.05 × (1 + 5×-0.3) = 0.0125 (1.25%)    │  │
│  │   (clamped to 0 if negative)                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Level 0 Configuration

### Generation Parameters

```gdscript
class_name Level0Generator extends LevelGenerator
## Generates Backrooms Level 0 - Endless Yellow Hallways

func get_level_config() -> Dictionary:
    return {
        "name": "Level 0",
        "theme": "yellow_office",

        # Maze generation parameters
        "maze_generation": {
            "corridor_length": Vector2i(5, 12),  # Long hallways
            "corridor_width": 1,  # Single tile wide
            "room_chance": 0.15,  # 15% chance per sub-chunk
            "room_size_range": Vector2i(4, 8),
            "branching_factor": 0.25,  # Low branching for monotony
        },

        # Corruption mechanics
        "corruption": {
            "base_value": 0.0,
            "increase_per_chunk": 0.1,  # Slow escalation
            "max_value": 10.0,
        },

        # Permitted entities with spawn probabilities
        "permitted_entities": {
            # Hostile entities - get MORE common with corruption
            "enemies": [
                {
                    "type": "smiler",
                    "base_probability": 0.05,  # 5% per sub-chunk
                    "corruption_multiplier": 1.5,  # Gets MORE common
                },
                {
                    "type": "hound",
                    "base_probability": 0.03,  # 3% per sub-chunk
                    "corruption_multiplier": 2.0,  # Gets MUCH more common
                },
            ],

            # Neutral/friendly NPCs - get LESS common with corruption
            "npcs": [
                {
                    "type": "wanderer",
                    "base_probability": 0.01,  # 1% per sub-chunk
                    "corruption_multiplier": -0.5,  # Gets LESS common
                },
            ],

            # Environmental structures
            "structures": [
                {
                    "type": "fluorescent_light",
                    "base_probability": 0.8,  # 80% per sub-chunk (common)
                    "corruption_multiplier": -0.1,  # Slightly less common
                },
                {
                    "type": "broken_light",
                    "base_probability": 0.05,  # 5% per sub-chunk
                    "corruption_multiplier": 1.2,  # More common with corruption
                },
            ],

            # Level exits - get MORE common with corruption (forces exit!)
            "exits": [
                {
                    "type": "stairs_to_level_1",
                    "base_probability": 0.001,  # 0.1% per sub-chunk (very rare!)
                    "corruption_multiplier": 2.0,  # Gets MORE common (FORCES exit)
                    # At corruption 5: 0.001 × (1 + 5×2.0) = 0.011 (1.1%)
                    # At corruption 10: 0.001 × (1 + 10×2.0) = 0.021 (2.1%)
                },
            ],

            # Items for player - get LESS common with corruption
            "items": [
                {
                    "type": "almond_water",
                    "base_probability": 0.05,  # 5% per sub-chunk
                    "corruption_multiplier": -0.3,  # Gets less common
                },
                {
                    "type": "flashlight",
                    "base_probability": 0.02,  # 2% per sub-chunk
                    "corruption_multiplier": -0.4,  # Gets much less common
                },
            ],
        },
    }
```

### Exit Rarity Progression

**Goal**: Player explores, corruption rises, exits become more common, forcing eventual progression.

| Corruption | Chunks Loaded | Exit Probability | Expected Exits in 576 Sub-chunks |
|------------|---------------|------------------|----------------------------------|
| 0.0        | 0             | 0.1%             | 0.58 (~50% chance of finding one)|
| 2.0        | 20            | 0.5%             | 2.88 (likely found one)          |
| 5.0        | 50            | 1.1%             | 6.34 (multiple exits available)  |
| 10.0       | 100           | 2.1%             | 12.1 (exits everywhere - GTFO!)  |

**Design Intent**:
- Early game: Exits are rare, player can explore freely
- Mid game: Exits start appearing, player has choice
- Late game: Exits common, overwhelming pressure to leave

---

## Data Structures

### SubChunk

```gdscript
class_name SubChunk extends RefCounted
## Represents a 16×16 tile section within a chunk

const SIZE := 16

var local_position: Vector2i  # Position within parent chunk (0-7, 0-7)
var world_position: Vector2i  # Absolute tile position
var tile_data: Array[Array]  # 16×16 tile types
var entities: Array[int] = []  # Entity IDs spawned here

func get_tile(local_pos: Vector2i) -> int:
    if local_pos.x < 0 or local_pos.x >= SIZE:
        return -1
    if local_pos.y < 0 or local_pos.y >= SIZE:
        return -1
    return tile_data[local_pos.y][local_pos.x]

func set_tile(local_pos: Vector2i, tile_type: int) -> void:
    if local_pos.x < 0 or local_pos.x >= SIZE:
        return
    if local_pos.y < 0 or local_pos.y >= SIZE:
        return
    tile_data[local_pos.y][local_pos.x] = tile_type

func get_random_walkable_position(rng: RandomNumberGenerator) -> Vector2i:
    """Get random walkable tile in this sub-chunk"""
    var walkable: Array[Vector2i] = []
    for y in range(SIZE):
        for x in range(SIZE):
            if tile_data[y][x] == 0:  # TILE_FLOOR
                walkable.append(Vector2i(x, y))

    if walkable.is_empty():
        return Vector2i(-1, -1)

    return walkable[rng.randi() % walkable.size()]
```

### Chunk

```gdscript
class_name Chunk extends RefCounted
## Represents a 128×128 tile chunk (8×8 sub-chunks)

const SIZE := 128
const SUB_CHUNK_SIZE := 16
const SUB_CHUNKS_PER_SIDE := 8  # 128 / 16 = 8

var position: Vector2i  # Chunk coordinates
var level_id: int = 0  # Which Backrooms level
var island_id: int = -1  # Which maze island
var sub_chunks: Array[SubChunk] = []  # 64 sub-chunks
var metadata: Dictionary = {}  # Light positions, etc.

func _init():
    # Initialize 64 sub-chunks (8×8 grid)
    for sy in range(SUB_CHUNKS_PER_SIDE):
        for sx in range(SUB_CHUNKS_PER_SIDE):
            var sub := SubChunk.new()
            sub.local_position = Vector2i(sx, sy)
            sub.world_position = position * SIZE + Vector2i(sx, sy) * SUB_CHUNK_SIZE
            sub_chunks.append(sub)

func get_sub_chunk(local_pos: Vector2i) -> SubChunk:
    """Get sub-chunk at local position (0-7, 0-7)"""
    if local_pos.x < 0 or local_pos.x >= SUB_CHUNKS_PER_SIDE:
        return null
    if local_pos.y < 0 or local_pos.y >= SUB_CHUNKS_PER_SIDE:
        return null
    var index := local_pos.y * SUB_CHUNKS_PER_SIDE + local_pos.x
    return sub_chunks[index]

func get_sub_chunk_at_tile(tile_pos: Vector2i) -> SubChunk:
    """Get sub-chunk containing a specific tile"""
    var local_tile := tile_pos - (position * SIZE)
    var sub_local := Vector2i(
        local_tile.x / SUB_CHUNK_SIZE,
        local_tile.y / SUB_CHUNK_SIZE
    )
    return get_sub_chunk(sub_local)

func get_tile(tile_pos: Vector2i) -> int:
    """Get tile at world position"""
    var sub := get_sub_chunk_at_tile(tile_pos)
    if not sub:
        return -1

    var local_tile := tile_pos - (position * SIZE)
    var sub_local_tile := Vector2i(
        local_tile.x % SUB_CHUNK_SIZE,
        local_tile.y % SUB_CHUNK_SIZE
    )
    return sub.get_tile(sub_local_tile)
```

### CorruptionTracker

```gdscript
class_name CorruptionTracker extends RefCounted
## Tracks per-level corruption escalation

var corruption_by_level: Dictionary = {}  # level_id -> float

func increase_corruption(level_id: int, amount: float, max_value: float) -> void:
    """Increase corruption for a level"""
    var current := corruption_by_level.get(level_id, 0.0)
    corruption_by_level[level_id] = minf(current + amount, max_value)

    Log.turn("Corruption increased on Level %d: %.2f" % [
        level_id,
        corruption_by_level[level_id]
    ])

func get_corruption(level_id: int) -> float:
    """Get current corruption value for a level"""
    return corruption_by_level.get(level_id, 0.0)

func calculate_spawn_probability(
    base_prob: float,
    multiplier: float,
    corruption: float
) -> float:
    """Calculate final spawn probability with corruption modifier

    Formula: final_prob = base_prob × (1 + corruption × multiplier)

    - Positive multiplier: probability increases with corruption
    - Negative multiplier: probability decreases with corruption
    - Result is clamped to [0.0, 1.0]
    """
    var final := base_prob * (1.0 + corruption * multiplier)
    return clampf(final, 0.0, 1.0)

func reset_level(level_id: int) -> void:
    """Reset corruption for a level (new run)"""
    corruption_by_level.erase(level_id)

func reset_all() -> void:
    """Reset all corruption (new run)"""
    corruption_by_level.clear()
```

---

## Core Systems

### ChunkManager (Autoload Singleton)

```gdscript
extends Node
## Manages chunk loading, unloading, and corruption escalation
##
## Responsibilities:
## - Load chunks near player
## - Unload distant chunks
## - Increase corruption per chunk loaded
## - Coordinate with generators and spawners
## - Track chunks per level

# Constants
const CHUNK_SIZE := 128
const ACTIVE_RADIUS := 3  # Chunks to keep loaded around player
const GENERATION_RADIUS := 5  # Chunks to pre-generate
const UNLOAD_RADIUS := 8  # Chunks to unload
const MAX_LOADED_CHUNKS := 50

# State
var loaded_chunks: Dictionary = {}  # Vector3i(x, y, level) -> Chunk
var generating_chunks: Array[Vector3i] = []
var world_seed: int = 0

# Systems
var corruption_tracker: CorruptionTracker
var island_manager: IslandManager
var entity_spawner: EntitySpawner
var level_generator_factory: LevelGeneratorFactory

func _ready() -> void:
    corruption_tracker = CorruptionTracker.new()
    island_manager = IslandManager.new()
    entity_spawner = EntitySpawner.new()
    entity_spawner.corruption_tracker = corruption_tracker
    level_generator_factory = LevelGeneratorFactory.new()

    add_child(island_manager)
    add_child(entity_spawner)

    # Generate world seed
    world_seed = randi()

    Log.system("ChunkManager initialized (seed: %d)" % world_seed)

func _process(_delta: float) -> void:
    _update_chunks_around_player()
    _process_generation_queue()
    _unload_distant_chunks()

func _update_chunks_around_player() -> void:
    """Queue chunks for loading near player"""
    var player_tile := PlayerManager.get_position()
    var player_level := LevelManager.current_level
    var player_chunk := tile_to_chunk(player_tile)

    # Queue generation for nearby chunks
    for y in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
        for x in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
            var chunk_pos := player_chunk + Vector2i(x, y)
            var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, player_level)

            if chunk_key not in loaded_chunks and chunk_key not in generating_chunks:
                generating_chunks.append(chunk_key)

func _process_generation_queue() -> void:
    """Generate one chunk per frame to avoid stuttering"""
    if generating_chunks.is_empty():
        return

    var chunk_key := generating_chunks.pop_front()
    var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
    var level_id := chunk_key.z

    var chunk := _generate_chunk(chunk_pos, level_id)
    loaded_chunks[chunk_key] = chunk

    # Notify Grid to render it
    if has_node("/root/Game/Grid"):
        get_node("/root/Game/Grid").load_chunk(chunk)

    Log.grid("Loaded chunk %s on Level %d (corruption: %.2f)" % [
        chunk_pos,
        level_id,
        corruption_tracker.get_corruption(level_id)
    ])

func _generate_chunk(chunk_pos: Vector2i, level_id: int) -> Chunk:
    """Generate a new chunk"""
    var chunk := Chunk.new()
    chunk.position = chunk_pos
    chunk.level_id = level_id

    # Get appropriate generator for this level
    var generator: LevelGenerator = level_generator_factory.get_generator(level_id)
    var level_config := generator.get_level_config()

    # Generate maze data for all sub-chunks
    generator.generate_chunk(chunk, world_seed)

    # Spawn entities based on corruption
    entity_spawner.spawn_entities_in_chunk(chunk, level_config)

    # Increase corruption AFTER chunk is generated
    var corruption_config: Dictionary = level_config["corruption"]
    corruption_tracker.increase_corruption(
        level_id,
        corruption_config["increase_per_chunk"],
        corruption_config["max_value"]
    )

    return chunk

func _unload_distant_chunks() -> void:
    """Unload chunks far from player"""
    if loaded_chunks.size() <= MAX_LOADED_CHUNKS:
        return

    var player_tile := PlayerManager.get_position()
    var player_level := LevelManager.current_level
    var player_chunk := tile_to_chunk(player_tile)

    var chunks_to_unload: Array[Vector3i] = []

    for chunk_key in loaded_chunks.keys():
        var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
        var chunk_level := chunk_key.z

        # Only unload chunks on current level
        if chunk_level != player_level:
            continue

        var distance := player_chunk.distance_to(chunk_pos)
        if distance > UNLOAD_RADIUS:
            chunks_to_unload.append(chunk_key)

    # Unload oldest chunks first (TODO: track last access time)
    for chunk_key in chunks_to_unload:
        _unload_chunk(chunk_key)

        if loaded_chunks.size() <= MAX_LOADED_CHUNKS * 0.8:
            break

func _unload_chunk(chunk_key: Vector3i) -> void:
    """Unload a chunk from memory"""
    var chunk: Chunk = loaded_chunks[chunk_key]

    # TODO: Save chunk state if modified (entities killed, items taken)

    # Remove from render
    if has_node("/root/Game/Grid"):
        get_node("/root/Game/Grid").unload_chunk(chunk)

    # Remove from memory
    loaded_chunks.erase(chunk_key)

    Log.grid("Unloaded chunk %s" % Vector2i(chunk_key.x, chunk_key.y))

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
    """Convert tile position to chunk position"""
    return Vector2i(
        floori(float(tile_pos.x) / CHUNK_SIZE),
        floori(float(tile_pos.y) / CHUNK_SIZE)
    )

func chunk_to_world(chunk_pos: Vector2i) -> Vector2i:
    """Convert chunk position to world tile position (chunk origin)"""
    return chunk_pos * CHUNK_SIZE

func tile_to_local(tile_pos: Vector2i) -> Vector2i:
    """Convert tile position to local chunk position (0-127)"""
    return Vector2i(
        posmod(tile_pos.x, CHUNK_SIZE),
        posmod(tile_pos.y, CHUNK_SIZE)
    )

# ============================================================================
# PUBLIC API
# ============================================================================

func get_chunk_at_tile(tile_pos: Vector2i, level_id: int) -> Chunk:
    """Get chunk containing a tile"""
    var chunk_pos := tile_to_chunk(tile_pos)
    var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
    return loaded_chunks.get(chunk_key, null)

func is_tile_walkable(tile_pos: Vector2i, level_id: int) -> bool:
    """Check if tile is walkable"""
    var chunk := get_chunk_at_tile(tile_pos, level_id)
    if not chunk:
        return false

    return chunk.get_tile(tile_pos) == 0  # TILE_FLOOR

func start_new_run(seed: int = -1) -> void:
    """Start a new run, clear all state"""
    if seed == -1:
        world_seed = randi()
    else:
        world_seed = seed

    loaded_chunks.clear()
    generating_chunks.clear()
    corruption_tracker.reset_all()

    Log.system("New run started (seed: %d)" % world_seed)
```

### EntitySpawner

```gdscript
class_name EntitySpawner extends Node
## Spawns entities in chunks based on level config and corruption

var corruption_tracker: CorruptionTracker

func spawn_entities_in_chunk(chunk: Chunk, level_config: Dictionary) -> void:
    """Spawn entities in all sub-chunks of this chunk"""
    var corruption := corruption_tracker.get_corruption(chunk.level_id)

    # Process each sub-chunk
    for sub_chunk in chunk.sub_chunks:
        _spawn_in_sub_chunk(sub_chunk, corruption, level_config)

func _spawn_in_sub_chunk(
    sub_chunk: SubChunk,
    corruption: float,
    level_config: Dictionary
) -> void:
    """Spawn entities in a single 16×16 sub-chunk"""
    var rng := RandomNumberGenerator.new()
    rng.randomize()  # TODO: Use chunk seed for determinism

    var permitted: Dictionary = level_config["permitted_entities"]

    # Spawn enemies
    for enemy_config in permitted.get("enemies", []):
        if _should_spawn(enemy_config, corruption, rng):
            _spawn_entity("enemy", enemy_config["type"], sub_chunk, rng)

    # Spawn NPCs
    for npc_config in permitted.get("npcs", []):
        if _should_spawn(npc_config, corruption, rng):
            _spawn_entity("npc", npc_config["type"], sub_chunk, rng)

    # Spawn structures
    for structure_config in permitted.get("structures", []):
        if _should_spawn(structure_config, corruption, rng):
            _spawn_entity("structure", structure_config["type"], sub_chunk, rng)

    # Spawn exits (RARE!)
    for exit_config in permitted.get("exits", []):
        if _should_spawn(exit_config, corruption, rng):
            _spawn_entity("exit", exit_config["type"], sub_chunk, rng)

    # Spawn items
    for item_config in permitted.get("items", []):
        if _should_spawn(item_config, corruption, rng):
            _spawn_entity("item", item_config["type"], sub_chunk, rng)

func _should_spawn(
    config: Dictionary,
    corruption: float,
    rng: RandomNumberGenerator
) -> bool:
    """Determine if entity should spawn based on probability"""
    var base_prob: float = config["base_probability"]
    var mult: float = config["corruption_multiplier"]

    var final_prob := corruption_tracker.calculate_spawn_probability(
        base_prob,
        mult,
        corruption
    )

    return rng.randf() < final_prob

func _spawn_entity(
    category: String,
    type: String,
    sub_chunk: SubChunk,
    rng: RandomNumberGenerator
) -> void:
    """Actually spawn the entity"""
    var spawn_pos := sub_chunk.get_random_walkable_position(rng)
    if spawn_pos == Vector2i(-1, -1):
        return  # No walkable tiles in this sub-chunk

    # Convert to world position
    var world_pos := sub_chunk.world_position + spawn_pos

    # Create entity (delegate to factory)
    # TODO: Implement EntityFactory
    # var entity = EntityFactory.create_entity(category, type, world_pos)
    # if entity:
    #     sub_chunk.entities.append(entity.id)

    Log.grid("Spawned %s '%s' at %s" % [category, type, world_pos])
```

---

## Implementation Phases

### Phase 1: Core Chunk System (Week 1)

**Files to Create:**
- `scripts/procedural/sub_chunk.gd`
- `scripts/procedural/chunk.gd`
- `scripts/procedural/chunk_manager.gd` (Autoload)
- `scripts/procedural/corruption_tracker.gd`

**Goals:**
- ChunkManager as autoload singleton
- Chunk/SubChunk data structures
- Coordinate conversion utilities
- Corruption tracking system
- Simple placeholder generation (walls on edges)

**Test:**
- Player can walk indefinitely
- Chunks load/unload smoothly
- Corruption increases per chunk
- Memory usage reasonable

---

### Phase 2: Level Generator Base (Week 1-2)

**Files to Create:**
- `scripts/procedural/level_generator.gd` (abstract base)
- `scripts/procedural/level_generator_factory.gd`

**Goals:**
- Extensible generator system
- Per-level configuration structure
- Factory pattern for generator selection

**Test:**
- Factory can create generators
- Base class defines interface
- Config structure validated

---

### Phase 3: Level 0 Maze Generation (Week 2)

**Files to Create:**
- `scripts/procedural/level_0_generator.gd`

**Implement:**
- Recursive backtracking algorithm
- Long corridor generation (5-12 tiles)
- Low branching factor (25%)
- Occasional rooms (15% per sub-chunk)
- Sub-chunk connectivity

**Test:**
- Long hallways generated
- Liminal monotonous feel
- Occasional rooms break it up
- All tiles reachable

---

### Phase 4: Probabilistic Entity Spawner (Week 2)

**Files to Create:**
- `scripts/procedural/entity_spawner.gd`

**Implement:**
- Per-sub-chunk entity spawning
- Corruption-modified probabilities
- All entity categories (enemies, NPCs, structures, exits, items)
- Stub entity creation (actual entities come later)

**Test:**
- Enemies spawn more with corruption
- Exits are rare initially, common at high corruption
- Structures appear consistently
- Items become scarcer
- Probabilities feel right

---

### Phase 5: Island System (Week 3)

**Files to Create:**
- `scripts/procedural/island_manager.gd`
- `scripts/procedural/maze_island.gd`

**Implement:**
- Group chunks into islands (2×2 to 4×4 chunks)
- Island connections (doors between islands)
- Difficulty tiers per island

**Test:**
- Multiple islands generate
- Doors connect islands
- Player can traverse between islands

---

### Phase 6: Level Transitions (MVP) (Week 3)

**Files to Create:**
- `scripts/procedural/level_transition.gd`
- `scripts/player/interaction_system.gd`

**Implement:**
- Exit stairs entity type
- Walk-over detection
- Action preview shows "Coming Soon" message
- No actual level switching (stub)

**Test:**
- Player can find rare exit stairs
- Walking over shows message
- Turn preview updates
- Stairs become more common with corruption

---

### Phase 7: Chunk Persistence (Week 3-4)

**Implement in ChunkManager:**
- Track modified chunks (entities killed, items taken)
- Save/load within run
- Clear on new run start

**Test:**
- Player changes chunk (kill enemy)
- Leave and return
- Changes persist
- New run resets

---

### Phase 8: Integration & Polish (Week 4)

**Modify/Scrap:**
- Existing Grid system to use ChunkManager
- Player spawning to use chunk system
- Camera to handle large world coordinates

**Test:**
- Full game loop with procedural generation
- Performance with 50 loaded chunks
- Corruption escalation feels right
- Exit rarity progression works
- Player is forced to explore but eventually finds exit

---

## File Structure

```
/scripts/procedural/
├── chunk.gd                      # 128×128 chunk with 64 sub-chunks
├── sub_chunk.gd                  # 16×16 sub-chunk
├── chunk_manager.gd              # Autoload singleton - loading/unloading
├── corruption_tracker.gd         # Per-level corruption system
├── island_manager.gd             # Island grouping and connections
├── maze_island.gd                # Island data structure
├── level_generator.gd            # Abstract base class
├── level_generator_factory.gd   # Factory for generators
├── level_0_generator.gd          # Backrooms Level 0 (yellow halls)
├── level_1_generator.gd          # Level 1 stub (future)
├── entity_spawner.gd             # Probabilistic entity spawning
└── level_transition.gd           # Transition data

/autoload/ (Project Settings)
├── ChunkManager (scripts/procedural/chunk_manager.gd)
└── LevelManager (scripts/level_manager.gd) - if needed
```

---

## Testing Strategy

### Unit Tests (Manual GDScript Testing)

- Chunk coordinate conversion accuracy
- Sub-chunk indexing correctness
- Corruption probability calculations
- Seed determinism (same seed = same maze)

### Integration Tests (Manual Playthrough)

- Walk through Level 0 for 15 minutes
- Observe corruption increase
- Verify enemies spawn more frequently
- Verify exits become more common
- Find and interact with exit stairs
- Start new run, verify reset

### Performance Tests

- Generate 50 chunks, measure time
- Load/unload chunks rapidly
- Memory usage monitoring
- Frame time during generation (target: <2ms per chunk)

---

## Configuration Tuning Guide

### Tunable Parameters

All parameters in `level_config` can be adjusted without code changes:

**Corruption Escalation Speed:**
```gdscript
"increase_per_chunk": 0.1  # Higher = faster escalation
"max_value": 10.0          # Higher = longer games possible
```

**Exit Rarity:**
```gdscript
"base_probability": 0.001     # Lower = rarer exits
"corruption_multiplier": 2.0  # Higher = faster appearance with corruption
```

**Enemy Density:**
```gdscript
"base_probability": 0.05      # Higher = more enemies early
"corruption_multiplier": 1.5  # Higher = sharper increase with corruption
```

**Maze Complexity:**
```gdscript
"corridor_length": Vector2i(5, 12)  # Longer = more liminal
"branching_factor": 0.25             # Higher = more complex mazes
"room_chance": 0.15                  # Higher = more rooms
```

### Balancing Goals

1. **Exit Discovery Time**: Player should find exit after exploring 30-50% of available chunks
2. **Corruption Pressure**: Player should feel pressure to leave around corruption 7-8
3. **Enemy Density**: Should feel empty early, crowded late
4. **Resource Scarcity**: Items should become scarce, forcing exit search

---

## Future Extensions

### Level 1 (Industrial Theme)

```gdscript
class_name Level1Generator extends LevelGenerator

func get_level_config() -> Dictionary:
    return {
        "name": "Level 1",
        "theme": "industrial",
        "maze_generation": {
            "corridor_length": Vector2i(3, 8),  # Shorter
            "corridor_width": 2,  # Wider hallways
            "room_chance": 0.3,  # More rooms
            "branching_factor": 0.4,  # More complex
        },
        "corruption": {
            "increase_per_chunk": 0.15,  # Faster escalation
            "max_value": 12.0,
        },
        # Different entity pools...
    }
```

### Multi-Level Traversal

- Implement actual level switching
- Track visited levels
- Maintain chunk persistence across levels
- Handle player spawn positions

### Advanced Features

- Noclip zones (random teleports)
- Locked doors (require keys)
- Safe rooms (corruption doesn't increase)
- Boss arenas (special large rooms)

---

## Implementation Ready

✅ Architecture designed
✅ Configuration structure defined
✅ Corruption system specified
✅ Entity spawning system planned
✅ Phase breakdown complete
✅ Exit forcing mechanic clarified (MORE common with corruption)

**Ready to begin Phase 1 implementation.**
