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

# Grid data (same as 2D version)
var grid_size: Vector2i = GRID_SIZE
var walkable_cells: Dictionary = {}  # Vector2i -> bool (using Dictionary for O(1) erase instead of O(n))

# Current level configuration
var current_level: LevelConfig = null

# Player reference (for line-of-sight proximity fade)
var player_node: Node3D = null

# Procedural generation mode (set by ChunkManager)
var use_procedural_generation: bool = false

# Cached materials for proximity fade (for updating player_position uniform)
var wall_materials: Array[ShaderMaterial] = []
var ceiling_materials: Array[ShaderMaterial] = []

# MeshLibrary item IDs
enum TileType {
	FLOOR = 0,
	WALL = 1,
	CEILING = 2,
}

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

	print("[Grid3D] Initialized: %d x %d (octant size: %d)" % [grid_size.x, grid_size.y, grid_map.cell_octant_size])

func configure_from_level(level_config: LevelConfig) -> void:
	"""Configure grid from a LevelConfig resource"""
	if not level_config:
		push_error("[Grid3D] Cannot configure from null LevelConfig")
		return

	current_level = level_config
	grid_size = level_config.grid_size

	Log.system("Configuring grid for: %s" % level_config.display_name)
	Log.system("Grid size: %d x %d" % [grid_size.x, grid_size.y])

	# Check if ChunkManager exists (indicates procedural generation mode)
	if has_node("/root/ChunkManager"):
		use_procedural_generation = true
		Log.system("ChunkManager detected - enabling procedural generation mode")

		# Debug: Log our node path so ChunkManager can find us
		var our_path = get_path()
		Log.system("Grid3D path: %s" % our_path)

	# Apply visual settings
	_apply_level_visuals(level_config)

	# Procedural mode: ChunkManager will populate via load_chunk()
	Log.system("Procedural generation mode enabled - waiting for ChunkManager")

	# Cache materials and generate examination overlay
	_cache_wall_materials()
	_cache_ceiling_materials()
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
			Log.system("Applied background color: %s" % config.background_color)

			# Fog settings (future: enable when fog system is ready)
			# Will create depth and atmosphere, hide distant geometry
			# env.fog_enabled = true
			# env.fog_light_color = config.fog_color
			# env.fog_density = ...
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

		Log.system("Applied directional light: color=%s energy=%.2f rotation=%s" % [
			config.directional_light_color,
			config.directional_light_energy,
			config.directional_light_rotation
		])
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
			Log.system("Loaded MeshLibrary: %s" % config.mesh_library_path)
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

					# Place floor or wall based on tile type (Y=0 layer)
					if tile_type == SubChunk.TileType.WALL:
						grid_map.set_cell_item(grid_pos, TileType.WALL)
						wall_count += 1
					elif tile_type == SubChunk.TileType.FLOOR:
						grid_map.set_cell_item(grid_pos, TileType.FLOOR)
						floor_count += 1
						walkable_cells[world_tile_pos] = true

					# Place ceiling from chunk data (Y=1 layer) - level generator controls placement
					var ceiling_tile_type = sub_chunk.get_tile_at_layer(tile_pos, 1)
					if ceiling_tile_type == SubChunk.TileType.CEILING:
						grid_map.set_cell_item(Vector3i(world_tile_pos.x, 1, world_tile_pos.y), TileType.CEILING)

	var load_time := (Time.get_ticks_usec() - load_start) / 1000.0

	# Render items in chunk
	if item_renderer:
		item_renderer.render_chunk_items(chunk)

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

	Log.grid("Unloaded chunk %s from GridMap" % chunk.position)

func _cache_wall_materials() -> void:
	"""Cache wall materials from MeshLibrary for player position updates"""
	wall_materials.clear()

	var mesh_library = grid_map.mesh_library
	if not mesh_library:
		push_warning("[Grid3D] No MeshLibrary found, cannot cache wall materials")
		return

	# Get wall material from MeshLibrary
	var wall_mesh = mesh_library.get_item_mesh(TileType.WALL)
	if not wall_mesh:
		push_warning("[Grid3D] Wall mesh not found in MeshLibrary")
		return

	# Get material from the wall mesh
	for i in range(wall_mesh.get_surface_count()):
		var material = wall_mesh.surface_get_material(i)
		if material and material is ShaderMaterial:
			wall_materials.append(material)
			var shader_path = material.shader.resource_path if material.shader else "no shader"
			print("[Grid3D] Cached wall material %d: %s" % [i, shader_path])

			# Try to get current player_position value to verify uniform exists
			var test_value = material.get_shader_parameter("player_position")
			if test_value != null:
				print("[Grid3D] ✓ Material has player_position uniform (current: %s)" % test_value)
			else:
				push_warning("[Grid3D] ✗ Material missing player_position uniform!")

	print("[Grid3D] Total wall materials cached: %d" % wall_materials.size())

func _cache_ceiling_materials() -> void:
	"""Cache ceiling materials from MeshLibrary for player position updates"""
	ceiling_materials.clear()

	var mesh_library = grid_map.mesh_library
	if not mesh_library:
		push_warning("[Grid3D] No MeshLibrary found, cannot cache ceiling materials")
		return

	# Get ceiling material from MeshLibrary
	var ceiling_mesh = mesh_library.get_item_mesh(TileType.CEILING)
	if not ceiling_mesh:
		push_warning("[Grid3D] Ceiling mesh not found in MeshLibrary")
		return

	# Get material from the ceiling mesh
	for i in range(ceiling_mesh.get_surface_count()):
		var material = ceiling_mesh.surface_get_material(i)
		if material and material is ShaderMaterial:
			ceiling_materials.append(material)
			var shader_path = material.shader.resource_path if material.shader else "no shader"
			print("[Grid3D] Cached ceiling material %d: %s" % [i, shader_path])

			# Try to get current player_position value to verify uniform exists
			var test_value = material.get_shader_parameter("player_position")
			if test_value != null:
				print("[Grid3D] ✓ Material has player_position uniform (current: %s)" % test_value)
			else:
				push_warning("[Grid3D] ✗ Material missing player_position uniform!")

	print("[Grid3D] Total ceiling materials cached: %d" % ceiling_materials.size())

# Debug: Track frame count for periodic logging
var _frame_count: int = 0

func _process(_delta: float) -> void:
	"""Update wall and ceiling shader uniforms with player position for line-of-sight fade"""
	_frame_count += 1

	if not player_node or (wall_materials.is_empty() and ceiling_materials.is_empty()):
		if _frame_count % 60 == 0:  # Log once per second
			if not player_node:
				print("[Grid3D] No player_node set for proximity fade")
			if wall_materials.is_empty():
				print("[Grid3D] No wall materials cached")
			if ceiling_materials.is_empty():
				print("[Grid3D] No ceiling materials cached")
		return

	# Update all materials with current player position
	var player_pos = player_node.global_position

	# Update wall materials
	for material in wall_materials:
		material.set_shader_parameter("player_position", player_pos)

	# Update ceiling materials
	for material in ceiling_materials:
		material.set_shader_parameter("player_position", player_pos)

func set_player(player: Node3D) -> void:
	"""Set player reference for line-of-sight proximity fade"""
	player_node = player
	Log.msg(Log.Category.GRID, Log.Level.INFO,
		"Player linked to Grid3D for proximity fade updates")

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
	"""Check if grid position is walkable

	For procedural generation (infinite world), queries GridMap directly.
	For static levels, checks bounds first.
	"""
	# For procedural generation: infinite world, no bounds checking
	if use_procedural_generation:
		var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
		return cell_item == TileType.FLOOR

	# For static levels: check bounds first
	if not is_in_bounds(pos):
		return false

	var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
	return cell_item == TileType.FLOOR

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
