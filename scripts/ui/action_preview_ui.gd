class_name ActionPreviewUI
extends Control
## UI overlay showing what will happen on next turn
##
## Displays preview of actions that will execute when player presses RT/Left Click
## Updates in real-time based on player state and active input device

# ============================================================================
# CONSTANTS
# ============================================================================

## Resolution scale threshold for high-res mode (minimap scale >= 3 means 4K+)
const HIGH_RES_SCALE_THRESHOLD := 3

## Font sizes for normal resolution
const FONT_SIZE_HEADER := 14
const FONT_SIZE_ICON := 16
const FONT_SIZE_TEXT := 14
const FONT_SIZE_COST := 12

## Font size multiplier for high-res mode
const HIGH_RES_FONT_MULTIPLIER := 1.5

# ============================================================================
# NODE REFERENCES
# ============================================================================

# Node references (created programmatically)
var panel: PanelContainer
var header_label: Label  # Shows input prompt: "[RT]" or "[Left Click]"
var action_list: VBoxContainer  # Shows list of actions that will execute

# Font with emoji fallback (loaded once, used for all labels)
var emoji_font: Font = null

# ============================================================================
# STATE
# ============================================================================

var current_actions: Array[Action] = []
var current_input_device: InputManager.InputDevice = InputManager.InputDevice.MOUSE_KEYBOARD
var is_paused: bool = false
var is_high_res: bool = false  # True when minimap scale > HIGH_RES_SCALE_THRESHOLD

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Load emoji font (project setting doesn't auto-apply to programmatic Labels)
	emoji_font = load("res://assets/fonts/default_font.tres")

	# Build UI programmatically
	_build_ui()

	# Connect to InputManager for device changes
	if InputManager:
		InputManager.input_device_changed.connect(_on_input_device_changed)
		current_input_device = InputManager.current_input_device

	# Connect to PauseManager for pause state changes
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)
		is_paused = PauseManager.is_paused

	# Hide by default (will show when actions provided)
	panel.visible = false

func _build_ui() -> void:
	"""Build action preview UI programmatically"""
	# Set control to fill viewport
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create panel (center top)
	panel = PanelContainer.new()
	panel.name = "ActionPreviewPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# Position at center top (auto-sizes based on content)
	panel.anchor_left = 0.5   # Center horizontally
	panel.anchor_top = 0.0    # Top edge
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.0
	panel.offset_left = -140   # 280px wide panel, centered (-280/2)
	panel.offset_right = 140   # 280px wide panel, centered (+280/2)
	panel.offset_top = 16      # 16px margin from top
	# No offset_bottom - let content determine height
	panel.grow_vertical = Control.GROW_DIRECTION_END  # Grow downward from top

	# Style panel (consistent with examination UI)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)  # Nearly opaque black
	style.border_color = Color(1, 1, 1, 1)  # White border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	# Content container
	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Header showing input prompt
	header_label = Label.new()
	header_label.text = "[Left Click] Next Turn"
	header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		header_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(header_label)

	# Separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	vbox.add_child(separator)

	# Action list container
	action_list = VBoxContainer.new()
	action_list.name = "ActionList"
	action_list.add_theme_constant_override("separation", 2)
	vbox.add_child(action_list)

# ============================================================================
# PUBLIC API
# ============================================================================

func show_preview(actions: Array[Action], player) -> void:
	"""Display preview for given actions"""
	# Store actions for later (when unpausing)
	current_actions = actions

	if actions.is_empty():
		hide_preview()
		return

	# Clear previous action list
	for child in action_list.get_children():
		child.queue_free()

	# Add action entries
	for action in actions:
		var info = action.get_preview_info(player)
		_add_action_entry(info)

	# Update header with current input device
	_update_header()

	# Show panel
	panel.visible = true

func hide_preview() -> void:
	"""Hide the action preview"""
	panel.visible = false
	current_actions.clear()

func set_resolution_scale(scale_factor: int) -> void:
	"""Update UI scaling based on resolution (called by minimap when scale changes)"""
	var new_high_res = scale_factor >= HIGH_RES_SCALE_THRESHOLD
	if new_high_res == is_high_res:
		return  # No change

	is_high_res = new_high_res
	Log.system("ActionPreviewUI: High-res mode %s (scale=%d, threshold=%d)" % [
		"enabled" if is_high_res else "disabled", scale_factor, HIGH_RES_SCALE_THRESHOLD
	])

	# Update header font size immediately
	header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))

	# Update existing action entries if visible
	for entry in action_list.get_children():
		if entry is HBoxContainer:
			var children = entry.get_children()
			if children.size() >= 1 and children[0] is Label:
				children[0].add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ICON))
			if children.size() >= 2 and children[1] is Label:
				children[1].add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_TEXT))
			if children.size() >= 3 and children[2] is Label:
				children[2].add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_COST))

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

func _get_font_size(base_size: int) -> int:
	"""Get font size adjusted for resolution"""
	if is_high_res:
		return int(base_size * HIGH_RES_FONT_MULTIPLIER)
	return base_size

func _rebuild_action_list(player) -> void:
	"""Rebuild action list with current font sizes (called after resolution change)"""
	if current_actions.is_empty():
		return

	# Clear and rebuild
	for child in action_list.get_children():
		child.queue_free()

	for action in current_actions:
		var info = action.get_preview_info(player)
		_add_action_entry(info)

	# Also update header font size
	header_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))

func _add_action_entry(info: Dictionary) -> void:
	"""Add an action entry to the list"""
	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	# Icon (uses emoji font for emoji/symbol support)
	var icon_label = Label.new()
	icon_label.text = info.get("icon", "?")
	icon_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ICON))
	icon_label.add_theme_color_override("font_color", Color.WHITE)
	if emoji_font:
		icon_label.add_theme_font_override("font", emoji_font)
	entry.add_child(icon_label)

	# Action name + target (uses emoji font for arrow symbols like →)
	var text_label = Label.new()
	var target = info.get("target", "")
	if target != "":
		text_label.text = "%s %s" % [info.get("name", "Unknown"), target]
	else:
		text_label.text = info.get("name", "Unknown")
	text_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_TEXT))
	text_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if emoji_font:
		text_label.add_theme_font_override("font", emoji_font)
	entry.add_child(text_label)

	# Cost (if any)
	var cost = info.get("cost", "")
	if cost != "":
		var cost_label = Label.new()
		cost_label.text = cost
		cost_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_COST))
		cost_label.add_theme_color_override("font_color", Color.YELLOW)
		if emoji_font:
			cost_label.add_theme_font_override("font", emoji_font)
		entry.add_child(cost_label)

	action_list.add_child(entry)

func _update_header() -> void:
	"""Update header text based on current input device"""
	if is_paused:
		header_label.text = "GAME PAUSED"
		return

	var button_text = "[Left Click]"
	if current_input_device == InputManager.InputDevice.GAMEPAD:
		button_text = "[RT]"

	header_label.text = "%s Next Turn" % button_text

func _show_pause_message() -> void:
	"""Show pause message instead of action preview"""
	# Clear action list
	for child in action_list.get_children():
		child.queue_free()

	# Update header to show pause state
	header_label.text = "GAME PAUSED"

	# Show panel
	panel.visible = true

# ============================================================================
# SIGNALS
# ============================================================================

func _on_input_device_changed(device: InputManager.InputDevice) -> void:
	"""Handle input device switching"""
	current_input_device = device
	_update_header()

func _on_pause_toggled(paused: bool) -> void:
	"""Handle pause state changes"""
	is_paused = paused
	# Note: game.gd handles showing/hiding the preview content on pause
	# We just track state here for header updates via _update_header()

# ============================================================================
# LAYOUT MANAGEMENT (Portrait/Landscape)
# ============================================================================

func set_portrait_mode(is_portrait: bool) -> void:
	"""Position is always center top in both modes - no change needed"""
	pass  # Panel stays at center top in both portrait and landscape
