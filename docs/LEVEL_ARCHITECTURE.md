# Level Architecture - Resource-Based Level System

**Last Updated**: 2025-11-09
**Status**: Design Document (Not Yet Implemented)

---

## Overview

This document defines the architecture for managing multiple Backrooms levels in a scalable, data-driven way. Each level has unique visual themes, entities, hazards, and gameplay rules while sharing common systems (grid, turn-based logic, player controls).

**Core Design Principles**:
- **Resource-based configuration**: Each level is a `.tres` file extending `LevelConfig`
- **Hot-reloadable**: Change level data without restarting game (development aid)
- **Memory efficient**: Load/unload levels on demand, not all at once
- **Easy to extend**: Adding Level 10 should be as simple as copying Level 0's config
- **Data-driven**: Designers configure levels without touching code

---

## Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                    LEVELMANAGER (Autoload)                  │
│  - Loads/unloads LevelConfig resources                      │
│  - Handles transitions between levels                       │
│  - Manages memory (max 2-3 levels loaded at once)           │
│  - Provides current level reference to other systems        │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│               LEVELCONFIG (Resource Base Class)             │
│  - Level metadata (name, description, clearance)            │
│  - Visual assets (MeshLibrary, materials, shaders)          │
│  - Spawn rules (entities, items, hazards)                   │
│  - Gameplay rules (temperature, corruption rate)            │
│  - Exit conditions (how to escape this level)               │
└──────────────────┬──────────────────────────────────────────┘
                   │
         ┌─────────┴─────────┬─────────────┐
         │                   │             │
┌────────▼────────┐ ┌────────▼────────┐  ┌▼──────────────┐
│ Level0Config    │ │ Level1Config    │  │ Level2Config  │
│ (yellow office) │ │ (industrial)    │  │ (tunnels)     │
└─────────────────┘ └─────────────────┘  └───────────────┘
```

---

## LevelConfig Base Class

**File**: `scripts/resources/level_config.gd`

```gdscript
class_name LevelConfig
extends Resource

## Base class for all Backrooms level configurations
## Each level (Level 0, Level 1, etc.) extends this and provides specific data

# ============================================================================
# METADATA
# ============================================================================

## Internal level ID (e.g., "level_00", "level_01")
@export var level_id: String = ""

## Display name (e.g., "The Lobby", "Industrial Complex")
@export var level_name: String = ""

## Multi-line description for knowledge database
@export_multiline var description: String = ""

## Minimum clearance level required to access this level
@export var clearance_required: int = 0

## Danger rating (1-10, affects UI display)
@export_range(1, 10) var danger_rating: int = 1


# ============================================================================
# VISUAL ASSETS
# ============================================================================

## MeshLibrary for GridMap (walls, floors, ceilings, props)
@export var mesh_library: MeshLibrary

## Default floor material (PSX style, color tint)
@export var floor_material: Material

## Default wall material
@export var wall_material: Material

## Default ceiling material
@export var ceiling_material: Material

## Ambient light color for this level
@export var ambient_light_color: Color = Color(1.0, 1.0, 0.9, 1.0)

## Ambient light energy (brightness)
@export var ambient_light_energy: float = 0.3

## Optional post-process shader (corruption, glitch effects)
@export var post_process_shader: Shader


# ============================================================================
# GENERATION RULES
# ============================================================================

## Map dimensions (grid size)
@export var map_size: Vector2i = Vector2i(128, 128)

## Room generation algorithm type
@export_enum("Maze", "Rooms", "CellularAutomata", "BSP") var generation_type: String = "Maze"

## Room density (0.0 = sparse, 1.0 = dense)
@export_range(0.0, 1.0) var room_density: float = 0.5

## Corridor width (in tiles)
@export_range(1, 5) var corridor_width: int = 1

## Prop spawn chance per walkable tile (0.0-1.0)
@export_range(0.0, 1.0) var prop_spawn_chance: float = 0.05


# ============================================================================
# ENTITY SPAWNING
# ============================================================================

## Entity spawn table: [entity_id, weight, min_clearance]
## Example: [["smiler", 10, 0], ["skin_stealer", 5, 1]]
@export var entity_spawn_table: Array[Dictionary] = []

## Base entity spawn rate (entities per 100 tiles)
@export var entity_spawn_rate: float = 2.0

## Maximum concurrent entities allowed
@export var max_entities: int = 50

## Horde escalation rate (multiplier per minute survived)
@export var horde_escalation: float = 1.2


# ============================================================================
# HAZARDS & PHYSICS
# ============================================================================

## Liquid spawn rules: [liquid_type, spawn_chance, pool_size_range]
@export var liquid_spawn_rules: Array[Dictionary] = []

## Temperature range for this level (min, max in Celsius)
@export var temperature_range: Vector2 = Vector2(15.0, 25.0)

## Reality corruption rate (0.0 = stable, 1.0 = chaotic)
@export_range(0.0, 1.0) var corruption_rate: float = 0.1

## Electrical hazard zones (true = has sparking wires, faulty lights)
@export var has_electrical_hazards: bool = false

## Darkness zones (affects entity behavior, visibility)
@export var has_darkness_zones: bool = false


# ============================================================================
# ITEMS & LOOT
# ============================================================================

## Item spawn table: [item_id, weight, min_clearance]
@export var item_spawn_table: Array[Dictionary] = []

## Items per 100 tiles
@export var item_spawn_rate: float = 1.0

## Guaranteed starting items (given when entering level)
@export var starting_items: Array[String] = []


# ============================================================================
# EXIT CONDITIONS
# ============================================================================

## How to escape this level (narrative text)
@export_multiline var exit_description: String = "Find a noclip zone to descend deeper."

## Exit spawn rules: how many exits, where they lead
@export var exit_destinations: Array[String] = []  # ["level_01", "level_02"]

## Exits per level instance
@export var exit_count: int = 3


# ============================================================================
# AUDIO
# ============================================================================

## Ambient audio track (humming, buzzing, dripping)
@export var ambient_audio: AudioStream

## Ambient volume (0.0-1.0)
@export_range(0.0, 1.0) var ambient_volume: float = 0.5

## Music track (optional, can be null for pure ambience)
@export var music_track: AudioStream


# ============================================================================
# GAMEPLAY MODIFIERS
# ============================================================================

## Sanity drain rate (per turn)
@export var sanity_drain_per_turn: float = 0.1

## Stamina drain rate (per move action)
@export var stamina_drain_per_move: float = 1.0

## Hunger rate (resource depletion speed)
@export var hunger_rate: float = 0.05

## Special rules text (displayed in knowledge database)
@export_multiline var special_rules: String = ""


# ============================================================================
# HELPER METHODS
# ============================================================================

## Roll a weighted random entity from the spawn table
func get_random_entity() -> String:
    if entity_spawn_table.is_empty():
        return ""
    
    var total_weight = 0.0
    for entry in entity_spawn_table:
        total_weight += entry.get("weight", 0)
    
    var roll = randf() * total_weight
    var cumulative = 0.0
    
    for entry in entity_spawn_table:
        cumulative += entry.get("weight", 0)
        if roll <= cumulative:
            return entry.get("entity_id", "")
    
    return entity_spawn_table[0].get("entity_id", "")


## Roll a weighted random item from the spawn table
func get_random_item() -> String:
    if item_spawn_table.is_empty():
        return ""
    
    var total_weight = 0.0
    for entry in item_spawn_table:
        total_weight += entry.get("weight", 0)
    
    var roll = randf() * total_weight
    var cumulative = 0.0
    
    for entry in item_spawn_table:
        cumulative += entry.get("weight", 0)
        if roll <= cumulative:
            return entry.get("item_id", "")
    
    return item_spawn_table[0].get("item_id", "")


## Check if player has sufficient clearance to access this level
func is_accessible(player_clearance: int) -> bool:
    return player_clearance >= clearance_required


## Get spawn density (entities per tile, adjusted by current time)
func get_adjusted_spawn_rate(time_survived: float) -> float:
    var escalation_factor = pow(horde_escalation, time_survived / 60.0)
    return entity_spawn_rate * escalation_factor
```

---

## LevelManager Autoload

**File**: `scripts/autoload/level_manager.gd`

```gdscript
extends Node

## LevelManager singleton - handles loading/unloading levels, transitions
## Access via: LevelManager.current_level, LevelManager.load_level("level_01")

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when a new level finishes loading
signal level_loaded(level_id: String)

## Emitted when transitioning between levels (before unload)
signal level_unloading(level_id: String)

## Emitted when level transition is complete
signal level_transition_complete(from_level: String, to_level: String)


# ============================================================================
# STATE
# ============================================================================

## Currently active level
var current_level: LevelConfig = null

## Cache of loaded levels (max 3 to conserve memory)
var _loaded_levels: Dictionary = {}  # level_id -> LevelConfig

## Maximum levels to keep in memory
const MAX_CACHED_LEVELS = 3

## Level load order (for LRU cache eviction)
var _load_order: Array[String] = []


# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
    Logger.info("LevelManager", "Initialized")


# ============================================================================
# LEVEL LOADING
# ============================================================================

## Load a level by ID (e.g., "level_00")
## Returns true if successful, false otherwise
func load_level(level_id: String) -> bool:
    Logger.info("LevelManager", "Loading level: %s" % level_id)
    
    # Check cache first
    if _loaded_levels.has(level_id):
        Logger.debug("LevelManager", "Level found in cache")
        current_level = _loaded_levels[level_id]
        _update_load_order(level_id)
        level_loaded.emit(level_id)
        return true
    
    # Load from disk
    var path = "res://assets/levels/%s/%s_config.tres" % [level_id, level_id]
    
    if not ResourceLoader.exists(path):
        Logger.error("LevelManager", "Level config not found: %s" % path)
        return false
    
    var config = ResourceLoader.load(path) as LevelConfig
    if not config:
        Logger.error("LevelManager", "Failed to load level config: %s" % path)
        return false
    
    # Add to cache and update current level
    _add_to_cache(level_id, config)
    current_level = config
    
    Logger.info("LevelManager", "Level loaded successfully: %s" % config.level_name)
    level_loaded.emit(level_id)
    return true


## Transition to a new level (unloads current, loads target)
func transition_to_level(target_level_id: String) -> bool:
    var from_level = current_level.level_id if current_level else "none"
    
    Logger.info("LevelManager", "Transitioning from %s to %s" % [from_level, target_level_id])
    
    # Emit unload signal
    if current_level:
        level_unloading.emit(current_level.level_id)
    
    # Load new level
    var success = load_level(target_level_id)
    
    if success:
        level_transition_complete.emit(from_level, target_level_id)
    
    return success


## Preload a level into cache (for seamless transitions)
func preload_level(level_id: String) -> void:
    if _loaded_levels.has(level_id):
        Logger.debug("LevelManager", "Level already cached: %s" % level_id)
        return
    
    var path = "res://assets/levels/%s/%s_config.tres" % [level_id, level_id]
    if ResourceLoader.exists(path):
        var config = ResourceLoader.load(path) as LevelConfig
        if config:
            _add_to_cache(level_id, config)
            Logger.debug("LevelManager", "Preloaded level: %s" % level_id)


## Clear a specific level from cache
func unload_level(level_id: String) -> void:
    if _loaded_levels.has(level_id):
        _loaded_levels.erase(level_id)
        _load_order.erase(level_id)
        Logger.debug("LevelManager", "Unloaded level from cache: %s" % level_id)


## Clear all cached levels except current
func clear_cache() -> void:
    var current_id = current_level.level_id if current_level else ""
    
    for level_id in _loaded_levels.keys():
        if level_id != current_id:
            _loaded_levels.erase(level_id)
    
    _load_order.clear()
    if not current_id.is_empty():
        _load_order.append(current_id)
    
    Logger.debug("LevelManager", "Cleared level cache")


# ============================================================================
# CACHE MANAGEMENT (LRU)
# ============================================================================

func _add_to_cache(level_id: String, config: LevelConfig) -> void:
    # Evict oldest level if cache is full
    if _loaded_levels.size() >= MAX_CACHED_LEVELS and not _loaded_levels.has(level_id):
        var oldest = _load_order.pop_front()
        _loaded_levels.erase(oldest)
        Logger.debug("LevelManager", "Evicted level from cache: %s" % oldest)
    
    _loaded_levels[level_id] = config
    _update_load_order(level_id)


func _update_load_order(level_id: String) -> void:
    # Move to end (most recently used)
    _load_order.erase(level_id)
    _load_order.append(level_id)


# ============================================================================
# QUERY METHODS
# ============================================================================

## Get a specific level config without loading it as current
func get_level_config(level_id: String) -> LevelConfig:
    if _loaded_levels.has(level_id):
        return _loaded_levels[level_id]
    
    var path = "res://assets/levels/%s/%s_config.tres" % [level_id, level_id]
    if ResourceLoader.exists(path):
        return ResourceLoader.load(path) as LevelConfig
    
    return null


## Get list of all available level IDs
func get_available_levels() -> Array[String]:
    var levels: Array[String] = []
    var dir = DirAccess.open("res://assets/levels/")
    
    if not dir:
        Logger.warn("LevelManager", "Could not open levels directory")
        return levels
    
    dir.list_dir_begin()
    var folder_name = dir.get_next()
    
    while folder_name != "":
        if dir.current_is_dir() and folder_name.begins_with("level_"):
            levels.append(folder_name)
        folder_name = dir.get_next()
    
    dir.list_dir_end()
    return levels


## Check if a level exists
func level_exists(level_id: String) -> bool:
    var path = "res://assets/levels/%s/%s_config.tres" % [level_id, level_id]
    return ResourceLoader.exists(path)


## Get the default starting level
func get_starting_level() -> String:
    return "level_00"  # Always start at Level 0 (The Lobby)
```

---

## Example Level Configs

### Level 0: "The Lobby" (Yellow Offices)

**File**: `assets/levels/level_00/level_00_config.tres`

```gdscript
[gd_resource type="Resource" script_class="LevelConfig" load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/resources/level_config.gd" id="1"]
[ext_resource type="MeshLibrary" path="res://assets/levels/level_00/level_00_meshlib.tres" id="2"]
[ext_resource type="Material" path="res://assets/levels/level_00/floor_yellow.tres" id="3"]
[ext_resource type="Material" path="res://assets/levels/level_00/wall_beige.tres" id="4"]
[ext_resource type="AudioStream" path="res://assets/audio/ambient/fluorescent_hum.ogg" id="5"]

[resource]
script = ExtResource("1")
level_id = "level_00"
level_name = "The Lobby"
description = "An endless maze of yellow-wallpapered rooms lit by flickering fluorescent lights. The air is thick with the smell of moist carpet and the constant hum of electricity. Reality feels thin here."
clearance_required = 0
danger_rating = 2

mesh_library = ExtResource("2")
floor_material = ExtResource("3")
wall_material = ExtResource("4")
ceiling_material = null
ambient_light_color = Color(1.0, 0.95, 0.7, 1.0)
ambient_light_energy = 0.4
post_process_shader = null

map_size = Vector2i(128, 128)
generation_type = "Maze"
room_density = 0.6
corridor_width = 2
prop_spawn_chance = 0.03

entity_spawn_table = [
    {"entity_id": "smiler", "weight": 10, "min_clearance": 0},
    {"entity_id": "hound", "weight": 5, "min_clearance": 0},
    {"entity_id": "skin_stealer", "weight": 2, "min_clearance": 1}
]
entity_spawn_rate = 1.5
max_entities = 30
horde_escalation = 1.15

liquid_spawn_rules = [
    {"liquid_type": "water", "spawn_chance": 0.02, "pool_size": Vector2i(2, 5)}
]
temperature_range = Vector2(18.0, 24.0)
corruption_rate = 0.05
has_electrical_hazards = true
has_darkness_zones = false

item_spawn_table = [
    {"item_id": "almond_water", "weight": 10, "min_clearance": 0},
    {"item_id": "flashlight", "weight": 8, "min_clearance": 0},
    {"item_id": "crowbar", "weight": 5, "min_clearance": 0}
]
item_spawn_rate = 1.0
starting_items = []

exit_description = "Look for walls that flicker. Noclipping through unstable geometry will take you deeper."
exit_destinations = ["level_01", "level_02"]
exit_count = 3

ambient_audio = ExtResource("5")
ambient_volume = 0.6
music_track = null

sanity_drain_per_turn = 0.05
stamina_drain_per_move = 0.8
hunger_rate = 0.03
special_rules = "The hum of the lights never stops. Entities are attracted to noise."
```

---

### Level 1: "Industrial Complex"

**File**: `assets/levels/level_01/level_01_config.tres`

```gdscript
[gd_resource type="Resource" script_class="LevelConfig" load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/resources/level_config.gd" id="1"]
[ext_resource type="MeshLibrary" path="res://assets/levels/level_01/level_01_meshlib.tres" id="2"]
[ext_resource type="Material" path="res://assets/levels/level_01/floor_concrete.tres" id="3"]
[ext_resource type="Material" path="res://assets/levels/level_01/wall_metal.tres" id="4"]
[ext_resource type="AudioStream" path="res://assets/audio/ambient/machinery_distant.ogg" id="5"]

[resource]
script = ExtResource("1")
level_id = "level_01"
level_name = "Industrial Complex"
description = "A vast network of concrete corridors and rusted metal catwalks. Machinery echoes in the distance, though no source is ever found. Steam vents hiss at random intervals. The temperature fluctuates wildly."
clearance_required = 1
danger_rating = 4

mesh_library = ExtResource("2")
floor_material = ExtResource("3")
wall_material = ExtResource("4")
ceiling_material = null
ambient_light_color = Color(0.8, 0.85, 0.9, 1.0)
ambient_light_energy = 0.3
post_process_shader = null

map_size = Vector2i(128, 128)
generation_type = "Rooms"
room_density = 0.4
corridor_width = 3
prop_spawn_chance = 0.08

entity_spawn_table = [
    {"entity_id": "hound", "weight": 15, "min_clearance": 1},
    {"entity_id": "skin_stealer", "weight": 10, "min_clearance": 1},
    {"entity_id": "clump", "weight": 8, "min_clearance": 1},
    {"entity_id": "smiler", "weight": 5, "min_clearance": 0}
]
entity_spawn_rate = 2.5
max_entities = 50
horde_escalation = 1.25

liquid_spawn_rules = [
    {"liquid_type": "oil", "spawn_chance": 0.05, "pool_size": Vector2i(3, 8)},
    {"liquid_type": "acid", "spawn_chance": 0.01, "pool_size": Vector2i(1, 3)}
]
temperature_range = Vector2(5.0, 40.0)
corruption_rate = 0.15
has_electrical_hazards = true
has_darkness_zones = true

item_spawn_table = [
    {"item_id": "almond_water", "weight": 8, "min_clearance": 1},
    {"item_id": "rope", "weight": 6, "min_clearance": 1},
    {"item_id": "wire_cutters", "weight": 5, "min_clearance": 1},
    {"item_id": "hazmat_suit", "weight": 3, "min_clearance": 2}
]
item_spawn_rate = 0.8
starting_items = []

exit_description = "Find the maintenance shafts. They lead deeper into the complex—or out of it entirely."
exit_destinations = ["level_02", "level_03", "level_00"]
exit_count = 4

ambient_audio = ExtResource("5")
ambient_volume = 0.5
music_track = null

sanity_drain_per_turn = 0.08
stamina_drain_per_move = 1.2
hunger_rate = 0.05
special_rules = "Temperature extremes cause damage. Oil puddles are flammable. Darkness attracts certain entities."
```

---

### Level 2: "Utility Tunnels"

**File**: `assets/levels/level_02/level_02_config.tres`

```gdscript
[gd_resource type="Resource" script_class="LevelConfig" load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/resources/level_config.gd" id="1"]
[ext_resource type="MeshLibrary" path="res://assets/levels/level_02/level_02_meshlib.tres" id="2"]
[ext_resource type="Material" path="res://assets/levels/level_02/floor_grate.tres" id="3"]
[ext_resource type="AudioStream" path="res://assets/audio/ambient/water_drip.ogg" id="4"]

[resource]
script = ExtResource("1")
level_id = "level_02"
level_name = "Utility Tunnels"
description = "Narrow maintenance tunnels with exposed pipes and electrical conduits. Water drips constantly from unseen sources. The walls are slick with condensation. Mold grows in the corners."
clearance_required = 1
danger_rating = 5

mesh_library = ExtResource("2")
floor_material = ExtResource("3")
wall_material = null
ceiling_material = null
ambient_light_color = Color(0.6, 0.7, 0.8, 1.0)
ambient_light_energy = 0.25
post_process_shader = null

map_size = Vector2i(128, 128)
generation_type = "Maze"
room_density = 0.3
corridor_width = 1
prop_spawn_chance = 0.1

entity_spawn_table = [
    {"entity_id": "clump", "weight": 20, "min_clearance": 1},
    {"entity_id": "bacteria", "weight": 15, "min_clearance": 2},
    {"entity_id": "hound", "weight": 10, "min_clearance": 1},
    {"entity_id": "skin_stealer", "weight": 5, "min_clearance": 1}
]
entity_spawn_rate = 3.0
max_entities = 60
horde_escalation = 1.3

liquid_spawn_rules = [
    {"liquid_type": "water", "spawn_chance": 0.15, "pool_size": Vector2i(5, 20)},
    {"liquid_type": "sewage", "spawn_chance": 0.05, "pool_size": Vector2i(3, 10)}
]
temperature_range = Vector2(12.0, 18.0)
corruption_rate = 0.2
has_electrical_hazards = true
has_darkness_zones = true

item_spawn_table = [
    {"item_id": "almond_water", "weight": 5, "min_clearance": 1},
    {"item_id": "rope", "weight": 8, "min_clearance": 1},
    {"item_id": "glow_stick", "weight": 10, "min_clearance": 1},
    {"item_id": "gas_mask", "weight": 4, "min_clearance": 2}
]
item_spawn_rate = 0.6
starting_items = []

exit_description = "Follow the pipes. They lead somewhere—but not necessarily where you want to go."
exit_destinations = ["level_01", "level_03", "level_04"]
exit_count = 2

ambient_audio = ExtResource("4")
ambient_volume = 0.7
music_track = null

sanity_drain_per_turn = 0.1
stamina_drain_per_move = 1.5
hunger_rate = 0.06
special_rules = "Cramped tunnels restrict movement. Water conducts electricity. Mold spores cause sanity drain."
```

---

## Folder Structure

```
assets/
├── levels/
│   ├── level_00/                        # Level 0: The Lobby
│   │   ├── level_00_config.tres         # LevelConfig resource
│   │   ├── level_00_meshlib.tres        # MeshLibrary (walls, floors, props)
│   │   ├── floor_yellow.tres            # Material: yellow carpet
│   │   ├── wall_beige.tres              # Material: beige wallpaper
│   │   ├── meshes/                      # 3D models for this level
│   │   │   ├── office_chair.glb
│   │   │   ├── desk.glb
│   │   │   └── fluorescent_light.glb
│   │   └── textures/                    # Textures for this level
│   │       ├── carpet_yellow.png
│   │       └── wallpaper_beige.png
│   │
│   ├── level_01/                        # Level 1: Industrial Complex
│   │   ├── level_01_config.tres
│   │   ├── level_01_meshlib.tres
│   │   ├── floor_concrete.tres
│   │   ├── wall_metal.tres
│   │   ├── meshes/
│   │   │   ├── pipe_rusty.glb
│   │   │   ├── catwalk.glb
│   │   │   └── steam_vent.glb
│   │   └── textures/
│   │       ├── concrete_cracked.png
│   │       └── metal_corroded.png
│   │
│   ├── level_02/                        # Level 2: Utility Tunnels
│   │   ├── level_02_config.tres
│   │   ├── level_02_meshlib.tres
│   │   ├── floor_grate.tres
│   │   ├── meshes/
│   │   │   ├── pipe_cluster.glb
│   │   │   ├── valve.glb
│   │   │   └── conduit.glb
│   │   └── textures/
│   │       ├── grate_metal.png
│   │       └── pipe_wet.png
│   │
│   └── [level_03, level_04, ...]       # Future levels follow same pattern
│
├── audio/
│   └── ambient/                         # Per-level ambient tracks
│       ├── fluorescent_hum.ogg          # Level 0
│       ├── machinery_distant.ogg        # Level 1
│       └── water_drip.ogg               # Level 2
│
└── shaders/
    └── post_process/                    # Per-level visual effects
        ├── corruption_glitch.gdshader
        └── chromatic_aberration.gdshader

scripts/
├── autoload/
│   └── level_manager.gd                 # LevelManager singleton
└── resources/
    └── level_config.gd                  # LevelConfig base class
```

---

## Integration with Existing Systems

### Grid3D Integration

**Current**: `Grid3D.gd` manages GridMap with hardcoded MeshLibrary

**After Implementation**:
```gdscript
# In Grid3D.gd
func load_level_visuals(config: LevelConfig) -> void:
    # Set MeshLibrary from config
    if config.mesh_library:
        grid_map.mesh_library = config.mesh_library
    
    # Apply materials
    if config.floor_material:
        _apply_material_to_tiles(TILE_TYPE.FLOOR, config.floor_material)
    
    if config.wall_material:
        _apply_material_to_tiles(TILE_TYPE.WALL, config.wall_material)
    
    # Update ambient light
    if has_node("WorldEnvironment"):
        var env = get_node("WorldEnvironment")
        env.environment.ambient_light_color = config.ambient_light_color
        env.environment.ambient_light_energy = config.ambient_light_energy
```

**Usage in Game3D.gd**:
```gdscript
func _ready() -> void:
    # Connect to LevelManager signal
    LevelManager.level_loaded.connect(_on_level_loaded)
    
    # Load starting level
    LevelManager.load_level(LevelManager.get_starting_level())

func _on_level_loaded(level_id: String) -> void:
    var config = LevelManager.current_level
    
    # Update grid visuals
    grid_3d.load_level_visuals(config)
    
    # Regenerate map with new parameters
    grid_3d.generate_map(config.map_size, config.generation_type)
    
    # Spawn entities
    _spawn_entities_from_config(config)
    
    # Update UI
    _update_level_display(config.level_name)
```

---

## Guidelines for Adding New Levels

### Step-by-Step: Creating Level 10

1. **Create folder structure**:
   ```bash
   mkdir -p assets/levels/level_10/meshes
   mkdir -p assets/levels/level_10/textures
   ```

2. **Create MeshLibrary**:
   - In Godot Editor: Scene → New 3D Scene
   - Add MeshInstance3D nodes for walls, floors, props
   - Scene → Export As MeshLibrary
   - Save as `level_10_meshlib.tres`

3. **Create materials**:
   - Create StandardMaterial3D or ShaderMaterial
   - Configure colors, textures, PSX parameters
   - Save as `floor_[style].tres`, `wall_[style].tres`

4. **Create LevelConfig resource**:
   - In FileSystem: Right-click `assets/levels/level_10/`
   - New Resource → Search "LevelConfig"
   - Fill in all exported properties (see examples above)
   - Save as `level_10_config.tres`

5. **Configure spawn tables**:
   ```gdscript
   entity_spawn_table = [
       {"entity_id": "new_entity", "weight": 10, "min_clearance": 5},
       {"entity_id": "hound", "weight": 5, "min_clearance": 1}
   ]
   ```

6. **Test the level**:
   ```gdscript
   # In Game3D.gd or debug menu
   LevelManager.load_level("level_10")
   ```

7. **Add to exit destinations**:
   - Edit previous levels' configs to include "level_10" in `exit_destinations`

---

## Memory Management Strategy

### Problem
Loading 10+ levels with all their assets (MeshLibraries, materials, textures) would consume excessive memory.

### Solution: LRU Cache with Preloading
```gdscript
# In LevelManager.gd
const MAX_CACHED_LEVELS = 3

# Cache stores:
# - Current level (always loaded)
# - Previous level (for backtracking)
# - Next likely level (preloaded)

# Example: Player in Level 1
# Cache contains: [Level 0, Level 1, Level 2]

# Player transitions to Level 2:
# Cache evicts Level 0, loads Level 3
# Cache now: [Level 1, Level 2, Level 3]
```

### Preloading Strategy
```gdscript
# When loading a level, preload its exit destinations
func _on_level_loaded(level_id: String) -> void:
    var config = LevelManager.current_level
    
    # Preload adjacent levels in background
    for exit_dest in config.exit_destinations:
        if not LevelManager._loaded_levels.has(exit_dest):
            LevelManager.preload_level(exit_dest)
```

### Manual Cache Control
```gdscript
# For cutscenes or specific moments, clear cache
LevelManager.clear_cache()

# For hub area (loads nothing else)
LevelManager.load_level("hub")
LevelManager.clear_cache()  # Free all level assets
```

---

## Implementation Roadmap

### Phase 1: Foundation (2-3 hours)
1. ✅ Create design document (this file)
2. ⬜ Create `LevelConfig` base class (`scripts/resources/level_config.gd`)
3. ⬜ Create `LevelManager` autoload (`scripts/autoload/level_manager.gd`)
4. ⬜ Add LevelManager to project autoloads
5. ⬜ Create folder structure for `level_00`, `level_01`, `level_02`

### Phase 2: Level 0 Setup (2-4 hours)
6. ⬜ Create Level 0 MeshLibrary (office theme)
7. ⬜ Create Level 0 materials (yellow carpet, beige walls)
8. ⬜ Create `level_00_config.tres` with realistic data
9. ⬜ Test loading Level 0 via LevelManager

### Phase 3: Grid3D Integration (2-3 hours)
10. ⬜ Add `load_level_visuals()` method to Grid3D
11. ⬜ Update `Game3D.gd` to use LevelManager
12. ⬜ Test level loading in-game (verify visuals update)
13. ⬜ Add debug UI to switch levels (for testing)

### Phase 4: Additional Levels (1-2 hours each)
14. ⬜ Create Level 1 (industrial theme)
15. ⬜ Create Level 2 (tunnels theme)
16. ⬜ Test transitions between levels
17. ⬜ Verify cache eviction works correctly

### Phase 5: Polish & Documentation (1-2 hours)
18. ⬜ Add level name/description to in-game UI
19. ⬜ Add transition animations (fade, glitch effect)
20. ⬜ Update ARCHITECTURE.md with implemented system
21. ⬜ Create tutorial for adding new levels

---

## Testing Strategy

### Unit Tests (Manual)
- **Cache Management**:
  - Load 5 levels sequentially
  - Verify only 3 are kept in memory
  - Check LRU eviction order

- **Resource Loading**:
  - Test loading non-existent level (should fail gracefully)
  - Test loading corrupted config (should log error)
  - Test hot-reloading (edit config while game running)

### Integration Tests
- **Level Transitions**:
  - Walk to exit in Level 0
  - Trigger transition to Level 1
  - Verify visuals update (MeshLibrary, materials)
  - Verify entities despawn/respawn

- **Memory Usage**:
  - Profile memory before/after loading 10 levels
  - Verify cache limits prevent unbounded growth

### Performance Tests
- **Load Times**:
  - Measure time to load level from disk (target: <100ms)
  - Measure time to switch from cached level (target: <16ms)

- **Transition Smoothness**:
  - No frame drops during level load
  - Preloading should happen in background (no stutters)

---

## Future Enhancements

### Dynamic Level Parameters (v2.0)
- Modify level configs at runtime (increase spawn rates, change corruption)
- "Mutation" system: levels evolve over multiple runs

### Procedural Level Mixing (v2.0)
- Blend two level themes (e.g., Level 0 + Level 3 = "Electrified Offices")
- Crossover zones at level boundaries

### Level-Specific Scripts (v2.0)
```gdscript
# In LevelConfig
@export var custom_script: GDScript

# In LevelManager
if config.custom_script:
    var instance = config.custom_script.new()
    instance.on_level_enter()
```

### Streaming Level Loading (v3.0)
- Load level in chunks (128x128 grid too large for instant load)
- Stream tiles as player approaches

---

## Notes for Future Claude Instances

### Key Decisions Made
- **Why resource-based?** Godot's resource system is perfect for data-driven design. Designers can edit `.tres` files directly or via Inspector.
- **Why LRU cache?** Backrooms has 10+ levels, loading all would exceed memory budget. LRU ensures smooth transitions while capping memory.
- **Why not scenes?** Levels are data, not behavior. Using scenes would couple visuals to logic. Resources are pure data.

### Common Pitfalls
- **Don't hardcode level references**: Always use `LevelManager.current_level`
- **Don't forget to preload**: Transitions feel instant when next level is cached
- **Don't skip folder structure**: Consistent naming makes adding levels trivial

### Extension Points
- `LevelConfig` is designed to be subclassed (e.g., `BossLevelConfig` with boss-specific data)
- `LevelManager` signals allow hooking into transitions (e.g., save game state on level change)
- `exit_destinations` supports non-linear level progression (Level 1 → Level 3 shortcut)

---

**End of Document**
