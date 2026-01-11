extends Node
## InputManager - Centralized input handling for turn-based roguelike
##
## This autoload singleton provides:
## - Unified controller + keyboard input
## - Deadzone handling and configuration
## - Analog → 8-direction grid conversion
## - Debug input visualization
##
## Usage:
##   InputManager.get_aim_direction() -> Vector2
##   InputManager.get_aim_direction_grid() -> Vector2i
##   InputManager.is_action_just_pressed("action_name") -> bool

# ============================================================================
# INPUT DEVICE TRACKING
# ============================================================================

enum InputDevice {
	GAMEPAD,           ## Controller/gamepad input
	MOUSE_KEYBOARD     ## Mouse + keyboard input
}

## Signal emitted when input device changes (gamepad ↔ mouse+keyboard)
signal input_device_changed(device: InputDevice)

## Current active input device (auto-detected from last input)
var current_input_device: InputDevice = InputDevice.MOUSE_KEYBOARD

# ============================================================================
# CONFIGURATION
# ============================================================================

## Analog stick deadzone for aim direction (radial)
@export var aim_deadzone: float = 0.15  # Reduced for better sensitivity

## Enable debug printing for input events
@export var debug_input: bool = true

## Trigger threshold - treat trigger as "pressed" when above this value (0.0-1.0)
const TRIGGER_THRESHOLD: float = 0.5

## Xbox controller trigger axis indices
const TRIGGER_AXIS_LEFT: int = 4   # LT (Left Trigger)
const TRIGGER_AXIS_RIGHT: int = 5  # RT (Right Trigger)

# ============================================================================
# INPUT STATE
# ============================================================================

## Current aim direction (Vector2 normalized, or ZERO if below deadzone)
var aim_direction: Vector2 = Vector2.ZERO

## Grid-snapped aim direction (Vector2i for 8-way movement)
var aim_direction_grid: Vector2i = Vector2i.ZERO

## Track which actions were just pressed this frame
var _actions_this_frame: Dictionary = {}  # String -> bool

## Trigger state - analog values (0.0 to 1.0)
var left_trigger_value: float = 0.0
var right_trigger_value: float = 0.0

## Trigger state - digital (above threshold)
var left_trigger_pressed: bool = false
var right_trigger_pressed: bool = false

## Trigger state - just pressed this frame (for action synthesis)
var _left_trigger_just_pressed: bool = false
var _right_trigger_just_pressed: bool = false

## Mouse button state - for input parity (left click = RT)
var left_mouse_pressed: bool = false
var _left_mouse_just_pressed: bool = false

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Controller detection (for debugging - warnings if none detected)
	var joypads = Input.get_connected_joypads()
	if joypads.size() == 0:
		Log.warn(Log.Category.SYSTEM, "No controllers detected (keyboard fallback available)")

func _process(_delta: float) -> void:
	# Clear frame-based action tracking
	_actions_this_frame.clear()
	_left_trigger_just_pressed = false
	_right_trigger_just_pressed = false
	_left_mouse_just_pressed = false

	# Update trigger state
	_update_triggers()

	# Update mouse button state
	_update_mouse_buttons()

	# Update continuous aim direction every frame
	_update_aim_direction()

func _input(event: InputEvent) -> void:
	# Detect input device from event type (use _input so we catch all events, even consumed ones)
	_detect_input_device(event)

func _unhandled_input(event: InputEvent) -> void:
	# Track action presses for this frame
	# Note: This runs AFTER scene input handlers, so it won't interfere
	var tracked_actions := [
		"move_confirm",
		"toggle_ability_1",
		"toggle_ability_2",
		"toggle_ability_3",
		"toggle_ability_4",
		"look_mode",
		"pause"
	]

	for action in tracked_actions:
		if event.is_action_pressed(action):
			_actions_this_frame[action] = true

func _detect_input_device(event: InputEvent) -> void:
	"""Auto-detect which input device is being used based on event type"""
	var new_device: InputDevice

	# Gamepad inputs
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		new_device = InputDevice.GAMEPAD
	# Mouse + keyboard inputs
	elif event is InputEventKey or event is InputEventMouse:
		new_device = InputDevice.MOUSE_KEYBOARD
	else:
		return  # Unknown input type, don't switch

	# Only emit signal if device actually changed
	if new_device != current_input_device:
		current_input_device = new_device
		input_device_changed.emit(new_device)

# ============================================================================
# AIM DIRECTION (Continuous analog input)
# ============================================================================

func _update_aim_direction() -> void:
	"""Read left stick / WASD for aim direction with deadzone handling"""
	# Godot's Input.get_vector handles per-axis deadzones from project.godot
	# We add radial deadzone on top for better 8-way precision
	var raw_input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Apply radial deadzone (more precise than per-axis for diagonals)
	if raw_input.length() > aim_deadzone:
		aim_direction = raw_input.normalized()

		# Convert to 8-way grid direction using angle-based snapping
		var new_grid_dir = _analog_to_grid_8_direction(raw_input)
		aim_direction_grid = new_grid_dir
	else:
		aim_direction = Vector2.ZERO
		aim_direction_grid = Vector2i.ZERO

func _analog_to_grid_8_direction(analog: Vector2) -> Vector2i:
	"""Convert analog stick input to 8-direction grid movement"""
	if analog.length() < aim_deadzone:
		return Vector2i.ZERO

	# Use angle-based approach for cleaner diagonal snapping
	var angle = analog.angle()

	# Convert angle to octant (8 directions)
	# Each octant is PI/4 radians (45 degrees)
	var octant = int(round(angle / (PI / 4.0))) % 8

	# Map octants to 8 cardinal/diagonal directions
	# NOTE: In grid space, +X=right, +Y=down (forward in 3D world is +Z)
	var directions := [
		Vector2i(1, 0),   # 0: Right (0°)
		Vector2i(1, 1),   # 1: Down-Right (45°) = +X,+Z in world
		Vector2i(0, 1),   # 2: Down (90°) = +Z in world
		Vector2i(-1, 1),  # 3: Down-Left (135°) = -X,+Z in world
		Vector2i(-1, 0),  # 4: Left (180°)
		Vector2i(-1, -1), # 5: Up-Left (225°) = -X,-Z in world
		Vector2i(0, -1),  # 6: Up (270°) = -Z in world
		Vector2i(1, -1)   # 7: Up-Right (315°) = +X,-Z in world
	]

	var result = directions[octant]
	return result

## Get current aim direction (normalized Vector2, or ZERO if below deadzone)
func get_aim_direction() -> Vector2:
	return aim_direction

## Get grid-snapped aim direction (Vector2i for 8-way movement)
func get_aim_direction_grid() -> Vector2i:
	return aim_direction_grid

# ============================================================================
# TRIGGER HANDLING
# ============================================================================

func _update_triggers() -> void:
	"""Read trigger axes and synthesize button events for actions"""
	# Read raw axis values from controller 0
	# Note: Triggers return 0.0 to 1.0 (not -1.0 to 1.0 like sticks)
	left_trigger_value = Input.get_joy_axis(0, TRIGGER_AXIS_LEFT as JoyAxis)
	right_trigger_value = Input.get_joy_axis(0, TRIGGER_AXIS_RIGHT as JoyAxis)

	# Convert to digital state (above threshold = "pressed")
	var left_now_pressed = left_trigger_value > TRIGGER_THRESHOLD
	var right_now_pressed = right_trigger_value > TRIGGER_THRESHOLD

	# Track "just pressed" (transition from not pressed -> pressed)
	_left_trigger_just_pressed = left_now_pressed and not left_trigger_pressed
	_right_trigger_just_pressed = right_now_pressed and not right_trigger_pressed

	# Update pressed state for next frame
	left_trigger_pressed = left_now_pressed
	right_trigger_pressed = right_now_pressed

	# Synthesize action events for triggers
	# RT (right trigger) -> move_confirm action
	if _right_trigger_just_pressed:
		_actions_this_frame["move_confirm"] = true
		# Input event logging handled by _log_input_event()


func _update_mouse_buttons() -> void:
	"""Track mouse button state for input parity (left click = RT)"""
	# Only track when mouse is captured (otherwise it's for UI/camera)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		left_mouse_pressed = false
		_left_mouse_just_pressed = false
		return

	# Check current state
	var mouse_now_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# Track "just pressed" (transition from not pressed -> pressed)
	_left_mouse_just_pressed = mouse_now_pressed and not left_mouse_pressed

	# Update pressed state for next frame
	left_mouse_pressed = mouse_now_pressed

	# Synthesize action events for mouse buttons
	# Left click -> move_confirm action (same as RT)
	if _left_mouse_just_pressed:
		_actions_this_frame["move_confirm"] = true
		# Input event logging handled by _log_input_event()

# ============================================================================
# ACTION QUERIES
# ============================================================================

## Check if an action was just pressed this frame
## This is similar to Input.is_action_just_pressed() but centralized
func is_action_just_pressed(action: String) -> bool:
	return _actions_this_frame.get(action, false)

## Check if an action is currently held down
## Handles both regular actions AND trigger-synthesized actions
func is_action_pressed(action: String) -> bool:
	# Special handling for move_confirm - check RT trigger state + mouse button
	if action == "move_confirm":
		# move_confirm is "pressed" if any of:
		# 1. Physical RT trigger is above threshold
		# 2. Left mouse button is pressed (input parity!)
		# 3. Regular keyboard/button action is pressed (Space)
		return right_trigger_pressed or left_mouse_pressed or Input.is_action_pressed(action)

	# Special handling for look_mode - check LT trigger state
	if action == "look_mode":
		# look_mode is "pressed" if any of:
		# 1. Physical LT trigger is above threshold (already mapped in project.godot)
		# 2. RMB (already mapped in project.godot)
		return left_trigger_pressed or Input.is_action_pressed(action)

	# For other actions, use Godot's built-in system
	return Input.is_action_pressed(action)

# ============================================================================
# CONFIGURATION
# ============================================================================

func set_aim_deadzone(deadzone: float) -> void:
	"""Set aim deadzone (0.0 to 0.9)"""
	aim_deadzone = clampf(deadzone, 0.0, 0.9)

func set_debug_mode(enabled: bool) -> void:
	"""Enable/disable debug logging"""
	debug_input = enabled

# ============================================================================
# DEBUG UTILITIES
# ============================================================================

func get_debug_info() -> Dictionary:
	"""Get current input state for debugging UI"""
	return {
		"aim_direction": aim_direction,
		"aim_direction_grid": aim_direction_grid,
		"actions_this_frame": _actions_this_frame.keys(),
		"deadzone": aim_deadzone
	}
