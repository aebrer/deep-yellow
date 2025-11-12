extends Node3D
## 3D game viewport - embedded in main HUD scene
##
## This scene contains only the 3D world (grid, player, camera).
## All UI is handled by the parent game.gd scene.
##
## ============================================================================
## PER-LEVEL DESIGN SYSTEM
## ============================================================================
## Environment settings (lighting, background, fog) are NOT hardcoded in this scene!
## Instead, they are defined per-level in LevelConfig resources and applied at runtime.
##
## Scene file (game_3d.tscn) contains NEUTRAL DEFAULTS that get overridden when
## a level loads. This allows each Backrooms level to have unique atmosphere:
##   - Level 0: Greyish-beige ceiling, fluorescent lighting
##   - Level 1: Different colors/lighting (future)
##   - Level 2: Different colors/lighting (future)
##
## Flow:
##   1. LevelManager.load_level(0) → Loads level_00_config.tres
##   2. grid.configure_from_level(level_0) → Applies settings to scene nodes
##   3. Runtime: WorldEnvironment and OverheadLight updated with level-specific values
##
## To customize a level's appearance:
##   - Edit scripts/resources/level_XX_config.gd
##   - Set background_color, directional_light_color, directional_light_energy, etc.
##   - Grid3D._apply_level_visuals() handles the runtime application
## ============================================================================

@onready var grid: Grid3D = $Grid3D
@onready var player: Player3D = $Player3D
@onready var move_indicator: Node3D = $MoveIndicator

func _ready() -> void:
	Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Initializing 3D viewport (640x480 with PSX shaders)")

	# ========================================================================
	# LEVEL LOADING - Environment settings applied here
	# ========================================================================
	# Load Level 0 config (defines appearance, generation params, entity spawns, etc.)
	var level_0 := LevelManager.load_level(0)
	if level_0:
		# Configure grid with level-specific settings
		# This applies: background color, lighting, materials, fog, etc.
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
