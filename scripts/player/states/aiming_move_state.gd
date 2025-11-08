extends PlayerInputState
## Aiming Move State - Player is aiming movement direction
##
## In this state:
## - Left stick/WASD shows movement preview indicator
## - Right trigger/Space confirms movement and executes turn
## - Releasing stick returns to IdleState

## Track previous direction to detect stick release
var last_direction: Vector2i = Vector2i.ZERO

func _init() -> void:
	state_name = "AimingMoveState"

func enter() -> void:
	super.enter()
	if InputManager:
		last_direction = InputManager.get_aim_direction_grid()
	if player:
		player.movement_target = last_direction
		player.update_move_indicator()

func exit() -> void:
	super.exit()
	if player:
		player.hide_move_indicator()

func handle_input(event: InputEvent) -> void:
	# Confirm movement with move_confirm action
	if event.is_action_pressed("move_confirm"):
		_confirm_movement()

func process_frame(delta: float) -> void:
	# Update aim direction from InputManager
	if not InputManager:
		return

	# Check for move confirmation (from trigger or other synthesized actions)
	if InputManager.is_action_just_pressed("move_confirm"):
		_confirm_movement()
		return

	var aim = InputManager.get_aim_direction_grid()

	# Check if stick was released (returned to zero)
	if aim == Vector2i.ZERO and last_direction != Vector2i.ZERO:
		# Player released stick, return to idle
		transition_to("IdleState")
		return

	# Update movement target and indicator
	if aim != last_direction:
		last_direction = aim
		if player:
			player.movement_target = aim
			player.update_move_indicator()

func _confirm_movement() -> void:
	"""Player confirmed movement - execute action and advance turn"""
	if player.movement_target == Vector2i.ZERO:
		print("[AimingMoveState] No movement target, ignoring confirm")
		return

	# Create movement action
	var action = MovementAction.new(player.movement_target)

	# Validate and execute
	if action.can_execute(player):
		# Transition to executing state
		player.pending_action = action
		transition_to("ExecutingTurnState")
	else:
		print("[AimingMoveState] Invalid movement - blocked!")
		# Could add visual/audio feedback here
