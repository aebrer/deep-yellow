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
@onready var char_stats: Label = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CharacterSheet/Stats
@onready var inventory_items: Label = $MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/CoreInventory/Items

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

	# Connect to player signals if needed
	# player.turn_changed.connect(_on_turn_changed)

	_update_ui()

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Game ready - 3D viewport: 640x480, UI: native resolution")

func _process(_delta: float) -> void:
	# Update UI every frame
	_update_ui()

func _update_ui() -> void:
	"""Update character stats display"""
	if not player:
		return

	# Update character sheet
	char_stats.text = "[PLACEHOLDER]
hp  100/100
sn   80/100
st   50/50

turn %d
pos  (%d, %d)" % [
		player.turn_count,
		player.grid_position.x,
		player.grid_position.y
	]

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
	# Choose color based on level
	var color := "gray"
	match level:
		Log.Level.ERROR:
			color = "#ff6b6b"  # Red
		Log.Level.WARN:
			color = "#ffd93d"  # Yellow
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
