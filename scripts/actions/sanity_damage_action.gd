class_name SanityDamageAction
extends Action
## Preview action showing upcoming sanity damage from environmental pressure
##
## Sanity damage occurs every 13th turn based on:
## - Number of enemies in perception range (weighted by threat level)
## - Current corruption level
##
## This action is display-only for the preview UI - actual damage
## is applied in PreTurnState.

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
# PROPERTIES
# ============================================================================

var sanity_damage: float = 0.0
var turns_until_damage: int = 0
var enemy_count: int = 0
var weighted_enemy_count: int = 0
var corruption: float = 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(p_sanity_damage: float, p_turns_until: int, p_enemy_count: int, p_weighted_count: int, p_corruption: float) -> void:
	action_name = "SanityDamage"
	sanity_damage = p_sanity_damage
	turns_until_damage = p_turns_until
	enemy_count = p_enemy_count
	weighted_enemy_count = p_weighted_count
	corruption = p_corruption

# ============================================================================
# ACTION INTERFACE
# ============================================================================

func can_execute(_player) -> bool:
	return false  # Display-only action

func execute(_player) -> void:
	pass  # Display-only action

func get_preview_info(_player) -> Dictionary:
	if turns_until_damage == 1:
		# Damage happening on the next turn player takes
		return {
			"name": "Sanity Drain",
			"target": "→ -%.1f" % sanity_damage,
			"icon": "🧠",
			"cost": "NEXT TURN"
		}
	else:
		# Warning: damage coming in N turns
		return {
			"name": "Sanity Drain",
			"target": "-%.1f in %d turns" % [sanity_damage, turns_until_damage],
			"icon": "🧠",
			"cost": ""
		}

# ============================================================================
# STATIC HELPERS
# ============================================================================

static func calculate_sanity_damage(player, grid) -> Dictionary:
	"""Calculate sanity damage and related info for preview/application.

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
	# Preview shows what happens AFTER the player takes their next action
	# So from player's current perspective:
	# - If damage happens on next turn: turns_until = 1 (displayed as "NEXT TURN")
	# - If damage happens 1 turn after next: turns_until = 2 (displayed as "in 2 turns")
	var next_turn = player.turn_count + 1  # The turn that will execute when player acts
	var turns_since_last = next_turn % SANITY_DAMAGE_INTERVAL

	if turns_since_last == 0:
		# Damage happens on the next turn player takes
		result["turns_until"] = 1
		result["is_damage_turn"] = true
	else:
		# Calculate turns until next damage event
		# Formula: remaining turns in interval + 1 (to account for "next turn" being turn 1)
		# Example: interval=13, turns_since_last=5 → 13-5+1=9 turns until damage
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
		result["enemy_count"] = entities_in_range.size()

		# Calculate weighted count based on threat levels + entity-specific bonuses
		var weighted_count: int = 0
		for entity_pos in entities_in_range:
			var entity = grid.entity_renderer.get_entity_at(entity_pos)
			if entity:
				# Get threat level from entity type
				var threat_level = _get_threat_level_for_entity(entity.entity_type)
				weighted_count += EntityRegistry.THREAT_WEIGHTS.get(threat_level, 1)

				# Add bonus for psychological horror entities (e.g., Smiler)
				if SANITY_BONUS_ENTITIES.has(entity.entity_type):
					weighted_count += SANITY_BONUS_ENTITIES[entity.entity_type]

		result["weighted_count"] = weighted_count

	# Calculate damage using corruption-scaled formula
	# At 0.01 corruption: base=0, per-enemy=0.2 → 3 enemies = 0.6
	# At 0.1 corruption: base=1, per-enemy=0.8 → 3 enemies = 1 + 2.4 = 3.4
	# Formula: base = corruption * 10, per_enemy = 0.2 + corruption * 6
	var corruption = result["corruption"]
	var base_damage = corruption * 10.0
	var per_enemy_damage = 0.2 + corruption * 6.0
	var damage = base_damage + result["weighted_count"] * per_enemy_damage
	result["damage"] = damage

	return result

static func _get_threat_level_for_entity(entity_type: String) -> int:
	"""Get threat level for an entity type from EntityRegistry.

	Args:
		entity_type: Entity type ID (e.g., "bacteria_spawn")

	Returns:
		Threat level 0-5 (defaults to 1 if not found)
	"""
	if EntityRegistry:
		# EntityRegistry.get_info() returns a Dictionary with threat_level key
		var info = EntityRegistry.get_info(entity_type, 0)  # clearance 0 is fine for threat_level
		if info and info.has("threat_level"):
			return info["threat_level"]

	# Fallback: default to Daleth (weak)
	return 1

static func is_sanity_damage_turn(turn_count: int) -> bool:
	"""Check if a given turn number is a sanity damage turn.

	Args:
		turn_count: Turn number to check (1-indexed for display)

	Returns:
		true if this turn triggers sanity damage
	"""
	return turn_count > 0 and turn_count % SANITY_DAMAGE_INTERVAL == 0
