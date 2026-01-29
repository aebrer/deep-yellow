extends Control
## Start menu with 3D Backrooms corridor background
##
## Features:
##   - SubViewport renders a small Level 0 corridor with slowly drifting camera
##   - Spraypaint lore phrases on the corridor floor
##   - PSX dither post-processing on the 3D scene
##   - Menu: Start Game, Settings (with controls reference)
##   - Controller + keyboard input parity
##
## The 3D background is self-contained — it doesn't use ChunkManager or Grid3D.
## It manually builds a small GridMap corridor using Level 0's mesh library.

# ============================================================================
# CONSTANTS
# ============================================================================

## Corridor dimensions (in grid cells)
const CORRIDOR_LENGTH := 20
const CORRIDOR_WIDTH := 5
const CELL_SIZE := Vector3(2.0, 1.0, 2.0)  # Must match Grid3D.CELL_SIZE

## Camera drift
const CAMERA_DRIFT_SPEED := 0.8  # Units per second (slow forward drift)
const CAMERA_BOB_AMPLITUDE := 0.05  # Subtle vertical bob
const CAMERA_BOB_SPEED := 0.7

## Lore phrases painted on the corridor floor
const LORE_PHRASES := [
	"get strong",
	"keep going",
	"don't give up",
	"become something else",
	"you are not alone",
	"the walls remember",
	"power is patience",
	"descend",
]

## Lore phrase colors (muted, spraypaint-like)
const LORE_COLOR := Color(0.9, 0.9, 0.85)  # Off-white (matches in-game spraypaint)
const LORE_COLOR_RED := Color(0.8, 0.2, 0.2)  # Red emphasis

## Font sizes
const FONT_SIZE_TITLE := 48
const FONT_SIZE_SUBTITLE := 16
const FONT_SIZE_BUTTON := 24
const FONT_SIZE_HINT := 14
const FONT_SIZE_CONTROL := 12

# ============================================================================
# STATE
# ============================================================================

var _starting := false
var _showing_settings := false
var _camera: Camera3D = null
var _camera_start_z := 0.0
var _camera_end_z := 0.0
var _time := 0.0

## UI references (CenterContainers that wrap VBoxContainers)
var _menu_container: CenterContainer = null
var _settings_container: CenterContainer = null
var _start_button: Button = null
var _settings_button: Button = null
var _back_button: Button = null
var _fullscreen_button: Button = null

## Font with emoji fallback
var _emoji_font: Font = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	_emoji_font = load("res://assets/fonts/default_font.tres")

	# Build the 3D background
	_build_3d_background()

	# Build UI overlay
	_build_ui_overlay()

	# Show main menu
	_show_main_menu()

	if OS.has_feature("web"):
		print("[StartMenu] Web export detected - click will enable mouse capture")

func _process(delta: float) -> void:
	_time += delta

	# Animate camera drift
	if _camera:
		# Drift forward, loop back when reaching end
		var drift_pos := fmod(_time * CAMERA_DRIFT_SPEED, _camera_end_z - _camera_start_z)
		_camera.position.z = _camera_start_z + drift_pos
		_camera.position.y = 0.85 + sin(_time * CAMERA_BOB_SPEED) * CAMERA_BOB_AMPLITUDE

	# Handle RT/move_confirm input (synthesized by InputManager)
	if _starting:
		return

	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		if _showing_settings:
			return  # Don't start game from settings
		_starting = true
		_on_start_pressed()

func _input(event: InputEvent) -> void:
	if _starting:
		return

	# START button starts the game (from main menu) or goes back (from settings)
	if event.is_action_pressed("pause"):
		if _showing_settings:
			_show_main_menu()
		else:
			_starting = true
			_on_start_pressed()
		get_viewport().set_input_as_handled()

	# A button / Enter activates focused button
	if event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused and focused is Button:
			focused.pressed.emit()
			get_viewport().set_input_as_handled()
			return

	# B button / ESC goes back from settings
	if _showing_settings and event.is_action_pressed("ui_cancel"):
		_show_main_menu()
		get_viewport().set_input_as_handled()

# ============================================================================
# 3D BACKGROUND
# ============================================================================

func _build_3d_background() -> void:
	"""Build a SubViewport with a small Level 0 corridor"""

	# SubViewportContainer fills the screen
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	# SubViewport for 3D rendering
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)

	# World environment (Level 0 style)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.8, 0.75)  # Stained ceiling tiles at horizon
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.95, 0.7)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.75, 0.5)
	env.fog_density = 0.03
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	# Overhead light (fluorescent, straight down)
	var light := DirectionalLight3D.new()
	light.light_color = Color(0.95, 0.97, 1.0)
	light.light_energy = 0.9
	light.rotation_degrees = Vector3(-90, 0, 0)
	viewport.add_child(light)

	# GridMap corridor
	var grid_map := _build_corridor(viewport)

	# Spraypaint lore on the floor
	_build_spraypaint(viewport)

	# Camera (first-person, looking down the corridor)
	_camera = Camera3D.new()
	_camera.fov = 90.0
	# Start position: middle of corridor width, eye height above floor
	# Floor is at Y=0, ceiling at Y=1. Eye height ~0.85 for first-person feel.
	var mid_x := (CORRIDOR_WIDTH / 2.0) * CELL_SIZE.x + CELL_SIZE.x / 2.0
	_camera_start_z = 2.0 * CELL_SIZE.z
	_camera_end_z = float(CORRIDOR_LENGTH - 2) * CELL_SIZE.z
	_camera.position = Vector3(mid_x, 0.85, _camera_start_z)
	# Look straight down the corridor (positive Z)
	_camera.rotation_degrees = Vector3(0, 180, 0)
	viewport.add_child(_camera)

	# Post-process dither overlay (inside the SubViewport)
	var pp_layer := CanvasLayer.new()
	pp_layer.layer = 999
	viewport.add_child(pp_layer)

	var dither_mat = load("res://post_process/dither-banding_mat.tres")
	if dither_mat:
		var dither_rect := ColorRect.new()
		dither_rect.material = dither_mat
		dither_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		dither_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pp_layer.add_child(dither_rect)

func _build_corridor(viewport: SubViewport) -> GridMap:
	"""Build a small corridor using Level 0's mesh library"""
	var mesh_lib = load("res://assets/level_00_mesh_library.tres") as MeshLibrary
	if not mesh_lib:
		push_warning("[StartMenu] Failed to load Level 0 mesh library")
		return null

	var grid_map := GridMap.new()
	grid_map.mesh_library = mesh_lib
	grid_map.cell_size = CELL_SIZE
	viewport.add_child(grid_map)

	# Item IDs in Level 0 mesh library:
	# 0 = Floor, 1 = Wall, 2 = Ceiling
	# (These are the base tile types from SubChunk.TileType mapping)
	var FLOOR_ITEM := 0
	var WALL_ITEM := 1
	var CEILING_ITEM := 2

	# Build corridor: floor + ceiling for walkable area, walls on edges
	for z in range(CORRIDOR_LENGTH):
		for x in range(CORRIDOR_WIDTH + 2):  # +2 for walls on each side
			if x == 0 or x == CORRIDOR_WIDTH + 1:
				# Wall columns on edges
				grid_map.set_cell_item(Vector3i(x, 0, z), WALL_ITEM)
			else:
				# Floor
				grid_map.set_cell_item(Vector3i(x, 0, z), FLOOR_ITEM)
				# Ceiling
				grid_map.set_cell_item(Vector3i(x, 1, z), CEILING_ITEM)

	# End walls
	for x in range(CORRIDOR_WIDTH + 2):
		grid_map.set_cell_item(Vector3i(x, 0, -1), WALL_ITEM)
		grid_map.set_cell_item(Vector3i(x, 0, CORRIDOR_LENGTH), WALL_ITEM)

	return grid_map

func _build_spraypaint(viewport: SubViewport) -> void:
	"""Place lore phrases as Label3D on the corridor floor"""
	var spray_font = load("res://assets/fonts/spraypaint_font.tres")
	if not spray_font:
		push_warning("[StartMenu] Failed to load spraypaint font")
		return

	var mid_x := (CORRIDOR_WIDTH / 2.0) * CELL_SIZE.x + CELL_SIZE.x / 2.0

	# Space phrases along the corridor
	var spacing := float(CORRIDOR_LENGTH - 2) / float(LORE_PHRASES.size())

	for i in range(LORE_PHRASES.size()):
		var label := Label3D.new()
		label.text = LORE_PHRASES[i]
		label.font = spray_font
		label.font_size = 48
		# Alternate between off-white and red
		label.modulate = LORE_COLOR_RED if i % 3 == 0 else LORE_COLOR
		label.outline_size = 8
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
		label.no_depth_test = true
		label.render_priority = 1
		label.double_sided = true
		label.alpha_cut = Label3D.ALPHA_CUT_DISABLED

		# Position on floor, facing up
		var z_pos := (1.0 + i * spacing) * CELL_SIZE.z + CELL_SIZE.z / 2.0
		label.position = Vector3(mid_x, 0.51, z_pos)
		label.rotation_degrees = Vector3(-90.0, 180.0, 0.0)

		viewport.add_child(label)

# ============================================================================
# UI OVERLAY
# ============================================================================

func _build_ui_overlay() -> void:
	"""Build the menu UI on top of the 3D background"""

	# Semi-transparent dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.4)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Main menu (CenterContainer wrapping VBoxContainer)
	_menu_container = _build_main_menu()
	add_child(_menu_container)

	# Settings (CenterContainer wrapping VBoxContainer, initially hidden)
	_settings_container = _build_settings_menu()
	_settings_container.visible = false
	add_child(_settings_container)

func _build_main_menu() -> CenterContainer:
	"""Build the main menu (title + buttons) inside a CenterContainer"""
	var center := CenterContainer.new()
	center.name = "MainMenu"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "BACKROOMS\nPOWER CRAWL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_TITLE))
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	if _emoji_font:
		title.add_theme_font_override("font", _emoji_font)
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "an infinite dungeon crawler"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_SUBTITLE))
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	if _emoji_font:
		subtitle.add_theme_font_override("font", _emoji_font)
	vbox.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# Start Game button
	_start_button = _create_menu_button("START GAME")
	_start_button.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_button)

	# Settings button
	_settings_button = _create_menu_button("SETTINGS")
	_settings_button.pressed.connect(_on_settings_pressed)
	vbox.add_child(_settings_button)

	return center

func _build_settings_menu() -> CenterContainer:
	"""Build the settings panel (Fullscreen + Controls + Back) inside a CenterContainer"""
	var center := CenterContainer.new()
	center.name = "SettingsMenu"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(400, 0)
	center.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "SETTINGS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(20))
	header.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	if _emoji_font:
		header.add_theme_font_override("font", _emoji_font)
	vbox.add_child(header)

	var sep1 := HSeparator.new()
	sep1.add_theme_constant_override("separation", 8)
	vbox.add_child(sep1)

	# Fullscreen toggle
	_fullscreen_button = _create_menu_button(
		"Fullscreen: ON" if _is_fullscreen() else "Fullscreen: OFF",
		FONT_SIZE_HINT
	)
	_fullscreen_button.pressed.connect(_on_fullscreen_toggled)
	vbox.add_child(_fullscreen_button)

	# Controls section
	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 8)
	vbox.add_child(sep2)

	var controls_header := Label.new()
	controls_header.text = "CONTROLS"
	controls_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HINT))
	controls_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if _emoji_font:
		controls_header.add_theme_font_override("font", _emoji_font)
	vbox.add_child(controls_header)

	# Controls rows from SettingsPanel (single source of truth)
	var is_gamepad := InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD
	for mapping in SettingsPanel.CONTROL_MAPPINGS:
		var action_name: String = mapping[0]
		var input_label: String = mapping[1] if is_gamepad else mapping[2]
		var row := _create_control_row(action_name, input_label)
		vbox.add_child(row)

	var sep3 := HSeparator.new()
	sep3.add_theme_constant_override("separation", 8)
	vbox.add_child(sep3)

	# Back button
	_back_button = _create_menu_button("BACK", FONT_SIZE_HINT)
	_back_button.pressed.connect(_show_main_menu)
	vbox.add_child(_back_button)

	return center

func _create_control_row(action_name: String, input_label: String) -> HBoxContainer:
	"""Create a single control mapping row"""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var input_lbl := Label.new()
	input_lbl.text = input_label
	input_lbl.custom_minimum_size = Vector2(120, 0)
	input_lbl.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_CONTROL))
	input_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7))
	if _emoji_font:
		input_lbl.add_theme_font_override("font", _emoji_font)
	row.add_child(input_lbl)

	var action_lbl := Label.new()
	action_lbl.text = action_name
	action_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_lbl.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_CONTROL))
	action_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	if _emoji_font:
		action_lbl.add_theme_font_override("font", _emoji_font)
	row.add_child(action_lbl)

	return row

# ============================================================================
# MENU NAVIGATION
# ============================================================================

func _show_main_menu() -> void:
	"""Show main menu, hide settings"""
	_showing_settings = false
	_menu_container.visible = true
	_settings_container.visible = false

	# Set focus neighbors (must be in tree)
	if _start_button and _settings_button:
		_start_button.focus_neighbor_bottom = _settings_button.get_path()
		_start_button.focus_neighbor_top = _settings_button.get_path()
		_settings_button.focus_neighbor_top = _start_button.get_path()
		_settings_button.focus_neighbor_bottom = _start_button.get_path()
		_start_button.grab_focus()

func _show_settings() -> void:
	"""Show settings, hide main menu"""
	_showing_settings = true
	_menu_container.visible = false
	_settings_container.visible = true

	if _fullscreen_button:
		_fullscreen_button.text = "Fullscreen: ON" if _is_fullscreen() else "Fullscreen: OFF"

	# Set focus neighbors (must be in tree)
	if _fullscreen_button and _back_button:
		_fullscreen_button.focus_neighbor_bottom = _back_button.get_path()
		_fullscreen_button.focus_neighbor_top = _back_button.get_path()
		_back_button.focus_neighbor_top = _fullscreen_button.get_path()
		_back_button.focus_neighbor_bottom = _fullscreen_button.get_path()
		_fullscreen_button.grab_focus()

# ============================================================================
# BUTTON ACTIONS
# ============================================================================

func _on_start_pressed() -> void:
	if _starting and not _showing_settings:
		# Already triggered via _input
		pass
	_starting = true

	print("[StartMenu] Starting game...")

	if _start_button:
		_start_button.disabled = true
		_start_button.text = "Loading..."

	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_settings_pressed() -> void:
	_show_settings()

func _on_fullscreen_toggled() -> void:
	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_fullscreen_button.text = "Fullscreen: ON" if _is_fullscreen() else "Fullscreen: OFF"

func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

# ============================================================================
# UI HELPERS
# ============================================================================

func _create_menu_button(text: String, font_size: int = FONT_SIZE_BUTTON) -> Button:
	"""Create a styled menu button"""
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 0)
	button.add_theme_font_size_override("font_size", _get_font_size(font_size))
	if _emoji_font:
		button.add_theme_font_override("font", _emoji_font)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Dark semi-transparent style
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.5, 0.5, 0.45, 0.8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(1.0, 1.0, 0.5, 0.2)
	focus.border_color = Color(1.0, 1.0, 0.5, 0.8)
	focus.set_border_width_all(2)
	focus.content_margin_left = 12
	focus.content_margin_right = 12
	focus.content_margin_top = 8
	focus.content_margin_bottom = 8

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	hover.set_border_width_all(1)
	hover.border_color = Color(0.7, 0.7, 0.65, 0.8)
	hover.content_margin_left = 12
	hover.content_margin_right = 12
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("hover", hover)

	button.focus_mode = Control.FOCUS_ALL
	return button

func _get_font_size(base_size: int) -> int:
	if UIScaleManager:
		return UIScaleManager.get_scaled_font_size(base_size)
	return base_size
