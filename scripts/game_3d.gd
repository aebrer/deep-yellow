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

	# Initialize grid
	grid.initialize(Grid3D.GRID_SIZE)

	# Link player to grid and indicator
	player.grid = grid
	player.move_indicator = move_indicator

	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "3D viewport ready - controls active")
