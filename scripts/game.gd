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
@onready var log_text: RichTextLabel = $MarginContainer/HBoxContainer/LeftSide/LogPanel/MarginContainer/VBoxContainer/LogText
@onready var stats_panel: VBoxContainer = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CharacterSheet/StatsPanel
@onready var inventory_items: Label = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CoreInventory/Items
@onready var examination_panel: ExaminationPanel = $TextUIOverlay/ExaminationPanel
@onready var action_preview_ui: ActionPreviewUI = $TextUIOverlay/ActionPreviewUI

## Access to player in 3D scene
var player: Node3D

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

	# Wire up stats panel to player
	if stats_panel:
		stats_panel.set_player(player)
		Log.system("StatsPanel connected to player")

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Game ready - 3D viewport: 640x480, UI: native resolution")

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
