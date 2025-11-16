class_name FirstPersonCamera
extends Node3D
## First-person look camera for examination mode
##
## Attached to Player3D, activated when LT/RMB held.
## Shares rotation controls with TacticalCamera for input parity.

# No longer need SurfaceType enum - objects declare what they are via Examinable

# Camera configuration
@export var rotation_speed: float = 360.0  # Same as TacticalCamera
@export var mouse_sensitivity: float = 0.15  # Same as TacticalCamera
@export var rotation_deadzone: float = 0.3  # Right stick deadzone

# Vertical rotation limits (full range for first-person)
@export var pitch_min: float = -89.0  # Look down
@export var pitch_max: float = 89.0   # Look up

# FOV (field of view)
@export var default_fov: float = 75.0
@export var fov_min: float = 60.0
@export var fov_max: float = 90.0
@export var fov_zoom_speed: float = 5.0

# Node references
@onready var h_pivot: Node3D = $HorizontalPivot
@onready var v_pivot: Node3D = $HorizontalPivot/VerticalPivot
@onready var camera: Camera3D = $HorizontalPivot/VerticalPivot/Camera3D

# State
var active: bool = false  # Controlled by LookModeState

# On-demand examination tile cache
const MAX_CACHED_TILES := 20  # Limit memory usage
var examination_tile_cache: Dictionary = {}  # Vector2i(grid_pos) -> ExaminableEnvironmentTile
var examination_world: Node3D = null  # Parent for cached tiles

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Position at player eye height (set by parent Player3D)
	position = Vector3(0, 1.6, 0)  # Eye height

	# Initial rotation (facing forward)
	h_pivot.rotation_degrees.y = 0.0
	v_pivot.rotation_degrees.x = 0.0

	# Camera settings
	camera.fov = default_fov
	camera.current = false  # Start inactive

	Log.camera("FirstPersonCamera initialized - FOV: %.1f" % default_fov)

func _process(delta: float) -> void:
	if not active:
		return

	# Handle right stick camera controls (SAME AS TACTICAL CAMERA!)
	var right_stick_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var right_stick_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	# Right stick X = horizontal rotation (yaw)
	if abs(right_stick_x) > rotation_deadzone:
		h_pivot.rotation_degrees.y -= right_stick_x * rotation_speed * delta
		h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)

	# Right stick Y = vertical rotation (pitch)
	if abs(right_stick_y) > rotation_deadzone:
		v_pivot.rotation_degrees.x -= right_stick_y * rotation_speed * delta
		v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return

	# Mouse camera control (SAME AS TACTICAL CAMERA!)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Mouse X = horizontal rotation (yaw)
		h_pivot.rotation_degrees.y -= event.relative.x * mouse_sensitivity
		h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)

		# Mouse Y = vertical rotation (pitch)
		v_pivot.rotation_degrees.x -= event.relative.y * mouse_sensitivity
		v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)

		get_viewport().set_input_as_handled()

	# FOV zoom (optional - LB/RB or mouse wheel)
	if event.is_action_pressed("camera_zoom_in"):
		adjust_fov(-fov_zoom_speed)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		adjust_fov(fov_zoom_speed)
		get_viewport().set_input_as_handled()

# ============================================================================
# CAMERA CONTROL
# ============================================================================

func activate() -> void:
	"""Switch to first-person camera"""
	active = true
	camera.current = true

	# Create examination world container if needed
	if not examination_world:
		examination_world = Node3D.new()
		examination_world.name = "OnDemandExaminationWorld"
		get_tree().root.add_child(examination_world)
		Log.camera("Created on-demand examination world")

	Log.camera("First-person camera activated")

func deactivate() -> void:
	"""Switch back to tactical camera"""
	active = false
	camera.current = false

	# Clear examination tile cache
	_clear_examination_cache()

	Log.camera("First-person camera deactivated")

func adjust_fov(delta_fov: float) -> void:
	"""Adjust field of view (zoom effect)"""
	camera.fov = clampf(camera.fov + delta_fov, fov_min, fov_max)

func reset_rotation() -> void:
	"""Reset camera to forward facing (optional utility)"""
	h_pivot.rotation_degrees.y = 0.0
	v_pivot.rotation_degrees.x = 0.0

# ============================================================================
# RAYCAST UTILITIES
# ============================================================================

func get_look_raycast() -> Dictionary:
	"""Perform raycast from camera center, return hit info"""
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)
	var ray_length = 5.0  # Close examination distance (too long causes distant hits)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	# Layer 4 (bit 8) = Examination overlay (ExaminableEnvironmentTile + entities)
	# No longer check GridMap layer 2 - using separate examination overlay now
	query.collision_mask = 8  # Layer 4 only

	var result = space_state.intersect_ray(query)
	return result  # Empty dict if no hit, else {position, normal, collider, etc.}

func get_current_target() -> Examinable:
	"""Get what the player is looking at (ON-DEMAND TILE CREATION!)

	1. First checks examination overlay (layer 4) for existing Examinable
	2. If not found, raycasts GridMap (layer 2) and creates examination tile on-demand
	3. Caches tiles for reuse (max 20 tiles)

	Returns:
		Examinable component (entity OR on-demand environment tile), or null
	"""
	# First: Check for existing examination overlay on layer 4
	var hit = get_look_raycast()
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider:
			# Check if collider IS an Examinable
			if collider is Examinable:
				return collider

			# Check descendants for Examinable
			for child in collider.get_children():
				if child is Examinable:
					return child

	# Second: Raycast GridMap on layer 2 for on-demand tile creation
	var gridmap_hit = _raycast_gridmap()
	if gridmap_hit.is_empty():
		Log.trace(Log.Category.SYSTEM, "No GridMap hit detected")
		return null

	Log.trace(Log.Category.SYSTEM, "GridMap hit detected at: %s" % gridmap_hit.get("position"))

	# Get Grid3D reference from scene tree (sibling of Player3D)
	# FirstPersonCamera -> Player3D -> Game (parent) -> Grid3D (sibling)
	var player = get_parent()  # Player3D
	if not player:
		Log.warn(Log.Category.SYSTEM, "Player not found (parent of FirstPersonCamera)")
		return null

	var game = player.get_parent()  # Game node
	if not game:
		Log.warn(Log.Category.SYSTEM, "Game node not found (parent of Player)")
		return null

	var grid_3d = game.get_node_or_null("Grid3D")
	if not grid_3d:
		Log.warn(Log.Category.SYSTEM, "Grid3D not found as child of Game node")
		return null

	# Convert hit position to grid coordinates and extract surface normal
	var hit_pos: Vector3 = gridmap_hit.get("position")
	var hit_normal: Vector3 = gridmap_hit.get("normal")
	var grid_pos: Vector2 = grid_3d.world_to_grid(hit_pos)

	# Determine tile type from GridMap using surface normal (industry-standard approach)
	var tile_type := _get_tile_type_at_position(grid_3d, grid_pos, hit_normal)
	if tile_type == "":
		return null

	# Check cache for existing tile
	var cache_key := Vector2i(grid_pos.x, grid_pos.y)
	if examination_tile_cache.has(cache_key):
		var cached_tile: ExaminableEnvironmentTile = examination_tile_cache[cache_key]
		return cached_tile.examinable

	# Create new examination tile on-demand
	return _create_examination_tile(grid_3d, grid_pos, tile_type, cache_key)

# ============================================================================
# ON-DEMAND EXAMINATION TILE HELPERS
# ============================================================================

func _raycast_gridmap() -> Dictionary:
	"""Raycast GridMap collision layer (layer 2) for on-demand tile creation"""
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)
	var ray_length = 5.0  # Close examination distance (too long causes distant hits)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	query.collision_mask = 2  # Layer 2 = GridMap collision

	var result = space_state.intersect_ray(query)

	if not result.is_empty():
		Log.trace(Log.Category.SYSTEM, "GridMap raycast hit at Y=%.2f, normal=%s" % [result.get("position").y, result.get("normal")])

	return result

func _get_tile_type_at_position(grid_3d, grid_pos: Vector2, hit_normal: Vector3) -> String:
	"""Determine tile type (floor/wall/ceiling) from GridMap using surface normal

	Uses dot product with Vector3.UP to determine orientation (industry-standard):
	- Floor: normal points upward (dot > 0.7)
	- Ceiling: normal points downward (dot < -0.7)
	- Wall: normal is horizontal (-0.7 <= dot <= 0.7)

	Threshold of 0.7 ≈ cos(45°) handles slopes and float precision.
	This is the same approach used by CharacterBody3D.is_on_floor().
	"""
	const THRESHOLD = 0.7  # ~45° tolerance

	var cell_3d := Vector3i(grid_pos.x, 0, grid_pos.y)
	var cell_item: int = grid_3d.grid_map.get_cell_item(cell_3d)

	# Calculate dot product with up vector to classify surface
	var dot_up = hit_normal.dot(Vector3.UP)

	# DEBUG: Always log ceiling detection attempts
	Log.system("🔍 Tile detection at (%d,%d): Y=0 item=%d, dot_up=%.2f, normal=%s" % [grid_pos.x, grid_pos.y, cell_item, dot_up, hit_normal])

	# Check if wall (horizontal normal, or explicit wall tile)
	if cell_item == grid_3d.TileType.WALL:
		Log.system("→ Detected as WALL")
		return "wall"

	# Check for ceiling at Y=1 layer (normal points downward)
	var ceiling_cell := Vector3i(grid_pos.x, 1, grid_pos.y)
	var ceiling_item: int = grid_3d.grid_map.get_cell_item(ceiling_cell)
	var passes_threshold = dot_up < -THRESHOLD
	Log.system("  🔍 Y=1 ceiling_item=%d (CEILING=%d), dot_up=%.2f < -%.2f? %s" % [ceiling_item, grid_3d.TileType.CEILING, dot_up, THRESHOLD, passes_threshold])

	if ceiling_item == grid_3d.TileType.CEILING and passes_threshold:
		Log.system("→ ✓ Detected as CEILING!")
		return "ceiling"
	elif ceiling_item == grid_3d.TileType.CEILING:
		Log.system("→ ✗ Ceiling tile exists but normal check failed (dot_up=%.2f, need < -%.2f)" % [dot_up, THRESHOLD])
	elif passes_threshold:
		Log.system("→ ✗ Normal points down but no ceiling tile at Y=1 (item=%d)" % ceiling_item)

	# Check if floor (normal points upward)
	if cell_item == grid_3d.TileType.FLOOR and dot_up > THRESHOLD:
		Log.system("→ Detected as FLOOR")
		return "floor"

	Log.system("→ No tile type detected")
	return ""

func _create_examination_tile(grid_3d, grid_pos: Vector2, tile_type: String, cache_key: Vector2i) -> Examinable:
	"""Create examination tile on-demand and add to cache"""
	# Manage cache size (LRU-style: remove oldest if at limit)
	if examination_tile_cache.size() >= MAX_CACHED_TILES:
		var oldest_key = examination_tile_cache.keys()[0]
		var oldest_tile: ExaminableEnvironmentTile = examination_tile_cache[oldest_key]
		oldest_tile.queue_free()
		examination_tile_cache.erase(oldest_key)
		Log.trace(Log.Category.SYSTEM, "Evicted oldest examination tile from cache")

	# Determine entity ID and world position based on tile type
	var entity_id := ""
	var world_pos: Vector3 = grid_3d.grid_to_world(grid_pos)

	match tile_type:
		"floor":
			entity_id = "level_0_floor"
			world_pos.y = 0.0
		"wall":
			entity_id = "level_0_wall"
			world_pos.y = 2.0
		"ceiling":
			entity_id = "level_0_ceiling"
			# CRITICAL: Y=2.98, NOT Y=3 or Y=4! Ceiling positioned just below wall tops for tactical camera.
			# Walls top at Y=3, ceiling at Y=2.98 allows tactical camera to see maze layout from above.
			# Matches grid_mesh_library.tres ceiling collision height.
			world_pos.y = 2.98

	# Load and instantiate examination tile scene
	const EXAM_TILE_SCENE = preload("res://scenes/environment/examinable_environment_tile.tscn")
	var tile := EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
	examination_world.add_child(tile)
	tile.setup(tile_type, entity_id, grid_pos, world_pos)

	# Configure collision shape based on type
	var collision := tile.get_node("CollisionShape3D") as CollisionShape3D
	var shape := BoxShape3D.new()
	match tile_type:
		"floor", "ceiling":
			shape.size = Vector3(2.0, 0.1, 2.0)  # Thin slab
		"wall":
			shape.size = Vector3(2.0, 4.0, 2.0)  # Full height
	collision.shape = shape

	# Add to cache
	examination_tile_cache[cache_key] = tile

	Log.trace(Log.Category.SYSTEM, "Created on-demand examination tile: %s at %s" % [tile_type, grid_pos])

	return tile.examinable

func _clear_examination_cache() -> void:
	"""Clear all cached examination tiles"""
	for tile in examination_tile_cache.values():
		tile.queue_free()
	examination_tile_cache.clear()

	if examination_world:
		examination_world.queue_free()
		examination_world = null

	Log.camera("Cleared examination tile cache")
