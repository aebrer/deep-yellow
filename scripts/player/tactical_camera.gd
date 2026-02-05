class_name TacticalCamera
extends Node3D
## Third-person tactical camera for turn-based gameplay
##
## Features:
## - Fortnite-style third-person view with right stick rotation
## - Zoom with shoulder buttons (LB/RB) or mouse wheel
## - Optional 45° rotation snapping for tactical clarity
## - Smooth camera movement

# Camera configuration
@export var default_distance: float = 15.0
@export var default_pitch: float = -45.0  # Look down angle
@export var default_yaw: float = 45.0     # Starting rotation

# Camera control
@export var rotation_speed: float = 360.0  # Degrees per second when stick held
@export var mouse_sensitivity: float = 0.15  # Mouse rotation sensitivity
@export var rotation_deadzone: float = 0.3  # Right stick deadzone

@export var zoom_speed: float = 2.0
@export var zoom_min: float = 8.0
@export var zoom_max: float = 25.0

# Zoom-based pitch adjustment
@export var pitch_min: float = -90.0    # Look down limit
@export var pitch_max: float = -1.0     # Look up limit (negative = looking down)
@export var pitch_near: float = -30.0   # Default when zoomed in
@export var pitch_far: float = -60.0    # Default when zoomed out

# Node references
@onready var h_pivot: Node3D = $HorizontalPivot
@onready var v_pivot: Node3D = $HorizontalPivot/VerticalPivot
@onready var camera: Camera3D = $HorizontalPivot/VerticalPivot/Camera3D

# State
var current_zoom: float
var manual_pitch_override: bool = false  # Track if user manually adjusted pitch

# Mouse motion accumulator (fixes Firefox drift at integer zoom levels)
var mouse_motion_accumulator := Vector2.ZERO
const MOTION_SAMPLE_THRESHOLD := 0.001  # Ignore micro-drift accumulation

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Set initial angles
	v_pivot.rotation_degrees.x = default_pitch
	h_pivot.rotation_degrees.y = default_yaw

	current_zoom = default_distance

	# Position camera at default distance (no SpringArm, direct positioning)
	camera.position.z = default_distance

	# Camera settings
	camera.fov = 70.0  # Field of view

	# Capture mouse for camera control (standard third-person)
	# For web exports, browsers block mouse capture until user interaction (security)
	# Mouse will be captured on first click via _unhandled_input
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	# Block camera movement when paused (UI navigation takes over)
	if PauseManager and PauseManager.is_paused:
		mouse_motion_accumulator = Vector2.ZERO  # Clear any accumulated motion
		return

	# Apply accumulated mouse motion (from _unhandled_input)
	# Averaging across events filters Firefox's systematic rounding drift
	if mouse_motion_accumulator.length_squared() > MOTION_SAMPLE_THRESHOLD:
		h_pivot.rotation_degrees.y -= mouse_motion_accumulator.x * mouse_sensitivity
		h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)

		v_pivot.rotation_degrees.x -= mouse_motion_accumulator.y * mouse_sensitivity
		v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)

		manual_pitch_override = true

	# Reset accumulator after applying
	mouse_motion_accumulator = Vector2.ZERO

	# Handle right stick camera controls (Fortnite-style!)
	var right_stick_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var right_stick_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	# Right stick X = horizontal rotation (yaw)
	if abs(right_stick_x) > rotation_deadzone:
		h_pivot.rotation_degrees.y -= right_stick_x * rotation_speed * delta
		h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)

	# Right stick Y = vertical rotation (pitch) - SAME AS MOUSE!
	if abs(right_stick_y) > rotation_deadzone:
		v_pivot.rotation_degrees.x -= right_stick_y * rotation_speed * delta
		v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)
		manual_pitch_override = true

func _unhandled_input(event: InputEvent) -> void:
	# Block camera input when paused (PauseManager handles pause/unpause)
	if PauseManager and PauseManager.is_paused:
		return

	# For web: Capture mouse on first click (browsers require user interaction)
	if OS.has_feature("web") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	# Mouse camera control (standard third-person!)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Accumulate motion events across frame (applied in _process)
		# This filters Firefox's systematic rounding drift at integer zoom levels
		# https://github.com/w3c/pointerlock/issues/23
		mouse_motion_accumulator += event.screen_relative
		get_viewport().set_input_as_handled()

	# Zoom controls (shoulder buttons + mouse wheel)
	if event.is_action_pressed("camera_zoom_in"):
		zoom(-zoom_speed)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		zoom(zoom_speed)
		get_viewport().set_input_as_handled()

# ============================================================================
# CAMERA CONTROLS
# ============================================================================

func zoom(delta: float) -> void:
	"""Adjust camera distance"""
	current_zoom = clampf(current_zoom + delta, zoom_min, zoom_max)
	camera.position.z = current_zoom  # Direct camera positioning (no SpringArm)

	# Auto-adjust pitch based on zoom ONLY if user hasn't manually controlled it
	if not manual_pitch_override:
		# More zoomed out = steeper angle for tactical view
		var zoom_ratio = (current_zoom - zoom_min) / (zoom_max - zoom_min)
		var target_pitch = lerp(pitch_near, pitch_far, zoom_ratio)
		v_pivot.rotation_degrees.x = target_pitch

# ============================================================================
# UTILITY
# ============================================================================

func get_camera_forward() -> Vector3:
	"""Get forward direction in world space (for aiming)"""
	return -camera.global_transform.basis.z


