class_name TouchControls
extends Control
## Touch control overlay for mobile/portrait mode
##
## Features:
## - Left side: Invisible touchpad for directional swipe input (8-direction)
## - Right side: Action buttons (Confirm Move, Look Mode)
## - Only visible in portrait mode
## - Sends input events through InputManager

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

func _ready() -> void:
	# Connect button signals
	confirm_button.pressed.connect(_on_confirm_pressed)
	look_button.pressed.connect(_on_look_pressed)

	# Setup touchpad for touch input detection
	touchpad.gui_input.connect(_on_touchpad_input)

	Log.system("TouchControls ready")

func _on_touchpad_input(event: InputEvent) -> void:
	"""Handle touch input on the invisible touchpad"""
	if event is InputEventScreenTouch:
		if event.pressed:
			# Touch started
			touchpad_touch_index = event.index
			touchpad_start_pos = event.position
			touchpad_current_pos = event.position
			Log.input("Touchpad touch started at: %v" % [touchpad_start_pos])
		else:
			# Touch ended - detect swipe direction
			if touchpad_touch_index == event.index:
				_detect_swipe_direction()
				touchpad_touch_index = -1

	elif event is InputEventScreenDrag:
		if touchpad_touch_index == event.index:
			touchpad_current_pos = event.position

func _detect_swipe_direction() -> void:
	"""Detect 8-directional swipe from start to end position"""
	var swipe_vector := touchpad_current_pos - touchpad_start_pos
	var swipe_distance := swipe_vector.length()

	# Ignore short swipes
	if swipe_distance < swipe_threshold:
		Log.input("Swipe too short: %.1f < %.1f" % [swipe_distance, swipe_threshold])
		return

	# Convert swipe to 8-direction
	var angle := swipe_vector.angle()  # Radians, 0 = right, increases counterclockwise
	var direction := _angle_to_direction(angle)

	Log.input("Swipe detected: %v -> direction %v" % [swipe_vector, direction])

	# Send direction input to InputManager
	InputManager.set_movement_direction(direction)

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

func _on_confirm_pressed() -> void:
	"""Handle confirm button press (space/RT equivalent)"""
	Log.input("Touch: Confirm button pressed")
	# Trigger confirm action through InputManager
	InputManager.trigger_confirm_action()

func _on_look_pressed() -> void:
	"""Handle look mode button press (right-click/LT equivalent)"""
	Log.input("Touch: Look mode button pressed")
	# Trigger look mode through InputManager
	InputManager.trigger_look_mode()
