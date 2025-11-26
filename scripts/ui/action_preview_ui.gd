class_name ActionPreviewUI
extends Control
## UI overlay showing what will happen on next turn
##
## Displays preview of actions that will execute when player presses RT/Left Click
## Updates in real-time based on player state and active input device

# Node references (created programmatically)
var panel: PanelContainer
var header_label: Label  # Shows input prompt: "[RT]" or "[Left Click]"
var action_list: VBoxContainer  # Shows list of actions that will execute

# State
var current_actions: Array[Action] = []
var current_input_device: InputManager.InputDevice = InputManager.InputDevice.MOUSE_KEYBOARD
var is_paused: bool = false

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	Log.system("ActionPreviewUI _ready() called")

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

	Log.system("ActionPreviewUI initialization complete")

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
	header_label.add_theme_font_size_override("font_size", 14)
	header_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
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

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

func _add_action_entry(info: Dictionary) -> void:
	"""Add an action entry to the list"""
	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	# Icon
	var icon_label = Label.new()
	icon_label.text = info.get("icon", "?")
	icon_label.add_theme_font_size_override("font_size", 16)
	icon_label.add_theme_color_override("font_color", Color.WHITE)
	entry.add_child(icon_label)

	# Action name + target
	var text_label = Label.new()
	var target = info.get("target", "")
	if target != "":
		text_label.text = "%s %s" % [info.get("name", "Unknown"), target]
	else:
		text_label.text = info.get("name", "Unknown")
	text_label.add_theme_font_size_override("font_size", 14)
	text_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(text_label)

	# Cost (if any)
	var cost = info.get("cost", "")
	if cost != "":
		var cost_label = Label.new()
		cost_label.text = cost
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.add_theme_color_override("font_color", Color.YELLOW)
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
