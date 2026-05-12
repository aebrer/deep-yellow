extends PlayerInputState
## Post-Turn State - Processing world updates after action execution
##
## In this state:
## - Input is blocked (player cannot interrupt world updates)
## - ChunkManager processes chunk loading/unloading
## - Future: Enemy turns, physics simulation, environmental effects
## - Returns to IdleState when all updates complete

func _init() -> void:
	state_name = "PostTurnState"

func enter() -> void:
	super.enter()

	# Connect to ChunkManager's completion signal (one-shot to avoid leaks)
	if ChunkManager:
		if not ChunkManager.chunk_updates_completed.is_connected(_on_chunk_updates_complete):
			ChunkManager.chunk_updates_completed.connect(_on_chunk_updates_complete, CONNECT_ONE_SHOT)
	else:
		# Fallback: if ChunkManager not found, skip directly to return state
		var target_state = player.return_state if player and player.return_state else "IdleState"
		Log.warn(Log.Category.STATE, "ChunkManager not found, skipping PostTurnState, returning to %s" % target_state)
		transition_to(target_state)

func handle_input(_event: InputEvent) -> void:
	# Block ALL input during post-turn processing
	# This prevents input queuing while chunks generate (~80ms)
	pass

func _on_chunk_updates_complete() -> void:
	"""Called when ChunkManager finishes chunk generation"""
	# Don't transition if player is dead (game over screen is handling things)
	# Death occurs when HP or Sanity reaches 0
	if player and player.stats:
		if player.stats.current_hp <= 0.0 or player.stats.current_sanity <= 0.0:
			return

	# Check if player is standing on exit stairs
	if _check_exit_stairs():
		return  # Level transition will handle everything

	var target_state = "IdleState"
	if player and player.return_state:
		target_state = player.return_state
	transition_to(target_state)

func _check_exit_stairs() -> bool:
	"""Check if player is on EXIT_STAIRS tile and trigger level transition"""
	if not player or not ChunkManager:
		return false

	var current_level := LevelManager.get_current_level()
	if not current_level:
		return false

	var tile_type := ChunkManager.get_tile_type(player.grid_position, current_level.level_id)
	if tile_type != SubChunk.TileType.EXIT_STAIRS:
		return false

	# Determine destination from the explicit stair entity/type at this tile.
	# exit_destinations is only an allowlist/preload hint, never an ordered progression rule.
	var exit_entity: WorldEntity = ChunkManager.get_exit_entity_at_tile(player.grid_position, current_level.level_id)
	if not exit_entity:
		Log.error(Log.Category.SYSTEM, "EXIT_STAIRS tile at %s has no explicit exit entity; refusing implicit transition" % player.grid_position)
		return false

	var target_level_id: int = exit_entity.exit_destination_level_id
	if target_level_id == -999999:
		Log.error(Log.Category.SYSTEM, "Exit entity '%s' at %s has no explicit destination" % [exit_entity.entity_type, player.grid_position])
		return false

	if not current_level.exit_destinations.has(target_level_id):
		Log.warn(Log.Category.SYSTEM, "Exit entity '%s' leads to level %d, which is not in exit_destinations preload allowlist" % [exit_entity.entity_type, target_level_id])

	Log.system("EXIT_STAIRS '%s' triggered! Transitioning to level %d" % [exit_entity.entity_type, target_level_id])

	# Use ChunkManager.change_level() for mid-run level transition
	# This preserves run state (seed, corruption) while switching level geometry
	ChunkManager.change_level(target_level_id)
	return true
