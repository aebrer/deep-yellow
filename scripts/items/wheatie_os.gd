class_name WheatieOs extends Item
"""Wheatie-O's Cereal - Nutritious BODY stat boost.

Properties (scale with level N):
- +2 BODY stat per level (double normal item bonus)

Example Scaling:
- Level 1: +2 BODY
- Level 2: +4 BODY
- Level 3: +6 BODY

Design Intent:
- Pure stat booster for BODY pool
- Provides significant HP and strength scaling
- Simple but effective "breakfast of champions" item
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "wheatie_os"
const ITEM_NAME = "Wheatie-O's"
const POOL = Item.PoolType.BODY
const RARITY_TYPE = ItemRarity.Tier.COMMON

# BODY bonus per level (double normal item bonus)
const BODY_PER_LEVEL = 2

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/wheatie_os.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Wheatie-O's with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A crumpled box of Wheatie-O's breakfast cereal. The mascot - a muscular wheat stalk - grins from the faded packaging. 'Part of a Complete Breakfast!' the tagline reads."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "BODY bonus increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# STAT BONUS (Override)
# ============================================================================

func _apply_stat_bonus(player: Player3D) -> void:
	"""Apply enhanced BODY stat bonus (+2 per level instead of +1)."""
	if not player or not player.stats:
		return

	player.stats.body += BODY_PER_LEVEL * level

func _remove_stat_bonus(player: Player3D) -> void:
	"""Remove enhanced BODY stat bonus."""
	if not player or not player.stats:
		return

	player.stats.body -= BODY_PER_LEVEL * level

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
	desc += "\nDesignation: Nutritional Supplement"
	desc += "\nProperties: Enhances physical constitution"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var total_bonus = BODY_PER_LEVEL * level
		desc += "\n\nMechanics:"
		desc += "\n- BODY stat bonus: +%d" % total_bonus
		desc += "\n- Affects max HP and strength"

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: WheatieOs extends Item"
		desc += "\npool: BODY"
		desc += "\n\n_apply_stat_bonus():"
		desc += "\n  player.stats.body += %d * level" % BODY_PER_LEVEL

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var total_bonus = BODY_PER_LEVEL * level
	return "WheatieOs(Level %d, +%d BODY, %s)" % [
		level,
		total_bonus,
		"Equipped" if equipped else "Ground"
	]
