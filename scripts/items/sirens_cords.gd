class_name SirensCords extends Item
"""Siren's Cords - Transforms BODY attack into a sonic scream.

Properties (scale with level N):
- Changes BODY attack to "Siren Scream" (sound-based AOE)
- Adds "sound" tag to BODY attack (synergizes with Coach's Whistle!)
- Changes attack pattern to AOE_AROUND (hits all enemies in range)
- +0.5 range per level
- Standard BODY stat bonus (+N BODY)

Example Scaling:
- Level 1: AOE_AROUND, +0.5 range, +1 BODY
- Level 2: AOE_AROUND, +1.0 range, +2 BODY
- Level 3: AOE_AROUND, +1.5 range, +3 BODY

Design Intent:
- EPIC rarity transformation item
- Converts melee punch into ranged sonic attack
- Synergizes with Coach's Whistle (sound damage multiplier!)
- Combo: Brass Knuckles + Siren's Cords + Coach's Whistle = multiple sound AOE attacks
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "sirens_cords"
const ITEM_NAME = "Siren's Cords"
const POOL = Item.PoolType.BODY
const RARITY_TYPE = ItemRarity.Tier.EPIC

# Range bonus per level
const RANGE_PER_LEVEL = 0.5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/sirens_cords.png"

# Preload attack types for area enum
const _AttackTypes = preload("res://scripts/combat/attack_types.gd")

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Siren's Cords with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A dried, leathery strip of tissue preserved in a glass vial. When held close to your ear, you can almost hear a distant, haunting melody. The label reads 'VOCAL SPECIMEN - HANDLE WITH CARE'."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Sonic range increases with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# ATTACK MODIFIERS
# ============================================================================

func get_attack_modifiers() -> Dictionary:
	"""Transform BODY attack into sound-based AOE."""
	var range_bonus = RANGE_PER_LEVEL * level

	return {
		# Transform to sound-based attack
		"add_tags": ["sound"],
		"remove_tags": ["melee"],  # No longer melee - it's a scream

		# Change to AOE around player (like whistle)
		"area": _AttackTypes.Area.AOE_AROUND,

		# Increase range (base BODY range is 1.5)
		"range_add": range_bonus,

		# Rename the attack
		"attack_name": "Siren Scream",
		"attack_emoji": "🔊",
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
	desc += "\nDesignation: Anomalous Vocal Tissue"
	desc += "\nProperties: Grants sonic projection capabilities"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var range_bonus = RANGE_PER_LEVEL * level
		desc += "\n\nMechanics:"
		desc += "\n- Transforms Punch → Siren Scream"
		desc += "\n- Attack pattern: AOE around player"
		desc += "\n- Adds 'sound' tag (Coach's Whistle synergy!)"
		desc += "\n- Range bonus: +%.1f tiles" % range_bonus
		desc += "\n- Also grants +%d BODY" % level

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: SirensCords extends Item"
		desc += "\npool: BODY, rarity: EPIC"
		desc += "\n\nget_attack_modifiers():"
		desc += "\n  add_tags: ['sound']"
		desc += "\n  remove_tags: ['melee']"
		desc += "\n  area: AOE_AROUND"
		desc += "\n  range_add: %.1f * level" % RANGE_PER_LEVEL

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var range_bonus = RANGE_PER_LEVEL * level
	return "SirensCords(Level %d, +%.1f range, %s)" % [
		level,
		range_bonus,
		"Equipped" if equipped else "Ground"
	]
