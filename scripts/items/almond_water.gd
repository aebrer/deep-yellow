class_name AlmondWater extends Item
"""Almond Water - Iconic Backrooms restorative item.

Properties (scale with level N):
- +0.5% Sanity regen per turn per level
- Standard MIND stat bonus (+N MIND)

Example Scaling:
- Level 1: +0.5% Sanity regen/turn, +1 MIND
- Level 2: +1.0% Sanity regen/turn, +2 MIND
- Level 3: +1.5% Sanity regen/turn, +3 MIND

Design Intent:
- Core MIND sustain item (parallels Trail Mix for BODY)
- Provides passive sanity recovery to counter environmental drain
- Essential for long exploration runs
- Classic Backrooms lore item
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "almond_water"
const ITEM_NAME = "Almond Water"
const POOL = Item.PoolType.MIND
const RARITY_TYPE = ItemRarity.Tier.RARE

# Sanity regen bonus per level (0.5% per level)
const SANITY_REGEN_PER_LEVEL = 0.5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/almond_water.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Almond Water with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A plastic bottle of slightly cloudy water with a faint almond scent. The label is missing, but someone wrote 'SAFE' on it in permanent marker. Tastes like hope."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Sanity regeneration increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# EQUIP/UNEQUIP (Override for Sanity regen modifier)
# ============================================================================

func on_equip(player: Player3D) -> void:
	"""Apply Sanity regen bonus when equipped."""
	super.on_equip(player)  # Apply base stat bonus (+N MIND)

	# Add Sanity regen modifier
	var regen_bonus = SANITY_REGEN_PER_LEVEL * level
	player.stats.sanity_regen_percent += regen_bonus

	Log.player("ALMOND_WATER equipped: +%.1f%% Sanity regen/turn" % regen_bonus)

func on_unequip(player: Player3D) -> void:
	"""Remove Sanity regen bonus when unequipped."""
	super.on_unequip(player)  # Remove base stat bonus

	# Remove Sanity regen modifier
	var regen_bonus = SANITY_REGEN_PER_LEVEL * level
	player.stats.sanity_regen_percent -= regen_bonus

	Log.player("ALMOND_WATER unequipped")

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
	desc += "\nDesignation: Restorative Liquid"
	desc += "\nProperties: Calming effect, mental restoration"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var regen = SANITY_REGEN_PER_LEVEL * level
		desc += "\n\nMechanics:"
		desc += "\n- Sanity regen: +%.1f%% per turn" % regen
		desc += "\n- Also grants +%d MIND" % level

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: AlmondWater extends Item"
		desc += "\npool: MIND, rarity: RARE"
		desc += "\n\non_equip():"
		desc += "\n  sanity_regen_percent += %.1f * level" % SANITY_REGEN_PER_LEVEL

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var regen = SANITY_REGEN_PER_LEVEL * level
	return "AlmondWater(Level %d, +%.1f%% sanity regen, %s)" % [
		level,
		regen,
		"Equipped" if equipped else "Ground"
	]
