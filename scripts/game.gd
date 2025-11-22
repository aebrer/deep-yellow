extends Control
## Main game scene with HUD layout
##
## Structure:
## - 3D viewport (top-left) renders at 640x480 with PSX shaders
## - Character sheet (right) shows stats and build
## - Game log (bottom) shows events and examine descriptions
## - All UI renders at native resolution (crisp text)

## References to UI elements
@onready var viewport_container: SubViewportContainer = $MarginContainer/HBoxContainer/LeftSide/ViewportPanel/MarginContainer/SubViewportContainer
@onready var game_3d: Node3D = $MarginContainer/HBoxContainer/LeftSide/ViewportPanel/MarginContainer/SubViewportContainer/SubViewport/Game3D
@onready var log_text: RichTextLabel = $MarginContainer/HBoxContainer/LeftSide/LogPanel/MarginContainer/HBoxContainer/VBoxContainer/LogText
@onready var stats_panel: VBoxContainer = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CharacterSheet/StatsPanel
@onready var inventory_items: Label = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CoreInventory/Items
@onready var examination_panel: ExaminationPanel = $TextUIOverlay/ExaminationPanel
@onready var action_preview_ui: ActionPreviewUI = $TextUIOverlay/ActionPreviewUI
@onready var minimap: Control = $MarginContainer/HBoxContainer/LeftSide/LogPanel/MarginContainer/HBoxContainer/Minimap/MarginContainer/AspectRatioContainer/MinimapControl
@onready var fps_counter: Label = $FPSCounter

## Access to player in 3D scene
var player: Node3D

## Layout management for responsive design
enum LayoutMode { LANDSCAPE, PORTRAIT }
var current_layout: LayoutMode = LayoutMode.LANDSCAPE
var last_viewport_size: Vector2 = Vector2.ZERO

## References to layout containers
@onready var margin_container: MarginContainer = $MarginContainer
@onready var main_container: HBoxContainer = $MarginContainer/HBoxContainer
@onready var left_side: VBoxContainer = $MarginContainer/HBoxContainer/LeftSide
@onready var right_side: PanelContainer = $MarginContainer/HBoxContainer/RightSide
@onready var viewport_panel: PanelContainer = $MarginContainer/HBoxContainer/LeftSide/ViewportPanel
@onready var log_panel: PanelContainer = $MarginContainer/HBoxContainer/LeftSide/LogPanel
@onready var minimap_node: PanelContainer = $MarginContainer/HBoxContainer/LeftSide/LogPanel/MarginContainer/HBoxContainer/Minimap
@onready var log_container: VBoxContainer = $MarginContainer/HBoxContainer/LeftSide/LogPanel/MarginContainer/HBoxContainer/VBoxContainer
@onready var character_sheet: VBoxContainer = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CharacterSheet
@onready var core_inventory: VBoxContainer = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CoreInventory

## Portrait layout container (created dynamically)
var portrait_container: VBoxContainer = null

## Touch controls (for portrait mode)
var touch_controls: Control = null
const TOUCH_CONTROLS_SCENE := preload("res://scenes/ui/touch_controls.tscn")

func _ready() -> void:
	# Connect to logging system for UI display
	Log.message_logged.connect(_on_log_message)

	# Clear placeholder text
	log_text.clear()

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Initializing game with HUD layout")

	# Get player reference from 3D scene
	player = game_3d.get_node_or_null("Player3D")

	if not player:
		Log.msg(Log.Category.SYSTEM, Log.Level.ERROR, "Failed to find Player3D in game_3d scene")
		return

	# Connect to player signals
	player.action_preview_changed.connect(_on_player_action_preview_changed)
	player.turn_completed.connect(_on_player_turn_completed)

	# Wire up stats panel to player
	if stats_panel:
		stats_panel.set_player(player)
		Log.system("StatsPanel connected to player")

	# Wire up minimap to grid and player
	if minimap:
		var grid = game_3d.get_node_or_null("Grid3D")
		if grid:
			minimap.set_grid(grid)
			minimap.set_player(player)
			Log.system("Minimap connected to grid and player")

			# Connect to ChunkManager autoload for chunk updates
			if ChunkManager:
				ChunkManager.chunk_updates_completed.connect(_on_chunk_updates_completed)
				Log.system("Minimap connected to ChunkManager")
		else:
			Log.error(Log.Category.SYSTEM, "Failed to find Grid3D for minimap")

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Game ready - 3D viewport: 640x480, UI: native resolution")

	# Connect to window size changes (web-compatible!)
	get_window().size_changed.connect(_on_window_size_changed)

	# Initial aspect ratio check
	_check_aspect_ratio()

func _process(_delta: float) -> void:
	"""Update FPS counter"""
	if fps_counter:
		fps_counter.text = "FPS: %d" % Engine.get_frames_per_second()

func _on_window_size_changed() -> void:
	"""Handle window/canvas resize events (triggered by browser resize)"""
	var window_size := get_window().size
	Log.system("Window size changed: %v" % [window_size])
	_check_aspect_ratio()

func add_log_message(message: String, color: String = "white") -> void:
	"""Add a message to the game log with optional color"""
	log_text.append_text("[color=%s]> %s[/color]\n" % [color, message])

func set_examine_text(description: String) -> void:
	"""Display examine description in log panel (for look mode)"""
	log_text.clear()
	log_text.append_text("[color=cyan]examining:[/color]\n")
	log_text.append_text("[color=white]%s[/color]" % description)

func _on_log_message(category: Log.Category, level: Log.Level, message: String) -> void:
	"""Handle log messages and display them in the UI"""
	# Filter: Only show PLAYER level and above (player-facing messages, warnings, errors)
	# This keeps the in-game log clean for players
	if level < Log.Level.PLAYER:
		return  # Skip TRACE, DEBUG, INFO

	# Choose color based on level
	var color := "gray"
	match level:
		Log.Level.ERROR:
			color = "#ff6b6b"  # Red
		Log.Level.WARN:
			color = "#ffd93d"  # Yellow
		Log.Level.PLAYER:
			color = "#6bffb8"  # Bright cyan/green (player-facing messages)
		Log.Level.INFO:
			color = "white"
		Log.Level.DEBUG:
			color = "#a0a0a0"  # Light gray
		Log.Level.TRACE:
			color = "#707070"  # Dark gray

	# Format message (lowercase, simple prefix)
	var category_name := ""
	match category:
		Log.Category.INPUT:
			category_name = "input"
		Log.Category.STATE:
			category_name = "state"
		Log.Category.MOVEMENT:
			category_name = "move"
		Log.Category.ACTION:
			category_name = "action"
		Log.Category.TURN:
			category_name = "turn"
		Log.Category.GRID:
			category_name = "grid"
		Log.Category.CAMERA:
			category_name = "camera"
		Log.Category.ENTITY:
			category_name = "entity"
		Log.Category.ABILITY:
			category_name = "ability"
		Log.Category.PHYSICS:
			category_name = "physics"
		Log.Category.SYSTEM:
			category_name = "sys"

	# Append to log with minimal formatting
	log_text.append_text("[color=%s][%s] %s[/color]\n" % [color, category_name, message.to_lower()])

func _on_player_action_preview_changed(actions: Array[Action]) -> void:
	"""Forward action preview to UI (text overlay - always clean)"""
	if action_preview_ui:
		action_preview_ui.show_preview(actions, player)

func _on_player_turn_completed() -> void:
	"""Update minimap when player completes a turn"""
	if minimap and player:
		minimap.on_player_moved(player.grid_position)

func _on_chunk_updates_completed() -> void:
	"""Mark minimap dirty when chunks load/unload"""
	if minimap:
		# Chunk updates completed - mark minimap for redraw
		# (minimap checks grid.is_walkable() for each tile, so chunk changes affect rendering)
		minimap.content_dirty = true

# ============================================================================
# LAYOUT MANAGEMENT (Portrait/Landscape)
# ============================================================================

func _check_aspect_ratio() -> void:
	"""Detect aspect ratio and switch layout if needed"""
	# Use get_window().size for accurate canvas size on web exports
	var window_size := get_window().size
	var aspect_ratio := float(window_size.x) / float(window_size.y)

	# Portrait mode: height > width (aspect ratio < 1.0)
	var is_portrait := aspect_ratio < 1.0

	# Debug logging
	Log.system("Aspect ratio check - Window size: %v, Ratio: %.2f, Portrait: %s, Current: %s" % [
		window_size,
		aspect_ratio,
		"YES" if is_portrait else "NO",
		"PORTRAIT" if current_layout == LayoutMode.PORTRAIT else "LANDSCAPE"
	])

	# Switch layout if mode changed
	if is_portrait and current_layout == LayoutMode.LANDSCAPE:
		Log.system("Triggering switch to portrait")
		_switch_to_portrait()
	elif not is_portrait and current_layout == LayoutMode.PORTRAIT:
		Log.system("Triggering switch to landscape")
		_switch_to_landscape()

func _switch_to_portrait() -> void:
	"""Switch UI layout to portrait mode (vertical stack)"""
	Log.system("Switching to portrait layout")
	current_layout = LayoutMode.PORTRAIT

	# Create portrait container if it doesn't exist
	if not portrait_container:
		portrait_container = VBoxContainer.new()
		portrait_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait_container.add_theme_constant_override("separation", 5)

	# Hide landscape container
	main_container.visible = false

	# Add portrait container to margin container
	if portrait_container.get_parent() != margin_container:
		margin_container.add_child(portrait_container)

	# Reparent UI elements in portrait order
	# 1. Game viewport (largest, 60% height)
	if viewport_panel.get_parent() != portrait_container:
		viewport_panel.get_parent().remove_child(viewport_panel)
		portrait_container.add_child(viewport_panel)
		viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		viewport_panel.size_flags_stretch_ratio = 3.0  # Takes 60% of space

	# 2. Minimap (compact)
	if minimap_node.get_parent() != portrait_container:
		minimap_node.get_parent().remove_child(minimap_node)
		portrait_container.add_child(minimap_node)
		minimap_node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 3. Log (compact)
	if log_container.get_parent() != portrait_container:
		# Create a wrapper panel for log
		var log_wrapper = PanelContainer.new()
		var log_margin = MarginContainer.new()
		log_margin.add_theme_constant_override("margin_left", 10)
		log_margin.add_theme_constant_override("margin_top", 10)
		log_margin.add_theme_constant_override("margin_right", 10)
		log_margin.add_theme_constant_override("margin_bottom", 10)
		log_wrapper.add_child(log_margin)

		log_container.get_parent().remove_child(log_container)
		log_margin.add_child(log_container)
		portrait_container.add_child(log_wrapper)
		log_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_wrapper.size_flags_stretch_ratio = 1.0

	# 4. Character sheet (compact)
	if character_sheet.get_parent() != portrait_container:
		character_sheet.get_parent().remove_child(character_sheet)
		portrait_container.add_child(character_sheet)
		character_sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 5. Core inventory (compact)
	if core_inventory.get_parent() != portrait_container:
		core_inventory.get_parent().remove_child(core_inventory)
		portrait_container.add_child(core_inventory)
		core_inventory.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 6. Touch controls at bottom
	if not touch_controls:
		touch_controls = TOUCH_CONTROLS_SCENE.instantiate()

	if touch_controls.get_parent() != portrait_container:
		portrait_container.add_child(touch_controls)
		touch_controls.size_flags_vertical = Control.SIZE_SHRINK_END
		touch_controls.custom_minimum_size = Vector2(0, 150)  # Fixed height for touch controls

	touch_controls.visible = true
	Log.system("Portrait layout active with touch controls")

func _switch_to_landscape() -> void:
	"""Switch UI layout back to landscape mode (horizontal split)"""
	Log.system("Switching to landscape layout")
	current_layout = LayoutMode.LANDSCAPE

	# Hide touch controls
	if touch_controls:
		touch_controls.visible = false

	# Hide portrait container
	if portrait_container:
		portrait_container.visible = false

	# Show landscape container
	main_container.visible = true

	# Restore landscape layout structure
	# Restore viewport to left side
	if viewport_panel.get_parent() != left_side:
		viewport_panel.get_parent().remove_child(viewport_panel)
		left_side.add_child(viewport_panel)
		left_side.move_child(viewport_panel, 0)  # First child
		viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		viewport_panel.size_flags_stretch_ratio = 1.0

	# Restore minimap and log to log panel
	var log_panel_hbox = log_panel.get_node("MarginContainer/HBoxContainer")
	if minimap_node.get_parent() != log_panel_hbox:
		minimap_node.get_parent().remove_child(minimap_node)
		log_panel_hbox.add_child(minimap_node)
		log_panel_hbox.move_child(minimap_node, 0)  # First child
		minimap_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		minimap_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		minimap_node.size_flags_stretch_ratio = 0.3

	if log_container.get_parent() != log_panel_hbox:
		log_container.get_parent().remove_child(log_container)
		log_panel_hbox.add_child(log_container)
		log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Ensure log panel is in left side
	if log_panel.get_parent() != left_side:
		log_panel.get_parent().remove_child(log_panel)
		left_side.add_child(log_panel)
		log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_panel.size_flags_stretch_ratio = 0.25

	# Restore character sheet and inventory to right side
	var right_side_vbox = right_side.get_node("MarginContainer/VBoxContainer")
	if character_sheet.get_parent() != right_side_vbox:
		character_sheet.get_parent().remove_child(character_sheet)
		right_side_vbox.add_child(character_sheet)
		right_side_vbox.move_child(character_sheet, 0)  # First child
		character_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if core_inventory.get_parent() != right_side_vbox:
		core_inventory.get_parent().remove_child(core_inventory)
		right_side_vbox.add_child(core_inventory)
		# Add spacer before inventory
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 20)
		right_side_vbox.add_child(spacer)
		right_side_vbox.move_child(spacer, 1)
		right_side_vbox.move_child(core_inventory, 2)
		core_inventory.size_flags_vertical = Control.SIZE_EXPAND_FILL

	Log.system("Landscape layout restored")
