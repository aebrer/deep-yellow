class_name Grid3D
extends Node3D
## 3D grid system using GridMap for tile-based world
##
## Maintains same logical grid (Vector2i) as 2D version,
## but renders in 3D space using GridMap.
##
## Now supports LevelConfig for configurable generation parameters.

# Grid configuration
const GRID_SIZE := Vector2i(128, 128)
const CELL_SIZE := Vector3(2.0, 1.0, 2.0)  # X, Y (height), Z - doubled for visibility

# GridMap reference
@onready var grid_map: GridMap = $GridMap

# Item rendering
var item_renderer: ItemRenderer = null

# Entity rendering
var entity_renderer: EntityRenderer = null

# Spraypaint text rendering
var spraypaint_renderer: SpraypaintRenderer = null

# Grid data (same as 2D version)
var grid_size: Vector2i = GRID_SIZE
var walkable_cells: Dictionary = {}  # Vector2i -> bool (using Dictionary for O(1) erase instead of O(n))

# Current level configuration
var current_level: LevelConfig = null

# Player reference (for line-of-sight proximity fade)
var player_node: Node3D = null

# Procedural generation mode (set by ChunkManager)
var use_procedural_generation: bool = false

# Cached materials for proximity fade and lighting uniforms
var wall_materials: Array[ShaderMaterial] = []
var ceiling_materials: Array[ShaderMaterial] = []
var floor_materials: Array[ShaderMaterial] = []

# All lit materials (union of floor + wall + ceiling) for lighting uniform updates
var all_lit_materials: Array[ShaderMaterial] = []

# ============================================================================
# SHADER-BASED LIGHTING
# ============================================================================
# Light positions, colors, and ranges are passed as uniform arrays to all lit
# shaders every frame. This replaces OmniLight3D nodes entirely.
# See shaders/psx_lighting.gdshaderinc for the shader-side implementation.

const MAX_SHADER_LIGHTS := 16

# Pre-allocated arrays for shader uniforms (avoid per-frame allocation)
var _light_positions: Array = []  # Array of Vector3
var _light_colors: Array = []     # Array of Vector3 (RGB * energy)
var _light_ranges: Array = []     # Array of float

# Player light config (subtle always-on light attached to player)
var _player_light_color := Vector3(1.0, 0.98, 0.9)  # Warm white
var _player_light_range := 7.0
var _player_light_energy := 0.6

# Movement threshold: only re-sort lights when player moves >1 cell
var _last_light_update_pos := Vector3.INF

# Exit tile positions: tracked for minimap rendering
var exit_tile_positions: Dictionary = {}  # Vector2i -> true (world positions of EXIT_STAIRS)

# ============================================================================
# TILE TYPE SYSTEM (Data-Driven)
# ============================================================================
# Tile categories are determined by the current level's tile_mapping dictionary.
# Each level maps SubChunk.TileType values to MeshLibrary item IDs.
# These static caches are rebuilt when configure_from_level() is called.

# Cached sets of MeshLibrary item IDs by category (rebuilt per level)
static var _floor_items: Dictionary = {}  # {item_id: true}
static var _wall_items: Dictionary = {}   # {item_id: true}
static var _ceiling_items: Dictionary = {} # {item_id: true}
static var _door_items: Dictionary = {}    # {item_id: true} (doors in any state)
# Cached tile_mapping from current level
static var _tile_mapping: Dictionary = {}

static func _rebuild_tile_category_cache(tile_mapping: Dictionary) -> void:
	"""Rebuild category caches from a level's tile_mapping dictionary"""
	_floor_items.clear()
	_wall_items.clear()
	_ceiling_items.clear()
	_door_items.clear()
	_tile_mapping = tile_mapping
	for subchunk_type in tile_mapping:
		var item_id: int = tile_mapping[subchunk_type]
		if SubChunk.is_door_type(subchunk_type):
			_door_items[item_id] = true
		if SubChunk.is_floor_type(subchunk_type):
			_floor_items[item_id] = true
		elif SubChunk.is_wall_type(subchunk_type):
			_wall_items[item_id] = true
		elif SubChunk.is_ceiling_type(subchunk_type):
			_ceiling_items[item_id] = true

# ============================================================================
# TILE TYPE HELPERS
# ============================================================================

static func is_floor_tile(item_id: int) -> bool:
	"""Check if a GridMap cell item is any floor variant in the current level"""
	return _floor_items.has(item_id)

static func is_wall_tile(item_id: int) -> bool:
	"""Check if a GridMap cell item is any wall variant in the current level"""
	return _wall_items.has(item_id)

static func is_ceiling_tile(item_id: int) -> bool:
	"""Check if a GridMap cell item is any ceiling variant in the current level"""
	return _ceiling_items.has(item_id)

static func is_door_tile(item_id: int) -> bool:
	"""Check if a GridMap cell item is a door (open or closed) in the current level"""
	return _door_items.has(item_id)

static func subchunk_to_gridmap_item(tile_type: int) -> int:
	"""Convert SubChunk.TileType to MeshLibrary item ID using current level's mapping"""
	if _tile_mapping.has(tile_type):
		return _tile_mapping[tile_type]
	# Fallback: map variant to its base type
	if SubChunk.is_floor_type(tile_type):
		return _tile_mapping.get(0, 0)  # Fall back to base floor
	elif SubChunk.is_wall_type(tile_type):
		return _tile_mapping.get(1, 1)  # Fall back to base wall
	elif SubChunk.is_ceiling_type(tile_type):
		return _tile_mapping.get(2, 2)  # Fall back to base ceiling
	return tile_type  # Last resort passthrough

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	grid_map.cell_size = CELL_SIZE

	# Increase octant size for better procedural generation performance
	# Default is 8, higher values reduce update overhead during chunk population
	# Trade-off: More draw calls per octant (acceptable for modern renderers)
	grid_map.cell_octant_size = 16

	# Create item renderer
	item_renderer = ItemRenderer.new()
	add_child(item_renderer)

	# Create entity renderer
	entity_renderer = EntityRenderer.new()
	add_child(entity_renderer)

	# Create spraypaint renderer
	spraypaint_renderer = SpraypaintRenderer.new()
	add_child(spraypaint_renderer)

	print("[Grid3D] Initialized: %d x %d (octant size: %d)" % [grid_size.x, grid_size.y, grid_map.cell_octant_size])

func configure_from_level(level_config: LevelConfig) -> void:
	"""Configure grid from a LevelConfig resource"""
	if not level_config:
		push_error("[Grid3D] Cannot configure from null LevelConfig")
		return

	current_level = level_config
	grid_size = level_config.grid_size

	# Build tile category caches from level's tile_mapping
	if not level_config.tile_mapping.is_empty():
		Grid3D._rebuild_tile_category_cache(level_config.tile_mapping)
	else:
		push_warning("[Grid3D] Level %d has empty tile_mapping — tile category checks may fail" % level_config.level_id)

	# Check if ChunkManager exists (indicates procedural generation mode)
	if has_node("/root/ChunkManager"):
		use_procedural_generation = true

		# Debug: Log our node path so ChunkManager can find us
		var our_path = get_path()

	# Apply visual settings
	_apply_level_visuals(level_config)

	# Procedural mode: ChunkManager will populate via load_chunk()

	# Cache materials for proximity fade and lighting uniforms
	_cache_wall_materials()
	_cache_ceiling_materials()
	_cache_floor_materials()
	_build_all_lit_materials()
	# Note: Examination overlay will be generated per-chunk as they load

	# Lifecycle hook
	level_config.on_generation_complete()

func _apply_level_visuals(config: LevelConfig) -> void:
	"""Apply visual settings from level config to scene nodes at runtime

	This function is the bridge between level configs and the actual scene.
	It takes level-specific settings (colors, lighting, materials) and applies
	them to the WorldEnvironment, DirectionalLight3D, and GridMap nodes.

	WHY: Each Backrooms level has unique atmosphere. Level 0 has fluorescent
	lighting and beige ceilings, but Level 1 might have red emergency lighting
	and dark industrial backgrounds. By centralizing this logic here, we can
	easily add new levels without touching scene files.

	IMPORTANT: game_3d.tscn has NEUTRAL DEFAULTS (grey background, white light).
	Those defaults are ALWAYS overridden by level config values at runtime.
	"""

	# ========================================================================
	# ENVIRONMENT - Background, fog, ambient lighting
	# ========================================================================
	# The WorldEnvironment defines what you see beyond geometry (horizon/skybox)
	# and atmospheric effects like fog.
	# NOTE: Using relative path "../WorldEnvironment" because Grid3D is a sibling
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env:
		var env = world_env.environment
		if env:
			# Background color: What player sees at horizon in tactical cam
			# Level 0: Greyish-beige (like stained office ceiling tiles)
			# Future levels: Could be black void, red emergency lights, etc.
			env.background_mode = Environment.BG_COLOR
			env.background_color = config.background_color

			# Ambient light — fills shadowed areas so geometry isn't pitch black
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = config.ambient_light_color
			env.ambient_light_energy = config.ambient_light_intensity

			# Fog settings (distance-based)
			if config.fog_start > 0.0 and config.fog_end > 0.0:
				env.fog_enabled = true
				env.fog_light_color = config.fog_color
				env.fog_depth_begin = config.fog_start
				env.fog_depth_end = config.fog_end
				env.fog_density = 0.001  # Near-zero density, rely on depth range
			else:
				env.fog_enabled = false
	else:
		push_warning("[Grid3D] WorldEnvironment node not found - cannot apply background color")

	# ========================================================================
	# DIRECTIONAL LIGHT - Main scene lighting (sun/overhead lights)
	# ========================================================================
	# DirectionalLight3D illuminates the entire level uniformly from one direction.
	# Think of it as the "sun" for outdoor scenes, or "fluorescent panels" for
	# indoor scenes like the Backrooms.
	# NOTE: Using relative path "../OverheadLight" because Grid3D is a sibling
	var light = get_node_or_null("../OverheadLight")
	if light and light is DirectionalLight3D:
		# Color: Tints the lighting (white = neutral, blue = cold, yellow = warm)
		# Level 0: Slight blue tint for fluorescent light feel
		light.light_color = config.directional_light_color

		# Energy: Brightness/intensity (0.0 = off, 1.0 = standard, 2.0 = very bright)
		# Level 0: 0.9 for well-lit office environment
		light.light_energy = config.directional_light_energy

		# Rotation: Direction light comes from (in degrees)
		# Level 0: (0, 0, 80) = nearly straight down from above (overhead fluorescents)
		# Future: (45, 0, 45) might be angled like setting sun, etc.
		light.rotation_degrees = config.directional_light_rotation
	else:
		push_warning("[Grid3D] OverheadLight node not found - cannot apply lighting settings")

	# ========================================================================
	# MESH LIBRARY - Tile geometry and materials
	# ========================================================================
	# Each level can have different wall/floor/ceiling meshes and textures.
	# MeshLibrary defines what gets placed when GridMap sets a cell.
	var current_mesh_lib_path = grid_map.mesh_library.resource_path if grid_map.mesh_library else ""
	if not config.mesh_library_path.is_empty() and config.mesh_library_path != current_mesh_lib_path:
		var mesh_lib = load(config.mesh_library_path) as MeshLibrary
		if mesh_lib:
			grid_map.mesh_library = mesh_lib
		else:
			push_error("[Grid3D] Failed to load MeshLibrary: %s" % config.mesh_library_path)

# ============================================================================
# CHUNK LOADING (Procedural Generation Integration)
# ============================================================================

func load_chunk(chunk: Chunk) -> void:
	"""Load a chunk from ChunkManager into GridMap

	Converts chunk's SubChunk tile data into GridMap cells.
	Each chunk is 128×128 tiles, organized as 8×8 sub-chunks (16×16 each).
	"""
	if not chunk:
		push_warning("[Grid3D] Attempted to load null chunk")
		return

	var load_start := Time.get_ticks_usec()

	# Convert chunk position to world tile offset
	var chunk_world_offset := chunk.position * Chunk.SIZE

	# Track tile counts for debugging
	var wall_count := 0
	var floor_count := 0

	# Iterate through all sub-chunks in the chunk
	for sub_y in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sub_x in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub_chunk := chunk.get_sub_chunk(Vector2i(sub_x, sub_y))
			if not sub_chunk:
				Log.warn(Log.Category.GRID, "Null sub-chunk at (%d, %d) in chunk %s - skipping tiles" % [sub_x, sub_y, chunk.position])
				continue

			# Calculate sub-chunk's world tile offset
			var sub_world_offset := chunk_world_offset + Vector2i(sub_x, sub_y) * SubChunk.SIZE

			# Place tiles from sub-chunk
			for tile_y in range(SubChunk.SIZE):
				for tile_x in range(SubChunk.SIZE):
					var tile_pos := Vector2i(tile_x, tile_y)
					var tile_type: int = sub_chunk.get_tile(tile_pos)
					var world_tile_pos := sub_world_offset + tile_pos

					# Convert to 3D grid coordinates
					var grid_pos := Vector3i(world_tile_pos.x, 0, world_tile_pos.y)

					# Convert SubChunk tile type to MeshLibrary item ID
					var gridmap_item: int = Grid3D.subchunk_to_gridmap_item(tile_type)

					# Place floor or wall based on tile type (Y=0 layer)
					if SubChunk.is_wall_type(tile_type):
						grid_map.set_cell_item(grid_pos, gridmap_item)
						wall_count += 1
					elif SubChunk.is_floor_type(tile_type):
						grid_map.set_cell_item(grid_pos, gridmap_item)
						floor_count += 1
						walkable_cells[world_tile_pos] = true

					# Place ceiling from chunk data (Y=1 layer) - level generator controls placement
					var ceiling_tile_type = sub_chunk.get_tile_at_layer(tile_pos, 1)
					if SubChunk.is_ceiling_type(ceiling_tile_type):
						var ceiling_item: int = Grid3D.subchunk_to_gridmap_item(ceiling_tile_type)
						grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), ceiling_item)

	# Scan for EXIT_STAIRS tiles and spawn exit_hole entities (rendered by EntityRenderer)
	_scan_exit_stairs_for_chunk(chunk)

	var load_time := (Time.get_ticks_usec() - load_start) / 1000.0

	# Render items in chunk (items are already in chunk data from _on_chunk_completed)
	if item_renderer:
		item_renderer.render_chunk_items(chunk)

	# Render spraypaint text in chunk
	if spraypaint_renderer:
		spraypaint_renderer.render_chunk_spraypaint(chunk)

	# NOTE: Entity rendering is handled by ChunkManager AFTER entity spawning
	# because entities need is_walkable() which requires GridMap to be populated first

func unload_chunk(chunk: Chunk) -> void:
	"""Unload a chunk from GridMap

	Removes all tiles from this chunk's area.
	"""
	if not chunk:
		push_warning("[Grid3D] Attempted to unload null chunk")
		return

	# Convert chunk position to world tile offset
	var chunk_world_offset := chunk.position * Chunk.SIZE

	# Clear all tiles in chunk area
	for y in range(Chunk.SIZE):
		for x in range(Chunk.SIZE):
			var world_tile_pos := chunk_world_offset + Vector2i(x, y)
			var grid_pos := Vector3i(world_tile_pos.x, 0, world_tile_pos.y)

			# Clear floor/wall
			grid_map.set_cell_item(grid_pos, GridMap.INVALID_CELL_ITEM)

			# Clear ceiling
			grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), GridMap.INVALID_CELL_ITEM)

			# Remove from walkable cells
			walkable_cells.erase(world_tile_pos)

	# Unload item billboards
	if item_renderer:
		item_renderer.unload_chunk_items(chunk)

	# Unload entity billboards
	if entity_renderer:
		entity_renderer.unload_chunk_entities(chunk)

	# Unload spraypaint labels
	if spraypaint_renderer:
		spraypaint_renderer.unload_chunk_spraypaint(chunk)

	# Unload exit hole position tracking for chunk
	_unload_exit_positions_for_chunk(chunk)


# ============================================================================
# EXIT HOLE TRACKING (EXIT_STAIRS tiles → WorldEntity objects)
# ============================================================================

func _scan_exit_stairs_for_chunk(chunk: Chunk) -> void:
	"""Scan chunk for EXIT_STAIRS tiles and spawn exit_hole entities.

	Creates WorldEntity objects for each EXIT_STAIRS tile found and adds them
	to the subchunk. EntityRenderer handles visual rendering (floor decal mode).
	Also tracks positions in exit_tile_positions for the minimap.
	"""
	var chunk_world_offset := chunk.position * Chunk.SIZE

	for sub_y in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sub_x in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub_chunk := chunk.get_sub_chunk(Vector2i(sub_x, sub_y))
			if not sub_chunk:
				continue

			var sub_world_offset := chunk_world_offset + Vector2i(sub_x, sub_y) * SubChunk.SIZE

			for tile_y in range(SubChunk.SIZE):
				for tile_x in range(SubChunk.SIZE):
					var tile_type: int = sub_chunk.get_tile(Vector2i(tile_x, tile_y))
					if tile_type == SubChunk.TileType.EXIT_STAIRS:
						var world_tile_pos := sub_world_offset + Vector2i(tile_x, tile_y)
						exit_tile_positions[world_tile_pos] = true

						# Spawn exit_hole entity if not already present
						var existing = false
						for entity in sub_chunk.world_entities:
							if entity.world_position == world_tile_pos and entity.entity_type == "exit_hole":
								existing = true
								break
						if not existing:
							var exit_entity := WorldEntity.new("exit_hole", world_tile_pos, 99999.0, 0)
							EntityRegistry.apply_defaults(exit_entity)
							sub_chunk.add_world_entity(exit_entity)

func _unload_exit_positions_for_chunk(chunk: Chunk) -> void:
	"""Remove exit tile position tracking for a chunk (entity cleanup handled by EntityRenderer)"""
	var chunk_world_offset := chunk.position * Chunk.SIZE
	for sub_y in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sub_x in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub_world_offset := chunk_world_offset + Vector2i(sub_x, sub_y) * SubChunk.SIZE
			for tile_y in range(SubChunk.SIZE):
				for tile_x in range(SubChunk.SIZE):
					var pos := sub_world_offset + Vector2i(tile_x, tile_y)
					exit_tile_positions.erase(pos)

func clear_exit_holes() -> void:
	"""Clear exit hole position tracking (used during level transitions)"""
	exit_tile_positions.clear()

# ============================================================================
# TILE UPDATES
# ============================================================================

func update_tile(world_tile_pos: Vector2i, tile_type: int, ceiling_type: int = -1) -> void:
	"""Update a single tile in the GridMap (used for post-generation modifications).

	Args:
		world_tile_pos: World tile position to update
		tile_type: TileType for layer 0 (any floor or wall variant)
		ceiling_type: TileType for layer 1, or -1 to skip ceiling update
	"""
	var grid_pos := Vector3i(world_tile_pos.x, 0, world_tile_pos.y)

	# Update floor/wall layer
	if Grid3D.is_wall_tile(tile_type):
		grid_map.set_cell_item(grid_pos, tile_type)
		walkable_cells.erase(world_tile_pos)
	elif Grid3D.is_floor_tile(tile_type):
		grid_map.set_cell_item(grid_pos, tile_type)
		walkable_cells[world_tile_pos] = true

	# Update ceiling layer if requested
	if ceiling_type >= 0:
		grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), ceiling_type)


# ============================================================================
# DOOR SYSTEM (tile swapping between wall/floor variants)
# ============================================================================

func toggle_door(world_tile_pos: Vector2i) -> bool:
	"""Toggle a door between open (floor variant) and closed (wall variant).

	Handles:
	- GridMap cell swap (visual)
	- walkable_cells update
	- SubChunk tile_data persistence (via ChunkManager)
	- Pathfinding graph update (via PathfindingManager)
	- Ceiling add/remove (open doors need ceilings, closed doors don't)

	Returns:
		true if door was toggled, false if tile at position is not a door
	"""
	# Get current tile type from SubChunk data (authoritative source)
	var current_tile := _get_subchunk_tile_type(world_tile_pos)
	if current_tile < 0:
		return false

	if not SubChunk.is_door_type(current_tile):
		return false

	var new_tile: int = SubChunk.get_door_pair(current_tile)
	if new_tile < 0:
		return false

	# Convert new tile type to GridMap item ID
	var new_item: int = Grid3D.subchunk_to_gridmap_item(new_tile)
	var grid_pos := Vector3i(world_tile_pos.x, 0, world_tile_pos.y)

	# Swap tile in GridMap
	grid_map.set_cell_item(grid_pos, new_item)

	# Update walkable_cells
	if SubChunk.is_floor_type(new_tile):
		# Door opened → now walkable
		walkable_cells[world_tile_pos] = true
		# Add ceiling above open door
		var ceiling_item: int = Grid3D.subchunk_to_gridmap_item(SubChunk.TileType.CEILING)
		grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), ceiling_item)
		# Update pathfinding
		Pathfinding.add_walkable_tile(world_tile_pos)
	else:
		# Door closed → now impassable
		walkable_cells.erase(world_tile_pos)
		# Remove ceiling above closed door (walls have no ceiling)
		grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), GridMap.INVALID_CELL_ITEM)
		# Remove from pathfinding
		Pathfinding.remove_walkable_tile(world_tile_pos)

	# Persist to SubChunk data (survives chunk unload/reload)
	_set_subchunk_tile_type(world_tile_pos, new_tile)
	# Also persist ceiling layer
	if SubChunk.is_floor_type(new_tile):
		_set_subchunk_tile_at_layer(world_tile_pos, 1, SubChunk.TileType.CEILING)
	else:
		_set_subchunk_tile_at_layer(world_tile_pos, 1, -1)

	Log.grid("Door toggled at %s: %d → %d" % [world_tile_pos, current_tile, new_tile])
	return true


func is_closed_door(world_tile_pos: Vector2i) -> bool:
	"""Check if tile at position is a closed door"""
	var tile := _get_subchunk_tile_type(world_tile_pos)
	return SubChunk.is_door_closed(tile)


func _get_chunk_for_tile(world_tile_pos: Vector2i) -> Chunk:
	"""Get the loaded Chunk containing a world tile position (via ChunkManager)"""
	var cm = get_node_or_null("/root/ChunkManager")
	if not cm:
		return null
	var level_id := 0
	var current := LevelManager.get_current_level()
	if current:
		level_id = current.level_id
	var chunk_pos := Vector2i(
		floori(float(world_tile_pos.x) / Chunk.SIZE),
		floori(float(world_tile_pos.y) / Chunk.SIZE)
	)
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
	if not cm.loaded_chunks.has(chunk_key):
		return null
	return cm.loaded_chunks[chunk_key]


func _get_subchunk_tile_type(world_tile_pos: Vector2i) -> int:
	"""Get SubChunk tile type at world position"""
	var chunk := _get_chunk_for_tile(world_tile_pos)
	if not chunk:
		return -1
	return chunk.get_tile(world_tile_pos)


func _set_subchunk_tile_type(world_tile_pos: Vector2i, tile_type: int) -> void:
	"""Set SubChunk tile type at world position"""
	var chunk := _get_chunk_for_tile(world_tile_pos)
	if not chunk:
		return
	chunk.set_tile(world_tile_pos, tile_type)


func _set_subchunk_tile_at_layer(world_tile_pos: Vector2i, layer: int, tile_type: int) -> void:
	"""Set SubChunk tile at world position and layer"""
	var chunk := _get_chunk_for_tile(world_tile_pos)
	if not chunk:
		return
	chunk.set_tile_at_layer(world_tile_pos, layer, tile_type)


func _cache_wall_materials() -> void:
	"""Cache wall materials from MeshLibrary for player position updates"""
	wall_materials.clear()

	var mesh_library = grid_map.mesh_library
	if not mesh_library:
		push_warning("[Grid3D] No MeshLibrary found, cannot cache wall materials")
		return

	# Cache materials from all wall-type items (base + variants)
	for item_id in _wall_items:
		var wall_mesh = mesh_library.get_item_mesh(item_id)
		if not wall_mesh:
			continue

		for i in range(wall_mesh.get_surface_count()):
			var material = wall_mesh.surface_get_material(i)
			if material and material is ShaderMaterial:
				if material not in wall_materials:
					wall_materials.append(material)
					var test_value = material.get_shader_parameter("player_position")
					if test_value == null:
						push_warning("[Grid3D] Wall material (item %d) missing player_position uniform!" % item_id)

func _cache_ceiling_materials() -> void:
	"""Cache ceiling materials from MeshLibrary for player position updates"""
	ceiling_materials.clear()

	var mesh_library = grid_map.mesh_library
	if not mesh_library:
		push_warning("[Grid3D] No MeshLibrary found, cannot cache ceiling materials")
		return

	# Cache materials from all ceiling-type items (base + variants)
	for item_id in _ceiling_items:
		var ceiling_mesh = mesh_library.get_item_mesh(item_id)
		if not ceiling_mesh:
			continue

		for i in range(ceiling_mesh.get_surface_count()):
			var material = ceiling_mesh.surface_get_material(i)
			if material and material is ShaderMaterial:
				if material not in ceiling_materials:
					ceiling_materials.append(material)
					var test_value = material.get_shader_parameter("player_position")
					if test_value == null:
						push_warning("[Grid3D] Ceiling material (item %d) missing player_position uniform!" % item_id)

func _cache_floor_materials() -> void:
	"""Cache floor materials from MeshLibrary for lighting uniform updates"""
	floor_materials.clear()

	var mesh_library = grid_map.mesh_library
	if not mesh_library:
		return

	for item_id in _floor_items:
		var floor_mesh = mesh_library.get_item_mesh(item_id)
		if not floor_mesh:
			continue

		for i in range(floor_mesh.get_surface_count()):
			var material = floor_mesh.surface_get_material(i)
			if material and material is ShaderMaterial:
				if material not in floor_materials:
					floor_materials.append(material)


func _build_all_lit_materials() -> void:
	"""Build combined list of all materials that receive lighting uniforms"""
	all_lit_materials.clear()
	for mat in floor_materials:
		if mat not in all_lit_materials:
			all_lit_materials.append(mat)
	for mat in wall_materials:
		if mat not in all_lit_materials:
			all_lit_materials.append(mat)
	for mat in ceiling_materials:
		if mat not in all_lit_materials:
			all_lit_materials.append(mat)
	print("[Grid3D] Cached %d lit materials for shader lighting" % all_lit_materials.size())

	# Push ambient light uniform from level config (replaces Godot's ambient
	# which is bypassed by render_mode unshaded).
	# Multiplier is needed because Godot's ambient system adds to vertex_lighting,
	# but in unshaded mode ambient is the ONLY baseline light in unlit areas.
	if current_level:
		var ac: Color = current_level.ambient_light_color
		var ai: float = current_level.ambient_light_intensity
		var ambient := Vector3(ac.r * ai, ac.g * ai, ac.b * ai)
		ambient *= 5.0  # Compensate for unshaded mode (no Godot ambient pipeline)
		for mat in all_lit_materials:
			mat.set_shader_parameter("ambient_light", ambient)


# Debug: Track frame count for periodic logging
var _frame_count: int = 0

func _process(_delta: float) -> void:
	"""Update shader uniforms: player position (proximity fade) + light data (point lights)"""
	_frame_count += 1

	if not player_node or all_lit_materials.is_empty():
		if _frame_count % 60 == 0:
			if not player_node:
				print("[Grid3D] No player_node set for proximity fade")
		return

	var player_pos = player_node.global_position

	# Update proximity fade player position (wall + ceiling materials only)
	for material in wall_materials:
		material.set_shader_parameter("player_position", player_pos)
	for material in ceiling_materials:
		material.set_shader_parameter("player_position", player_pos)

	# Collect nearest light positions from EntityRenderer
	_update_light_uniforms(player_pos)

func _update_light_uniforms(player_pos: Vector3) -> void:
	"""Collect nearest light positions from EntityRenderer and pass to all lit shaders.

	Replaces OmniLight3D nodes entirely. Light data comes from EntityRenderer's
	entity_cache — light-emitting entities store their world positions there.
	We sort by distance to player and take the nearest MAX_SHADER_LIGHTS.

	Optimization: only re-sorts when player moves >2 world units (1 grid cell).
	Light fixtures are static, so the sort order only changes with player movement.
	"""
	if not entity_renderer:
		return

	# Skip re-sort if player hasn't moved significantly (fixtures are static)
	if _last_light_update_pos.distance_squared_to(player_pos) < 4.0:  # 2.0^2
		# Still update player light position (it moves every frame)
		var pl_color := Vector3(
			_player_light_color.x * _player_light_energy,
			_player_light_color.y * _player_light_energy,
			_player_light_color.z * _player_light_energy
		)
		for material in all_lit_materials:
			material.set_shader_parameter("player_light_pos", player_pos)
			material.set_shader_parameter("player_light_color", pl_color)
			material.set_shader_parameter("player_light_range", _player_light_range)
		return
	_last_light_update_pos = player_pos

	# Collect all light-emitting entity positions and configs
	# EntityRenderer.entity_cache: Vector2i -> WorldEntity
	# EntityRenderer.ENTITY_LIGHT_CONFIG: entity_type -> {color, energy, range, ...}
	_light_positions.clear()
	_light_colors.clear()
	_light_ranges.clear()

	# Build unsorted list of (distance_sq, position, color, range)
	var light_data: Array = []
	for pos in entity_renderer.entity_cache:
		var entity: WorldEntity = entity_renderer.entity_cache[pos]
		if not entity or entity.is_dead:
			continue
		if not EntityRenderer.ENTITY_LIGHT_CONFIG.has(entity.entity_type):
			continue

		var config: Dictionary = EntityRenderer.ENTITY_LIGHT_CONFIG[entity.entity_type]
		var height: float = EntityRenderer.ENTITY_HEIGHT_OVERRIDES.get(entity.entity_type, EntityRenderer.BILLBOARD_HEIGHT)
		var world_3d: Vector3 = grid_to_world_centered(pos, height)
		var dist_sq: float = player_pos.distance_squared_to(world_3d)

		light_data.append({
			"dist_sq": dist_sq,
			"pos": world_3d,
			"color": config.get("color", Color.WHITE),
			"energy": config.get("energy", 1.0),
			"range": config.get("range", 8.0),
		})

	# Sort by distance (nearest first) and take MAX_SHADER_LIGHTS
	light_data.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	var count: int = mini(light_data.size(), MAX_SHADER_LIGHTS)

	# Build uniform arrays
	for i in range(count):
		var ld = light_data[i]
		_light_positions.append(ld.pos)
		var c: Color = ld.color
		var e: float = ld.energy
		_light_colors.append(Vector3(c.r * e, c.g * e, c.b * e))
		_light_ranges.append(ld.range)

	# Pad arrays to MAX_SHADER_LIGHTS (shader expects fixed-size arrays)
	while _light_positions.size() < MAX_SHADER_LIGHTS:
		_light_positions.append(Vector3.ZERO)
		_light_colors.append(Vector3.ZERO)
		_light_ranges.append(0.0)

	# Player light
	var pl_color := Vector3(
		_player_light_color.x * _player_light_energy,
		_player_light_color.y * _player_light_energy,
		_player_light_color.z * _player_light_energy
	)

	# Push to all lit materials
	for material in all_lit_materials:
		material.set_shader_parameter("light_count", count)
		material.set_shader_parameter("light_positions", _light_positions)
		material.set_shader_parameter("light_colors", _light_colors)
		material.set_shader_parameter("light_ranges", _light_ranges)
		material.set_shader_parameter("player_light_pos", player_pos)
		material.set_shader_parameter("player_light_color", pl_color)
		material.set_shader_parameter("player_light_range", _player_light_range)


func set_player(player: Node3D) -> void:
	"""Set player reference for line-of-sight proximity fade"""
	player_node = player
	Log.msg(Log.Category.GRID, Log.Level.INFO,
		"Player linked to Grid3D for proximity fade updates")

func set_proximity_fade_enabled(enabled: bool) -> void:
	"""Enable or disable proximity fade on wall/ceiling materials.

	Used to disable the see-through-walls effect in FPV mode where it
	breaks immersion by allowing players to see through nearby walls.
	"""
	for material in wall_materials:
		material.set_shader_parameter("enable_proximity_fade", enabled)

	for material in ceiling_materials:
		material.set_shader_parameter("enable_proximity_fade", enabled)

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	"""Convert 2D grid coordinates to 3D world position"""
	# Use GridMap's built-in conversion
	var cell_3d = Vector3i(grid_pos.x, 0, grid_pos.y)
	return grid_map.map_to_local(cell_3d)

func grid_to_world_centered(grid_pos: Vector2i, height: float = 0.0) -> Vector3:
	"""Convert 2D grid coordinates to 3D world position (centered in cell)

	Uses manual centering calculation for pixel-perfect alignment.
	This is the canonical centering method used by items and indicators.

	Args:
		grid_pos: Grid coordinates (x, y)
		height: Y position in world space (default 0.0)

	Returns:
		Vector3 position centered in the grid cell at specified height
	"""
	var cell_size = grid_map.cell_size
	return Vector3(
		grid_pos.x * cell_size.x + cell_size.x / 2.0,
		height,
		grid_pos.y * cell_size.z + cell_size.z / 2.0
	)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convert 3D world position to 2D grid coordinates"""
	var cell_3d = grid_map.local_to_map(world_pos)
	return Vector2i(cell_3d.x, cell_3d.z)

# ============================================================================
# GRID QUERIES (Same API as 2D version)
# ============================================================================

func is_walkable(pos: Vector2i) -> bool:
	"""Check if grid position is walkable (any floor variant + no entity blocking)

	For procedural generation (infinite world), queries GridMap directly.
	For static levels, checks bounds first.
	Also checks for entities blocking the position.
	"""
	# For procedural generation: infinite world, no bounds checking
	if use_procedural_generation:
		var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
		if not Grid3D.is_floor_tile(cell_item):
			return false

		# Check for entities blocking this position
		return not _is_position_blocked_by_entity(pos)

	# For static levels: check bounds first
	if not is_in_bounds(pos):
		return false

	var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
	if not Grid3D.is_floor_tile(cell_item):
		return false

	# Check for entities blocking this position
	return not _is_position_blocked_by_entity(pos)

func _is_position_blocked_by_entity(pos: Vector2i) -> bool:
	"""Check if a movement-blocking entity is occupying this grid position

	Returns true if blocked, false if clear.
	Only entities with blocks_movement=true block the tile.
	"""
	if entity_renderer:
		var entity = entity_renderer.get_entity_at(pos)
		return entity != null and not entity.is_dead and entity.blocks_movement
	return false

# ============================================================================
# ENTITY QUERIES
# ============================================================================

func get_entity_at(world_pos: Vector2i) -> WorldEntity:
	"""Get WorldEntity at world position

	Args:
		world_pos: World tile coordinates

	Returns:
		WorldEntity or null if no living entity at position
	"""
	if entity_renderer:
		return entity_renderer.get_entity_at(world_pos)
	return null

func is_in_bounds(pos: Vector2i) -> bool:
	"""Check if position is within grid bounds

	For procedural generation (infinite world), always returns true.
	For static levels, checks against grid_size.
	"""
	# For procedural generation: infinite world, no bounds
	if use_procedural_generation:
		return true

	# For static levels: check actual bounds
	return pos.x >= 0 and pos.x < grid_size.x and \
		   pos.y >= 0 and pos.y < grid_size.y

func get_random_walkable_position() -> Vector2i:
	"""Get random walkable position"""
	if walkable_cells.is_empty():
		# Fallback to grid center when no walkable cells
		@warning_ignore("integer_division")
		var center_x: int = grid_size.x / 2
		@warning_ignore("integer_division")
		var center_y: int = grid_size.y / 2
		return Vector2i(center_x, center_y)
	return walkable_cells.keys().pick_random()

# ============================================================================
# LINE OF SIGHT
# ============================================================================

func has_line_of_sight(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	"""Check if there's a clear line of sight between two positions.

	Uses Bresenham's line algorithm to check all tiles between positions.
	A wall (non-FLOOR tile) blocks line of sight.
	Entities do NOT block line of sight (attacks can pass through enemies).

	Args:
		from_pos: Starting grid position (e.g., player position)
		to_pos: Target grid position (e.g., enemy position)

	Returns:
		true if clear line of sight, false if blocked by wall
	"""
	# Same position = always has LOS
	if from_pos == to_pos:
		return true

	# Use Bresenham's line algorithm to get all tiles on the line
	var line_tiles = _get_line_tiles(from_pos, to_pos)

	# Check each tile (excluding start and end positions)
	for i in range(1, line_tiles.size() - 1):
		var tile_pos = line_tiles[i]
		if _is_tile_blocking_los(tile_pos):
			return false

	# Check diagonal wall gaps: consecutive tiles that differ on both axes
	# mean a diagonal step — block LOS if both adjacent cardinals are walls
	for i in range(line_tiles.size() - 1):
		var curr = line_tiles[i]
		var next = line_tiles[i + 1]
		var dx_step = abs(next.x - curr.x)
		var dy_step = abs(next.y - curr.y)
		if dx_step == 1 and dy_step == 1:
			var adj_x := Vector2i(next.x, curr.y)
			var adj_y := Vector2i(curr.x, next.y)
			if _is_tile_blocking_los(adj_x) and _is_tile_blocking_los(adj_y):
				return false

	return true


func _get_line_tiles(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	"""Get all tile positions on a line between two points using Bresenham's algorithm.

	Returns array of positions from start to end (inclusive).
	"""
	var tiles: Array[Vector2i] = []

	var x0 = from_pos.x
	var y0 = from_pos.y
	var x1 = to_pos.x
	var y1 = to_pos.y

	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy

	while true:
		tiles.append(Vector2i(x0, y0))

		if x0 == x1 and y0 == y1:
			break

		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return tiles


func _is_tile_blocking_los(pos: Vector2i) -> bool:
	"""Check if a tile blocks line of sight (walls block, floor doesn't).

	This is different from is_walkable() because:
	- Entities don't block LOS (attacks pass through enemies to hit all)
	- Only terrain/walls block LOS
	"""
	var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
	return not Grid3D.is_floor_tile(cell_item)
