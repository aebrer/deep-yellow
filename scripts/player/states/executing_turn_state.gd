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
	# Execute the turn immediately
	_execute_turn()

func handle_input(event: InputEvent) -> void:
	# Block all input during turn execution
	pass

func _execute_turn() -> void:
	"""Execute the pending action and process turn"""
	if not player or not player.pending_action:
		push_warning("[ExecutingTurnState] No pending action!")
		transition_to("IdleState")
		return

	# Execute player action
	player.pending_action.execute(player)
	player.pending_action = null

	# TODO: Process enemy turns
	# TODO: Process environmental effects
	# TODO: Check win/loss conditions

	# Turn complete, return to idle
	transition_to("IdleState")
