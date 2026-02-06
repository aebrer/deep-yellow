class_name MapOverlayPanel
extends Control
## Full-screen map overlay with three-column layout
##
## Center: MapOverlayRenderer (north-up map with fog of war)
## Left: MarkerPanel (future — Phase 4)
## Right: EnemyListPanel (future — Phase 3)
##
## Opens with X key / X button, closes with X/B/ESC.
## Pauses the game while open.

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 18
const FONT_SIZE_ENTRY := 14
const FONT_SIZE_HINT := 12

## Delay before accepting input (prevents button press from immediately closing)
const INPUT_ACCEPT_DELAY := 0.3

# ============================================================================
# SIGNALS
# ============================================================================

signal overlay_closed
signal goto_requested(position: Vector2i)

# ============================================================================
# COLUMN NAVIGATION
# ============================================================================

enum Column { MARKERS, MAP, ENEMIES }
var active_column: Column = Column.MAP

# ============================================================================
# NODE REFERENCES
# ============================================================================

var background: ColorRect
var main_hbox: HBoxContainer
var map_renderer: MapOverlayRenderer
var left_panel_container: PanelContainer
var right_panel_container: PanelContainer
## Side panel references
var enemy_list_panel: EnemyListPanel = null
var marker_panel: MapMarkerPanel = null

# ============================================================================
# STATE
# ============================================================================

## Frame on which overlay was last closed (prevents same-frame reopen)
static var closed_on_frame: int = -1

var _accepting_input: bool = false
var _player_ref: Node = null
var _grid_ref: Node = null
var _was_paused: bool = false
var _footer_label: Label = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	z_index = 50

	_build_ui()

	# Connect to InputManager for input-device-sensitive footer
	if InputManager:
		InputManager.input_device_changed.connect(_on_input_device_changed)
		_update_footer()

func _build_ui() -> void:
	"""Build the three-column overlay layout."""
	# Semi-transparent background
	background = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.02, 0.02, 0.05, 0.92)
	background.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to game
	add_child(background)

	# Main margin container
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	add_child(margin)

	# Vertical layout: header + body + footer
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "MAP"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(header)

	# Body: three columns
	main_hbox = HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(main_hbox)

	# Left panel (Markers — placeholder for now)
	left_panel_container = _create_side_panel()
	left_panel_container.size_flags_stretch_ratio = 0.20
	main_hbox.add_child(left_panel_container)

	marker_panel = MapMarkerPanel.new()
	marker_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	marker_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel_container.add_child(marker_panel)

	# Cross-highlighting: selecting a marker highlights its position on the map
	marker_panel.entry_selected.connect(_on_marker_selected)
	# Go To: close overlay and auto-explore to marker position
	marker_panel.goto_requested.connect(_on_marker_goto_requested)

	# Center panel (Map renderer)
	var center_panel = PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_stretch_ratio = 0.55
	var center_style = StyleBoxFlat.new()
	center_style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	center_style.border_color = Color(0.25, 0.25, 0.35, 1.0)
	center_style.set_border_width_all(1)
	center_panel.add_theme_stylebox_override("panel", center_style)
	main_hbox.add_child(center_panel)

	map_renderer = MapOverlayRenderer.new()
	map_renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_panel.add_child(map_renderer)

	# Right panel (Enemies — placeholder for now)
	right_panel_container = PanelContainer.new()
	right_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel_container.size_flags_stretch_ratio = 0.25
	var right_style = StyleBoxFlat.new()
	right_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	right_style.border_color = Color(0.25, 0.25, 0.35, 1.0)
	right_style.set_border_width_all(1)
	right_style.content_margin_left = 8
	right_style.content_margin_right = 8
	right_style.content_margin_top = 8
	right_style.content_margin_bottom = 8
	right_panel_container.add_theme_stylebox_override("panel", right_style)
	main_hbox.add_child(right_panel_container)

	enemy_list_panel = EnemyListPanel.new()
	enemy_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel_container.add_child(enemy_list_panel)

	# Cross-highlighting: selecting an enemy highlights its position on the map
	enemy_list_panel.entry_selected.connect(_on_enemy_selected)

	# Footer hints (text set by _update_footer based on input device)
	_footer_label = Label.new()
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_font_size_override("font_size", FONT_SIZE_HINT)
	_footer_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	_update_footer()
	vbox.add_child(_footer_label)

func _create_side_panel() -> PanelContainer:
	"""Create a styled side panel container."""
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_color = Color(0.25, 0.25, 0.35, 1.0)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ============================================================================
# SHOW / HIDE
# ============================================================================

func show_overlay(player: Node, grid: Node) -> void:
	"""Show the map overlay and pause the game."""
	if visible:
		return

	_player_ref = player
	_grid_ref = grid

	# Set visible BEFORE pausing so settings panel's _is_blocking_popup_visible() sees us
	visible = true
	active_column = Column.MAP
	_accepting_input = false

	# Pause (store previous state)
	_was_paused = PauseManager.is_paused if PauseManager else false
	if PauseManager and not PauseManager.is_paused:
		PauseManager.toggle_pause()

	# Start accepting input after delay, then give initial focus to Place Marker button
	get_tree().create_timer(INPUT_ACCEPT_DELAY, true).timeout.connect(func():
		_accepting_input = true
		if marker_panel and marker_panel._place_button:
			marker_panel._place_button.grab_focus()
	)

	# Render the map
	map_renderer.show_map(player, grid)

	# Refresh side panels
	if enemy_list_panel:
		enemy_list_panel.refresh(player, grid)
	if marker_panel:
		marker_panel.refresh(player)

func hide_overlay() -> void:
	"""Hide the overlay and unpause."""
	if not visible:
		return

	closed_on_frame = Engine.get_process_frames()
	visible = false
	_accepting_input = false

	# Clear highlight to stop ongoing render loop
	if map_renderer:
		map_renderer._is_highlighting = false
		map_renderer.highlight_pos = Vector2i(-999999, -999999)

	# Release any GUI focus
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

	# Unpause if we paused it
	if PauseManager and PauseManager.is_paused and not _was_paused:
		PauseManager.toggle_pause()

	overlay_closed.emit()

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	"""Handle one-shot input events (buttons, keys, mouse).
	Stick navigation uses _process() with Input.is_action_just_pressed() for debouncing."""
	if not visible or not _accepting_input:
		return

	# ---- CLOSE: X key/button, B button, ESC, MMB, START/pause ----
	if event.is_action_pressed("open_map"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			hide_overlay()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_B:
			hide_overlay()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			hide_overlay()
			get_viewport().set_input_as_handled()
			return

	# START button closes (catches any other pause-mapped inputs)
	if event.is_action_pressed("pause"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

	# ---- ZOOM: D-Pad L/R, mouse wheel, arrow keys L/R ----
	if event.is_action_pressed("minimap_zoom_in"):
		map_renderer.change_zoom(1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("minimap_zoom_out"):
		map_renderer.change_zoom(-1)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_renderer.change_zoom(1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_renderer.change_zoom(-1)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_LEFT:
			map_renderer.change_zoom(-1)
			get_viewport().set_input_as_handled()
			return
		elif event.physical_keycode == KEY_RIGHT:
			map_renderer.change_zoom(1)
			get_viewport().set_input_as_handled()
			return

	# ---- LET UI NAVIGATION THROUGH TO GODOT GUI ----
	# ui_accept (A/Enter), ui_up/down/left/right must reach the GUI layer so
	# Godot's native focus navigation and button activation work on our buttons.
	if event.is_action("ui_accept") or event.is_action("ui_up") \
		or event.is_action("ui_down") or event.is_action("ui_left") \
		or event.is_action("ui_right"):
		return

	# Catch-all: consume all other keyboard/controller input while overlay is visible
	# Mouse events are NOT consumed — MOUSE_FILTER_STOP on the background handles that
	if event is InputEventKey or event is InputEventJoypadButton \
		or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()

# ============================================================================
# CROSS-HIGHLIGHTING
# ============================================================================

func _on_enemy_selected(world_pos: Vector2i) -> void:
	"""Toggle highlight for enemy position on center map."""
	if map_renderer:
		if map_renderer._is_highlighting and map_renderer.highlight_pos == world_pos:
			map_renderer.clear_highlight()
		else:
			map_renderer.highlight_position(world_pos)

func _on_marker_selected(world_pos: Vector2i) -> void:
	"""Toggle highlight for marker position on center map."""
	if map_renderer:
		if map_renderer._is_highlighting and map_renderer.highlight_pos == world_pos:
			map_renderer.clear_highlight()
		else:
			map_renderer.highlight_position(world_pos)

func _on_marker_goto_requested(world_pos: Vector2i) -> void:
	"""Close overlay and auto-explore to marker position."""
	goto_requested.emit(world_pos)
	hide_overlay()

# ============================================================================
# GAMEPAD / KEYBOARD NAVIGATION
# ============================================================================

func _switch_column(direction: int) -> void:
	"""Switch active column left (-1) or right (+1)."""
	var col_int := int(active_column) + direction
	col_int = clampi(col_int, 0, 2)
	var new_column: Column = col_int as Column

	if new_column == active_column:
		return

	# Clear focus on old column
	_clear_panel_focus()
	active_column = new_column
	_update_column_indicator()

func _navigate_entry(direction: int) -> void:
	"""Navigate entries within the active side panel."""
	match active_column:
		Column.MARKERS:
			if marker_panel:
				marker_panel.gamepad_navigate(direction)
		Column.ENEMIES:
			if enemy_list_panel:
				enemy_list_panel.gamepad_navigate(direction)
		Column.MAP:
			pass  # Map column has no navigable entries

func _activate_entry() -> void:
	"""Activate the focused entry in the active side panel."""
	match active_column:
		Column.MARKERS:
			if marker_panel:
				marker_panel.gamepad_activate()
		Column.ENEMIES:
			if enemy_list_panel:
				enemy_list_panel.gamepad_activate()
		Column.MAP:
			pass

func _clear_panel_focus() -> void:
	"""Clear gamepad focus on all side panels."""
	if marker_panel and marker_panel.has_method("clear_gamepad_focus"):
		marker_panel.clear_gamepad_focus()
	if enemy_list_panel and enemy_list_panel.has_method("clear_gamepad_focus"):
		enemy_list_panel.clear_gamepad_focus()

func _update_column_indicator() -> void:
	"""Update visual border to show active column."""
	_set_panel_active(left_panel_container, active_column == Column.MARKERS)
	_set_panel_active(right_panel_container, active_column == Column.ENEMIES)

func _set_panel_active(panel: PanelContainer, active: bool) -> void:
	"""Set panel border style to indicate active/inactive state."""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if active:
		style.border_color = Color(0.5, 0.5, 0.8, 1.0)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.25, 0.25, 0.35, 1.0)
		style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

# ============================================================================
# FOOTER
# ============================================================================

func _update_footer() -> void:
	"""Update footer hints based on current input device."""
	if not _footer_label:
		return
	if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
		_footer_label.text = "[X/B] Close    [Stick] Navigate    [A] Select    [D-Pad] Zoom"
	else:
		_footer_label.text = "[X/ESC/MMB] Close    [Arrows] Navigate    [Click/Enter] Select    [L-R/Wheel] Zoom"

func _on_input_device_changed(_device) -> void:
	"""Update footer when input device changes."""
	_update_footer()
