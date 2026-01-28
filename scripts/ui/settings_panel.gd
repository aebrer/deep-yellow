class_name SettingsPanel
extends Control
## Settings panel shown when game is paused
##
## Displays settings controls on the left side of the game viewport:
## - Fullscreen toggle
## - Look sensitivity slider (mouse + controller)
## - FOV slider
## - Controls reference (adapts to current input device)
## - Restart Run button
## - Quit to Desktop button
##
## Shows automatically when paused, hides when unpaused.
## Designed to be tab-ready for future expansion.

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 20
const FONT_SIZE_LABEL := 14
const FONT_SIZE_BUTTON := 14
const FONT_SIZE_CONTROL_HINT := 12
const PANEL_WIDTH := 280.0
const PANEL_MARGIN := 20.0  # Offset from left edge of game viewport

## Delay before accepting input (prevents accidental clicks from held buttons)
const INPUT_ACCEPT_DELAY := 0.3  # seconds (shorter than level-up since less critical)

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var content_vbox: VBoxContainer
var focusable_controls: Array[Control] = []

## Font with emoji fallback
var emoji_font: Font = null

# Settings controls
var fullscreen_button: Button
var sensitivity_slider: HSlider
var sensitivity_value_label: Label
var fov_slider: HSlider
var fov_value_label: Label
var codex_button: Button
var restart_button: Button
var quit_button: Button

# Controls section container (for device-specific label updates)
var _controls_vbox: VBoxContainer = null

# Reference to codex panel (set by game.gd)
var codex_panel: CodexPanel = null

# State
var _accepting_input: bool = false
var _player_ref: Player3D = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	emoji_font = load("res://assets/fonts/default_font.tres")

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_panel()

	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

	if InputManager:
		InputManager.input_device_changed.connect(_on_input_device_changed)

func _build_panel() -> void:
	"""Build the settings panel UI"""
	panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(0.6, 0.6, 0.6, 1)  # Gray border (neutral, not event-specific)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	content_vbox = VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.add_theme_constant_override("separation", 8)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content_vbox)

	_build_content()

func _build_content() -> void:
	"""Build all settings controls"""
	focusable_controls.clear()

	# Header
	var header = Label.new()
	header.text = "SETTINGS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(header)

	# Separator
	var sep1 = HSeparator.new()
	sep1.add_theme_constant_override("separation", 6)
	content_vbox.add_child(sep1)

	# --- Fullscreen toggle ---
	fullscreen_button = _create_toggle_button(
		"Fullscreen: ON" if _is_fullscreen() else "Fullscreen: OFF"
	)
	fullscreen_button.pressed.connect(_on_fullscreen_toggled)
	content_vbox.add_child(fullscreen_button)
	focusable_controls.append(fullscreen_button)

	# --- Look Sensitivity ---
	var sens_label = _create_setting_label("Look Sensitivity")
	content_vbox.add_child(sens_label)

	var sens_row = HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 8)
	content_vbox.add_child(sens_row)

	sensitivity_slider = HSlider.new()
	sensitivity_slider.min_value = 0.05
	sensitivity_slider.max_value = 0.50
	sensitivity_slider.step = 0.01
	sensitivity_slider.value = 0.15  # Default, updated in set_player
	sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_slider.custom_minimum_size = Vector2(150, 0)
	sensitivity_slider.add_to_group("hud_focusable")
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	sens_row.add_child(sensitivity_slider)
	focusable_controls.append(sensitivity_slider)

	sensitivity_value_label = Label.new()
	sensitivity_value_label.text = "0.15"
	sensitivity_value_label.custom_minimum_size = Vector2(40, 0)
	sensitivity_value_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_LABEL))
	if emoji_font:
		sensitivity_value_label.add_theme_font_override("font", emoji_font)
	sens_row.add_child(sensitivity_value_label)

	# --- FOV ---
	var fov_label = _create_setting_label("Field of View")
	content_vbox.add_child(fov_label)

	var fov_row = HBoxContainer.new()
	fov_row.add_theme_constant_override("separation", 8)
	content_vbox.add_child(fov_row)

	fov_slider = HSlider.new()
	fov_slider.min_value = 60.0
	fov_slider.max_value = 110.0
	fov_slider.step = 5.0
	fov_slider.value = 90.0  # Default, updated in set_player
	fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_slider.custom_minimum_size = Vector2(150, 0)
	fov_slider.add_to_group("hud_focusable")
	fov_slider.value_changed.connect(_on_fov_changed)
	fov_row.add_child(fov_slider)
	focusable_controls.append(fov_slider)

	fov_value_label = Label.new()
	fov_value_label.text = "90"
	fov_value_label.custom_minimum_size = Vector2(40, 0)
	fov_value_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_LABEL))
	if emoji_font:
		fov_value_label.add_theme_font_override("font", emoji_font)
	fov_row.add_child(fov_value_label)

	# --- Codex ---
	codex_button = _create_action_button("Codex")
	codex_button.pressed.connect(_on_codex_pressed)
	content_vbox.add_child(codex_button)
	focusable_controls.append(codex_button)

	# --- Controls Reference ---
	_build_controls_section()

	# Separator before actions
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 10)
	content_vbox.add_child(sep2)

	# --- Restart Run ---
	restart_button = _create_action_button("Restart Run")
	restart_button.pressed.connect(_on_restart_pressed)
	content_vbox.add_child(restart_button)
	focusable_controls.append(restart_button)

	# --- Quit to Desktop ---
	quit_button = _create_action_button("Quit to Desktop")
	quit_button.pressed.connect(_on_quit_pressed)
	content_vbox.add_child(quit_button)
	focusable_controls.append(quit_button)

# ============================================================================
# CONTROLS SECTION
# ============================================================================

## Control mappings: [action_name, gamepad_label, mkb_label]
const CONTROL_MAPPINGS := [
	["Move Forward", "RT", "LMB"],
	["Wait / Pass Turn", "LT", "RMB"],
	["Look Around", "Right Stick", "Mouse"],
	["Pause", "START", "ESC / MMB"],
	["Camera Mode", "SELECT", "C"],
	["Zoom", "LB / RB", "Scroll Wheel"],
	["Navigate HUD", "Left Stick", "Mouse Hover"],
	["Minimap Zoom", "D-Pad L/R", "Arrow Keys"],
]

func _build_controls_section() -> void:
	"""Build the controls reference section"""
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	content_vbox.add_child(sep)

	var controls_header = Label.new()
	controls_header.text = "CONTROLS"
	controls_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	controls_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		controls_header.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(controls_header)

	_controls_vbox = VBoxContainer.new()
	_controls_vbox.add_theme_constant_override("separation", 2)
	content_vbox.add_child(_controls_vbox)

	_populate_controls()

func _populate_controls() -> void:
	"""Populate control hints based on current input device"""
	# Clear existing entries
	for child in _controls_vbox.get_children():
		child.queue_free()

	var is_gamepad := InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD

	for mapping in CONTROL_MAPPINGS:
		var action_name: String = mapping[0]
		var input_label: String = mapping[1] if is_gamepad else mapping[2]
		_add_control_row(action_name, input_label)

func _add_control_row(action_name: String, input_label: String) -> void:
	"""Add a single control mapping row"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var input_lbl = Label.new()
	input_lbl.text = input_label
	input_lbl.custom_minimum_size = Vector2(100, 0)
	input_lbl.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_CONTROL_HINT))
	input_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7))
	if emoji_font:
		input_lbl.add_theme_font_override("font", emoji_font)
	row.add_child(input_lbl)

	var action_lbl = Label.new()
	action_lbl.text = action_name
	action_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_lbl.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_CONTROL_HINT))
	action_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	if emoji_font:
		action_lbl.add_theme_font_override("font", emoji_font)
	row.add_child(action_lbl)

	_controls_vbox.add_child(row)

func _on_input_device_changed(_device) -> void:
	"""Refresh controls section when input device changes"""
	if _controls_vbox:
		_populate_controls()

# ============================================================================
# PUBLIC API
# ============================================================================

func set_player(player: Player3D) -> void:
	"""Set player reference for reading/writing camera settings"""
	_player_ref = player

	# Read current values from cameras
	if player:
		var fp_cam = player.get_node_or_null("FirstPersonCamera")
		if fp_cam:
			sensitivity_slider.value = fp_cam.mouse_sensitivity
			sensitivity_value_label.text = "%.2f" % fp_cam.mouse_sensitivity
			fov_slider.value = fp_cam.default_fov
			fov_value_label.text = "%d" % int(fp_cam.default_fov)

# ============================================================================
# UI HELPERS
# ============================================================================

func _create_setting_label(text: String) -> Label:
	"""Create a label for a setting row"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_LABEL))
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	if emoji_font:
		label.add_theme_font_override("font", emoji_font)
	return label

func _create_toggle_button(text: String) -> Button:
	"""Create a styled toggle button"""
	var button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_BUTTON))
	if emoji_font:
		button.add_theme_font_override("font", emoji_font)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_apply_button_styles(button)
	button.add_to_group("hud_focusable")
	return button

func _create_action_button(text: String) -> Button:
	"""Create a styled action button"""
	var button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_BUTTON))
	if emoji_font:
		button.add_theme_font_override("font", emoji_font)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_apply_button_styles(button)
	button.add_to_group("hud_focusable")
	return button

func _apply_button_styles(button: Button) -> void:
	"""Apply consistent button styling (matching LevelUpPanel pattern)"""
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(1.0, 1.0, 0.5, 0.3)
	focus_style.border_color = Color(1.0, 1.0, 0.5, 0.8)
	focus_style.set_border_width_all(2)
	focus_style.content_margin_left = 8
	focus_style.content_margin_right = 8
	focus_style.content_margin_top = 6
	focus_style.content_margin_bottom = 6

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color(0.6, 0.6, 0.6, 1.0)
	hover_style.content_margin_left = 8
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 6
	hover_style.content_margin_bottom = 6

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("hover", hover_style)

# ============================================================================
# SETTINGS ACTIONS
# ============================================================================

func _is_fullscreen() -> bool:
	"""Check if window is in fullscreen mode"""
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func _on_codex_pressed() -> void:
	"""Open the codex panel"""
	if not _accepting_input:
		return
	if codex_panel:
		visible = false
		if not codex_panel.codex_closed.is_connected(_on_codex_closed):
			codex_panel.codex_closed.connect(_on_codex_closed)
		codex_panel.show_codex()

func _on_codex_closed() -> void:
	"""Re-show settings panel when codex is closed"""
	if PauseManager and PauseManager.is_paused:
		_show_panel()

func _on_fullscreen_toggled() -> void:
	"""Toggle fullscreen mode"""
	if not _accepting_input:
		return

	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		fullscreen_button.text = "Fullscreen: OFF"
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		fullscreen_button.text = "Fullscreen: ON"

## Default values for proportional scaling (mouse_sensitivity and rotation_speed
## are different units but should scale together)
const DEFAULT_MOUSE_SENSITIVITY := 0.15
const DEFAULT_ROTATION_SPEED := 360.0

func _on_sensitivity_changed(value: float) -> void:
	"""Update look sensitivity on both cameras (mouse + controller)"""
	sensitivity_value_label.text = "%.2f" % value

	if not _player_ref:
		return

	# Scale controller rotation_speed proportionally to mouse sensitivity change
	var scale_factor: float = value / DEFAULT_MOUSE_SENSITIVITY
	var new_rotation_speed: float = DEFAULT_ROTATION_SPEED * scale_factor

	var fp_cam = _player_ref.get_node_or_null("FirstPersonCamera")
	if fp_cam:
		fp_cam.mouse_sensitivity = value
		fp_cam.rotation_speed = new_rotation_speed

	var tac_cam = _player_ref.get_node_or_null("CameraRig")
	if tac_cam:
		tac_cam.mouse_sensitivity = value
		tac_cam.rotation_speed = new_rotation_speed

func _on_fov_changed(value: float) -> void:
	"""Update FOV on first-person camera"""
	fov_value_label.text = "%d" % int(value)

	if not _player_ref:
		return

	var fp_cam = _player_ref.get_node_or_null("FirstPersonCamera")
	if fp_cam:
		fp_cam.default_fov = value
		if fp_cam.camera:
			fp_cam.camera.fov = value

func _on_restart_pressed() -> void:
	"""Restart the current run"""
	if not _accepting_input:
		return

	visible = false

	# Unpause
	if PauseManager:
		PauseManager.set_pause(false)

	# Reset knowledge tracking
	if KnowledgeDB:
		KnowledgeDB.reset_knowledge()

	# Reset ChunkManager state
	if ChunkManager:
		ChunkManager.start_new_run()

	# Reload scene
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	"""Quit to desktop"""
	if not _accepting_input:
		return
	get_tree().quit()

# ============================================================================
# PANEL POSITIONING
# ============================================================================

func _update_panel_position() -> void:
	"""Position panel on left side of game viewport"""
	if not panel:
		return

	var game_ref = get_node_or_null("/root/Game")
	var viewport_rect: Rect2
	if game_ref and game_ref.has_method("get_game_viewport_rect"):
		viewport_rect = game_ref.get_game_viewport_rect()
	else:
		viewport_rect = get_viewport_rect()

	panel.reset_size()

	await get_tree().process_frame

	var panel_size: Vector2 = panel.size

	# Clamp height to viewport
	var max_height: float = viewport_rect.size.y * 0.9
	if panel_size.y > max_height:
		panel_size.y = max_height
		panel.size = panel_size

	# Position on left side with margin, vertically centered
	var pos_x: float = viewport_rect.position.x + PANEL_MARGIN
	var pos_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0

	panel.position = Vector2(pos_x, pos_y)

# ============================================================================
# PAUSE INTEGRATION
# ============================================================================

func _on_pause_toggled(is_paused: bool) -> void:
	"""Show/hide settings panel based on pause state"""
	if is_paused:
		_show_panel()
	else:
		_hide_panel()

func _show_panel() -> void:
	"""Show the settings panel"""
	# Don't show if another popup is active (level-up, game over, etc.)
	if _is_blocking_popup_visible():
		return

	# Update fullscreen label in case it changed
	fullscreen_button.text = "Fullscreen: ON" if _is_fullscreen() else "Fullscreen: OFF"

	# Sync FOV slider with current camera FOV (may have changed via zoom)
	_sync_fov_from_camera()

	_update_panel_position()
	visible = true

	# Enable focus on controls
	for control in focusable_controls:
		control.focus_mode = Control.FOCUS_ALL
		control.mouse_filter = Control.MOUSE_FILTER_STOP

	# Set up focus neighbors for stick navigation
	_setup_focus_neighbors()

	# Grab focus for controller users
	if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
		if focusable_controls.size() > 0:
			focusable_controls[0].grab_focus()

	# Input accept delay
	_accepting_input = false
	get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
		func(): _accepting_input = true if visible else false
	)

func _hide_panel() -> void:
	"""Hide the settings panel"""
	visible = false
	_accepting_input = false

	for control in focusable_controls:
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _is_blocking_popup_visible() -> bool:
	"""Check if a popup that should suppress the settings panel is visible"""
	for node in get_tree().get_nodes_in_group("hud_focusable"):
		var parent = node.get_parent()
		while parent:
			var script = parent.get_script()
			if script:
				var script_path = script.resource_path
				if "level_up_panel" in script_path or "game_over_panel" in script_path or "item_slot_selection_panel" in script_path or "codex_panel" in script_path:
					if parent.visible:
						return true
			parent = parent.get_parent()
	return false

# ============================================================================
# FOCUS NAVIGATION
# ============================================================================

func _setup_focus_neighbors() -> void:
	"""Set up focus neighbors for controller navigation"""
	for i in range(focusable_controls.size()):
		var control = focusable_controls[i]
		if i > 0:
			control.focus_neighbor_top = focusable_controls[i - 1].get_path()
		if i < focusable_controls.size() - 1:
			control.focus_neighbor_bottom = focusable_controls[i + 1].get_path()
		# Wrap around
		if i == 0:
			control.focus_neighbor_top = focusable_controls[focusable_controls.size() - 1].get_path()
		if i == focusable_controls.size() - 1:
			control.focus_neighbor_bottom = focusable_controls[0].get_path()

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad button presses"""
	if not visible or not _accepting_input:
		return

	if event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A and event.pressed:
			var focused = get_viewport().gui_get_focus_owner()
			if focused and focused is Button and focused in focusable_controls:
				focused.pressed.emit()
				get_viewport().set_input_as_handled()
			return

func _process(_delta: float) -> void:
	"""Handle RT/A button activation and sync FOV slider with camera"""
	if not visible:
		return

	# Sync FOV slider with actual camera FOV (changes from in-game zoom)
	_sync_fov_from_camera()

	if not _accepting_input:
		return

	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and focused in focusable_controls:
			focused.pressed.emit()
			return

	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and focused in focusable_controls:
			focused.pressed.emit()
			return

func _sync_fov_from_camera() -> void:
	"""Sync FOV slider with camera's actual FOV (reflects in-game zoom changes)"""
	if not _player_ref:
		return

	var fp_cam = _player_ref.get_node_or_null("FirstPersonCamera")
	if fp_cam and fp_cam.camera:
		var current_fov: float = fp_cam.camera.fov
		# Only update if different (avoid feedback loop with value_changed signal)
		if abs(fov_slider.value - current_fov) > 0.5:
			fov_slider.set_value_no_signal(current_fov)
			fov_value_label.text = "%d" % int(current_fov)

# ============================================================================
# UI SCALING
# ============================================================================

func _get_font_size(base_size: int) -> int:
	"""Get font size scaled by UIScaleManager"""
	if UIScaleManager:
		return UIScaleManager.get_scaled_font_size(base_size)
	return base_size
