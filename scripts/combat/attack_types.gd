class_name AttackTypes
"""Constants and enums for the auto-attack system.

There are THREE attack types (no LIGHT attack):
- BODY: Physical damage to HP (base: punch)
- MIND: Sanity damage (base: whistle)
- NULL: Anomalous damage, costs mana (base: unlocked when player gains mana)

Items do NOT have their own attacks. Items MODIFY the pool's single attack.
Each pool has ONE attack that fires automatically every N turns.
"""

# ============================================================================
# ENUMS
# ============================================================================

enum Type {
	BODY,   # Physical damage to HP
	MIND,   # Sanity damage
	NULL    # Anomalous damage (costs mana)
}

enum Area {
	SINGLE,       # Nearest enemy in range
	CONE,         # Triangle spread in facing direction
	AOE_3X3,      # 3x3 centered on target
	AOE_AROUND,   # All enemies within range of player (whistle)
	SWEEP,        # Target + perpendicular neighbors (shovel swing)
}

# ============================================================================
# BASE ATTACK PROPERTIES (before item modifiers)
# ============================================================================

# Base damage per attack type
# All attack types scale with their respective stat (STRENGTH/PERCEPTION/ANOMALY)
const BASE_DAMAGE = {
	Type.BODY: 5.0,   # Punch - scales with STRENGTH
	Type.MIND: 3.0,   # Whistle - scales with PERCEPTION
	Type.NULL: 5.0,   # Anomaly Burst - scales with ANOMALY
}

# Range in tiles (grid distance)
const BASE_RANGE = {
	Type.BODY: 1.5,   # Adjacent only (melee)
	Type.MIND: 3.0,   # Medium range (AOE around player)
	Type.NULL: 3.0,   # Cone range
}

# Turns between attacks
const BASE_COOLDOWN = {
	Type.BODY: 1,     # Every turn
	Type.MIND: 5,     # Every 5 turns (per user spec)
	Type.NULL: 4,     # Every 4 turns
}

# Default attack pattern
const BASE_AREA = {
	Type.BODY: Area.SINGLE,
	Type.MIND: Area.AOE_AROUND,  # Whistle hits all enemies in range
	Type.NULL: Area.CONE,        # Anomaly cone in facing direction
}

# Mana cost per attack
const BASE_MANA_COST = {
	Type.BODY: 0.0,   # Free
	Type.MIND: 0.0,   # Free
	Type.NULL: 5.0,   # Costs mana to use
}

# ============================================================================
# STAT SCALING
# ============================================================================

# Which derived stat scales damage for each type
const SCALING_STAT = {
	Type.BODY: "strength",    # Derived from BODY
	Type.MIND: "perception",  # Derived from MIND
	Type.NULL: "anomaly",     # Derived from NULL
}

# Scaling multiplier per stat point (different rates per attack type)
# Formula: damage *= (1.0 + stat_value * SCALING_RATE)
const SCALING_RATE = {
	Type.BODY: 0.10,   # +10% per STRENGTH point (steady, reliable)
	Type.MIND: 0.20,   # +20% per PERCEPTION point (more impactful)
	Type.NULL: 0.50,   # +50% per ANOMALY point (glass cannon)
}

# ============================================================================
# DISPLAY NAMES
# ============================================================================

const TYPE_NAMES = {
	Type.BODY: "BODY",
	Type.MIND: "MIND",
	Type.NULL: "NULL",
}

const BASE_ATTACK_NAMES = {
	Type.BODY: "Punch",
	Type.MIND: "Whistle",
	Type.NULL: "Anomaly Burst",
}

# Emojis for attack type icons (used in UI preview and hit VFX)
const BASE_ATTACK_EMOJIS = {
	Type.BODY: "👊",  # Punch/melee
	Type.MIND: "📢",  # Whistle/psychic
	Type.NULL: "✨",  # Anomaly/magic
}

# ============================================================================
# ATTACK TAGS (centralized string constants to avoid typos)
# ============================================================================

## Tag constants for attack type classification
## Use these instead of raw strings to prevent typos and enable refactoring
class Tags:
	# Damage type tags
	const PHYSICAL = "physical"  # Standard physical damage
	const SOUND = "sound"        # Sound-based (Smiler weakness)
	const PSYCHIC = "psychic"    # Mental/sanity damage
	const ANOMALY = "anomaly"    # Anomalous/supernatural

	# Range/pattern tags
	const MELEE = "melee"        # Close range attack
	const RANGED = "ranged"      # Distance attack

# Tags for each attack type (items can check these for conditional effects)
# Tags describe the nature of the attack: "physical", "sound", "psychic", "anomaly", etc.
const BASE_ATTACK_TAGS = {
	Type.BODY: [Tags.PHYSICAL, Tags.MELEE],      # Physical melee attack
	Type.MIND: [Tags.SOUND, Tags.PSYCHIC],       # Sound-based psychic attack (whistle)
	Type.NULL: [Tags.ANOMALY, Tags.RANGED],      # Anomalous ranged attack
}
