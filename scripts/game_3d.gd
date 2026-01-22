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
@onready var exp_bar: EXPBar = $ViewportUILayer/EXPBar
@onready var status_bars: StatusBars = $ViewportUILayer/StatusBars

func _ready() -> void:

	# ========================================================================
	# LEVEL LOADING - Game always starts on Level 0
	# ========================================================================
	# Transition to Level 0 (loads config and sets as current level)
	LevelManager.transition_to_level(0)

	# Configure grid with Level 0 settings (lighting, materials, fog, etc.)
	var current_level := LevelManager.get_current_level()
	grid.configure_from_level(current_level)

	# Link player to grid and indicator
	player.grid = grid
	player.move_indicator = move_indicator

	# Link grid back to player (for line-of-sight proximity fade)
	grid.set_player(player)

	# Connect entity death signal for EXP rewards
	if grid.entity_renderer:
		grid.entity_renderer.entity_died.connect(player._on_entity_died)

	# Wire up EXP bar to player
	if exp_bar:
		exp_bar.set_player(player)

	# Wire up status bars (HP/Sanity) to player
	if status_bars:
		status_bars.set_player(player)
