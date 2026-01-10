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
	LINE,         # All in a line from player
	CONE,         # Triangle spread in facing direction
	AOE_3X3,      # 3x3 centered on target
	AOE_AROUND,   # All enemies within range of player (whistle)
}

# ============================================================================
# BASE ATTACK PROPERTIES (before item modifiers)
# ============================================================================

# Base damage per attack type
# Note: NULL damage is REPLACED by current mana total (not added to base)
const BASE_DAMAGE = {
	Type.BODY: 5.0,   # Punch
	Type.MIND: 3.0,   # Whistle
	Type.NULL: 0.0,   # Damage = current_mana (set dynamically)
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
# Formula: damage *= (1.0 + stat_value / 100.0)
const SCALING_STAT = {
	Type.BODY: "strength",    # Derived from BODY
	Type.MIND: "perception",  # Derived from MIND
	Type.NULL: "anomaly",     # Derived from NULL
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
