extends Resource
class_name LevelConfig
## Base configuration resource for Backrooms levels
##
## This resource defines all the data needed to generate and configure a specific
## Backrooms level. Each level has unique visual assets, generation parameters,
## entity spawning rules, environmental hazards, and gameplay modifiers.
##
## To create a new level:
## 1. Create a new script that extends LevelConfig
## 2. Override _init() to set all properties
## 3. Save as .tres resource in assets/levels/level_XX/
##
## Example:
##   var level = load("res://assets/levels/level_00/level_00_config.tres")
##   LevelManager.load_level(level)

# ============================================================================
# METADATA
# ============================================================================

@export_group("Metadata")

## Unique identifier for this level (e.g., 0, 1, 2, etc.)
@export var level_id: int = 0

## Display name shown to player (e.g., "Level 0 - The Lobby")
@export var display_name: String = "Unknown Level"

## Lore description for this level (shown in knowledge database)
@export_multiline var description: String = ""

## Difficulty rating (0-10) - affects spawn rates, hazards, etc.
@export_range(0, 10) var difficulty: int = 1

## Clearance level required to access this level (progression gate)
@export_range(0, 5) var required_clearance: int = 0

# ============================================================================
# VISUAL ASSETS
# ============================================================================

@export_group("Visual Assets")

## Path to MeshLibrary resource for this level's tileset
@export_file("*.tres") var mesh_library_path: String = ""

## Material for wall tiles (PSX shader with level-specific textures)
@export var wall_material: Material = null

## Material for floor tiles
@export var floor_material: Material = null

## Material for ceiling tiles
@export var ceiling_material: Material = null

## Ambient light color for this level
@export var ambient_light_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Ambient light intensity (0.0 - 1.0)
@export_range(0.0, 1.0) var ambient_light_intensity: float = 0.3

## Fog color for distance culling
@export var fog_color: Color = Color(0.1, 0.1, 0.1, 1.0)

## Fog start distance
@export var fog_start: float = 10.0

## Fog end distance
@export var fog_end: float = 30.0

## Background/skybox color (what player sees at horizon in tactical cam)
## Examples:
##   - Level 0: Color(0.82, 0.8, 0.75) = greyish-beige ceiling tiles
##   - Level 1: Color(0.1, 0.1, 0.1) = black void
##   - Level 2: Color(0.3, 0.0, 0.0) = dark red emergency lighting
## IMPORTANT: This is NOT outdoor sky - it's what fills the "void" beyond geometry
@export var background_color: Color = Color(0.5, 0.5, 0.5, 1.0)

## Directional light color (tints all level lighting)
## Examples:
##   - Color(1.0, 1.0, 1.0) = pure white (neutral)
##   - Color(0.95, 0.97, 1.0) = slight blue tint (fluorescent lights)
##   - Color(1.0, 0.9, 0.7) = warm yellow (incandescent bulbs)
##   - Color(1.0, 0.3, 0.3) = red emergency lighting
@export var directional_light_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Directional light energy/intensity
## 0.0 = completely dark, 1.0 = standard brightness, 2.0 = very bright
## Examples: Level 0 = 0.9 (well-lit office), dark level = 0.3
@export_range(0.0, 2.0) var directional_light_energy: float = 0.8

## Directional light rotation in degrees (X=pitch, Y=yaw, Z=roll)
## Determines where light comes from:
##   - Vector3(0, 0, 80) = nearly straight down (overhead fluorescents)
##   - Vector3(0, 0, 45) = 45° angle from above (angled sun)
##   - Vector3(0, 90, 10) = light from side (dramatic shadows)
@export var directional_light_rotation: Vector3 = Vector3(0, 0, 80)

# ============================================================================
# GENERATION PARAMETERS
# ============================================================================

@export_group("Generation Parameters")

## Grid size for this level (default: 128x128)
@export var grid_size: Vector2i = Vector2i(128, 128)

## Room density (0.0 = all corridors, 1.0 = all rooms)
@export_range(0.0, 1.0) var room_density: float = 0.5

## Minimum room size in tiles
@export var min_room_size: Vector2i = Vector2i(3, 3)

## Maximum room size in tiles
@export var max_room_size: Vector2i = Vector2i(10, 10)

## Corridor width in tiles
@export_range(1, 5) var corridor_width: int = 1

## Wall placement probability (0.0 = open, 1.0 = maze-like)
@export_range(0.0, 1.0) var wall_probability: float = 0.7

## Use "island of mazes" chunk system (requires PROCEDURAL_GENERATION system)
@export var use_chunk_system: bool = false

## Chunk size if using chunk system (must be power of 2)
@export var chunk_size: int = 32

# ============================================================================
# ENTITY SPAWNING
# ============================================================================

@export_group("Entity Spawning")

## Entity spawn rules: [{"entity_scene": path, "weight": float, "min_distance": int}]
## Weight determines spawn probability (higher = more common)
@export var entity_spawn_table: Array[Dictionary] = []

## Maximum entities active at once
@export var max_entities: int = 50

## Minimum distance between entity spawns (in tiles)
@export var min_entity_distance: int = 10

## Base spawn interval in turns (lower = more frequent spawning)
@export_range(1, 100) var spawn_interval: int = 10

## Escalation rate: how much spawn_interval decreases per minute
@export var escalation_rate: float = 0.1

# ============================================================================
# ENVIRONMENTAL HAZARDS
# ============================================================================

@export_group("Environmental Hazards")

## Base temperature for this level (affects ice/fire mechanics)
@export_range(-50.0, 150.0) var base_temperature: float = 20.0

## Liquid types present in this level (for physics simulation)
## Example: ["almond_water", "sewage", "acid"]
@export var liquid_types: Array[String] = []

## Corruption rate per turn (affects reality stability)
@export_range(0.0, 1.0) var corruption_rate: float = 0.01

## Light level (0.0 = pitch black, 1.0 = fully lit)
@export_range(0.0, 1.0) var light_level: float = 0.7

## Noise echo multiplier (affects entity attraction range)
@export_range(0.0, 2.0) var noise_echo: float = 1.0

# ============================================================================
# ITEM SPAWNING
# ============================================================================

@export_group("Item Spawning")

## Item spawn rules: [{"item_scene": path, "weight": float}]
@export var item_spawn_table: Array[Dictionary] = []

## Item density (0.0 = rare, 1.0 = common)
@export_range(0.0, 1.0) var item_density: float = 0.1

## Guaranteed starting items for this level
@export var starting_items: Array[String] = []

# ============================================================================
# EXIT CONFIGURATION
# ============================================================================

@export_group("Exit Configuration")

## Probability of exit spawning in a room (0.0 - 1.0)
@export_range(0.0, 1.0) var exit_spawn_chance: float = 0.05

## Level IDs this level can exit to (for noclipping/transitions)
## Example: [1, 2, 3] means exits can lead to levels 1, 2, or 3
@export var exit_destinations: Array[int] = []

## Minimum distance from spawn point to nearest exit
@export var min_exit_distance: int = 50

# ============================================================================
# AUDIO
# ============================================================================

@export_group("Audio")

## Ambient sound loop (e.g., "fluorescent_hum", "machinery_rumble")
@export var ambient_sound: AudioStream = null

## Ambient sound volume (0.0 - 1.0)
@export_range(0.0, 1.0) var ambient_volume: float = 0.3

## Background music track (optional)
@export var music_track: AudioStream = null

## Music volume (0.0 - 1.0)
@export_range(0.0, 1.0) var music_volume: float = 0.2

# ============================================================================
# GAMEPLAY MODIFIERS
# ============================================================================

@export_group("Gameplay Modifiers")

## Time scale multiplier (affects animation speeds, not turn logic)
@export_range(0.5, 2.0) var time_scale: float = 1.0

## Sanity drain per turn
@export_range(0.0, 1.0) var sanity_drain_rate: float = 0.1

## Visibility range in tiles (fog of war)
@export_range(5, 50) var visibility_range: int = 15

## Enable ceiling transparency vignette (for top-down view)
@export var enable_ceiling_vignette: bool = true

## Ceiling vignette inner radius (0.0 - 1.0, center transparent)
@export_range(0.0, 1.0) var vignette_inner_radius: float = 0.2

## Ceiling vignette outer radius (0.0 - 1.0, edge opaque)
@export_range(0.0, 1.0) var vignette_outer_radius: float = 0.8

# ============================================================================
# LIFECYCLE HOOKS (Override in subclasses)
# ============================================================================

## Called when level is loaded (before grid generation)
func on_load() -> void:
	Log.system("Loading level: %s (ID: %d)" % [display_name, level_id])

## Called when level generation is complete
func on_generation_complete() -> void:
	Log.system("Level generation complete: %s" % display_name)

## Called when player enters this level
func on_enter() -> void:
	Log.player("Entered level: %s" % display_name)

## Called when player exits this level
func on_exit() -> void:
	Log.player("Exited level: %s" % display_name)

## Called when level is unloaded from memory
func on_unload() -> void:
	Log.system("Unloading level: %s" % display_name)

# ============================================================================
# HELPER METHODS
# ============================================================================

## Get a random entity scene path based on spawn weights
func get_random_entity() -> String:
	if entity_spawn_table.is_empty():
		return ""

	var total_weight := 0.0
	for entry in entity_spawn_table:
		total_weight += entry.get("weight", 1.0)

	var roll := randf() * total_weight
	var cumulative := 0.0

	for entry in entity_spawn_table:
		cumulative += entry.get("weight", 1.0)
		if roll <= cumulative:
			return entry.get("entity_scene", "")

	return ""

## Get a random item scene path based on spawn weights
func get_random_item() -> String:
	if item_spawn_table.is_empty():
		return ""

	var total_weight := 0.0
	for entry in item_spawn_table:
		total_weight += entry.get("weight", 1.0)

	var roll := randf() * total_weight
	var cumulative := 0.0

	for entry in item_spawn_table:
		cumulative += entry.get("weight", 1.0)
		if roll <= cumulative:
			return entry.get("item_scene", "")

	return ""

## Get a random exit destination level ID
func get_random_exit_destination() -> int:
	if exit_destinations.is_empty():
		return -1
	return exit_destinations[randi() % exit_destinations.size()]

## Validate configuration (called by LevelManager before loading)
func validate() -> bool:
	var valid := true

	if level_id < 0:
		push_error("[LevelConfig] Invalid level_id: %d" % level_id)
		valid = false

	if display_name.is_empty():
		push_warning("[LevelConfig] Missing display_name for level %d" % level_id)

	if mesh_library_path.is_empty():
		push_error("[LevelConfig] Missing mesh_library_path for level %d" % level_id)
		valid = false

	# Note: We don't check FileAccess.file_exists() because:
	# 1. It doesn't work reliably in web builds (packed filesystem)
	# 2. The actual load() in grid_3d.gd will fail with a clear error if file is missing
	# 3. Validation should check data correctness, not file system state

	return valid
