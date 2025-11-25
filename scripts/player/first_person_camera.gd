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

# Reference to tactical camera for rotation sync
var tactical_camera: TacticalCamera = null

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
	# Get tactical camera reference for rotation sync
	var player = get_parent()
	if player:
		tactical_camera = player.get_node_or_null("CameraRig")
		if not tactical_camera:
			push_error("TacticalCamera not found - FirstPersonCamera cannot sync rotation")

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

	# Sync rotation from tactical camera
	if tactical_camera:
		h_pivot.rotation_degrees.y = tactical_camera.h_pivot.rotation_degrees.y
		v_pivot.rotation_degrees.x = tactical_camera.v_pivot.rotation_degrees.x
		Log.camera("Synced rotation from tactical camera: yaw=%.1f, pitch=%.1f" % [
			h_pivot.rotation_degrees.y,
			v_pivot.rotation_degrees.x
		])

	# Clear any stale cache entries (e.g., from old cache key format)
	_clear_examination_cache()

	# Create examination world container
	examination_world = Node3D.new()
	examination_world.name = "OnDemandExaminationWorld"
	get_tree().root.add_child(examination_world)
	Log.camera("Created on-demand examination world")

	Log.camera("First-person camera activated")

func deactivate() -> void:
	"""Switch back to tactical camera"""
	active = false
	camera.current = false

	# Sync rotation back to tactical camera
	if tactical_camera:
		tactical_camera.h_pivot.rotation_degrees.y = h_pivot.rotation_degrees.y
		tactical_camera.v_pivot.rotation_degrees.x = v_pivot.rotation_degrees.x
		Log.camera("Synced rotation back to tactical camera")

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

	Creates examination tiles on-demand at cursor position using grid coordinate lookup.
	No GridMap raycasting - GridMap collision doesn't work for ceilings at Y=1.

	Returns:
		Examinable component (entity OR on-demand environment tile), or null
	"""
	# Check for existing examination overlay on layer 4 (entities or already-created tiles)
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

	# Get Grid3D reference
	var player = get_parent()
	if not player:
		return null
	var game = player.get_parent()
	if not game:
		return null
	var grid_3d = game.get_node_or_null("Grid3D")
	if not grid_3d:
		return null

	# Calculate ray intersection with floor/wall/ceiling planes
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)

	# Determine which plane to intersect based on pitch
	var pitch = v_pivot.rotation_degrees.x
	var tile_type := ""
	var target_pos := Vector3.ZERO
	var max_distance = 5.0  # Maximum examination distance

	if pitch < -10:  # Looking down at floor (negative pitch = looking down)
		tile_type = "floor"
		# Intersect with floor plane at Y=0
		if abs(ray_direction.y) > 0.01:  # Avoid division by zero
			var t = (0.0 - ray_origin.y) / ray_direction.y
			# Negative t means ray points away - need to negate direction
			var actual_t = abs(t)
			if actual_t < max_distance:
				# Negate ray_direction.y to flip vertical direction
				var corrected_dir = Vector3(ray_direction.x, -ray_direction.y, ray_direction.z)
				target_pos = ray_origin + corrected_dir * actual_t
			else:
				return null
		else:
			return null
	elif pitch > 10:  # Looking up at ceiling (positive pitch = looking up)
		tile_type = "ceiling"
		# Intersect with ceiling plane at Y=2.98
		if abs(ray_direction.y) > 0.01:
			var t = (2.98 - ray_origin.y) / ray_direction.y
			# Negative t means ray points away - need to negate direction
			var actual_t = abs(t)
			if actual_t < max_distance:
				# Negate ray_direction.y to flip vertical direction
				var corrected_dir = Vector3(ray_direction.x, -ray_direction.y, ray_direction.z)
				target_pos = ray_origin + corrected_dir * actual_t
			else:
				return null
		else:
			return null
	else:  # Looking horizontally at walls
		tile_type = "wall"
		# Cast ray and find nearest wall intersection using grid traversal
		# Start from current position and step along ray direction
		var step_distance = 0.5  # Check every half meter
		var found_wall = false
		target_pos = ray_origin

		for i in range(10):  # Max 10 steps = 5 meters
			var test_pos = ray_origin + ray_direction * (step_distance * i)
			var test_grid = grid_3d.world_to_grid(test_pos)
			var test_cell = Vector3i(test_grid.x, 0, test_grid.y)
			var cell_item = grid_3d.grid_map.get_cell_item(test_cell)

			if cell_item == grid_3d.TileType.WALL:
				target_pos = test_pos
				found_wall = true
				break

		if not found_wall:
			return null

	var grid_pos: Vector2i = grid_3d.world_to_grid(target_pos)

	# Verify tile exists at grid position
	if tile_type == "ceiling":
		var ceiling_cell := Vector3i(grid_pos.x, 1, grid_pos.y)
		var cell_item = grid_3d.grid_map.get_cell_item(ceiling_cell)
		if cell_item != grid_3d.TileType.CEILING:
			return null
	elif tile_type == "floor":
		var floor_cell := Vector3i(grid_pos.x, 0, grid_pos.y)
		var cell_item = grid_3d.grid_map.get_cell_item(floor_cell)
		if cell_item != grid_3d.TileType.FLOOR:
			return null
	else:  # wall
		var wall_cell := Vector3i(grid_pos.x, 0, grid_pos.y)
		var cell_item = grid_3d.grid_map.get_cell_item(wall_cell)
		if cell_item != grid_3d.TileType.WALL:
			return null

	# Check cache for existing tile (cache key MUST include tile type!)
	# Same grid position (67, 3) can have floor, wall, AND ceiling tiles
	var cache_key := "%d,%d,%s" % [grid_pos.x, grid_pos.y, tile_type]
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

	# Offset ray origin forward by camera near plane distance to avoid starting inside collision
	ray_origin += ray_direction * camera.near

	var ray_length = 5.0  # Close examination distance (too long causes distant hits)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	query.collision_mask = 2  # Layer 2 = GridMap collision

	var result = space_state.intersect_ray(query)

	# ALWAYS log raycast attempts, even when no hit
	if not result.is_empty():
		var hit_pos: Vector3 = result.get("position")
		var hit_normal: Vector3 = result.get("normal")
		pass
	else:
		# Check what tiles exist at this grid position
		var player = get_parent()
		if player:
			var game = player.get_parent()
			if game:
				var grid_3d = game.get_node_or_null("Grid3D")
				if grid_3d:
					var grid_pos: Vector2 = grid_3d.world_to_grid(ray_origin)
					var floor_cell := Vector3i(grid_pos.x, 0, grid_pos.y)
					var ceiling_cell := Vector3i(grid_pos.x, 1, grid_pos.y)
					var floor_item = grid_3d.grid_map.get_cell_item(floor_cell)
					var ceiling_item = grid_3d.grid_map.get_cell_item(ceiling_cell)
					pass

	return result

func _get_tile_type_at_position(grid_3d, grid_pos: Vector2, hit_pos: Vector3, hit_normal: Vector3) -> String:
	"""Determine tile type (floor/wall/ceiling) from surface normal

	Uses surface normal to classify hits - ignores hit position since walls extend above ceiling.
	"""
	const THRESHOLD = 0.7  # ~45° tolerance for normal direction

	var cell_3d := Vector3i(grid_pos.x, 0, grid_pos.y)
	var cell_item: int = grid_3d.grid_map.get_cell_item(cell_3d)

	# Calculate dot product with up vector to classify surface
	var dot_up = hit_normal.dot(Vector3.UP)

	# Ceiling: normal points DOWN (dot product with UP is negative)
	# Check for ceiling tile at Y=1 layer
	var ceiling_cell := Vector3i(grid_pos.x, 1, grid_pos.y)
	var ceiling_item: int = grid_3d.grid_map.get_cell_item(ceiling_cell)

	if ceiling_item == grid_3d.TileType.CEILING and dot_up < -THRESHOLD:
		return "ceiling"

	# Floor: normal points UP
	if cell_item == grid_3d.TileType.FLOOR and dot_up > THRESHOLD:
		return "floor"

	# Wall: horizontal normal (not up, not down)
	if cell_item == grid_3d.TileType.WALL or abs(dot_up) < THRESHOLD:
		return "wall"

	return ""

func _create_examination_tile(grid_3d, grid_pos: Vector2, tile_type: String, cache_key: String) -> Examinable:
	"""Create examination tile on-demand and add to cache"""
	# Manage cache size (LRU-style: remove oldest if at limit)
	if examination_tile_cache.size() >= MAX_CACHED_TILES:
		var oldest_key = examination_tile_cache.keys()[0]
		var oldest_tile: ExaminableEnvironmentTile = examination_tile_cache[oldest_key]
		oldest_tile.queue_free()
		examination_tile_cache.erase(oldest_key)

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
			# Matches MeshLibrary ceiling collision height.
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
