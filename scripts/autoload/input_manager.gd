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
	Log.system("InputManager initialized - Controller-first input system ready")
	Log.system("Aim deadzone: %.2f" % aim_deadzone)
	Log.system("Debug mode: %s" % ("ON" if debug_input else "OFF"))

	# List connected controllers for debugging
	var joypads = Input.get_connected_joypads()
	if joypads.size() > 0:
		Log.system("Connected controllers:")
		for joypad in joypads:
			Log.system("  - Device %d: %s" % [joypad, Input.get_joy_name(joypad)])
	else:
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

func _unhandled_input(event: InputEvent) -> void:
	# Generic input logging - log ALL input events when debug enabled
	if debug_input:
		_log_input_event(event)

	# Track action presses for this frame
	# Note: This runs AFTER scene input handlers, so it won't interfere
	var tracked_actions := [
		"move_confirm",
		"toggle_ability_1",
		"toggle_ability_2",
		"toggle_ability_3",
		"toggle_ability_4",
		"examine_mode"
	]

	for action in tracked_actions:
		if event.is_action_pressed(action):
			_actions_this_frame[action] = true

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

	# LT (left trigger) currently unmapped
	# Future: Could map to examine_mode or other actions

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

	# For other actions, use Godot's built-in system
	return Input.is_action_pressed(action)

# ============================================================================
# CONFIGURATION
# ============================================================================

func set_aim_deadzone(deadzone: float) -> void:
	"""Set aim deadzone (0.0 to 0.9)"""
	aim_deadzone = clampf(deadzone, 0.0, 0.9)
	Log.system("InputManager aim deadzone set to: %.2f" % aim_deadzone)

func set_debug_mode(enabled: bool) -> void:
	"""Enable/disable debug logging"""
	debug_input = enabled
	Log.system("InputManager debug mode: %s" % ("ON" if enabled else "OFF"))

# ============================================================================
# DEBUG UTILITIES
# ============================================================================

func _log_input_event(event: InputEvent) -> void:
	"""Generic input event logger - logs ALL input types automatically (TRACE level - very verbose)"""
	# Keyboard key presses
	if event is InputEventKey:
		if event.pressed and not event.echo:
			var key_name = OS.get_keycode_string(event.keycode)
			Log.input_trace("Key pressed: %s" % key_name)
		elif not event.pressed:
			var key_name = OS.get_keycode_string(event.keycode)
			Log.input_trace("Key released: %s" % key_name)

	# Joypad button presses
	elif event is InputEventJoypadButton:
		if event.pressed:
			var button_name = _get_button_name(event.button_index)
			Log.input_trace("Gamepad button pressed: %s (index: %d)" % [button_name, event.button_index])
		else:
			var button_name = _get_button_name(event.button_index)
			Log.input_trace("Gamepad button released: %s (index: %d)" % [button_name, event.button_index])

	# Joypad motion (analog sticks, triggers)
	elif event is InputEventJoypadMotion:
		var axis_name = _get_axis_name(event.axis)
		# Log all stick/trigger movement above deadzone
		if abs(event.axis_value) > 0.15:
			Log.input_trace("Gamepad %s: %.2f" % [axis_name, event.axis_value])

	# Mouse button presses
	elif event is InputEventMouseButton:
		if event.pressed:
			var button_name = _get_mouse_button_name(event.button_index)
			Log.input_trace("Mouse button pressed: %s" % button_name)
		else:
			var button_name = _get_mouse_button_name(event.button_index)
			Log.input_trace("Mouse button released: %s" % button_name)

	# Mouse motion - log when significant
	elif event is InputEventMouseMotion:
		if event.relative.length() > 5:
			Log.input_trace("Mouse moved: (%.1f, %.1f)" % [event.relative.x, event.relative.y])

func _get_axis_name(axis: int) -> String:
	"""Convert axis index to human-readable name"""
	match axis:
		JOY_AXIS_LEFT_X: return "LeftStick-X"
		JOY_AXIS_LEFT_Y: return "LeftStick-Y"
		JOY_AXIS_RIGHT_X: return "RightStick-X"
		JOY_AXIS_RIGHT_Y: return "RightStick-Y"
		JOY_AXIS_TRIGGER_LEFT: return "LeftTrigger"
		JOY_AXIS_TRIGGER_RIGHT: return "RightTrigger"
		_: return "Axis%d" % axis

func _get_button_name(button_index: int) -> String:
	"""Convert button index to human-readable name (Xbox layout)"""
	match button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "LeftStickClick"
		JOY_BUTTON_RIGHT_STICK: return "RightStickClick"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_GUIDE: return "Guide"
		JOY_BUTTON_DPAD_UP: return "DPad-Up"
		JOY_BUTTON_DPAD_DOWN: return "DPad-Down"
		JOY_BUTTON_DPAD_LEFT: return "DPad-Left"
		JOY_BUTTON_DPAD_RIGHT: return "DPad-Right"
		_: return "Button%d" % button_index

func _get_mouse_button_name(button_index: int) -> String:
	"""Convert mouse button index to human-readable name"""
	match button_index:
		MOUSE_BUTTON_LEFT: return "LeftClick"
		MOUSE_BUTTON_RIGHT: return "RightClick"
		MOUSE_BUTTON_MIDDLE: return "MiddleClick"
		MOUSE_BUTTON_WHEEL_UP: return "WheelUp"
		MOUSE_BUTTON_WHEEL_DOWN: return "WheelDown"
		MOUSE_BUTTON_XBUTTON1: return "Mouse4"
		MOUSE_BUTTON_XBUTTON2: return "Mouse5"
		_: return "MouseButton%d" % button_index

func get_debug_info() -> Dictionary:
	"""Get current input state for debugging UI"""
	return {
		"aim_direction": aim_direction,
		"aim_direction_grid": aim_direction_grid,
		"actions_this_frame": _actions_this_frame.keys(),
		"deadzone": aim_deadzone
	}
