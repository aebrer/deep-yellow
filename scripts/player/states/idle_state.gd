extends PlayerInputState
## Idle State - Waiting for player input
##
## This is the default resting state.
## Transitions to AimingMoveState when stick/WASD is pressed.

func _init() -> void:
	state_name = "IdleState"

func enter() -> void:
	super.enter()
	# Clear any previous aim indicators
	if player:
		player.movement_target = Vector2i.ZERO
		player.hide_move_indicator()

func handle_input(event: InputEvent) -> void:
	# System actions handled by player directly, not states
	pass

func process_frame(delta: float) -> void:
	# Check if player started aiming
	var aim = InputManager.get_aim_direction_grid()

	if aim != Vector2i.ZERO:
		# Player started aiming, transition to aiming state
		transition_to("AimingMoveState")
