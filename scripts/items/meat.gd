class_name Meat extends Item
"""Meat - Tutorial BODY item.

One-time boost: +5 BODY on equip.
Tutorial-only — never appears outside Level -1.

Design Intent:
- Introduces the BODY pool to the player
- Most common tutorial item (COMMON rarity)
- Simple, immediate power boost with no ongoing effects
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "meat"
const ITEM_NAME = "Meat"
const POOL = Item.PoolType.BODY
const RARITY_TYPE = ItemRarity.Tier.COMMON

# Flat stat boost (achieved by setting level = 5)
const STAT_BOOST = 5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/meat.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Meat with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE
	level = STAT_BOOST  # Base class _apply_stat_bonus grants +level to BODY

	# Visual description (CONSTANT - always shown)
	visual_description = "A thick slab of raw meat, wrapped in butcher paper. Still cold. Smells faintly of iron and salt."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "One-time BODY boost"

	# Load sprite texture
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# DESCRIPTIONS
# ============================================================================

func get_description(clearance_level: int) -> String:
	"""Get description that ADDITIVELY reveals info based on clearance level."""
	var desc = super.get_description(clearance_level)

	if clearance_level < 2:
		return desc

	# Clearance 2+: Basic behavior
	desc += "\nDesignation: Rations (Protein)"
	desc += "\nProperties: Dense caloric content"

	# Clearance 3+: Specific mechanics
	if clearance_level >= 3:
		desc += "\n\nMechanics:"
		desc += "\n- On equip: +%d BODY" % STAT_BOOST
		desc += "\n- Tutorial item (Level -1 only)"

	# Clearance 4+: Code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: Meat extends Item"
		desc += "\npool: BODY"
		desc += "\nrarity: COMMON"
		desc += "\nlevel: %d (flat boost, no scaling)" % STAT_BOOST

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	return "Meat(+%d BODY, %s)" % [
		STAT_BOOST,
		"Equipped" if equipped else "Ground"
	]
