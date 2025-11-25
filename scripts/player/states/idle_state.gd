extends PlayerInputState
## Idle State - Waiting for player input
##
## This is the default resting state.
## Handles forward movement with RT/Space/Left Click.

## RT/Click hold-to-repeat system
var rt_held: bool = false
var rt_hold_time: float = 0.0
var rt_repeat_timer: float = 0.0

## Blocked movement tracking (prevent spam)
var last_blocked_direction: Vector2i = Vector2i(-999, -999)  # Invalid initial value

# Repeat timing configuration
const INITIAL_DELAY: float = 0.3
const REPEAT_INTERVAL_START: float = 0.25
const REPEAT_INTERVAL_MIN: float = 0.08
const RAMP_TIME: float = 2.0

func _init() -> void:
	state_name = "IdleState"

func enter() -> void:
	super.enter()
	# Show forward indicator (1 cell ahead in camera direction)
	if player:
		player.update_move_indicator()
		_update_action_preview()

	# Check if RT/Click is already being held (from previous state)
	var rt_currently_held = InputManager.is_action_pressed("move_confirm")
	if rt_currently_held and rt_held:
		# Continue the hold timer
		pass
	else:
		# Fresh entry or RT released - reset
		rt_held = false
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0

func handle_input(event: InputEvent) -> void:
	# Check for look mode activation (LT/RMB press)
	if event.is_action_pressed("look_mode"):
		transition_to("LookModeState")
		return

	# Initial movement press handled in process_frame for consistent timing

func _move_forward() -> void:
	"""Move forward in camera direction (or pick up item if present)"""
	if not player:
		return

	# Get forward direction from camera
	var forward_direction = Vector2i.ZERO
	if player.has_method("get_camera_forward_grid_direction"):
		forward_direction = player.get_camera_forward_grid_direction()

	if forward_direction == Vector2i.ZERO:
		return

	# Check if there's an item at the target position
	var target_position = player.grid_position + forward_direction
	var item_at_target = _get_item_at_position(target_position)

	# Create appropriate action (pickup or movement)
	var action: Action
	if item_at_target:
		action = PickupItemAction.new(target_position, item_at_target)
	else:
		action = MovementAction.new(forward_direction)

	# Execute action
	if action.can_execute(player):
		player.pending_action = action
		player.return_state = "IdleState"  # Return here after turn completes
		last_blocked_direction = Vector2i(-999, -999)  # Reset blocked tracking on success
		transition_to("PreTurnState")
	else:
		# Only warn on initial press, not during hold-to-repeat (fast players can tell it's blocked)
		if not rt_held:
			Log.warn(Log.Category.MOVEMENT, "Cannot move forward - blocked!")

func process_frame(delta: float) -> void:
	if not InputManager:
		return

	# Skip input for one frame if requested (prevents UI button from triggering movement)
	if player and player.suppress_input_next_frame:
		player.suppress_input_next_frame = false
		# Still update indicator and preview, just don't process input
		player.update_move_indicator()
		_update_action_preview()
		return

	# Update forward indicator every frame (follows camera rotation)
	if player:
		player.update_move_indicator()
		_update_action_preview()

	# Check for look mode activation via InputManager (handles trigger synthesis)
	if InputManager.is_action_just_pressed("look_mode"):
		Log.system("[IdleState] look_mode action detected - transitioning to LookModeState")
		transition_to("LookModeState")
		return

	# Handle RT/Click press and hold-to-repeat
	if InputManager.is_action_just_pressed("move_confirm"):
		_move_forward()
		rt_held = true
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0
		return

	# Track RT/Click hold state for repeat
	var rt_is_down = InputManager.is_action_pressed("move_confirm")

	if rt_is_down and rt_held:
		# RT/Click is being held - update repeat system
		rt_hold_time += delta
		rt_repeat_timer += delta

		# Calculate current repeat interval (ramps from START to MIN)
		var ramp_progress = clampf(rt_hold_time / RAMP_TIME, 0.0, 1.0)
		var current_interval = lerp(REPEAT_INTERVAL_START, REPEAT_INTERVAL_MIN, ramp_progress)

		# Check if we should trigger a repeat
		var should_repeat = false
		if rt_hold_time < INITIAL_DELAY:
			should_repeat = false
		elif rt_repeat_timer >= current_interval:
			should_repeat = true
			rt_repeat_timer = 0.0

		if should_repeat:
			_move_forward()
			return
	elif not rt_is_down:
		# RT/Click released
		rt_held = false
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0
		last_blocked_direction = Vector2i(-999, -999)  # Reset blocked tracking on release

func _update_action_preview() -> void:
	"""Update action preview with current forward movement or item pickup"""
	if not player:
		return

	# Get forward direction from camera
	var forward_direction = Vector2i.ZERO
	if player.has_method("get_camera_forward_grid_direction"):
		forward_direction = player.get_camera_forward_grid_direction()

	if forward_direction == Vector2i.ZERO:
		# No valid direction - hide preview
		var empty_actions: Array[Action] = []
		player.action_preview_changed.emit(empty_actions)
		return

	# Check if there's an item at the target position
	var target_position = player.grid_position + forward_direction
	var item_at_target = _get_item_at_position(target_position)

	var preview_action: Action

	if item_at_target:
		# Show pickup action
		preview_action = PickupItemAction.new(target_position, item_at_target)
	else:
		# Show movement action
		preview_action = MovementAction.new(forward_direction)

	# Add look mode hint
	var look_mode_hint = ControlHintAction.new("👁", "Look Mode", "[LT/RMB]")

	# Emit preview signal with typed array (main action + look mode hint)
	var actions: Array[Action] = [preview_action, look_mode_hint]
	player.action_preview_changed.emit(actions)

func _get_item_at_position(grid_pos: Vector2i) -> Dictionary:
	"""Check if there's an item at the given grid position

	Args:
		grid_pos: Grid coordinates to check

	Returns:
		Item data Dictionary if item exists, empty Dictionary otherwise
	"""
	if not player or not player.grid or not player.grid.item_renderer:
		return {}

	return player.grid.item_renderer.get_item_at(grid_pos)
