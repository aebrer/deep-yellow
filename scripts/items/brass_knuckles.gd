class_name BrassKnuckles extends Item
"""Brass Knuckles - Classic melee power item.

Properties (scale with level N):
- +N extra attack per turn (attack 1+N times when BODY attack fires)
- +5% per level improved strength scaling (stacks with base 10%)

Example Scaling:
- Level 1: 2 attacks/turn, +15% damage per STR (base 10% + 5%)
- Level 2: 3 attacks/turn, +20% damage per STR
- Level 3: 4 attacks/turn, +25% damage per STR

Design Intent:
- Core BODY item that rewards stacking
- Extra attacks multiply effectiveness dramatically
- Strength scaling bonus makes STR stat more valuable
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "brass_knuckles"
const ITEM_NAME = "Brass Knuckles"
const POOL = Item.PoolType.BODY
const RARITY_TYPE = ItemRarity.Tier.RARE

# Extra attacks per level
const EXTRA_ATTACKS_PER_LEVEL = 1

# Strength scaling bonus per level (adds to base 10% per STR)
# At level 1: 10% + 5% = 15% per STR
# At level 2: 10% + 10% = 20% per STR
const STRENGTH_SCALING_BONUS_PER_LEVEL = 0.05

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/brass_knuckles.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Brass Knuckles with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A pair of heavy metal knuckles, worn smooth from use. The brass gleams dully under fluorescent lights."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Extra attacks and strength bonus increase with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# ATTACK MODIFIERS
# ============================================================================

func get_attack_modifiers() -> Dictionary:
	"""Return attack modifiers for BODY pool.

	- extra_attacks: +N per level (attack multiple times per turn)
	- damage_multiply: Simulates improved STR scaling
	  The base scaling is 10% per STR. We add 5% per level.
	  This is implemented as a damage multiplier based on current STR.
	"""
	return {
		"attack_name": "Brass Knuckles",
		"attack_emoji": "🥊",
		"extra_attacks": level * EXTRA_ATTACKS_PER_LEVEL,
		# Note: True STR scaling improvement requires access to player stats
		# For now, we add flat damage that scales with level
		"damage_add": float(level * 2),  # +2 damage per level as proxy
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
	desc += "\nDesignation: Improvised Melee Enhancer"
	desc += "\nProperties: Increases attack frequency"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		desc += "\n\nMechanics:"
		desc += "\n- Extra attacks per turn: +%d" % (level * EXTRA_ATTACKS_PER_LEVEL)
		desc += "\n- Bonus damage: +%d" % (level * 2)
		desc += "\n- Total attacks when BODY fires: %d" % (1 + level * EXTRA_ATTACKS_PER_LEVEL)

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: BrassKnuckles extends Item"
		desc += "\npool: BODY"
		desc += "\n\nget_attack_modifiers():"
		desc += "\n  return {"
		desc += "\n    \"extra_attacks\": level,"
		desc += "\n    \"damage_add\": level * 2,"
		desc += "\n  }"

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	return "BrassKnuckles(Level %d, +%d attacks, %s)" % [
		level,
		level * EXTRA_ATTACKS_PER_LEVEL,
		"Equipped" if equipped else "Ground"
	]
