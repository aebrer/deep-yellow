class_name AttackExecutor extends RefCounted
"""Builds and executes pool attacks each turn.

The AttackExecutor:
1. Tracks cooldowns per attack type (BODY/MIND/NULL)
2. Each turn, ticks cooldowns and checks which attacks are ready
3. For ready attacks: builds attack from pool items → finds targets → executes

CRITICAL: This is an AUTO-BATTLER. Player has NO agency over attack direction.
- Attacks automatically find and target enemies
- Camera direction is NEVER used for targeting
- Cone attacks aim toward the nearest enemy, then hit all enemies in that cone
- SINGLE attacks hit the nearest enemy in range
- AOE attacks hit all enemies in range
The player's camera position is purely cosmetic and irrelevant to combat mechanics.

Items provide modifiers via get_attack_modifiers() method.
Modifiers are aggregated: ADD first, then MULTIPLY.

Damage scaling:
- BODY attacks scale with STRENGTH (derived from BODY stat)
- MIND attacks scale with PERCEPTION (derived from MIND stat)
- NULL attacks scale with ANOMALY (derived from NULL stat) and cost mana

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
	Items can grant extra_attacks to make pools attack multiple times per turn.

	Args:
		player: Player3D reference (untyped to avoid circular dependency)
	"""
	# Tick all cooldowns first
	for type in _cooldowns.keys():
		if _cooldowns[type] > 0:
			_cooldowns[type] -= 1

	# Execute BODY attack (always available - base punch)
	_execute_pool_attacks(player, player.body_pool, _AttackTypes.Type.BODY)

	# Execute MIND attack (always available - base whistle)
	_execute_pool_attacks(player, player.mind_pool, _AttackTypes.Type.MIND)

	# Execute NULL attack (only if player has mana)
	_execute_pool_attacks(player, player.null_pool, _AttackTypes.Type.NULL)


func _execute_pool_attacks(player, pool, attack_type: int) -> void:
	"""Execute all attacks for a pool, including extra attacks from items.

	Args:
		player: Player3D reference
		pool: ItemPool for this attack type
		attack_type: AttackTypes.Type enum
	"""
	if _cooldowns[attack_type] > 0:
		return

	var attack = _build_attack(player, pool, attack_type)
	if not attack:
		return

	# Calculate total attacks: 1 base + extra_attacks from items
	var total_attacks = 1 + attack.extra_attacks

	# Execute each attack
	var any_hit = false
	for i in range(total_attacks):
		if _execute_attack(player, attack):
			any_hit = true

	# Reset cooldown if any attack connected
	if any_hit:
		_cooldowns[attack_type] = attack.cooldown

# ============================================================================
# ATTACK BUILDING
# ============================================================================

func _build_attack(player, pool: ItemPool, attack_type: int):
	"""Build attack from pool's equipped items.

	Aggregates modifiers from all enabled items:
	1. Start with base stats for attack type
	2. Add flat modifiers (damage_add, range_add, cooldown_add)
	3. Multiply by multipliers (damage_multiply, mana_cost_multiply)
	4. Apply stat scaling: damage *= (1.0 + stat_value * rate)
	   - BODY → STRENGTH (+10% per point)
	   - MIND → PERCEPTION (+20% per point)
	   - NULL → ANOMALY (+50% per point)
	5. Banker's rounding (round half to even, like Python)

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
	var extra_attacks: int = 0
	var tag_damage_multipliers: Dictionary = {}  # tag -> multiplier (collected from ALL pools!)
	var tags_to_add: Array[String] = []
	var tags_to_remove: Array[String] = []

	# First pass: collect pool-specific modifiers from this attack's pool only
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
				extra_attacks += mods.get("extra_attacks", 0)

				# Tag manipulation: add tags to attack (e.g., "Siren's Lungs" adds "sound")
				if mods.has("add_tags"):
					for tag in mods["add_tags"]:
						if tag not in tags_to_add:
							tags_to_add.append(tag)

				# Tag manipulation: remove tags from attack (for transformative items)
				if mods.has("remove_tags"):
					for tag in mods["remove_tags"]:
						if tag not in tags_to_remove:
							tags_to_remove.append(tag)

				# NOTE: tag_damage_multiply is collected from ALL pools in second pass below

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

	# Apply tag modifications (remove first, then add)
	for tag in tags_to_remove:
		attack.tags.erase(tag)
	for tag in tags_to_add:
		if tag not in attack.tags:
			attack.tags.append(tag)

	# Second pass: collect tag_damage_multiply from ALL pools
	# This enables cross-pool synergies like Coach's Whistle (MIND) boosting
	# Siren's Cords (BODY) when it adds the "sound" tag
	if player:
		var all_pools = [player.body_pool, player.mind_pool, player.null_pool]
		for p in all_pools:
			if not p:
				continue
			for i in range(p.max_slots):
				var item = p.items[i]
				var is_enabled = p.enabled[i]
				if item and is_enabled:
					var mods = item.get_attack_modifiers()
					if mods.has("tag_damage_multiply"):
						var tag_mults = mods["tag_damage_multiply"]
						for tag in tag_mults:
							if tag_damage_multipliers.has(tag):
								tag_damage_multipliers[tag] *= tag_mults[tag]
							else:
								tag_damage_multipliers[tag] = tag_mults[tag]

	# Apply modifiers to base stats
	attack.damage = (attack.damage + damage_add) * damage_multiply

	# Apply tag-based damage multipliers (after tag modifications!)
	for tag in attack.tags:
		if tag_damage_multipliers.has(tag):
			attack.damage *= tag_damage_multipliers[tag]
	attack.range_tiles = attack.range_tiles + range_add
	attack.cooldown = maxi(1, attack.cooldown + cooldown_add)  # Minimum 1 turn
	attack.mana_cost = attack.mana_cost * mana_cost_multiply
	attack.extra_attacks = extra_attacks  # Additional attacks per turn

	# Apply stat scaling (STRENGTH/PERCEPTION/ANOMALY)
	if player and player.stats:
		var scaling_stat = _AttackTypes.SCALING_STAT[attack_type]
		var scaling_rate = _AttackTypes.SCALING_RATE[attack_type]
		var stat_value: float = 0.0

		# Get the scaling stat value
		match scaling_stat:
			"strength":
				stat_value = player.stats.strength
			"perception":
				stat_value = player.stats.perception
			"anomaly":
				stat_value = player.stats.anomaly

		# Formula: damage *= (1.0 + stat_value * scaling_rate)
		# BODY: +10% per STR, MIND: +20% per PER, NULL: +50% per ANOM
		attack.damage *= (1.0 + stat_value * scaling_rate)

	# Banker's rounding (round half to even) - unbiased like Python's round()
	attack.damage = Utilities.bankers_round(attack.damage)

	return attack

# ============================================================================
# ATTACK EXECUTION
# ============================================================================

func _execute_attack(player, attack) -> bool:
	"""Execute attack against valid targets.

	Targets WorldEntity directly for damage (authoritative state).
	Uses EntityRenderer only for VFX (spawn_hit_vfx).

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

	# Apply damage to targets via WorldEntity (authoritative state)
	for target_pos in targets:
		var entity = player.grid.get_entity_at(target_pos)
		if entity and entity.is_alive():
			# Apply damage to WorldEntity (emits signals for health bar / death VFX)
			entity.take_damage(attack.damage)

			# Spawn hit VFX via renderer (render-only)
			player.grid.entity_renderer.spawn_hit_vfx(target_pos, attack.attack_emoji, attack.damage)

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

	# Filter by line of sight (walls block attacks, enemies don't)
	candidates = _filter_by_line_of_sight(player.grid, player.grid_position, candidates)

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

		_AttackTypes.Area.SWEEP:
			# Target nearest + perpendicular neighbors (shovel swing)
			return _filter_sweep_targets(player.grid_position, candidates)

		_:
			# Default: nearest
			candidates.sort_custom(func(a, b):
				return player.grid_position.distance_to(a) < player.grid_position.distance_to(b))
			return [candidates[0]]

func _filter_cone_targets(player, candidates: Array[Vector2i]) -> Array[Vector2i]:
	"""Filter candidates to those within a cone aimed at the nearest enemy.

	Auto-battler behavior: cone automatically aims toward the nearest enemy,
	then includes all enemies within 45 degrees of that direction.
	Player camera direction is irrelevant - attacks target automatically.

	Delegates to _filter_cone_targets_from_position with player's current position.
	"""
	return _filter_cone_targets_from_position(candidates, player.grid_position)

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

	# Filter by line of sight (walls block attacks, enemies don't)
	candidates = _filter_by_line_of_sight(player.grid, from_pos, candidates)

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
			# Return enemies in a cone aimed at nearest enemy
			return _filter_cone_targets_from_position(candidates, from_pos)

		_AttackTypes.Area.SWEEP:
			# Target nearest + perpendicular neighbors (shovel swing)
			return _filter_sweep_targets(from_pos, candidates)

		_:
			# Default: nearest
			candidates.sort_custom(func(a, b):
				return from_pos.distance_to(a) < from_pos.distance_to(b))
			return [candidates[0]]

func _filter_cone_targets_from_position(candidates: Array[Vector2i], from_pos: Vector2i) -> Array[Vector2i]:
	"""Filter candidates to those within a cone aimed at nearest enemy from a position.

	Auto-battler behavior: cone automatically aims toward the nearest enemy,
	NOT based on camera direction. Player has no agency over attack direction.

	Args:
		candidates: Array of potential target positions
		from_pos: Position to calculate cone from

	Returns:
		Array of positions within the cone
	"""
	if candidates.is_empty():
		return []

	# Find nearest enemy to determine cone direction
	var nearest_pos = candidates[0]
	var nearest_dist = from_pos.distance_to(nearest_pos)
	for pos in candidates:
		var dist = from_pos.distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = pos

	# Cone aims toward the nearest enemy
	var cone_delta = nearest_pos - from_pos
	if cone_delta == Vector2i.ZERO:
		return [nearest_pos]  # Edge case: enemy on same tile

	var cone_angle = atan2(cone_delta.y, cone_delta.x)

	# Include all enemies within 45 degrees of the cone direction
	var in_cone: Array[Vector2i] = []
	for pos in candidates:
		var delta = pos - from_pos
		if delta == Vector2i.ZERO:
			in_cone.append(pos)
			continue

		var target_angle = atan2(delta.y, delta.x)

		# Angular difference (handle wraparound)
		var angle_diff = abs(target_angle - cone_angle)
		if angle_diff > PI:
			angle_diff = TAU - angle_diff

		# Include if within ~45 degrees of cone direction (90 degree cone)
		if angle_diff <= PI / 4.0:
			in_cone.append(pos)

	return in_cone


func _filter_sweep_targets(from_pos: Vector2i, candidates: Array[Vector2i]) -> Array[Vector2i]:
	"""Filter candidates to those hit by a sweeping attack (target + perpendicular neighbors).

	The shovel swing pattern:
	1. Find the nearest enemy (primary target)
	2. Calculate the direction from player to target
	3. Include any enemies on the two tiles perpendicular to that direction

	Example: If player is at (0,0) and target is at (1,0) (east):
	- Primary target: (1,0)
	- Perpendicular tiles: (1,-1) and (1,1) (north and south of target)

	Args:
		from_pos: Player position
		candidates: Array of potential target positions (already filtered by range/LOS)

	Returns:
		Array of positions hit by the sweep (primary + perpendicular neighbors)
	"""
	if candidates.is_empty():
		return []

	# Find nearest enemy (primary target)
	var nearest_pos = candidates[0]
	var nearest_dist = from_pos.distance_to(nearest_pos)
	for pos in candidates:
		var dist = from_pos.distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = pos

	# Calculate direction from player to target
	var delta = nearest_pos - from_pos
	if delta == Vector2i.ZERO:
		return [nearest_pos]  # Edge case: on same tile

	# Perpendicular directions: rotate 90 degrees
	# If delta is (dx, dy), perpendicular is (-dy, dx) and (dy, -dx)
	var perp1 = Vector2i(-delta.y, delta.x)
	var perp2 = Vector2i(delta.y, -delta.x)

	# Normalize to unit length (for adjacent tile check)
	if perp1.x != 0:
		perp1.x = perp1.x / abs(perp1.x)
	if perp1.y != 0:
		perp1.y = perp1.y / abs(perp1.y)
	if perp2.x != 0:
		perp2.x = perp2.x / abs(perp2.x)
	if perp2.y != 0:
		perp2.y = perp2.y / abs(perp2.y)

	# Perpendicular tile positions (adjacent to target, not player)
	var sweep_pos1 = nearest_pos + perp1
	var sweep_pos2 = nearest_pos + perp2

	# Collect all positions that are hit
	var hit_positions: Array[Vector2i] = [nearest_pos]

	# Check if any candidates are on the perpendicular tiles
	for pos in candidates:
		if pos == nearest_pos:
			continue
		if pos == sweep_pos1 or pos == sweep_pos2:
			hit_positions.append(pos)

	return hit_positions


func _filter_by_line_of_sight(grid, from_pos: Vector2i, candidates: Array[Vector2i]) -> Array[Vector2i]:
	"""Filter target candidates to only those with clear line of sight.

	Walls block attacks (no shooting through walls).
	Enemies do NOT block attacks (AOE can hit multiple enemies in a row).

	Args:
		grid: Grid3D reference for LOS checks
		from_pos: Position attacking from (player position)
		candidates: Array of potential target positions

	Returns:
		Filtered array containing only targets with clear LOS
	"""
	var visible: Array[Vector2i] = []

	for target_pos in candidates:
		if grid.has_line_of_sight(from_pos, target_pos):
			visible.append(target_pos)

	return visible

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
		"extra_attacks": attack.extra_attacks if attack else 0,
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
