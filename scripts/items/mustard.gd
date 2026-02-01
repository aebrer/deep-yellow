class_name Mustard extends Item
"""Mustard - Tutorial NULL item.

One-time boost: +5 NULL on equip.
Tutorial-only — never appears outside Level -1.

Design Intent:
- Introduces the NULL pool to the player
- Rarest tutorial item (RARE) — the lucky find
- Seems completely normal at low clearance
- Gets increasingly weird at higher clearance
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "mustard"
const ITEM_NAME = "Mustard"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = ItemRarity.Tier.RARE

# Flat stat boost (achieved by setting level = 5)
const STAT_BOOST = 5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/mustard.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Mustard with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE
	level = STAT_BOOST  # Base class _apply_stat_bonus grants +level to NULL

	# Visual description (CONSTANT - always shown)
	visual_description = "A yellow squeeze bottle of mustard. French's Classic Yellow. Looks perfectly ordinary."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "One-time NULL boost"

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

	# Clearance 2+: Seems normal
	desc += "\nDesignation: Condiment (Standard)"
	desc += "\nProperties: None detected"
	desc += "\nStatus: Unremarkable"

	# Clearance 3+: Getting weird
	if clearance_level >= 3:
		desc += "\n\nMechanics:"
		desc += "\n- On equip: +%d NULL" % STAT_BOOST
		desc += "\n- Tutorial item (Level -1 only)"
		desc += "\n\nYup, turns out mustard was magic, huh."

	# Clearance 4+: Code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: Mustard extends Item"
		desc += "\npool: NULL"
		desc += "\nrarity: RARE"
		desc += "\nlevel: %d (flat boost, no scaling)" % STAT_BOOST
		desc += "\n\n# Favorite condiment of the King in Yellow."

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	return "Mustard(+%d NULL, %s)" % [
		STAT_BOOST,
		"Equipped" if equipped else "Ground"
	]
