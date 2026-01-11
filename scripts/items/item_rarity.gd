class_name ItemRarity
## Item rarity tiers with spawn probability modifiers
##
## Rarities from most to least common (except DEBUG):
## - DEBUG: 100% spawn chance (testing only)
## - common: ~5% base spawn chance
## - uncommon: ~2% base spawn chance
## - rare: ~0.5% base spawn chance
## - epic: ~0.1% base spawn chance
## - legendary: ~0.01% base spawn chance
## - anomaly: ~0.001% base spawn chance (corruption-dependent)

enum Tier {
	DEBUG,      ## Always spawns (testing only)
	COMMON,     ## Standard items
	UNCOMMON,   ## Slightly better items
	RARE,       ## Good items
	EPIC,       ## Very good items
	LEGENDARY,  ## Exceptional items
	ANOMALY     ## Strange/powerful items (corruption-dependent)
}

## Base spawn probabilities per rarity (before corruption modifiers)
## NOTE: Quadrupled for testing (original values in comments)
const BASE_SPAWN_PROBABILITY = {
	Tier.DEBUG: 1.0,       # 100% - always spawns
	Tier.COMMON: 0.20,     # 20% (was 5%)
	Tier.UNCOMMON: 0.08,   # 8% (was 2%)
	Tier.RARE: 0.02,       # 2% (was 0.5%)
	Tier.EPIC: 0.004,      # 0.4% (was 0.1%)
	Tier.LEGENDARY: 0.0004,   # 0.04% (was 0.01%)
	Tier.ANOMALY: 0.00004     # 0.004% (was 0.001%)
}

## Default corruption multipliers per rarity
## Used in formula: final_prob = base_prob × (1 + corruption × multiplier)
## Corruption is UNBOUNDED (0.0, 0.5, 1.0, 2.0, ...) so multipliers scale linearly
## Positive = more common as corruption rises
## Negative = less common as corruption rises (scarcity)
const CORRUPTION_MULTIPLIERS = {
	Tier.DEBUG: 0.0,        # Unaffected by corruption
	Tier.COMMON: -0.3,      # Gets less common (supplies dry up)
	Tier.UNCOMMON: -0.2,    # Slightly less common
	Tier.RARE: 0.0,         # Neutral
	Tier.EPIC: 0.1,         # Slightly more common
	Tier.LEGENDARY: 0.3,    # More common with corruption
	Tier.ANOMALY: 1.0       # Much more common with corruption
}

## Display colors per rarity (for UI)
const RARITY_COLORS = {
	Tier.DEBUG: Color(1.0, 0.0, 1.0),       # Magenta
	Tier.COMMON: Color(0.8, 0.8, 0.8),      # Light gray
	Tier.UNCOMMON: Color(0.3, 1.0, 0.3),    # Green
	Tier.RARE: Color(0.3, 0.5, 1.0),        # Blue
	Tier.EPIC: Color(0.8, 0.3, 1.0),        # Purple
	Tier.LEGENDARY: Color(1.0, 0.6, 0.0),   # Orange
	Tier.ANOMALY: Color(1.0, 0.2, 0.2)      # Red
}

## Display names per rarity
const RARITY_NAMES = {
	Tier.DEBUG: "DEBUG",
	Tier.COMMON: "Common",
	Tier.UNCOMMON: "Uncommon",
	Tier.RARE: "Rare",
	Tier.EPIC: "Epic",
	Tier.LEGENDARY: "Legendary",
	Tier.ANOMALY: "Anomaly"
}

static func get_color(rarity: Tier) -> Color:
	"""Get display color for rarity tier"""
	return RARITY_COLORS.get(rarity, Color.WHITE)

static func get_name(rarity: Tier) -> String:
	"""Get display name for rarity tier"""
	return RARITY_NAMES.get(rarity, "Unknown")

static func get_base_probability(rarity: Tier) -> float:
	"""Get base spawn probability for rarity tier"""
	return BASE_SPAWN_PROBABILITY.get(rarity, 0.0)

static func get_corruption_multiplier(rarity: Tier) -> float:
	"""Get corruption multiplier for rarity tier"""
	return CORRUPTION_MULTIPLIERS.get(rarity, 0.0)
