class_name Vegetables extends Item
"""Vegetables - Tutorial MIND item.

One-time boost: +5 MIND on equip.
Tutorial-only — never appears outside Level -1.

Design Intent:
- Introduces the MIND pool to the player
- Medium rarity tutorial item (UNCOMMON)
- Affects mind attack damage, max sanity, and perception/map reveal
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "vegetables"
const ITEM_NAME = "Vegetables"
const POOL = Item.PoolType.MIND
const RARITY_TYPE = ItemRarity.Tier.UNCOMMON

# Flat stat boost (achieved by setting level = 5)
const STAT_BOOST = 5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/vegetables.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Vegetables with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE
	level = STAT_BOOST  # Base class _apply_stat_bonus grants +level to MIND

	# Visual description (CONSTANT - always shown)
	visual_description = "A brown paper bag of assorted vegetables. Carrots, celery, a tomato, and what might be a parsnip. Surprisingly fresh."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "One-time MIND boost"

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
	desc += "\nDesignation: Rations (Produce)"
	desc += "\nProperties: Nutritionally dense organic matter"
	desc += "\nNote: \"Vegetable\" is a culinary term, not a botanical one. A tomato is both a berry and a vegetable. A strawberry is neither."

	# Clearance 3+: Specific mechanics
	if clearance_level >= 3:
		desc += "\n\nMechanics:"
		desc += "\n- On equip: +%d MIND" % STAT_BOOST
		desc += "\n- Affects: mind attack damage, max sanity, perception"
		desc += "\n- Tutorial item (Level -1 only)"

	# Clearance 4+: Code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: Vegetables extends Item"
		desc += "\npool: MIND"
		desc += "\nrarity: UNCOMMON"
		desc += "\nlevel: %d (flat boost, no scaling)" % STAT_BOOST
		desc += "\n\n# Botanically, \"vegetable\" means nothing."
		desc += "\n# It's a word we made up to describe plants we eat"
		desc += "\n# that aren't sweet enough to call fruit."

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	return "Vegetables(+%d MIND, %s)" % [
		STAT_BOOST,
		"Equipped" if equipped else "Ground"
	]
