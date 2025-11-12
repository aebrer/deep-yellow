class_name FirstPersonCamera
extends Node3D
## First-person look camera for examination mode
##
## Attached to Player3D, activated when LT/RMB held.
## Shares rotation controls with TacticalCamera for input parity.

# Surface types for grid tile classification
enum SurfaceType {
	FLOOR,
	WALL,
	CEILING,
	UNKNOWN
}

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
	Log.camera("First-person camera activated")

func deactivate() -> void:
	"""Switch back to tactical camera"""
	active = false
	camera.current = false
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
	var ray_length = 10.0  # Maximum examination distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	# Layer 2 (bit 1) = GridMap walls/floors/ceilings
	# Layer 4 (bit 3) = Examinable objects
	query.collision_mask = 2 | 8  # Check both GridMap (layer 2) and Examinables (layer 4)

	var result = space_state.intersect_ray(query)
	return result  # Empty dict if no hit, else {position, normal, collider, etc.}

func get_current_target() -> Examinable:
	"""Get Examinable component from raycast target (or null)"""
	var hit = get_look_raycast()
	if hit.is_empty():
		return null

	var collider = hit.get("collider")
	if not collider:
		return null

	# Check if collider is Examinable
	if collider is Examinable:
		return collider

	# Check all descendants recursively for Examinable
	var examinable = _find_examinable_in_descendants(collider)
	if examinable:
		return examinable

	return null

func get_current_target_or_grid() -> Variant:
	"""Get Examinable OR grid tile info (entity, grid tile dict, or null)"""
	var hit = get_look_raycast()

	# If we have a collision hit, check what it is
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider:
			# Check for Examinable component first (entities/items take priority)
			if collider is Examinable:
				return collider

			# Check all descendants recursively for Examinable
			var examinable = _find_examinable_in_descendants(collider)
			if examinable:
				return examinable

			# Check if we hit a GridMap (walls/floors/ceilings)
			if collider is GridMap:
				var hit_position: Vector3 = hit.get("position")
				var hit_normal: Vector3 = hit.get("normal")

				# Use surface normal to determine what we actually hit
				var surface_type = _classify_surface_by_normal(hit_normal)

				# Map surface type to tile type for KnowledgeDB
				var tile_type = _surface_type_to_tile_type(surface_type)

				Log.system("Physics raycast hit: pos=%s (Y=%.2f), normal=%s, surface=%s, tile_type=%d" % [
					hit_position,
					hit_position.y,
					hit_normal,
					_surface_type_name(surface_type),
					tile_type
				])

				# Return grid tile info with surface-based classification
				return {
					"type": "grid_tile",
					"grid_map": collider,
					"tile_type": tile_type,  # 0=FLOOR, 1=WALL, 2=CEILING
					"position": hit_position,
					"normal": hit_normal,
					"surface_type": surface_type
				}

	# Fallback: Manual grid raycast (check grid cells along ray path)
	# This catches walls/floors/ceilings even when collision mesh is missed
	var grid_result = _manual_grid_raycast()
	if grid_result:
		return grid_result

	return null

func _manual_grid_raycast() -> Variant:
	"""Manual grid-based raycast to catch walls/floors/ceilings

	Steps along the camera ray and checks grid cells for tiles.
	More reliable than physics raycast for examining environment.
	"""
	# Get GridMap from scene (assuming it's at ../../../GridMap from camera)
	var grid_map = get_node_or_null("../../Grid3D/GridMap")
	if not grid_map:
		return null

	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)

	# Step along ray in small increments
	var max_distance = 10.0
	var step_size = 0.2  # Check every 0.2 units
	var steps = int(max_distance / step_size)

	for i in range(steps):
		var check_pos = ray_origin + ray_direction * (i * step_size)
		var grid_cell = grid_map.local_to_map(check_pos)
		var cell_item = grid_map.get_cell_item(grid_cell)

		if cell_item != GridMap.INVALID_CELL_ITEM:
			# Found a tile! Use cell_item ID directly - it already maps to tile type
			# GridMap enum: FLOOR=0, WALL=1, CEILING=2
			var surface_type: SurfaceType
			match cell_item:
				0:  # FLOOR
					surface_type = SurfaceType.FLOOR
				1:  # WALL
					surface_type = SurfaceType.WALL
				2:  # CEILING
					surface_type = SurfaceType.CEILING
				_:
					surface_type = SurfaceType.UNKNOWN

			var tile_type = _surface_type_to_tile_type(surface_type)

			Log.system("Manual raycast hit: pos=%s (Y=%.2f), cell=%s, layer=%d, surface=%s, tile_type=%d" % [
				check_pos,
				check_pos.y,
				grid_cell,
				grid_cell.y,
				_surface_type_name(surface_type),
				tile_type
			])

			return {
				"type": "grid_tile",
				"grid_map": grid_map,
				"tile_type": tile_type,
				"position": check_pos,
				"surface_type": surface_type
			}

	return null

func _find_examinable_in_descendants(node: Node) -> Examinable:
	"""Recursively search for Examinable component in node's descendants"""
	for child in node.get_children():
		if child is Examinable:
			return child
		# Recurse into child's children
		var found = _find_examinable_in_descendants(child)
		if found:
			return found
	return null

# ============================================================================
# SURFACE CLASSIFICATION (Normal-Based Detection)
# ============================================================================

func _classify_surface_by_normal(normal: Vector3) -> SurfaceType:
	"""Classify surface type based on normal vector

	Uses dot product with Vector3.UP to determine orientation:
	- Floor: normal points upward (dot > 0.7)
	- Ceiling: normal points downward (dot < -0.7)
	- Wall: normal is horizontal (-0.7 <= dot <= 0.7)

	Threshold of 0.7 ≈ cos(45°) handles slopes and float precision.
	This is the industry-standard approach used by CharacterBody3D.is_on_floor().
	"""
	const THRESHOLD = 0.7  # ~45° tolerance

	var dot_up = normal.dot(Vector3.UP)

	if dot_up > THRESHOLD:
		return SurfaceType.FLOOR
	elif dot_up < -THRESHOLD:
		return SurfaceType.CEILING
	else:
		return SurfaceType.WALL

func _surface_type_to_tile_type(surface: SurfaceType) -> int:
	"""Convert SurfaceType enum to Grid3D.TileType for KnowledgeDB lookup"""
	match surface:
		SurfaceType.FLOOR:
			return 0  # Grid3D.TileType.FLOOR
		SurfaceType.WALL:
			return 1  # Grid3D.TileType.WALL
		SurfaceType.CEILING:
			return 2  # Grid3D.TileType.CEILING
		_:
			return -1  # Unknown

func _surface_type_name(type: SurfaceType) -> String:
	"""Convert SurfaceType enum to string for logging"""
	match type:
		SurfaceType.FLOOR: return "FLOOR"
		SurfaceType.CEILING: return "CEILING"
		SurfaceType.WALL: return "WALL"
		_: return "UNKNOWN"
