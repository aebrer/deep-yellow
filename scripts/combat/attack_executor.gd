class_name AttackExecutor extends RefCounted
"""Builds and executes pool attacks each turn.

The AttackExecutor:
1. Tracks cooldowns per attack type (BODY/MIND/NULL)
2. Each turn, ticks cooldowns and checks which attacks are ready
3. For ready attacks: builds attack from pool items → finds targets → executes

Items provide modifiers via get_attack_modifiers() method.
Modifiers are aggregated: ADD first, then MULTIPLY.

Special NULL behavior:
- Base damage = max_mana (total mana capacity, not current available)
- Only fires if player has mana to spend (costs mana)
- Thematic: anomaly power tied to mana pool size

Cooldown behavior:
- Ticked at start of each turn (before attack checks)
- Reset to attack.cooldown when attack successfully fires
- NOT reset if no valid targets (preserves cooldown for next turn)
- NOT reset if can't afford mana cost (NULL attack)
"""

# Preload dependencies to ensure correct load order
const _AttackTypes = preload("res://scripts/combat/attack_types.gd")
const _PoolAttack = preload("res://scripts/combat/pool_attack.gd")

# ============================================================================
# COOLDOWN STATE
# ============================================================================

## Current cooldown per attack type (0 = ready to fire)
var _cooldowns: Dictionary = {
	_AttackTypes.Type.BODY: 0,
	_AttackTypes.Type.MIND: 0,
	_AttackTypes.Type.NULL: 0,
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

func execute_turn(player) -> void:
	"""Execute all ready attacks for this turn.

	Called during turn execution, after player action but before item on_turn().

	Args:
		player: Player3D reference (untyped to avoid circular dependency)
	"""
	# Tick all cooldowns first
	for type in _cooldowns.keys():
		if _cooldowns[type] > 0:
			_cooldowns[type] -= 1

	# Execute BODY attack (always available - base punch)
	if _cooldowns[_AttackTypes.Type.BODY] <= 0:
		var attack = _build_attack(player, player.body_pool, _AttackTypes.Type.BODY)
		if attack and _execute_attack(player, attack):
			_cooldowns[_AttackTypes.Type.BODY] = attack.cooldown

	# Execute MIND attack (always available - base whistle)
	if _cooldowns[_AttackTypes.Type.MIND] <= 0:
		var attack = _build_attack(player, player.mind_pool, _AttackTypes.Type.MIND)
		if attack and _execute_attack(player, attack):
			_cooldowns[_AttackTypes.Type.MIND] = attack.cooldown

	# Execute NULL attack (only if player has mana)
	if _cooldowns[_AttackTypes.Type.NULL] <= 0:
		var attack = _build_attack(player, player.null_pool, _AttackTypes.Type.NULL)
		if attack and _execute_attack(player, attack):
			_cooldowns[_AttackTypes.Type.NULL] = attack.cooldown

# ============================================================================
# ATTACK BUILDING
# ============================================================================

func _build_attack(player, pool: ItemPool, attack_type: int):
	"""Build attack from pool's equipped items.

	Aggregates modifiers from all enabled items:
	1. Start with base stats for attack type
	2. Add flat modifiers (damage_add, range_add, cooldown_add)
	3. Multiply by multipliers (damage_multiply, mana_cost_multiply)
	4. Apply stat scaling (strength/perception/anomaly)
	5. For NULL: set base damage to current_mana

	Args:
		player: Player3D reference
		pool: ItemPool to query for modifiers (can be null)
		attack_type: AttackTypes.Type enum

	Returns:
		PoolAttack with all modifiers applied
	"""
	var attack = _PoolAttack.new(attack_type)

	# Collect modifiers from equipped items
	var damage_add: float = 0.0
	var damage_multiply: float = 1.0
	var range_add: float = 0.0
	var cooldown_add: int = 0
	var mana_cost_multiply: float = 1.0

	if pool:
		for i in range(pool.max_slots):
			var item = pool.items[i]
			var is_enabled = pool.enabled[i]

			if item and is_enabled:
				var mods = item.get_attack_modifiers()

				damage_add += mods.get("damage_add", 0.0)
				damage_multiply *= mods.get("damage_multiply", 1.0)
				range_add += mods.get("range_add", 0.0)
				cooldown_add += mods.get("cooldown_add", 0)
				mana_cost_multiply *= mods.get("mana_cost_multiply", 1.0)

				# Attack name override (last one wins - most recently equipped item names the attack)
				if mods.has("attack_name"):
					attack.attack_name = mods["attack_name"]

				# Attack emoji override (last one wins)
				if mods.has("attack_emoji"):
					attack.attack_emoji = mods["attack_emoji"]

				# Area override (last one wins)
				if mods.has("area"):
					attack.area = mods["area"]

				# Collect special effects
				if mods.has("special_effects"):
					attack.special_effects.append_array(mods["special_effects"])

	# Apply modifiers to base stats
	attack.damage = (attack.damage + damage_add) * damage_multiply
	attack.range_tiles = attack.range_tiles + range_add
	attack.cooldown = maxi(1, attack.cooldown + cooldown_add)  # Minimum 1 turn
	attack.mana_cost = attack.mana_cost * mana_cost_multiply

	# Special NULL behavior: base damage = TOTAL mana (max_mana)
	if attack_type == _AttackTypes.Type.NULL and player and player.stats:
		# For NULL, damage is max_mana + any damage_add modifiers
		# The base damage (0) gets replaced by max_mana (total mana capacity)
		# This ties anomaly power to your mana pool size, not current available mana
		attack.damage = (player.stats.max_mana + damage_add) * damage_multiply

	# Apply stat scaling
	if player and player.stats:
		var scaling_stat = _AttackTypes.SCALING_STAT[attack_type]
		var stat_value: float = 0.0

		# Get the scaling stat value
		match scaling_stat:
			"strength":
				stat_value = player.stats.strength
			"perception":
				stat_value = player.stats.perception
			"anomaly":
				stat_value = player.stats.anomaly

		# Formula: damage *= (1.0 + stat_value / 100.0)
		attack.damage *= (1.0 + stat_value / 100.0)

	return attack

# ============================================================================
# ATTACK EXECUTION
# ============================================================================

func _execute_attack(player, attack) -> bool:
	"""Execute attack against valid targets.

	Args:
		player: Player3D reference
		attack: Built PoolAttack

	Returns:
		true if attack fired (resets cooldown), false otherwise
	"""
	# Check mana cost for NULL attacks
	if not attack.can_afford(player.stats):
		return false

	# Find targets
	var targets = _find_targets(player, attack)
	if targets.is_empty():
		return false  # No targets, don't consume cooldown

	# Pay cost (NULL attacks consume mana)
	attack.pay_cost(player.stats)

	# Apply damage to targets
	for target_pos in targets:
		var success = player.grid.entity_renderer.damage_entity_at(target_pos, attack.damage, attack.attack_emoji)
		if success:
			var type_name = _AttackTypes.TYPE_NAMES.get(attack.attack_type, "UNKNOWN")
			Log.player("%s (%s) hits %s for %.0f damage" % [attack.attack_name, type_name, target_pos, attack.damage])

	# Apply special effects from items
	for effect in attack.special_effects:
		if effect.has_method("apply"):
			effect.apply(player, targets)

	return true

# ============================================================================
# TARGETING
# ============================================================================

func _find_targets(player, attack) -> Array[Vector2i]:
	"""Find valid targets for attack.

	Args:
		player: Player3D reference
		attack: Attack to find targets for

	Returns:
		Array of entity positions to hit
	"""
	if not player.grid or not player.grid.entity_renderer:
		return []

	var candidates = player.grid.entity_renderer.get_entities_in_range(
		player.grid_position,
		attack.range_tiles
	)

	if candidates.is_empty():
		return []

	match attack.area:
		_AttackTypes.Area.SINGLE:
			# Return nearest only
			candidates.sort_custom(func(a, b):
				return player.grid_position.distance_to(a) < player.grid_position.distance_to(b))
			return [candidates[0]]

		_AttackTypes.Area.AOE_3X3, _AttackTypes.Area.AOE_AROUND:
			# Return all in range (whistle hits everything nearby)
			return candidates

		_AttackTypes.Area.CONE:
			# Return enemies in a cone in player's facing direction
			return _filter_cone_targets(player, candidates)

		_:
			# Default: nearest
			candidates.sort_custom(func(a, b):
				return player.grid_position.distance_to(a) < player.grid_position.distance_to(b))
			return [candidates[0]]

func _filter_cone_targets(player, candidates: Array[Vector2i]) -> Array[Vector2i]:
	"""Filter candidates to those within a cone in player's facing direction.

	Cone is ~90 degrees wide (45 degrees each side of facing).
	"""
	var in_cone: Array[Vector2i] = []
	var facing = player.get_camera_forward_grid_direction()

	# Convert facing to angle (in radians)
	var facing_angle = atan2(facing.y, facing.x)

	for pos in candidates:
		var delta = pos - player.grid_position
		if delta == Vector2i.ZERO:
			continue

		# Angle to this target
		var target_angle = atan2(delta.y, delta.x)

		# Angular difference (handle wraparound)
		var angle_diff = abs(target_angle - facing_angle)
		if angle_diff > PI:
			angle_diff = TAU - angle_diff

		# Include if within ~45 degrees of facing (90 degree cone)
		if angle_diff <= PI / 4.0:
			in_cone.append(pos)

	return in_cone

func _find_targets_from_position(player, attack, from_pos: Vector2i) -> Array[Vector2i]:
	"""Find valid targets for attack from a specific position (for preview).

	Args:
		player: Player3D reference (for grid access and facing direction)
		attack: Attack to find targets for
		from_pos: Position to calculate targets from

	Returns:
		Array of entity positions to hit
	"""
	if not player.grid or not player.grid.entity_renderer:
		return []

	var candidates = player.grid.entity_renderer.get_entities_in_range(
		from_pos,
		attack.range_tiles
	)

	if candidates.is_empty():
		return []

	match attack.area:
		_AttackTypes.Area.SINGLE:
			# Return nearest only
			candidates.sort_custom(func(a, b):
				return from_pos.distance_to(a) < from_pos.distance_to(b))
			return [candidates[0]]

		_AttackTypes.Area.AOE_3X3, _AttackTypes.Area.AOE_AROUND:
			# Return all in range
			return candidates

		_AttackTypes.Area.CONE:
			# Return enemies in a cone in player's facing direction
			return _filter_cone_targets_from_position(player, candidates, from_pos)

		_:
			# Default: nearest
			candidates.sort_custom(func(a, b):
				return from_pos.distance_to(a) < from_pos.distance_to(b))
			return [candidates[0]]

func _filter_cone_targets_from_position(player, candidates: Array[Vector2i], from_pos: Vector2i) -> Array[Vector2i]:
	"""Filter candidates to those within a cone in player's facing direction from a position."""
	var in_cone: Array[Vector2i] = []
	var facing = player.get_camera_forward_grid_direction()

	# Convert facing to angle (in radians)
	var facing_angle = atan2(facing.y, facing.x)

	for pos in candidates:
		var delta = pos - from_pos
		if delta == Vector2i.ZERO:
			continue

		# Angle to this target
		var target_angle = atan2(delta.y, delta.x)

		# Angular difference (handle wraparound)
		var angle_diff = abs(target_angle - facing_angle)
		if angle_diff > PI:
			angle_diff = TAU - angle_diff

		# Include if within ~45 degrees of facing (90 degree cone)
		if angle_diff <= PI / 4.0:
			in_cone.append(pos)

	return in_cone

# ============================================================================
# PREVIEW (for UI)
# ============================================================================

func get_attack_preview(player, attack_type: int, from_position: Vector2i = Vector2i(-99999, -99999)) -> Dictionary:
	"""Get preview info for UI (attack stats, targets, ready state).

	Preview shows what will happen NEXT TURN after the player moves.
	Cooldowns tick at the START of each turn, so we preview with cooldown-1.

	Args:
		player: Player3D reference
		attack_type: AttackTypes.Type enum
		from_position: Position to calculate targets from (default: player's current position)

	Returns:
		Dictionary with preview data
	"""
	var pool = _get_pool_for_type(player, attack_type)
	var attack = _build_attack(player, pool, attack_type)

	# Use provided position or fall back to player's current position
	var check_pos = from_position if from_position != Vector2i(-99999, -99999) else player.grid_position

	# Preview shows what happens AFTER cooldown ticks (at start of next turn)
	# So cooldown 1 will be 0 after tick = ready to fire
	var cooldown_after_tick = maxi(0, _cooldowns[attack_type] - 1)

	# Check affordability now and after regen (for preview purposes)
	var can_afford_now = false
	var can_afford_after_regen = false
	var current_mana = 0.0
	var mana_after_regen = 0.0

	if attack and player and player.stats:
		can_afford_now = attack.can_afford(player.stats)
		current_mana = player.stats.current_mana
		mana_after_regen = player.stats.get_mana_after_regen()
		# Can afford after regen if predicted mana >= cost
		can_afford_after_regen = attack.mana_cost <= 0 or mana_after_regen >= attack.mana_cost
	elif attack:
		can_afford_now = attack.mana_cost <= 0
		can_afford_after_regen = attack.mana_cost <= 0

	return {
		"ready": cooldown_after_tick <= 0,
		"cooldown_remaining": cooldown_after_tick,
		"cooldown_total": attack.cooldown if attack else 1,
		"attack_name": attack.attack_name if attack else _AttackTypes.BASE_ATTACK_NAMES[attack_type],
		"attack_emoji": attack.attack_emoji if attack else _AttackTypes.BASE_ATTACK_EMOJIS[attack_type],
		"damage": attack.damage if attack else 0,
		"range": attack.range_tiles if attack else 0,
		"targets": _find_targets_from_position(player, attack, check_pos) if attack else [],
		"can_afford": can_afford_now,
		"can_afford_after_regen": can_afford_after_regen,
		"mana_cost": attack.mana_cost if attack else 0,
		"current_mana": current_mana,
		"mana_after_regen": mana_after_regen,
	}

func _get_pool_for_type(player, attack_type: int) -> ItemPool:
	"""Get the ItemPool for a given attack type."""
	match attack_type:
		_AttackTypes.Type.BODY:
			return player.body_pool
		_AttackTypes.Type.MIND:
			return player.mind_pool
		_AttackTypes.Type.NULL:
			return player.null_pool
	return null

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "AttackExecutor(BODY_cd=%d, MIND_cd=%d, NULL_cd=%d)" % [
		_cooldowns[_AttackTypes.Type.BODY],
		_cooldowns[_AttackTypes.Type.MIND],
		_cooldowns[_AttackTypes.Type.NULL],
	]
