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
@export var aim_deadzone: float = 0.2

## Enable debug printing for input events
@export var debug_input: bool = true

# ============================================================================
# INPUT STATE
# ============================================================================

## Current aim direction (Vector2 normalized, or ZERO if below deadzone)
var aim_direction: Vector2 = Vector2.ZERO

## Grid-snapped aim direction (Vector2i for 8-way movement)
var aim_direction_grid: Vector2i = Vector2i.ZERO

## Track which actions were just pressed this frame
var _actions_this_frame: Dictionary = {}  # String -> bool

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	print("[InputManager] Initialized - Controller-first input system ready")
	print("[InputManager] Aim deadzone: ", aim_deadzone)
	print("[InputManager] Debug mode: ", "ON" if debug_input else "OFF")

	# List connected controllers for debugging
	var joypads = Input.get_connected_joypads()
	if joypads.size() > 0:
		print("[InputManager] Connected controllers:")
		for joypad in joypads:
			print("  - Device %d: %s" % [joypad, Input.get_joy_name(joypad)])
	else:
		print("[InputManager] WARNING: No controllers detected (keyboard fallback available)")

func _process(_delta: float) -> void:
	# Clear frame-based action tracking
	_actions_this_frame.clear()

	# Update continuous aim direction every frame
	_update_aim_direction()

func _unhandled_input(event: InputEvent) -> void:
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
			if debug_input:
				print("[InputManager] Action detected: %s" % action)

	# Debug: Print controller button presses
	if debug_input and event is InputEventJoypadButton and event.pressed:
		print("[InputManager] Controller button %d pressed (%s)" % [event.button_index, event.as_text()])

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
		aim_direction_grid = _analog_to_grid_8_direction(raw_input)
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
	var directions := [
		Vector2i(1, 0),   # 0: Right (0°)
		Vector2i(1, 1),   # 1: Down-Right (45°)
		Vector2i(0, 1),   # 2: Down (90°)
		Vector2i(-1, 1),  # 3: Down-Left (135°)
		Vector2i(-1, 0),  # 4: Left (180°)
		Vector2i(-1, -1), # 5: Up-Left (225°)
		Vector2i(0, -1),  # 6: Up (270°)
		Vector2i(1, -1)   # 7: Up-Right (315°)
	]

	return directions[octant]

## Get current aim direction (normalized Vector2, or ZERO if below deadzone)
func get_aim_direction() -> Vector2:
	return aim_direction

## Get grid-snapped aim direction (Vector2i for 8-way movement)
func get_aim_direction_grid() -> Vector2i:
	return aim_direction_grid

# ============================================================================
# ACTION QUERIES
# ============================================================================

## Check if an action was just pressed this frame
## This is similar to Input.is_action_just_pressed() but centralized
func is_action_just_pressed(action: String) -> bool:
	return _actions_this_frame.get(action, false)

# ============================================================================
# CONFIGURATION
# ============================================================================

func set_aim_deadzone(deadzone: float) -> void:
	"""Set aim deadzone (0.0 to 0.9)"""
	aim_deadzone = clampf(deadzone, 0.0, 0.9)
	print("[InputManager] Aim deadzone set to: %f" % aim_deadzone)

func set_debug_mode(enabled: bool) -> void:
	"""Enable/disable debug logging"""
	debug_input = enabled
	print("[InputManager] Debug mode: %s" % ("ON" if enabled else "OFF"))

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
