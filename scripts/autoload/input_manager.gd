extends Node
## InputManager - Centralized input handling for turn-based roguelike
##
## This autoload singleton provides:
## - Unified controller + keyboard input
## - Trigger handling (analog → digital with threshold)
## - Mouse button input parity (LMB = RT, RMB = LT)
## - Device auto-detection (gamepad ↔ mouse+keyboard)
##
## Usage:
##   InputManager.is_action_just_pressed("action_name") -> bool
##   InputManager.is_action_pressed("action_name") -> bool

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

## Trigger threshold - treat trigger as "pressed" when above this value (0.0-1.0)
const TRIGGER_THRESHOLD: float = 0.5

## Xbox controller trigger axis indices
const TRIGGER_AXIS_LEFT: int = 4   # LT (Left Trigger)
const TRIGGER_AXIS_RIGHT: int = 5  # RT (Right Trigger)

# ============================================================================
# INPUT STATE
# ============================================================================

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

## Mouse button state - for input parity (left click = RT, right click = LT)
var left_mouse_pressed: bool = false
var _left_mouse_just_pressed: bool = false
var right_mouse_pressed: bool = false
var _right_mouse_just_pressed: bool = false

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
	_right_mouse_just_pressed = false

	# Update trigger state
	_update_triggers()

	# Update mouse button state
	_update_mouse_buttons()

func _input(event: InputEvent) -> void:
	# Detect input device from event type (use _input so we catch all events, even consumed ones)
	_detect_input_device(event)

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

	# LT (left trigger) -> wait_action
	if _left_trigger_just_pressed:
		_actions_this_frame["wait_action"] = true


func _update_mouse_buttons() -> void:
	"""Track mouse button state for input parity (left click = RT, right click = LT)"""
	# Only track when mouse is captured (otherwise it's for UI/camera)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		left_mouse_pressed = false
		_left_mouse_just_pressed = false
		right_mouse_pressed = false
		_right_mouse_just_pressed = false
		return

	# Check current state - LMB
	var lmb_now_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_left_mouse_just_pressed = lmb_now_pressed and not left_mouse_pressed
	left_mouse_pressed = lmb_now_pressed

	# Check current state - RMB
	var rmb_now_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_right_mouse_just_pressed = rmb_now_pressed and not right_mouse_pressed
	right_mouse_pressed = rmb_now_pressed

	# Synthesize action events for mouse buttons
	# Left click -> move_confirm action (same as RT)
	if _left_mouse_just_pressed:
		_actions_this_frame["move_confirm"] = true

	# Right click -> wait_action (same as LT)
	if _right_mouse_just_pressed:
		_actions_this_frame["wait_action"] = true

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

	# Special handling for wait_action - check LT trigger state + RMB
	if action == "wait_action":
		# wait_action is "pressed" if any of:
		# 1. Physical LT trigger is above threshold
		# 2. Right mouse button is pressed (input parity!)
		# 3. Regular keyboard action (if mapped)
		return left_trigger_pressed or right_mouse_pressed or Input.is_action_pressed(action)

	# For other actions, use Godot's built-in system
	return Input.is_action_pressed(action)
