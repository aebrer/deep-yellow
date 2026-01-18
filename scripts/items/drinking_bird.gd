class_name DrinkingBird extends Item
"""Drinking Bird - Global cooldown reduction.

Properties (scale with level N):
- Passive: Reduces ALL cooldowns (attack pools AND item internal cooldowns)
- Cooldown reduction scales asymptotically toward 50% at level 20
- Standard MIND stat bonus (+N MIND)

Asymptotic Formula:
- cooldown_multiply = 1.0 - 0.5 * (1.0 - exp(-level * DECAY_RATE))
- At level 1: ~7% faster cooldowns
- At level 5: ~24% faster cooldowns
- At level 10: ~39% faster cooldowns
- At level 20: ~48% faster cooldowns
- Cap: 50% faster cooldowns (0.5 multiplier)

Design Intent:
- Passive utility item for MIND pool
- Benefits ALL attacks and items with cooldowns
- Synergizes with high-cooldown items (Antigonous Notebook, Lucky Rabbit's Foot)
- Synergizes with high-cooldown attacks (MIND whistle at 5 turns)
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "drinking_bird"
const ITEM_NAME = "Drinking Bird"
const POOL = Item.PoolType.MIND
const RARITY_TYPE = ItemRarity.Tier.COMMON

# Asymptotic decay rate (tuned for ~48% reduction at level 20)
const DECAY_RATE = 0.15

# Maximum cooldown reduction (50% = 0.5 multiplier minimum)
const MAX_REDUCTION = 0.5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/drinking_bird.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Drinking Bird with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A novelty desk toy - a glass bird balanced on a pivot, perpetually dipping its beak into a cup of water. The fluid inside glows faintly. A label reads: 'For the thinking man, now with Verve!'"

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Cooldown reduction increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# PASSIVE MODIFIERS
# ============================================================================

func get_passive_modifiers() -> Dictionary:
	"""Provide cooldown reduction multiplier (affects ALL cooldowns).

	Uses asymptotic formula: multiplier = 1.0 - MAX_REDUCTION * (1.0 - exp(-level * DECAY_RATE))
	This approaches 0.5 (50% reduction) as level increases, reaching ~48% at level 20.
	"""
	# Calculate multiplier using asymptotic formula
	var reduction_factor = 1.0 - exp(-level * DECAY_RATE)
	var cooldown_mult = 1.0 - MAX_REDUCTION * reduction_factor

	return {
		"cooldown_multiply": cooldown_mult,
	}

func _get_cooldown_reduction_percent() -> float:
	"""Helper to get the current cooldown reduction as a percentage."""
	var mods = get_passive_modifiers()
	return (1.0 - mods["cooldown_multiply"]) * 100.0

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
	desc += "\nDesignation: Temporal Accelerator"
	desc += "\nProperties: Reduces recovery time for all abilities"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var reduction_pct = _get_cooldown_reduction_percent()
		desc += "\n\nMechanics:"
		desc += "\n- Cooldown reduction: %.0f%%" % reduction_pct
		desc += "\n- Affects: Attack cooldowns AND item cooldowns"
		desc += "\n- Also grants +%d MIND" % level

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: DrinkingBird extends Item"
		desc += "\npool: MIND, rarity: COMMON"
		desc += "\n\nget_passive_modifiers():"
		desc += "\n  cooldown_multiply: 1.0 - %.1f * (1.0 - exp(-level * %.2f))" % [MAX_REDUCTION, DECAY_RATE]
		desc += "\n  # Asymptotically approaches %.0f%% reduction" % (MAX_REDUCTION * 100)

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var reduction_pct = _get_cooldown_reduction_percent()
	return "DrinkingBird(Level %d, -%.0f%% cooldowns, %s)" % [
		level,
		reduction_pct,
		"Equipped" if equipped else "Ground"
	]
