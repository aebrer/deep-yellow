class_name TouchControls
extends Control
## Touch control overlay for mobile/portrait mode
##
## Features:
## - Left side: Touchpad for camera rotation (swipe to aim)
## - Right side: Action buttons (Confirm Move, Look Mode)
## - Only visible in portrait mode
## - Camera rotation handled directly, confirm/look buttons via InputManager

## Minimum swipe distance to register a direction (pixels)
@export var swipe_threshold: float = 30.0

## Touch areas
@onready var touchpad: Control = $HBoxContainer/Touchpad
@onready var button_container: VBoxContainer = $HBoxContainer/ButtonContainer
@onready var confirm_button: Button = $HBoxContainer/ButtonContainer/ConfirmButton
@onready var look_button: Button = $HBoxContainer/ButtonContainer/LookButton

## Touchpad state
var touchpad_touch_index: int = -1
var touchpad_start_pos: Vector2 = Vector2.ZERO
var touchpad_current_pos: Vector2 = Vector2.ZERO

## Player reference (for camera control)
var player: Node3D = null
var tactical_camera: Node = null

func _ready() -> void:
	# Connect button signals (use button_down/button_up for hold tracking)
	confirm_button.button_down.connect(_on_confirm_button_down)
	confirm_button.button_up.connect(_on_confirm_button_up)
	look_button.button_down.connect(_on_look_button_down)
	look_button.button_up.connect(_on_look_button_up)

	# Add visual border to touchpad for clarity
	var touchpad_style = StyleBoxFlat.new()
	touchpad_style.bg_color = Color(0, 0, 0, 0)  # Transparent background
	touchpad_style.border_color = Color(1, 1, 1, 0.3)  # Semi-transparent white border
	touchpad_style.set_border_width_all(2)
	touchpad.add_theme_stylebox_override("panel", touchpad_style)

	Log.system("TouchControls ready (camera reference will be set by game.gd)")

func set_camera_reference(camera: Node) -> void:
	"""Set the tactical camera reference (called by game.gd)"""
	tactical_camera = camera
	if tactical_camera:
		Log.system("TouchControls: Camera reference set successfully")
	else:
		Log.warn(Log.Category.SYSTEM, "TouchControls: Camera reference is null")

	# Debug: Log initial sizes and mouse_filter settings
	await get_tree().process_frame  # Wait for layout
	_debug_log_layout()

func _input(event: InputEvent) -> void:
	"""Handle touch input globally (allows mouse to pass through to viewport)"""
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Debug: Log ALL touch events
		Log.system("[TouchControls] Touch event received: %s at position %v" % [
			"ScreenTouch" if event is InputEventScreenTouch else "ScreenDrag",
			event.position
		])

		# Get touchpad bounds for debugging
		if touchpad:
			var touchpad_rect = touchpad.get_global_rect()
			Log.system("[TouchControls] Touchpad bounds: pos=%v, size=%v" % [
				touchpad_rect.position, touchpad_rect.size
			])

		# Check if touch is within touchpad bounds
		var in_touchpad = _is_touch_in_touchpad(event.position)
		Log.system("[TouchControls] Touch in touchpad? %s" % in_touchpad)

		if in_touchpad:
			_on_touchpad_input(event)

func _on_touchpad_input(event: InputEvent) -> void:
	"""Handle touch input on the invisible touchpad"""
	if event is InputEventScreenTouch:
		if event.pressed:
			# Touch started
			touchpad_touch_index = event.index
			touchpad_start_pos = event.position
			touchpad_current_pos = event.position
			Log.system("[TouchControls] Touchpad touch STARTED - index=%d, pos=%v" % [event.index, touchpad_start_pos])
		else:
			# Touch ended - detect swipe direction
			Log.system("[TouchControls] Touchpad touch ENDED - index=%d, tracking_index=%d" % [event.index, touchpad_touch_index])
			if touchpad_touch_index == event.index:
				Log.system("[TouchControls] Index match! Calling _detect_swipe_direction()")
				_detect_swipe_direction()
				touchpad_touch_index = -1
			else:
				Log.system("[TouchControls] Index mismatch - ignoring touch end")

	elif event is InputEventScreenDrag:
		Log.system("[TouchControls] Touchpad DRAG - index=%d, tracking_index=%d, pos=%v" % [event.index, touchpad_touch_index, event.position])
		if touchpad_touch_index == event.index:
			touchpad_current_pos = event.position
			Log.system("[TouchControls] Updated current_pos=%v" % [touchpad_current_pos])

func _detect_swipe_direction() -> void:
	"""Detect 8-directional swipe from start to end position"""
	var swipe_vector := touchpad_current_pos - touchpad_start_pos
	var swipe_distance := swipe_vector.length()

	Log.system("[TouchControls] _detect_swipe_direction() called - start=%v, end=%v, vector=%v, distance=%.1f" % [
		touchpad_start_pos, touchpad_current_pos, swipe_vector, swipe_distance
	])

	# Ignore short swipes
	if swipe_distance < swipe_threshold:
		Log.system("[TouchControls] Swipe too short: %.1f < %.1f threshold" % [swipe_distance, swipe_threshold])
		return

	# Convert swipe to 8-direction
	var angle := swipe_vector.angle()  # Radians, 0 = right, increases counterclockwise
	var direction := _angle_to_direction(angle)

	Log.system("[TouchControls] Swipe DETECTED! vector=%v, angle=%.2f rad, direction=%v" % [swipe_vector, angle, direction])

	# Rotate camera to face the swiped direction (like right stick on gamepad)
	if tactical_camera and tactical_camera.has_method("snap_to_grid_direction"):
		Log.system("[TouchControls] Rotating camera to direction %v" % [direction])
		tactical_camera.snap_to_grid_direction(direction)
	else:
		Log.warn(Log.Category.SYSTEM, "TouchControls: Cannot rotate camera - tactical_camera not available")

func _angle_to_direction(angle: float) -> Vector2i:
	"""Convert angle (radians) to 8-directional grid vector"""
	# Normalize angle to 0-2π
	while angle < 0:
		angle += TAU
	while angle >= TAU:
		angle -= TAU

	# Map to 8 directions (45° segments)
	# 0° = right, 90° = up, 180° = left, 270° = down
	var segment := int(round(angle / (TAU / 8.0))) % 8

	match segment:
		0:  # Right (0°)
			return Vector2i(1, 0)
		1:  # Up-Right (45°)
			return Vector2i(1, -1)
		2:  # Up (90°)
			return Vector2i(0, -1)
		3:  # Up-Left (135°)
			return Vector2i(-1, -1)
		4:  # Left (180°)
			return Vector2i(-1, 0)
		5:  # Down-Left (225°)
			return Vector2i(-1, 1)
		6:  # Down (270°)
			return Vector2i(0, 1)
		7:  # Down-Right (315°)
			return Vector2i(1, 1)
		_:
			return Vector2i.ZERO

func _on_confirm_button_down() -> void:
	"""Handle confirm button down (RT pressed)"""
	Log.system("[TouchControls] Confirm button DOWN - calling InputManager")
	InputManager.set_confirm_button_pressed(true)

func _on_confirm_button_up() -> void:
	"""Handle confirm button up (RT released)"""
	Log.system("[TouchControls] Confirm button UP - calling InputManager")
	InputManager.set_confirm_button_pressed(false)

func _on_look_button_down() -> void:
	"""Handle look button down (LT pressed)"""
	Log.system("[TouchControls] Look button DOWN - calling InputManager")
	InputManager.set_look_button_pressed(true)

func _on_look_button_up() -> void:
	"""Handle look button up (LT released)"""
	Log.system("[TouchControls] Look button UP - calling InputManager")
	InputManager.set_look_button_pressed(false)

func _is_touch_in_touchpad(touch_pos: Vector2) -> bool:
	"""Check if touch position is within touchpad area"""
	if not touchpad:
		return false

	# Get touchpad global rect
	var touchpad_rect = touchpad.get_global_rect()
	return touchpad_rect.has_point(touch_pos)

func _debug_log_layout() -> void:
	"""Debug logging for touch controls layout and settings"""
	Log.system("=== TouchControls Layout Debug ===")

	# Root control
	var root_rect = get_global_rect()
	Log.system("Root (TouchControls): size=%v, pos=%v, mouse_filter=%d" % [
		root_rect.size, root_rect.position, mouse_filter
	])

	# HBoxContainer
	var hbox = $HBoxContainer
	var hbox_rect = hbox.get_global_rect()
	Log.system("HBoxContainer: size=%v, pos=%v, mouse_filter=%d" % [
		hbox_rect.size, hbox_rect.position, hbox.mouse_filter
	])

	# Touchpad
	if touchpad:
		var touchpad_rect = touchpad.get_global_rect()
		Log.system("Touchpad: size=%v, pos=%v, mouse_filter=%d, visible=%s" % [
			touchpad_rect.size, touchpad_rect.position, touchpad.mouse_filter, touchpad.visible
		])

	# ButtonContainer
	if button_container:
		var btn_container_rect = button_container.get_global_rect()
		Log.system("ButtonContainer: size=%v, pos=%v, mouse_filter=%d" % [
			btn_container_rect.size, btn_container_rect.position, button_container.mouse_filter
		])

	# Confirm button
	if confirm_button:
		var confirm_rect = confirm_button.get_global_rect()
		Log.system("ConfirmButton: size=%v, pos=%v, visible=%s, min_size=%v" % [
			confirm_rect.size, confirm_rect.position, confirm_button.visible,
			confirm_button.custom_minimum_size
		])

	# Look button
	if look_button:
		var look_rect = look_button.get_global_rect()
		Log.system("LookButton: size=%v, pos=%v, visible=%s, min_size=%v" % [
			look_rect.size, look_rect.position, look_button.visible,
			look_button.custom_minimum_size
		])

	Log.system("=== End TouchControls Debug ===")
