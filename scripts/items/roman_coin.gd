class_name RomanCoin extends Item
"""Roman Coin - Ancient artifact that improves mana regeneration.

Properties (scale with level N):
- +5% mana regen per level (% of max mana per turn)
- Standard NULL stat bonus (+N NULL)

Example Scaling:
- Level 1: +5% mana regen, +1 NULL
- Level 2: +10% mana regen, +2 NULL
- Level 3: +15% mana regen, +3 NULL

Design Intent:
- Simple, reliable mana sustain item for NULL pool
- Synergizes with max mana items (debug_item, antigonous_notebook)
- Enables more frequent use of mana-costing abilities
- Stacks well with itself for mana-focused builds
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "roman_coin"
const ITEM_NAME = "Roman Coin"
const POOL = Item.PoolType.NULL
const RARITY_TYPE = ItemRarity.Tier.COMMON

# Mana regen bonus per level (% of max mana per turn)
const MANA_REGEN_PER_LEVEL = 5.0

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/roman_coin.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Roman Coin with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "An ancient bronze coin, green with verdigris. The faded visage of the emperor seems to be crying out in pain. Warm to the touch."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Mana regeneration increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# EQUIP/UNEQUIP (Override for mana regen modifier)
# ============================================================================

func on_equip(player: Player3D) -> void:
	"""Apply mana regen bonus when equipped."""
	super.on_equip(player)  # Apply base stat bonus (+N NULL)

	# Add mana regen bonus directly
	var regen_bonus = MANA_REGEN_PER_LEVEL * level
	player.stats.mana_regen_percent += regen_bonus

	Log.player("ROMAN COIN equipped: +%.0f%% mana regen" % regen_bonus)

func on_unequip(player: Player3D) -> void:
	"""Remove mana regen bonus when unequipped."""
	super.on_unequip(player)  # Remove base stat bonus

	# Remove mana regen bonus
	var regen_bonus = MANA_REGEN_PER_LEVEL * level
	player.stats.mana_regen_percent -= regen_bonus

	Log.player("ROMAN COIN unequipped")

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
	desc += "\nDesignation: Arcane Currency"
	desc += "\nProperties: Enhances anomalous energy recovery"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var total_regen = MANA_REGEN_PER_LEVEL * level
		desc += "\n\nMechanics:"
		desc += "\n- Mana regen bonus: +%.0f%% of max mana per turn" % total_regen
		desc += "\n- Also grants +%d NULL" % level
		desc += "\n- Stacks with base regen (NULL/2 per turn)"

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: RomanCoin extends Item"
		desc += "\npool: NULL"
		desc += "\n\non_equip():"
		desc += "\n  stats.mana_regen_percent += %.1f * level" % MANA_REGEN_PER_LEVEL

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var total_regen = MANA_REGEN_PER_LEVEL * level
	return "RomanCoin(Level %d, +%.0f%% mana regen, %s)" % [
		level,
		total_regen,
		"Equipped" if equipped else "Ground"
	]
