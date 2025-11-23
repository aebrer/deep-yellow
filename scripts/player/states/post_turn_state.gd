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
	var target_state = "IdleState"
	if player and player.return_state:
		target_state = player.return_state
	Log.state("Chunk updates complete, returning to %s" % target_state)
	transition_to(target_state)
