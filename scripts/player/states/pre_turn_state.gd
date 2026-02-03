extends PlayerInputState
## Pre-Turn State - Regenerate resources before action execution
##
## In this state:
## - Input is blocked (player cannot interrupt)
## - Resource regeneration happens:
##   - HP: hp_regen_percent % of max HP (from perks)
##   - Sanity: sanity_regen_percent % of max Sanity (from perks)
##   - Mana: NULL/2 base + mana_regen_percent % of max Mana (from perks)
## - Sanity damage is applied every 13th turn (based on enemies + corruption)
## - Transitions to ExecutingTurnState to execute the pending action

const _SanityDamageAction = preload("res://scripts/actions/sanity_damage_action.gd")

func _init() -> void:
	state_name = "PreTurnState"

func enter() -> void:
	super.enter()
	# Block input during pre-turn processing
	if player:
		player.hide_move_indicator()
	# Execute pre-turn processing immediately
	_execute_pre_turn()

func handle_input(_event: InputEvent) -> void:
	# Block all input during pre-turn processing
	pass

func _execute_pre_turn() -> void:
	"""Execute pre-turn processing (resource regeneration, future: status effects, etc.)"""
	if not player:
		Log.error(Log.Category.TURN, "No player in PreTurnState!")
		transition_to("IdleState")
		return

	Log.turn("===== TURN %d PRE-TURN =====" % (player.turn_count + 1))

	# Update exploration tracking (marks tiles within perception range as explored)
	if player.stats and ExplorationTracker:
		var perception_range: float = 15.0 + (player.stats.perception * 5.0)
		ExplorationTracker.mark_explored(player.grid_position, perception_range)

	# Regenerate all resources (HP, Sanity, Mana)
	if player.stats:
		player.stats.regenerate_resources()

	# Apply sanity damage every 13th turn (environmental pressure from enemies + corruption)
	_apply_sanity_damage()

	# TODO: Process start-of-turn status effects (buffs, debuffs, etc.)
	# TODO: Process environmental effects that trigger at turn start

	# Transition to ExecutingTurnState to execute the pending action
	transition_to("ExecutingTurnState")

func _apply_sanity_damage() -> void:
	"""Apply sanity damage based on enemies in perception range and corruption.

	Damage occurs every 13th turn. Formula:
	damage = base * (1 + weighted_enemies * 0.1 + corruption)

	Where weighted_enemies sums threat level weights for all visible enemies.
	"""
	if not player or not player.stats or not player.grid:
		return

	# Check if this is a sanity damage turn (turn_count is about to increment, so +1)
	var next_turn = player.turn_count + 1
	if not _SanityDamageAction.is_sanity_damage_turn(next_turn):
		return

	# Calculate sanity damage
	var damage_info = _SanityDamageAction.calculate_sanity_damage(player, player.grid)

	if damage_info["damage"] > 0:
		var damage = damage_info["damage"]
		player.stats.drain_sanity(damage)

		# Log the damage with context
		var msg = "🧠 SANITY DRAIN: -%.1f (Turn %d)" % [damage, next_turn]
		if damage_info["enemy_count"] > 0:
			msg += " [%d enemies nearby, weighted: %d]" % [damage_info["enemy_count"], damage_info["weighted_count"]]
		if damage_info["corruption"] > 0:
			msg += " [corruption: %.2f]" % damage_info["corruption"]
		Log.player(msg)
