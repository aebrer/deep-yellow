class_name Shovel extends Item
"""Shovel - Sweeping BODY attack with item spawn rate bonus.

Properties (scale with level N):
- Changes BODY attack to "Shovel Hit" (physical)
- Sweeping attack: hits target + perpendicular neighbors
- Item spawn rate bonus: +5% base, +1% per level after first
- Standard BODY stat bonus (+N BODY)

Example Scaling:
- Level 1: SWEEP attack, +5% item spawn rate, +1 BODY
- Level 2: SWEEP attack, +6% item spawn rate, +2 BODY
- Level 3: SWEEP attack, +7% item spawn rate, +3 BODY

Design Intent:
- Utility item that helps with both combat and loot
- Sweeping attack rewards positioning against groups
- Item spawn rate bonus encourages exploration
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "shovel"
const ITEM_NAME = "Shovel"
const POOL = Item.PoolType.BODY
const RARITY_TYPE = ItemRarity.Tier.UNCOMMON

# Item spawn rate bonus: +5% base, +1% per level after first
const SPAWN_RATE_BASE = 0.05  # +5% at level 1
const SPAWN_RATE_PER_LEVEL = 0.01  # +1% per level after first

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/shovel.png"

# Preload attack types for area enum
const _AttackTypes = preload("res://scripts/combat/attack_types.gd")

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Shovel with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A well-worn gardening shovel with a wooden handle and rusted metal blade. Surprisingly sturdy despite its age. Someone scratched tally marks into the handle."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Item discovery chance increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# ATTACK MODIFIERS
# ============================================================================

func get_attack_modifiers() -> Dictionary:
	"""Transform BODY attack into sweeping shovel hit."""
	return {
		# Change to sweep pattern (target + perpendicular neighbors)
		"area": _AttackTypes.Area.SWEEP,

		# Rename the attack
		"attack_name": "Shovel Hit",
		"attack_emoji": "🪓",  # Closest emoji to a shovel swing
	}

# ============================================================================
# PASSIVE MODIFIERS
# ============================================================================

func get_passive_modifiers() -> Dictionary:
	"""Provide item spawn rate bonus: +5% base, +1% per level after first."""
	# Level 1: 5%, Level 2: 6%, Level 3: 7%, etc.
	var spawn_bonus = SPAWN_RATE_BASE + SPAWN_RATE_PER_LEVEL * (level - 1)

	return {
		"item_spawn_rate_add": spawn_bonus,
	}

# ============================================================================
# DESCRIPTIONS
# ============================================================================

func get_description(clearance_level: int) -> String:
	"""Get description that ADDITIVELY reveals info based on clearance level."""
	# Start with base description (visual + scaling hint)
	var desc = super.get_description(clearance_level)

	# Clearance 0-1: Just the basics (no additional info)
	if clearance_level < 2:
		return desc

	# Clearance 2+: Add designation and basic behavior
	desc += "\nDesignation: Multi-Purpose Tool"
	desc += "\nProperties: Wide swing pattern, improves item discovery"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var spawn_bonus = (SPAWN_RATE_BASE + SPAWN_RATE_PER_LEVEL * (level - 1)) * 100  # Convert to percentage
		desc += "\n\nMechanics:"
		desc += "\n- Transforms Punch → Shovel Hit"
		desc += "\n- Attack pattern: Sweeping (hits target + neighbors)"
		desc += "\n- Item spawn rate: +%.0f%%" % spawn_bonus
		desc += "\n- Also grants +%d BODY" % level

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: Shovel extends Item"
		desc += "\npool: BODY, rarity: UNCOMMON"
		desc += "\n\nget_attack_modifiers():"
		desc += "\n  area: SWEEP"
		desc += "\n\nget_passive_modifiers():"
		desc += "\n  item_spawn_rate_add: %.0f%% + %.0f%% * (level-1)" % [SPAWN_RATE_BASE * 100, SPAWN_RATE_PER_LEVEL * 100]

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var spawn_bonus = (SPAWN_RATE_BASE + SPAWN_RATE_PER_LEVEL * (level - 1)) * 100
	return "Shovel(Level %d, +%.0f%% spawn rate, %s)" % [
		level,
		spawn_bonus,
		"Equipped" if equipped else "Ground"
	]
