extends PlayerInputState
## Executing Turn State - Processing player action and turn consequences
##
## In this state:
## - Input is blocked (player cannot interrupt)
## - Player action is executed
## - Enemy turns are processed (future)
## - Environmental effects are processed (future)
## - Returns to IdleState when complete

func _init() -> void:
	state_name = "ExecutingTurnState"

func enter() -> void:
	super.enter()
	# Hide movement indicator during turn execution
	if player:
		player.hide_move_indicator()
	# Execute the turn immediately
	_execute_turn()

func handle_input(_event: InputEvent) -> void:
	# Block all input during turn execution
	pass

func _execute_turn() -> void:
	"""Execute the pending action and process turn"""
	if not player or not player.pending_action:
		Log.error(Log.Category.TURN, "No pending action!")
		transition_to("IdleState")
		return

	Log.turn("===== TURN %d EXECUTING =====" % (player.turn_count + 1))

	# Execute player action (this advances turn_count)
	player.pending_action.execute(player)
	player.pending_action = null

	# TODO: Process enemy turns
	# TODO: Process environmental effects
	# TODO: Check win/loss conditions

	Log.turn("===== TURN %d COMPLETE =====" % player.turn_count)

	# Emit turn_completed signal for turn-based systems (ChunkManager, etc.)
	player.turn_completed.emit()

	# Transition to PostTurnState to process world updates
	# (PostTurnState blocks input while chunks generate, then returns to IdleState)
	transition_to("PostTurnState")
