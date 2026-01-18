extends PlayerInputState
## Idle State - Waiting for player input
##
## This is the default resting state.
## Handles forward movement with RT/Space/Left Click.

const _AttackTypes = preload("res://scripts/combat/attack_types.gd")
const _ItemStatusAction = preload("res://scripts/actions/item_status_action.gd")

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

func exit() -> void:
	super.exit()

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
	"""Update action preview with current forward movement or item pickup, plus pending attacks"""
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

	# Build action list: main action first
	var actions: Array[Action] = [preview_action]

	# Add attack previews from destination (shows what attacks will fire after moving)
	_add_attack_previews(actions, target_position)

	# Add look mode hint
	var look_mode_hint = ControlHintAction.new("👁", "Look Mode", "[LT/RMB]")
	actions.append(look_mode_hint)

	# Add cooldown displays at the bottom (understated)
	_add_cooldown_previews(actions)

	# Add item status displays (ready shields, item cooldowns)
	_add_item_status_previews(actions)

	# Add mana-blocked item effects
	_add_item_mana_blocked_previews(actions)

	# Emit preview signal
	player.action_preview_changed.emit(actions)

func _add_attack_previews(actions: Array[Action], destination: Vector2i) -> void:
	"""Add attack preview actions for attacks that will fire this turn from destination.

	Also highlights entities that will be attacked (red glow on billboards).

	Args:
		actions: Array to append attack previews to
		destination: Position player will be at when attacks fire
	"""
	if not player or not player.attack_executor:
		return

	# Check each attack type
	var attack_types = [_AttackTypes.Type.BODY, _AttackTypes.Type.MIND, _AttackTypes.Type.NULL]

	for attack_type in attack_types:
		# Get preview from destination position (where player will be after moving)
		var preview = player.attack_executor.get_attack_preview(player, attack_type, destination)

		# Only show attacks that are ready to fire
		if not preview.get("ready", false):
			continue

		# Skip NULL attack if player has no mana pool yet
		if attack_type == _AttackTypes.Type.NULL:
			if player.stats and player.stats.max_mana <= 0:
				continue

		var targets: Array = preview.get("targets", [])

		# Use attack_name from preview (may be modified by items)
		var attack_name = preview.get("attack_name", _AttackTypes.BASE_ATTACK_NAMES.get(attack_type, "Attack"))

		# Check if attack can afford after regen (preview shows post-regen state)
		var can_afford_after_regen = preview.get("can_afford_after_regen", true)

		# If attack has mana cost and can't afford even after regen, show mana blocked
		if not can_afford_after_regen:
			var mana_blocked = ManaBlockedAction.new(
				attack_name,
				preview.get("mana_cost", 0.0),
				preview.get("current_mana", 0.0),
				preview.get("mana_after_regen", 0.0)
			)
			actions.append(mana_blocked)
			continue

		# Only show in UI if there are targets - no targets = don't clutter UI
		if targets.is_empty():
			continue

		var attack_emoji = preview.get("attack_emoji", _AttackTypes.BASE_ATTACK_EMOJIS.get(attack_type, "⚔️"))
		var extra_attacks = preview.get("extra_attacks", 0)
		var attack_preview = AttackPreviewAction.new(
			attack_type,
			attack_name,
			attack_emoji,
			preview.get("damage", 0.0),
			targets.size(),
			preview.get("mana_cost", 0.0),
			extra_attacks
		)
		actions.append(attack_preview)

func _add_cooldown_previews(actions: Array[Action]) -> void:
	"""Add cooldown displays for attacks not ready to fire.

	Shows at bottom of preview with clock emoji, e.g. "🕐 Whistle 4 → 3"
	"""
	if not player or not player.attack_executor:
		return

	# Check each attack type for cooldowns
	var attack_types = [_AttackTypes.Type.BODY, _AttackTypes.Type.MIND, _AttackTypes.Type.NULL]

	for attack_type in attack_types:
		var preview = player.attack_executor.get_attack_preview(player, attack_type)

		# Only show if NOT ready (on cooldown)
		if preview.get("ready", false):
			continue

		# Skip NULL if player has no mana pool
		if attack_type == _AttackTypes.Type.NULL and player.stats and player.stats.max_mana <= 0:
			continue

		# Use attack_name from preview (may be modified by items)
		var attack_name = preview.get("attack_name", _AttackTypes.BASE_ATTACK_NAMES.get(attack_type, "Attack"))
		var cd_remaining = preview.get("cooldown_remaining", 0)

		# cooldown_remaining is already the "after tick" value from get_attack_preview
		# We need to show current -> after, so add 1 back to get current
		var cd_current = cd_remaining + 1

		var cooldown_preview = AttackCooldownAction.new(
			attack_name,
			cd_current,
			cd_remaining
		)
		actions.append(cooldown_preview)

func _add_item_status_previews(actions: Array[Action]) -> void:
	"""Add status displays for items with reactive effects or cooldowns.

	Shows items that have get_status_display() returning show=true.
	Examples:
	- "🛡 Protective Ward READY (5 mana)" - shield ready to block damage
	- "🕐 Lucky Reset 3 → 2" - item cooldown ticking down
	"""
	if not player:
		return

	# Check all equipped items in all pools
	var pools = [player.body_pool, player.mind_pool, player.null_pool]

	for pool in pools:
		if not pool:
			continue

		for i in range(pool.max_slots):
			var item = pool.items[i]
			var is_enabled = pool.enabled[i]

			if not item or not is_enabled:
				continue

			# Check if item has status to display
			var status = item.get_status_display()
			if status.is_empty() or not status.get("show", false):
				continue

			var status_type = status.get("type", "")

			if status_type == "ready":
				# Show ready status (e.g., shield ready to block)
				var status_action = _ItemStatusAction.new(
					item.item_name,
					_ItemStatusAction.StatusType.READY,
					0, 0,  # No cooldown values
					status.get("mana_cost", 0.0),
					status.get("description", "")
				)
				actions.append(status_action)

			elif status_type == "cooldown":
				# Show cooldown countdown
				var cd_current = status.get("cooldown_current", 1)
				var cd_after = status.get("cooldown_after", 0)
				var status_action = _ItemStatusAction.new(
					item.item_name,
					_ItemStatusAction.StatusType.COOLDOWN,
					cd_current, cd_after,
					0.0,
					status.get("description", "")
				)
				actions.append(status_action)

func _add_item_mana_blocked_previews(actions: Array[Action]) -> void:
	"""Add mana-blocked displays for equipped items that can't afford their turn effects.

	Shows items with on_turn() mana costs that won't be able to trigger.
	"""
	if not player or not player.stats:
		return

	var mana_after_regen = player.stats.get_mana_after_regen()
	var current_mana = player.stats.current_mana

	# Check all equipped items in all pools
	var pools = [player.body_pool, player.mind_pool, player.null_pool]

	for pool in pools:
		if not pool:
			continue

		for i in range(pool.max_slots):
			var item = pool.items[i]
			var is_enabled = pool.enabled[i]

			if not item or not is_enabled:
				continue

			# Check if item has turn effect info
			var effect_info = item.get_turn_effect_info()
			if effect_info.is_empty():
				continue

			var mana_cost = effect_info.get("mana_cost", 0.0)
			if mana_cost <= 0:
				continue

			# Check if item can afford its effect after regen
			if mana_after_regen >= mana_cost:
				continue  # Can afford, no need to show blocked

			# Show mana blocked for this item
			var effect_name = effect_info.get("effect_name", item.item_name)
			var mana_blocked = ManaBlockedAction.new(
				effect_name,
				mana_cost,
				current_mana,
				mana_after_regen
			)
			actions.append(mana_blocked)

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
