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
@onready var loading_screen: CanvasLayer = $LoadingScreen

var snowfall: Snowfall = null

func _ready() -> void:

	# ========================================================================
	# LEVEL LOADING - Game starts on Level -1 (tutorial)
	# ========================================================================
	# Always start at Level -1. Mid-run level changes use ChunkManager.change_level().
	LevelManager.transition_to_level(-1)

	# Configure grid with current level settings (lighting, materials, fog, etc.)
	var current_level := LevelManager.get_current_level()
	grid.configure_from_level(current_level)

	# Snowfall effect (toggled per level)
	if current_level and current_level.enable_snowfall:
		snowfall = Snowfall.new()
		add_child(snowfall)
		snowfall.set_target(player)
		snowfall.set_active(true)

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

	# Listen for mid-run level changes (exit stairs)
	if ChunkManager and not ChunkManager.level_changed.is_connected(_on_level_changed):
		ChunkManager.level_changed.connect(_on_level_changed)


func _on_level_changed(_new_level_id: int) -> void:
	"""Reconfigure visuals and respawn player when level changes mid-run"""
	var new_level := LevelManager.get_current_level()
	if not new_level:
		return

	# Show loading screen during transition
	if loading_screen:
		var label: Label = loading_screen.get_node_or_null("%LoadingLabel")
		if label:
			label.text = "Generating %s..." % new_level.display_name
		loading_screen.show()

	# Clear old level's rendered tiles and walkable cache
	grid.grid_map.clear()
	grid.walkable_cells.clear()

	# Clear old spraypaint, items, entities from renderers
	if grid.spraypaint_renderer:
		grid.spraypaint_renderer.clear_all_spraypaint()
	if grid.item_renderer:
		grid.item_renderer.clear_all_items()
	if grid.entity_renderer:
		grid.entity_renderer.clear_all_entities()
	grid.clear_exit_holes()

	# Reconfigure grid visuals (lighting, materials, fog, mesh library)
	grid.configure_from_level(new_level)

	# Toggle snowfall
	if new_level.enable_snowfall:
		if not snowfall:
			snowfall = Snowfall.new()
			add_child(snowfall)
			snowfall.set_target(player)
		snowfall.set_active(true)
	elif snowfall:
		snowfall.set_active(false)

	# Player needs to wait for new chunks then respawn
	# The ChunkManager will emit initial_load_completed when ready
	_respawn_player_for_new_level.call_deferred()


func _respawn_player_for_new_level() -> void:
	"""Wait for new level chunks to load, then respawn player"""
	if not player or not grid:
		return

	# Wait for initial chunks to generate for the new level
	if ChunkManager and not ChunkManager.initial_load_complete:
		await ChunkManager.initial_load_completed

	# Check for fixed spawn position
	var current_level := LevelManager.get_current_level()
	var fixed_spawn := current_level.player_spawn_position if current_level else Vector2i(-1, -1)

	if fixed_spawn != Vector2i(-1, -1):
		player.grid_position = fixed_spawn
		if current_level.player_spawn_camera_yaw != 0.0:
			player._set_camera_yaw(current_level.player_spawn_camera_yaw)
	else:
		player._find_procedural_spawn()

	player.update_visual_position()

	# DEBUG: Spawn a vending machine near the player on Level 0
	if current_level and current_level.level_id == 0:
		_spawn_debug_vending_machine(player.grid_position)

	# Transition state machine back to IdleState after level change
	# (PostTurnState called change_level and stopped transitioning)
	if player.state_machine:
		player.state_machine.change_state("IdleState")


func _spawn_debug_vending_machine(player_pos: Vector2i) -> void:
	"""DEBUG: Spawn a vending machine 3 tiles ahead of the player for testing"""
	# Try a few offsets to find a walkable spot
	var offsets = [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3),
		Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 0), Vector2i(0, 4)]

	var spawn_pos = Vector2i(-1, -1)
	for offset in offsets:
		var candidate = player_pos + offset
		if grid.is_walkable(candidate):
			spawn_pos = candidate
			break

	if spawn_pos == Vector2i(-1, -1):
		Log.system("[DEBUG] Could not find walkable position for debug vending machine")
		return

	# Create the WorldEntity
	var entity = WorldEntity.new("vending_machine", spawn_pos, 99999.0, 0)
	entity.hostile = false
	entity.blocks_movement = false

	# Add to the appropriate subchunk
	if ChunkManager:
		var current_level := LevelManager.get_current_level()
		if not current_level:
			Log.system("[DEBUG] No current level - cannot place debug vending machine in chunk")
			return
		var chunk = ChunkManager.get_chunk_at_tile(spawn_pos, current_level.level_id)
		if chunk:
			for subchunk in chunk.sub_chunks:
				var local_x = spawn_pos.x - subchunk.world_position.x
				var local_y = spawn_pos.y - subchunk.world_position.y
				if local_x >= 0 and local_x < SubChunk.SIZE and local_y >= 0 and local_y < SubChunk.SIZE:
					subchunk.add_world_entity(entity)
					break

	# Render the billboard
	if grid.entity_renderer:
		var billboard = grid.entity_renderer._create_billboard_for_entity(entity)
		if billboard:
			grid.entity_renderer.add_child(billboard)
			grid.entity_renderer.entity_billboards[spawn_pos] = billboard
			grid.entity_renderer.entity_cache[spawn_pos] = entity
			grid.entity_renderer.entity_to_pos[entity] = spawn_pos

	Log.system("[DEBUG] Spawned vending machine at %s (player at %s)" % [spawn_pos, player_pos])
