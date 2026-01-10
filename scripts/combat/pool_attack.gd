class_name PoolAttack extends RefCounted
"""Represents a single pool's attack with all item modifiers applied.

Created by AttackExecutor each turn by aggregating modifiers from equipped items.
This is a transient object - rebuilt each turn, not persisted.

Properties:
- attack_type: Which pool this attack belongs to (BODY/MIND/NULL)
- damage: Final calculated damage (base + modifiers + scaling)
- range_tiles: How far this attack can reach
- cooldown: Turns between attacks (minimum 1)
- area: Targeting pattern (SINGLE, AOE_3X3, etc.)
- mana_cost: Mana required for NULL attacks
- special_effects: Array of effect callbacks from items
"""

# Preload dependencies
const _AttackTypes = preload("res://scripts/combat/attack_types.gd")

# ============================================================================
# ATTACK PROPERTIES
# ============================================================================

var attack_type: int = 0  # _AttackTypes.Type.BODY (set in _init)
var attack_name: String = ""  # Display name (can be overridden by items)
var attack_emoji: String = ""  # Emoji for UI and VFX (can be overridden by items)
var damage: float = 0.0
var range_tiles: float = 1.0
var cooldown: int = 1
var area: int = 0  # _AttackTypes.Area.SINGLE (set in _init)
var mana_cost: float = 0.0
var special_effects: Array = []

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(type: int) -> void:
	"""Initialize with base stats for attack type.

	Args:
		type: AttackTypes.Type enum value
	"""
	attack_type = type

	# Set defaults from base stats
	attack_name = _AttackTypes.BASE_ATTACK_NAMES[type]
	attack_emoji = _AttackTypes.BASE_ATTACK_EMOJIS[type]
	damage = _AttackTypes.BASE_DAMAGE[type]
	range_tiles = _AttackTypes.BASE_RANGE[type]
	cooldown = _AttackTypes.BASE_COOLDOWN[type]
	area = _AttackTypes.BASE_AREA[type]
	mana_cost = _AttackTypes.BASE_MANA_COST[type]

# ============================================================================
# COST CHECKS
# ============================================================================

func can_afford(player_stats) -> bool:
	"""Check if player can afford the mana cost.

	Args:
		player_stats: StatBlock reference

	Returns:
		true if mana cost is 0 or player has enough mana
	"""
	if mana_cost <= 0:
		return true
	if not player_stats:
		return false
	return player_stats.current_mana >= mana_cost

func pay_cost(player_stats) -> bool:
	"""Consume mana cost from player.

	Args:
		player_stats: StatBlock reference

	Returns:
		true if cost was paid successfully
	"""
	if mana_cost <= 0:
		return true
	if not player_stats:
		return false
	return player_stats.consume_mana(mana_cost)

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	var type_name = _AttackTypes.TYPE_NAMES.get(attack_type, "UNKNOWN")
	return "PoolAttack(%s, dmg=%.1f, range=%.1f, cd=%d, area=%d, mana=%.1f)" % [
		type_name,
		damage,
		range_tiles,
		cooldown,
		area,
		mana_cost
	]
