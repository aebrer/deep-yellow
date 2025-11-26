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
@onready var core_inventory_panel: VBoxContainer = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CoreInventory
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
var _switching_layout: bool = false  # Guard flag to prevent feedback loop

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

	# Wire up core inventory to player
	if core_inventory_panel:
		core_inventory_panel.set_player(player)
		core_inventory_panel.reorder_state_changed.connect(_on_inventory_reorder_state_changed)
		Log.system("CoreInventory connected to player")

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

	# Connect to PauseManager to handle action preview on pause/unpause
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)
		Log.system("Game connected to PauseManager")

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
	if not action_preview_ui:
		return

	# When paused, ignore player state previews - pause hints are shown instead
	if PauseManager and PauseManager.is_paused:
		return

	action_preview_ui.show_preview(actions, player)

func _on_player_turn_completed() -> void:
	"""Update minimap when player completes a turn"""
	if minimap and player:
		minimap.on_player_moved(player.grid_position)

func _on_inventory_reorder_state_changed(is_reordering: bool) -> void:
	"""Update action preview when entering/exiting reorder mode or when pausing"""
	if not action_preview_ui or not PauseManager:
		return

	# Only show hints when paused
	if not PauseManager.is_paused:
		return

	var hints: Array[Action] = []

	if is_reordering:
		# Reorder mode hints
		hints.append(ControlHintAction.new("✋", "Hover over slot", "to select target"))
		hints.append(ControlHintAction.new("🖱️", "LMB / A", "drop item"))
		hints.append(ControlHintAction.new("🖱️", "RMB / X / B", "cancel"))
	else:
		# Normal pause mode hints
		hints.append(ControlHintAction.new("🖱️", "Hover / Stick", "navigate inventory"))
		hints.append(ControlHintAction.new("🖱️", "LMB / A", "toggle item ON/OFF"))
		hints.append(ControlHintAction.new("🖱️", "RMB / X", "reorder item"))
		hints.append(ControlHintAction.new("⏸️", "START / ESC / MMB", "unpause"))

	action_preview_ui.show_preview(hints, player)

func _on_pause_toggled(is_paused: bool) -> void:
	"""Handle pause state changes - show/hide action preview"""
	if not action_preview_ui:
		return

	if is_paused:
		# When pausing, show the pause mode hints
		_on_inventory_reorder_state_changed(false)
	else:
		# When unpausing, hide the action preview
		# The player state will re-emit action_preview_changed when appropriate
		action_preview_ui.hide_preview()

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
	# Prevent feedback loop: ignore resize events triggered during layout switch
	if _switching_layout:
		Log.system("Ignoring aspect ratio check during layout switch (preventing feedback loop)")
		return

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
	_switching_layout = true  # Set guard flag
	current_layout = LayoutMode.PORTRAIT

	# Hide landscape container
	main_container.visible = false

	# Create portrait container if it doesn't exist
	if not portrait_container:
		portrait_container = VBoxContainer.new()
		portrait_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		portrait_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portrait_container.add_theme_constant_override("separation", 3)
		margin_container.add_child(portrait_container)

	# Clear portrait container and rebuild layout
	for child in portrait_container.get_children():
		portrait_container.remove_child(child)

	# Show portrait container
	portrait_container.visible = true

	# 1. Game viewport (takes most vertical space)
	viewport_panel.get_parent().remove_child(viewport_panel)
	portrait_container.add_child(viewport_panel)
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_stretch_ratio = 3.0

	# Ensure viewport container receives input (critical for mouse control)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	Log.system("Portrait mode: Viewport container mouse_filter set to STOP")

	# 2. Stats panel (compact - subsections horizontal)
	# Wrap in PanelContainer to preserve black background
	var stats_panel_container = PanelContainer.new()
	stats_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait_container.add_child(stats_panel_container)

	character_sheet.get_parent().remove_child(character_sheet)
	stats_panel_container.add_child(character_sheet)
	character_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	character_sheet.visible = true

	# Switch stats panel to horizontal layout
	if stats_panel and stats_panel.has_method("set_layout_mode"):
		stats_panel.set_layout_mode(1)  # 1 = HORIZONTAL (can't reference enum from here)

	# Switch core inventory to horizontal layout
	if core_inventory and core_inventory.has_method("set_layout_mode"):
		core_inventory.set_layout_mode(1)  # 1 = HORIZONTAL

	# Reposition action preview to top-right
	if action_preview_ui and action_preview_ui.has_method("set_portrait_mode"):
		action_preview_ui.set_portrait_mode(true)

	# Reposition examination panel to bottom overlay
	if examination_panel and examination_panel.has_method("set_portrait_mode"):
		examination_panel.set_portrait_mode(true)

	# 3. Build panel (compact - subsections horizontal)
	# Wrap in PanelContainer to preserve black background
	var inventory_panel_container = PanelContainer.new()
	inventory_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_panel_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait_container.add_child(inventory_panel_container)

	core_inventory.get_parent().remove_child(core_inventory)
	inventory_panel_container.add_child(core_inventory)
	core_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_inventory.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	core_inventory.visible = true

	# 4. Minimap + Log row (compact info strip)
	# Wrap in PanelContainer to preserve black background
	var info_panel_container = PanelContainer.new()
	info_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_panel_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait_container.add_child(info_panel_container)

	var info_row = HBoxContainer.new()
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info_row.add_theme_constant_override("separation", 5)
	info_panel_container.add_child(info_row)

	minimap_node.get_parent().remove_child(minimap_node)
	info_row.add_child(minimap_node)
	minimap_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	minimap_node.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Expand vertically

	log_container.get_parent().remove_child(log_container)
	info_row.add_child(log_container)
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_container.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Expand vertically

	Log.system("Portrait layout active")

	# Clear guard flag AFTER all deferred layout events complete
	# This catches spurious resize events triggered by node reparenting
	call_deferred("_clear_layout_switch_flag")

func _switch_to_landscape() -> void:
	"""Switch UI layout back to landscape mode (horizontal split)"""
	Log.system("Switching to landscape layout")
	_switching_layout = true  # Set guard flag
	current_layout = LayoutMode.LANDSCAPE

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

	# Restore character sheet and inventory to right side (and make visible again)
	var right_side_vbox = right_side.get_node("MarginContainer/VBoxContainer")

	if character_sheet.get_parent():
		character_sheet.get_parent().remove_child(character_sheet)
	right_side_vbox.add_child(character_sheet)
	right_side_vbox.move_child(character_sheet, 0)  # First child
	character_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_sheet.visible = true

	# Switch stats panel back to vertical layout
	if stats_panel and stats_panel.has_method("set_layout_mode"):
		stats_panel.set_layout_mode(0)  # 0 = VERTICAL

	# Switch core inventory back to vertical layout
	if core_inventory and core_inventory.has_method("set_layout_mode"):
		core_inventory.set_layout_mode(0)  # 0 = VERTICAL

	# Restore action preview to bottom-right
	if action_preview_ui and action_preview_ui.has_method("set_portrait_mode"):
		action_preview_ui.set_portrait_mode(false)

	# Restore examination panel to left side
	if examination_panel and examination_panel.has_method("set_portrait_mode"):
		examination_panel.set_portrait_mode(false)

	if core_inventory.get_parent():
		core_inventory.get_parent().remove_child(core_inventory)
	right_side_vbox.add_child(core_inventory)
	core_inventory.size_flags_vertical = Control.SIZE_EXPAND_FILL
	core_inventory.visible = true

	Log.system("Landscape layout restored")

	# Clear guard flag AFTER all deferred layout events complete
	call_deferred("_clear_layout_switch_flag")

func _clear_layout_switch_flag() -> void:
	"""Clear layout switch guard flag (called deferred after layout complete)"""
	_switching_layout = false
	Log.system("Layout switch guard flag cleared")
