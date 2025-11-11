extends Node3D
## 3D game viewport - embedded in main HUD scene
##
## This scene contains only the 3D world (grid, player, camera).
## All UI is handled by the parent game.gd scene.

@onready var grid: Grid3D = $Grid3D
@onready var player: Player3D = $Player3D
@onready var move_indicator: Node3D = $MoveIndicator

func _ready() -> void:
	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Initializing 3D viewport (640x480 with PSX shaders)")

	# Load and configure Level 0
	var level_0 := LevelManager.load_level(0)
	if level_0:
		grid.configure_from_level(level_0)
		LevelManager.transition_to_level(0)
	else:
		# Fallback to default grid if level config not found
		push_warning("[Game3D] Level 0 config not found, using default grid")
		grid.initialize(Grid3D.GRID_SIZE)

	# Link player to grid and indicator
	player.grid = grid
	player.move_indicator = move_indicator

	# Link grid back to player (for line-of-sight proximity fade)
	grid.set_player(player)

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "3D viewport ready - controls active")
