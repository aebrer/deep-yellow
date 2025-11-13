extends PlayerInputState
## Idle State - Waiting for player input
##
## This is the default resting state.
## Handles forward movement with RT/Space/Left Click.

## RT/Click hold-to-repeat system
var rt_held: bool = false
var rt_hold_time: float = 0.0
var rt_repeat_timer: float = 0.0

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
		Log.movement("RT/Click still held - continuing hold_time=%.2fs" % rt_hold_time)
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
	"""Move forward in camera direction"""
	if not player:
		return

	# Get forward direction from camera
	var forward_direction = Vector2i.ZERO
	if player.has_method("get_camera_forward_grid_direction"):
		forward_direction = player.get_camera_forward_grid_direction()

	if forward_direction == Vector2i.ZERO:
		Log.movement("No forward direction, ignoring move")
		return

	Log.movement_info("Moving forward: direction=%s" % forward_direction)

	# Create and execute movement action
	var action = MovementAction.new(forward_direction)
	if action.can_execute(player):
		player.pending_action = action
		transition_to("ExecutingTurnState")
	else:
		Log.warn(Log.Category.MOVEMENT, "Cannot move forward - blocked!")

func process_frame(delta: float) -> void:
	if not InputManager:
		return

	# Update forward indicator every frame (follows camera rotation)
	if player:
		player.update_move_indicator()
		_update_action_preview()

	# Handle RT/Click press and hold-to-repeat
	if InputManager.is_action_just_pressed("move_confirm"):
		Log.movement("RT/Click just pressed - initial move")
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
			Log.movement("REPEAT! hold_time=%.2fs interval=%.2fs" % [rt_hold_time, current_interval])
			_move_forward()
			return
	elif not rt_is_down:
		# RT/Click released
		rt_held = false
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0

func _update_action_preview() -> void:
	"""Update action preview with current forward movement"""
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

	# Create movement action for preview (not executed yet)
	var preview_action = MovementAction.new(forward_direction)

	# Emit preview signal with typed array
	var actions: Array[Action] = [preview_action]
	player.action_preview_changed.emit(actions)
