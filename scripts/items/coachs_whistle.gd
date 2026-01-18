class_name CoachsWhistle extends Item
"""Coach's Whistle - Amplifies sound-based attacks.

Properties (scale with level N):
- 1.5x damage multiplier to "sound" tagged attacks per level
- Standard MIND stat bonus (+N MIND)

Example Scaling:
- Level 1: 1.5x sound damage, +1 MIND
- Level 2: 2.25x sound damage (1.5²), +2 MIND
- Level 3: 3.375x sound damage (1.5³), +3 MIND

Design Intent:
- Synergizes with the base MIND "Whistle" attack (has "sound" tag)
- Encourages investing in MIND pool for psychic damage builds
- Multipliers stack exponentially with level for dramatic scaling
"""

# ============================================================================
# STATIC CONFIGURATION
# ============================================================================

const ITEM_ID = "coachs_whistle"
const ITEM_NAME = "Coach's Whistle"
const POOL = Item.PoolType.MIND
const RARITY_TYPE = ItemRarity.Tier.UNCOMMON

# Sound damage multiplier per level (exponential: 1.5^level)
const SOUND_MULT_PER_LEVEL = 1.5

# Texture path
const TEXTURE_PATH = "res://assets/textures/items/coachs_whistle.png"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init():
	"""Initialize Coach's Whistle with default properties."""
	item_id = ITEM_ID
	item_name = ITEM_NAME
	pool_type = POOL
	rarity = RARITY_TYPE

	# Visual description (CONSTANT - always shown)
	visual_description = "A chrome whistle on a faded red lanyard. 'ACME' is stamped on the side. The kind gym teachers terrorized you with."

	# Scaling hint (CONSTANT - always shown)
	scaling_hint = "Sound attack damage increases dramatically with level"

	# Load sprite texture (will fail gracefully if missing)
	if ResourceLoader.exists(TEXTURE_PATH):
		ground_sprite = load(TEXTURE_PATH)

# ============================================================================
# ATTACK MODIFIERS
# ============================================================================

func get_attack_modifiers() -> Dictionary:
	"""Return tag-based damage multiplier for sound attacks."""
	var total_mult = pow(SOUND_MULT_PER_LEVEL, level)

	return {
		"tag_damage_multiply": {
			AttackTypes.Tags.SOUND: total_mult
		}
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
	desc += "\nDesignation: Acoustic Amplifier"
	desc += "\nProperties: Enhances sound-based psychic attacks"

	# Clearance 3+: Add specific mechanics
	if clearance_level >= 3:
		var total_mult = pow(SOUND_MULT_PER_LEVEL, level)
		desc += "\n\nMechanics:"
		desc += "\n- Sound attack multiplier: %.2fx" % total_mult
		desc += "\n- Also grants +%d MIND" % level
		desc += "\n- Stacks exponentially with level"

	# Clearance 4+: Add code revelation
	if clearance_level >= 4:
		desc += "\n\n--- SYSTEM DATA (CLEARANCE OMEGA) ---"
		desc += "\nclass_name: CoachsWhistle extends Item"
		desc += "\npool: MIND"
		desc += "\n\nget_attack_modifiers():"
		desc += "\n  tag_damage_multiply['sound'] = %.1f ^ level" % SOUND_MULT_PER_LEVEL

	return desc

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var total_mult = pow(SOUND_MULT_PER_LEVEL, level)
	return "CoachsWhistle(Level %d, %.2fx sound dmg, %s)" % [
		level,
		total_mult,
		"Equipped" if equipped else "Ground"
	]
