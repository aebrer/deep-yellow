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

# Grid data (same as 2D version)
var grid_size: Vector2i = GRID_SIZE
var walkable_cells: Array[Vector2i] = []

# Current level configuration
var current_level: LevelConfig = null

# Player reference for shader updates
var player: Node3D = null

# Obstruction system: any material can register for camera→player updates
var obstruction_materials: Array[ShaderMaterial] = []  # All materials using psx_wall_obstruction.gdshader
var obstructed_cells: Array[Vector3i] = []  # Cells currently obstructed by raycasting

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
	print("[Grid3D] Initialized: %d x %d" % [grid_size.x, grid_size.y])

	# Cache shader material references
	_cache_shader_materials()

func _process(_delta: float) -> void:
	"""Update shaders with camera and player positions each frame"""
	if not player:
		return

	# Get camera and player positions
	var camera_pos = Vector3.ZERO
	if player.camera_rig and player.camera_rig.camera:
		camera_pos = player.camera_rig.camera.global_position
	var player_pos = player.global_position

	# Raycast from camera to player to find obstructed cells
	obstructed_cells.clear()
	_raycast_obstructions(camera_pos, player_pos)

	# DEBUG: Log raycast results
	if obstructed_cells.size() > 0:
		Log.system("Grid3D: Raycasting found %d obstructed cells" % obstructed_cells.size())

	# Convert Vector3i array to PackedVector3Array for shader
	var obstructed_positions = PackedVector3Array()
	for cell in obstructed_cells:
		obstructed_positions.append(Vector3(cell))

	# Update all registered materials with obstruction data
	for mat in obstruction_materials:
		if mat:
			mat.set_shader_parameter("player_world_position", player_pos)
			mat.set_shader_parameter("obstructed_cell_count", obstructed_cells.size())
			mat.set_shader_parameter("obstructed_cells", obstructed_positions)

	# DEBUG: Log what we're sending to shader (disabled)
	# if obstructed_cells.size() > 0:
	# 	Log.system("Grid3D: Updated %d materials with %d obstructed cells" % [obstruction_materials.size(), obstructed_cells.size()])

func initialize(size: Vector2i) -> void:
	"""Initialize grid with given size (legacy method)"""
	grid_size = size
	_generate_grid()

func configure_from_level(level_config: LevelConfig) -> void:
	"""Configure grid from a LevelConfig resource"""
	if not level_config:
		push_error("[Grid3D] Cannot configure from null LevelConfig")
		return

	current_level = level_config
	grid_size = level_config.grid_size

	Log.system("Configuring grid for: %s" % level_config.display_name)
	Log.system("Grid size: %d x %d" % [grid_size.x, grid_size.y])

	# Apply visual settings
	_apply_level_visuals(level_config)

	# Generate grid with level parameters
	_generate_grid()

	# Lifecycle hook
	level_config.on_generation_complete()

func _apply_level_visuals(config: LevelConfig) -> void:
	"""Apply visual settings from level config"""
	# Apply materials if provided
	if config.floor_material:
		Log.system("Applying custom floor material")
		# TODO: Apply to GridMap when material system is implemented

	if config.wall_material:
		Log.system("Applying custom wall material")
		# TODO: Apply to GridMap when material system is implemented

	# Apply fog settings
	if has_node("/root/Game3D/WorldEnvironment"):
		var env = get_node("/root/Game3D/WorldEnvironment").environment
		if env:
			# TODO: Configure fog when Environment is set up
			pass

	# Load custom MeshLibrary if specified
	if not config.mesh_library_path.is_empty() and config.mesh_library_path != grid_map.mesh_library.resource_path:
		var mesh_lib = load(config.mesh_library_path) as MeshLibrary
		if mesh_lib:
			grid_map.mesh_library = mesh_lib
			Log.system("Loaded MeshLibrary: %s" % config.mesh_library_path)
		else:
			push_error("[Grid3D] Failed to load MeshLibrary: %s" % config.mesh_library_path)

# ============================================================================
# GRID GENERATION
# ============================================================================

func _generate_grid() -> void:
	"""Generate 3D grid using GridMap"""
	# For now, create simple open area with walls around edges
	# TODO: Replace with Backrooms procedural generation

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var pos = Vector2i(x, y)
			var is_edge = x == 0 or x == grid_size.x - 1 or y == 0 or y == grid_size.y - 1

			if is_edge:
				# Place wall
				grid_map.set_cell_item(Vector3i(x, 0, y), TileType.WALL)
			else:
				# Place floor
				grid_map.set_cell_item(Vector3i(x, 0, y), TileType.FLOOR)
				walkable_cells.append(pos)

			# Place ceiling everywhere (at y=1 in grid space, which is y=4 in world space due to mesh_transform)
			grid_map.set_cell_item(Vector3i(x, 1, y), TileType.CEILING)

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	"""Convert 2D grid coordinates to 3D world position"""
	# Use GridMap's built-in conversion
	var cell_3d = Vector3i(grid_pos.x, 0, grid_pos.y)
	return grid_map.map_to_local(cell_3d)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convert 3D world position to 2D grid coordinates"""
	var cell_3d = grid_map.local_to_map(world_pos)
	return Vector2i(cell_3d.x, cell_3d.z)

# ============================================================================
# GRID QUERIES (Same API as 2D version)
# ============================================================================

func is_walkable(pos: Vector2i) -> bool:
	"""Check if grid position is walkable"""
	if not is_in_bounds(pos):
		return false

	var cell_item = grid_map.get_cell_item(Vector3i(pos.x, 0, pos.y))
	return cell_item == TileType.FLOOR

func is_in_bounds(pos: Vector2i) -> bool:
	"""Check if position is within grid bounds"""
	return pos.x >= 0 and pos.x < grid_size.x and \
		   pos.y >= 0 and pos.y < grid_size.y

func get_random_walkable_position() -> Vector2i:
	"""Get random walkable position"""
	if walkable_cells.is_empty():
		return Vector2i(grid_size.x / 2, grid_size.y / 2)
	return walkable_cells.pick_random()

# ============================================================================
# CEILING TRANSPARENCY SYSTEM
# ============================================================================

func set_player(player_node: Node3D) -> void:
	"""Set the player reference for ceiling shader updates"""
	player = player_node
	Log.system("Grid3D: Player reference set for ceiling transparency")

func _cache_shader_materials() -> void:
	"""Cache shader materials from MeshLibrary for performance"""
	if not grid_map or not grid_map.mesh_library:
		Log.system("Grid3D: No GridMap or MeshLibrary found!")
		return

	var mesh_lib = grid_map.mesh_library as MeshLibrary
	if not mesh_lib:
		Log.system("Grid3D: MeshLibrary cast failed!")
		return

	Log.system("Grid3D: Caching shader materials from MeshLibrary...")

	# Check all tile types and register their materials
	for tile_id in [TileType.FLOOR, TileType.WALL, TileType.CEILING]:
		var mesh = mesh_lib.get_item_mesh(tile_id)
		if not mesh or mesh.get_surface_count() == 0:
			continue

		var mat = mesh.surface_get_material(0) as ShaderMaterial
		if not mat or not mat.shader:
			continue

		var shader_path = mat.shader.resource_path

		# Register obstruction materials (camera→player cone + player cylinder)
		if "psx_wall_obstruction" in shader_path:
			register_obstruction_material(mat)
			var tile_name = ["Floor", "Wall", "Ceiling"][tile_id]
			Log.system("Grid3D: ✅ Registered %s obstruction material" % tile_name)

func register_obstruction_material(mat: ShaderMaterial) -> void:
	"""Register a material to receive camera→player obstruction updates

	Any entity (wall, ceiling, enemy, etc.) can call this to enable
	camera→player cone transparency/wireframe rendering.
	"""
	if mat and mat not in obstruction_materials:
		obstruction_materials.append(mat)
		Log.system("Grid3D: Material registered for obstruction (%d total)" % obstruction_materials.size())

func _raycast_obstructions(camera_pos: Vector3, player_pos: Vector3) -> void:
	"""Use ShapeCast3D to detect obstructions between player and camera

	ShapeCast3D is a box matching camera's frustum - only hits what camera can see.
	This prevents hitting walls behind the player (unlike circle-based raycasting).
	"""
	var player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		return

	var shape_cast = player_node.get_node_or_null("ObstructionDetector")
	if not shape_cast:
		return

	# Orient shape_cast toward camera
	var to_camera = camera_pos - player_pos
	var distance = to_camera.length()
	shape_cast.target_position = player_node.to_local(camera_pos)

	# Force update
	shape_cast.force_shapecast_update()

	# Collect all collisions
	if shape_cast.is_colliding():
		for i in range(shape_cast.get_collision_count()):
			var collider = shape_cast.get_collider(i)
			if collider == grid_map:
				var hit_point = shape_cast.get_collision_point(i)
				var hit_cell = grid_map.local_to_map(grid_map.to_local(hit_point))
				# Project to floor cell (Y=0)
				var floor_cell = Vector3i(hit_cell.x, 0, hit_cell.z)
				if floor_cell not in obstructed_cells:
					obstructed_cells.append(floor_cell)
