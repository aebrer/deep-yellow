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

	# Determine destination level
	var destinations: Array[int] = current_level.exit_destinations
	if destinations.is_empty():
		Log.warn(Log.Category.SYSTEM, "EXIT_STAIRS found but no exit_destinations configured!")
		return false

	var target_level_id: int = destinations[0]  # First destination for now
	Log.system("EXIT_STAIRS triggered! Transitioning to level %d" % target_level_id)

	# Use ChunkManager.change_level() for mid-run level transition
	# This preserves run state (seed, corruption) while switching level geometry
	ChunkManager.change_level(target_level_id)
	return true
