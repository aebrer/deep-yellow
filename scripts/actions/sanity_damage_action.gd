class_name SanityDamageAction
extends RefCounted
## Static utility for sanity damage calculations
##
## Sanity damage occurs every 13th turn based on:
## - Number of enemies in perception range (weighted by threat level)
## - Current corruption level
##
## Used by PreTurnState to determine when and how much sanity damage to apply.

# ============================================================================
# CONSTANTS
# ============================================================================

## Turn interval for sanity damage (every Nth turn)
const SANITY_DAMAGE_INTERVAL: int = 13

## Base sanity damage
const BASE_SANITY_DAMAGE: float = 1.0

## Entity types with bonus sanity damage (psychological horror enemies)
## These are added ON TOP of their threat level weight
const SANITY_BONUS_ENTITIES: Dictionary = {
	"smiler": 5,  # Smiler causes extra psychological damage just by existing nearby
}

# ============================================================================
# STATIC HELPERS
# ============================================================================

static func calculate_sanity_damage(player, grid) -> Dictionary:
	"""Calculate sanity damage and related info.

	Args:
		player: Player reference (for position, stats, turn count)
		grid: Grid reference (for entity queries)

	Returns:
		Dictionary with:
		- damage: float - sanity damage amount
		- turns_until: int - turns until next damage (0 = this turn)
		- enemy_count: int - raw number of enemies in range
		- weighted_count: int - threat-weighted enemy count
		- corruption: float - current corruption level
		- is_damage_turn: bool - whether this is a damage turn
	"""
	var result = {
		"damage": 0.0,
		"turns_until": 0,
		"enemy_count": 0,
		"weighted_count": 0,
		"corruption": 0.0,
		"is_damage_turn": false
	}

	if not player or not grid:
		return result

	# Calculate turns until next sanity damage
	# Turn count is 0-indexed, damage on turns 13, 26, 39, etc.
	var next_turn = player.turn_count + 1
	var turns_since_last = next_turn % SANITY_DAMAGE_INTERVAL

	if turns_since_last == 0:
		result["turns_until"] = 1
		result["is_damage_turn"] = true
	else:
		var turns_remaining_in_interval = SANITY_DAMAGE_INTERVAL - turns_since_last
		result["turns_until"] = turns_remaining_in_interval + 1
		result["is_damage_turn"] = false

	# Get perception range (same as minimap uses)
	var perception_range: float = 15.0
	if player.stats:
		perception_range = 15.0 + (player.stats.perception * 5.0)

	# Get corruption level
	if ChunkManager and ChunkManager.corruption_tracker:
		var level_id = 0  # TODO: Get actual level ID when multi-level is implemented
		result["corruption"] = ChunkManager.corruption_tracker.get_corruption(level_id)

	# Count enemies in perception range with threat weighting
	if grid.entity_renderer:
		var entities_in_range = grid.entity_renderer.get_entities_in_range(player.grid_position, perception_range)

		# Calculate weighted count based on threat levels + entity-specific bonuses
		# Only hostile entities contribute to sanity damage
		var hostile_count: int = 0
		var weighted_count: int = 0
		for entity_pos in entities_in_range:
			var entity = grid.entity_renderer.get_entity_at(entity_pos)
			if entity and entity.hostile:
				hostile_count += 1
				var threat_level = _get_threat_level_for_entity(entity.entity_type)
				weighted_count += EntityRegistry.THREAT_WEIGHTS.get(threat_level, 1)

				# Add bonus for psychological horror entities (e.g., Smiler)
				if SANITY_BONUS_ENTITIES.has(entity.entity_type):
					weighted_count += SANITY_BONUS_ENTITIES[entity.entity_type]

		result["enemy_count"] = hostile_count
		result["weighted_count"] = weighted_count

	# Calculate damage using corruption-scaled formula
	# At 0.01 corruption: base=0, per-enemy=0.2 → 3 enemies = 0.6
	# At 0.5 corruption: base=2.5, per-enemy=1.7 → 3 enemies = 2.5 + 5.1 = 7.6
	# At 1.0 corruption: base=5, per-enemy=3.2 → 3 enemies = 5 + 9.6 = 14.6
	var corruption = result["corruption"]
	var base_damage = corruption * 5.0
	var per_enemy_damage = 0.2 + corruption * 3.0
	var damage = base_damage + result["weighted_count"] * per_enemy_damage
	result["damage"] = damage

	return result

static func _get_threat_level_for_entity(entity_type: String) -> int:
	"""Get threat level for an entity type from EntityRegistry."""
	if EntityRegistry:
		var info = EntityRegistry.get_info(entity_type, 0)
		if info and info.has("threat_level"):
			return info["threat_level"]
	return 1

static func is_sanity_damage_turn(turn_count: int) -> bool:
	"""Check if a given turn number is a sanity damage turn."""
	return turn_count > 0 and turn_count % SANITY_DAMAGE_INTERVAL == 0
