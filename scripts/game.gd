extends Node2D
## Main game scene - Turn-based roguelike
##
## Now using:
## - InputManager (autoload) for unified input
## - Grid class for map management
## - Player class with State Machine for turn logic
## - Action system for command pattern

const GRID_SIZE := Vector2i(128, 128)

## References to game components
@onready var grid: Grid = $Grid
@onready var player: Player = $Player
@onready var ui_layer: CanvasLayer = $UI
@onready var turn_label: Label = $UI/TurnCounter

func _ready() -> void:
	print("[Game] Initializing turn-based roguelike...")

	# Initialize grid
	grid.initialize(GRID_SIZE)

	# Setup player
	player.set_grid(grid)
	player.grid_position = Vector2i(64, 64)  # Start in center
	player.update_visual_position()

	_update_ui()

	print("[Game] Ready! InputManager active, State Machine initialized")
	print("[Game] Controls: Left stick/WASD to aim, Right trigger/Space to move")

func _process(_delta: float) -> void:
	# Update UI every frame
	_update_ui()

func _update_ui() -> void:
	"""Update UI elements"""
	turn_label.text = "Turn: %d | Pos: (%d, %d) | State: %s" % [
		player.turn_count,
		player.grid_position.x,
		player.grid_position.y,
		player.state_machine.get_current_state_name()
	]
