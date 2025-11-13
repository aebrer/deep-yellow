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
	# Layer 4 (bit 8) = Examination overlay (ExaminableEnvironmentTile + entities)
	# No longer check GridMap layer 2 - using separate examination overlay now
	query.collision_mask = 8  # Layer 4 only

	var result = space_state.intersect_ray(query)
	return result  # Empty dict if no hit, else {position, normal, collider, etc.}

func get_current_target() -> Examinable:
	"""Get what the player is looking at (SIMPLE!)

	Uses new examination overlay system - objects declare what they are.
	No more GridMap collision math, surface normals, or heuristics.

	Returns:
		Examinable component (entity OR environment tile), or null
	"""
	var hit = get_look_raycast()
	if hit.is_empty():
		return null

	var collider = hit.get("collider")
	if not collider:
		return null

	# Check if collider IS an Examinable (for entities with Examinable as root)
	if collider is Examinable:
		return collider

	# Check descendants for Examinable (environment tiles have Examinable as child)
	for child in collider.get_children():
		if child is Examinable:
			return child

	return null
