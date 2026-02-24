class_name ControlHints
extends Control
## Persistent MOVE/WAIT control hints at the top of the game viewport
##
## Shows the two core actions (Move Forward, Wait/Pass Turn) with input labels
## that automatically switch between gamepad and keyboard+mouse glyphs based
## on the active input device.
##
## Hidden during auto-explore (the AUTO-EXPLORE label takes that space).

# ============================================================================
# CONSTANTS
# ============================================================================

## Control labels — keep in sync with CONTROL_MAPPINGS in settings_panel.gd
const GAMEPAD_MOVE := "🎮 RT"
const GAMEPAD_WAIT := "🎮 LT"

## Keyboard+mouse labels
const KB_MOVE := "🖱 LMB"
const KB_WAIT := "🖱 RMB"

const FONT_SIZE := 16
const HINT_SPREAD := 120  # Pixels from center to each hint

# ============================================================================
# STATE
# ============================================================================

var move_label: Label
var wait_label: Label

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# MOVE hint — left of center
	move_label = _create_hint_label()
	move_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	move_label.offset_top = 4
	move_label.offset_left = -HINT_SPREAD - 120
	move_label.offset_right = -HINT_SPREAD + 40
	move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(move_label)

	# WAIT hint — right of center
	wait_label = _create_hint_label()
	wait_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wait_label.offset_top = 4
	wait_label.offset_left = HINT_SPREAD - 40
	wait_label.offset_right = HINT_SPREAD + 120
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(wait_label)

	_update_labels()

	# Listen for input device changes
	if InputManager:
		InputManager.input_device_changed.connect(_on_input_device_changed)

func _create_hint_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65, 0.8))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# ============================================================================
# UPDATES
# ============================================================================

func _update_labels() -> void:
	var is_gamepad := InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD
	var move_key := GAMEPAD_MOVE if is_gamepad else KB_MOVE
	var wait_key := GAMEPAD_WAIT if is_gamepad else KB_WAIT
	move_label.text = "MOVE  %s" % move_key
	wait_label.text = "WAIT  %s" % wait_key

func _on_input_device_changed(_device) -> void:
	_update_labels()
