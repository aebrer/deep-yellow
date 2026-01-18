extends PlayerInputState
## State for first-person examination mode
##
## Entered when player holds LT/RMB.
## Exits when player releases LT/RMB.
## Turn progression is PAUSED during look mode.

const _AttackTypes = preload("res://scripts/combat/attack_types.gd")
const _ItemStatusAction = preload("res://scripts/actions/item_status_action.gd")
const _SanityDamageAction = preload("res://scripts/actions/sanity_damage_action.gd")

# NOTE: These will be initialized in enter() since they depend on player node
var first_person_camera: FirstPersonCamera = null
var tactical_camera: TacticalCamera = null
var examination_crosshair: ExaminationCrosshair = null  # In viewport (can have effects)
var examination_panel: ExaminationPanel = null  # In main viewport (clean text)

var current_target: Examinable = null
var current_grid_tile: Dictionary = {}  # For grid tile examination

func _init() -> void:
	state_name = "LookModeState"

# ============================================================================
# STATE LIFECYCLE
# ============================================================================

func enter() -> void:
	super.enter()

	# Get camera and UI references (can't use @onready in state nodes)
	if not first_person_camera:
		first_person_camera = player.get_node_or_null("FirstPersonCamera")
	if not tactical_camera:
		tactical_camera = player.get_node_or_null("CameraRig")

	# Get split examination UI components
	if not examination_crosshair:
		var game_3d = player.get_parent()
		examination_crosshair = game_3d.get_node_or_null("ViewportUILayer/ExaminationCrosshair")
	if not examination_panel:
		examination_panel = get_node_or_null("/root/Game/MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/ExaminationPanel")
		if not examination_panel:
			Log.warn(Log.Category.STATE, "ExaminationPanel NOT found in RightSide VBoxContainer")

	if not first_person_camera:
		push_error("[LookModeState] FirstPersonCamera not found!")
		transition_to("IdleState")
		return

	if not tactical_camera:
		push_error("[LookModeState] TacticalCamera not found!")
		transition_to("IdleState")
		return


	# Capture mouse for camera control (standard FPS controls)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch cameras (activate() handles rotation sync)
	tactical_camera.camera.current = false
	first_person_camera.activate()

	# Hide tactical UI elements
	if player.has_method("hide_move_indicator"):
		player.hide_move_indicator()

	# Show examination crosshair (in viewport, can have effects)
	if examination_crosshair:
		examination_crosshair.show_crosshair()
	else:
		Log.warn(Log.Category.STATE, "ExaminationCrosshair not found in ViewportUILayer")

	# Update action preview to show wait action
	_update_action_preview()

func exit() -> void:
	super.exit()


	# Recapture mouse for tactical camera control (unless paused)
	if not PauseManager.is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch back to tactical camera (deactivate() handles rotation sync)
	if first_person_camera:
		first_person_camera.deactivate()
	if tactical_camera:
		tactical_camera.camera.current = true

	# Hide examination UI components
	if examination_crosshair:
		examination_crosshair.hide_crosshair()
	if examination_panel:
		examination_panel.hide_panel()

	# Restore tactical UI
	if player.has_method("update_move_indicator"):
		player.update_move_indicator()

	# Clear current target
	current_target = null

# ============================================================================
# INPUT HANDLING
# ============================================================================

func handle_input(event: InputEvent) -> void:
	# Exit look mode when trigger released
	if event.is_action_released("look_mode"):
		transition_to("IdleState")
		return

	# Block all other inputs while in look mode
	# (Camera rotation handled by FirstPersonCamera directly)
	# (RT/LMB handled in process_frame via InputManager)

func process_frame(_delta: float) -> void:
	# Check if look mode button released
	# InputManager.is_action_pressed handles: LT trigger, RMB
	if InputManager and not InputManager.is_action_pressed("look_mode"):
		transition_to("IdleState")
		return

	# Handle RT/LMB for wait action (using InputManager for proper action tracking)
	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		_execute_wait_action()
		return

	# Update raycast and examination target (uses examination overlay system)
	if not first_person_camera:
		return

	var new_target = first_person_camera.get_current_target()

	# Check if target changed
	var target_changed = (new_target != current_target)
	current_target = new_target

	# Update UI with target (or hide if nothing)
	if target_changed:
		if new_target:
			# Examine the target - route to correct examination function based on entity_type
			if new_target.entity_type == Examinable.EntityType.ENVIRONMENT:
				# Extract simple type from "level_0_floor" → "floor"
				var env_type = new_target.entity_id.replace("level_0_", "")
				KnowledgeDB.examine_environment(env_type)
			elif new_target.entity_type == Examinable.EntityType.ITEM:
				# Items - need to get rarity for correct EXP reward
				var item = KnowledgeDB._get_item_by_id(new_target.entity_id)
				if item:
					var rarity_name = ItemRarity.RARITY_NAMES[item.rarity].to_lower()
					KnowledgeDB.examine_item(new_target.entity_id, rarity_name)
				else:
					# Fallback if item not found
					KnowledgeDB.examine_item(new_target.entity_id, "common")
			else:
				# Entities, hazards
				KnowledgeDB.examine_entity(new_target.entity_id)

			if examination_panel:
				examination_panel.show_panel(new_target)
			else:
				Log.warn(Log.Category.STATE, "Cannot show panel - examination_panel is null")
		else:
			# Looking at nothing
			if examination_panel:
				examination_panel.hide_panel()

# ============================================================================
# ACTIONS
# ============================================================================

func _execute_wait_action() -> void:
	"""Execute a wait action (pass turn without moving) via state machine flow"""
	var wait_action = WaitAction.new()

	# Set pending action and return state, then transition through turn flow
	# PreTurnState → ExecutingTurnState → PostTurnState → back to LookModeState
	if wait_action.can_execute(player):
		player.pending_action = wait_action
		player.return_state = "LookModeState"  # Return here after turn completes
		transition_to("PreTurnState")

func _update_action_preview() -> void:
	"""Update action preview with wait action and pending attacks"""
	if not player:
		return

	# In look mode, player will wait (pass turn) when clicking RT/LMB
	var preview_action = WaitAction.new()

	# Build action list: wait action first
	var actions: Array[Action] = [preview_action]

	# Add attack previews from current position (player stays in place when waiting)
	_add_attack_previews(actions, player.grid_position)

	# Add cooldown displays at the bottom
	_add_cooldown_previews(actions)

	# Add item status displays (ready shields, item cooldowns)
	_add_item_status_previews(actions)

	# Add mana-blocked item effects
	_add_item_mana_blocked_previews(actions)

	# Add sanity damage preview (shows when next sanity drain will occur)
	_add_sanity_damage_preview(actions)

	# Emit preview signal
	player.action_preview_changed.emit(actions)

func _add_attack_previews(actions: Array[Action], destination: Vector2i) -> void:
	"""Add attack preview actions for attacks that will fire this turn from destination."""
	if not player or not player.attack_executor:
		return

	var attack_types = [_AttackTypes.Type.BODY, _AttackTypes.Type.MIND, _AttackTypes.Type.NULL]

	for attack_type in attack_types:
		var preview = player.attack_executor.get_attack_preview(player, attack_type, destination)

		if not preview.get("ready", false):
			continue

		# Skip NULL attack if player has no mana pool yet
		if attack_type == _AttackTypes.Type.NULL:
			if player.stats and player.stats.max_mana <= 0:
				continue

		var targets: Array = preview.get("targets", [])
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
	"""Add cooldown displays for attacks not ready to fire."""
	if not player or not player.attack_executor:
		return

	var attack_types = [_AttackTypes.Type.BODY, _AttackTypes.Type.MIND, _AttackTypes.Type.NULL]

	for attack_type in attack_types:
		var preview = player.attack_executor.get_attack_preview(player, attack_type)

		if preview.get("ready", false):
			continue

		if attack_type == _AttackTypes.Type.NULL and player.stats and player.stats.max_mana <= 0:
			continue

		var attack_name = preview.get("attack_name", _AttackTypes.BASE_ATTACK_NAMES.get(attack_type, "Attack"))
		var cd_remaining = preview.get("cooldown_remaining", 0)
		var cd_current = cd_remaining + 1

		var cooldown_preview = AttackCooldownAction.new(
			attack_name,
			cd_current,
			cd_remaining
		)
		actions.append(cooldown_preview)

func _add_item_mana_blocked_previews(actions: Array[Action]) -> void:
	"""Add mana-blocked displays for equipped items that can't afford their turn effects."""
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

func _add_sanity_damage_preview(actions: Array[Action]) -> void:
	"""Add sanity damage preview showing when next sanity drain will occur.

	Shows:
	- "🧠 Sanity Drain → -X NOW" when damage happens this turn
	- "🧠 Sanity Drain -X in N turns" as warning
	"""
	if not player or not player.grid:
		return

	# Calculate sanity damage info
	var damage_info = _SanityDamageAction.calculate_sanity_damage(player, player.grid)

	# Only show if damage is coming within 4 turns (turns_until uses 1-indexed: 1=next turn, 4=in 4 turns)
	if damage_info["turns_until"] > 4:
		return

	var sanity_action = _SanityDamageAction.new(
		damage_info["damage"],
		damage_info["turns_until"],
		damage_info["enemy_count"],
		damage_info["weighted_count"],
		damage_info["corruption"]
	)
	actions.append(sanity_action)

# All target handling now unified - no special cases for grid tiles vs entities
