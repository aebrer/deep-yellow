class_name CorruptionDebuffs extends RefCounted
## Static utility class for corrupted item debuffs.
##
## Debuffs are "dark mirrors" of positive item effects — they scale the same
## way (with item_level), amplified by world corruption. Each debuff inverts
## something a real item does: stat bonuses become drains, regen becomes decay,
## damage multipliers become damage penalties.
##
## Scaling formula: effective_value = base_value * (1 + corruption) * item_level
## Corruption is queried live, so debuffs worsen as the game progresses.

# ============================================================================
# DEBUFF CATEGORIES
# ============================================================================

enum Category {
	STAT,      # Applied/removed on equip/enable/disable/unequip
	PER_TURN,  # Triggers each turn while enabled
	ON_USE,    # Triggers when pool attack fires
}

# ============================================================================
# DEBUFF POOL
# ============================================================================

## All possible debuffs. "Dark mirror" versions of positive item effects.
## STAT debuffs modify base stats (body/mind/null_stat) — the same stats that
## items grant bonuses to. This keeps apply/remove perfectly reversible.
## PER_TURN debuffs invert regen effects (trail mix, almond water, roman coin).
## ON_USE debuffs invert attack bonuses (damage multipliers, mana efficiency).
const DEBUFF_POOL: Array[Dictionary] = [
	# --- Stat debuffs: mirror of +N body/mind/null from item equip ---
	# Items grant +level to body/mind/null. These drain the SAME base stats.
	{
		"id": "body_drain",
		"name": "Muscle Atrophy",
		"description": "Reduces BODY (lowers max HP and Strength)",
		"category": Category.STAT,
		"stat": "body",
		"base_value": 1,  # -1 body per level (mirrors +1 body per level)
	},
	{
		"id": "mind_drain",
		"name": "Mind Fracture",
		"description": "Reduces MIND (lowers max Sanity and Perception)",
		"category": Category.STAT,
		"stat": "mind",
		"base_value": 1,  # -1 mind per level
	},
	{
		"id": "null_drain",
		"name": "Void Leak",
		"description": "Reduces NULL (lowers max Mana and Anomaly)",
		"category": Category.STAT,
		"stat": "null_stat",
		"base_value": 1,  # -1 null per level
	},
	# --- Per-turn debuffs: mirrors of regen items ---
	# Trail Mix gives +0.5% HP regen/turn per level. This drains instead.
	{
		"id": "vitality_rot",
		"name": "Vitality Rot",
		"description": "Drains HP each turn (inverts Trail Mix)",
		"category": Category.PER_TURN,
		"effect": "hp_drain",
		"base_value": 0.5,  # 0.5 flat HP/turn per level (scales with corruption)
	},
	# Almond Water gives +0.5% Sanity regen/turn per level. This drains instead.
	{
		"id": "whispers",
		"name": "Whispers",
		"description": "Drains Sanity each turn (inverts Almond Water)",
		"category": Category.PER_TURN,
		"effect": "sanity_drain",
		"base_value": 0.5,  # 0.5 flat Sanity/turn per level
	},
	# Corruption leak — unique to corruption system, no positive mirror.
	{
		"id": "corruption_bleed",
		"name": "Corruption Leak",
		"description": "Passively increases corruption each turn",
		"category": Category.PER_TURN,
		"effect": "corruption",
		"base_value": 0.002,  # Small corruption increase per turn per level
	},
	# --- On-use debuffs: mirrors of attack bonuses ---
	# Baseball Bat gives damage_multiply. This reduces damage.
	{
		"id": "brittle_strikes",
		"name": "Brittle Strikes",
		"description": "Reduces attack damage (inverts Baseball Bat)",
		"category": Category.ON_USE,
		"effect": "damage_penalty",
		"base_value": 0.1,  # -10% damage per level (applied as multiplier reduction)
	},
	# Mana tax — mirror of efficient NULL item mana usage.
	{
		"id": "mana_tax",
		"name": "Mana Parasite",
		"description": "Increases mana cost of pool attacks",
		"category": Category.ON_USE,
		"effect": "mana_tax",
		"base_value": 0.15,  # +15% mana cost per level
	},
	# Corruption spike on attack — unique to corruption system.
	{
		"id": "corruption_spike",
		"name": "Corruption Burst",
		"description": "Spikes corruption when pool attacks",
		"category": Category.ON_USE,
		"effect": "corruption_spike",
		"base_value": 0.005,  # Corruption increase per attack per level
	},
]

# ============================================================================
# ROLLING
# ============================================================================

static func roll_debuff() -> Dictionary:
	"""Pick a random debuff from the pool.

	Returns:
		A copy of the debuff definition dictionary.
	"""
	var entry = DEBUFF_POOL[randi() % DEBUFF_POOL.size()]
	return entry.duplicate()

# ============================================================================
# SCALING
# ============================================================================

static func get_effective_value(debuff: Dictionary, corruption: float, item_level: int) -> float:
	"""Calculate the effective debuff value based on corruption and item level.

	Formula: base_value * (1 + corruption) * item_level

	Args:
		debuff: Debuff definition dictionary
		corruption: Current corruption level (queried live)
		item_level: Item's current level

	Returns:
		Scaled debuff value
	"""
	var base = debuff.get("base_value", 0.0)
	return base * (1.0 + corruption) * item_level

static func _get_current_corruption() -> float:
	"""Query current corruption from ChunkManager.

	Returns 0.0 if corruption tracker is unavailable.
	"""
	if ChunkManager and ChunkManager.corruption_tracker:
		var level_id: int = 0
		if LevelManager:
			var current_level = LevelManager.get_current_level()
			if current_level:
				level_id = current_level.level_id
		return ChunkManager.corruption_tracker.get_corruption(level_id)
	return 0.0

# ============================================================================
# STAT DEBUFF APPLICATION
# ============================================================================

static func apply_stat_debuffs(debuffs: Array, player, corruption: float, item_level: int) -> void:
	"""Apply all stat-category debuffs to the player.

	Called when a corrupted item is equipped or enabled.

	Args:
		debuffs: Array of debuff dictionaries
		player: Player3D reference
		corruption: Current corruption level
		item_level: Item's current level
	"""
	if not player or not player.stats:
		return

	for debuff in debuffs:
		if debuff.get("category") != Category.STAT:
			continue

		var value = get_effective_value(debuff, corruption, item_level)
		var stat = debuff.get("stat", "")
		var mode = debuff.get("mode", "flat")

		_apply_single_stat_debuff(player.stats, stat, mode, value)

static func remove_stat_debuffs(debuffs: Array, player, corruption: float, item_level: int) -> void:
	"""Remove all stat-category debuffs from the player.

	Called when a corrupted item is unequipped or disabled.
	Uses the same corruption/level to calculate the exact value to reverse.

	Args:
		debuffs: Array of debuff dictionaries
		player: Player3D reference
		corruption: Current corruption level
		item_level: Item's current level
	"""
	if not player or not player.stats:
		return

	for debuff in debuffs:
		if debuff.get("category") != Category.STAT:
			continue

		var value = get_effective_value(debuff, corruption, item_level)
		var stat = debuff.get("stat", "")
		var mode = debuff.get("mode", "flat")

		_remove_single_stat_debuff(player.stats, stat, mode, value)

static func _apply_single_stat_debuff(stats, stat: String, _mode: String, value: float) -> void:
	"""Apply a single stat debuff by reducing a base stat.

	Works at the same level as item bonuses — modifying body/mind/null_stat
	directly, which automatically recalculates all derived stats (max_hp,
	strength, max_sanity, perception, max_mana, anomaly) via the cache system.
	"""
	var int_value = int(value)
	match stat:
		"body":
			stats.body -= int_value
		"mind":
			stats.mind -= int_value
		"null_stat":
			stats.null_stat -= int_value

static func _remove_single_stat_debuff(stats, stat: String, _mode: String, value: float) -> void:
	"""Remove a single stat debuff (reverse the application)."""
	var int_value = int(value)
	match stat:
		"body":
			stats.body += int_value
		"mind":
			stats.mind += int_value
		"null_stat":
			stats.null_stat += int_value

# ============================================================================
# PER-TURN DEBUFF APPLICATION
# ============================================================================

static func apply_per_turn_debuffs(debuffs: Array, player, corruption: float, item_level: int) -> void:
	"""Apply all per-turn debuffs. Called each turn while item is enabled.

	Args:
		debuffs: Array of debuff dictionaries
		player: Player3D reference
		corruption: Current corruption level
		item_level: Item's current level
	"""
	if not player or not player.stats:
		return

	for debuff in debuffs:
		if debuff.get("category") != Category.PER_TURN:
			continue

		var value = get_effective_value(debuff, corruption, item_level)
		var effect = debuff.get("effect", "")

		match effect:
			"corruption":
				if ChunkManager and ChunkManager.corruption_tracker:
					var cl = LevelManager.get_current_level() if LevelManager else null
					var level_id: int = cl.level_id if cl else 0
					ChunkManager.corruption_tracker.increase_corruption(level_id, value, 0.0)
			"sanity_drain":
				player.stats.drain_sanity(value)
			"hp_drain":
				player.stats.take_damage(value)

# ============================================================================
# ON-USE DEBUFF APPLICATION
# ============================================================================

static func apply_on_use_debuffs(debuffs: Array, player, corruption: float, item_level: int) -> void:
	"""Apply all on-use debuffs. Called when an item's on_turn effect fires.

	Args:
		debuffs: Array of debuff dictionaries
		player: Player3D reference
		corruption: Current corruption level
		item_level: Item's current level
	"""
	if not player or not player.stats:
		return

	for debuff in debuffs:
		if debuff.get("category") != Category.ON_USE:
			continue

		var value = get_effective_value(debuff, corruption, item_level)
		var effect = debuff.get("effect", "")

		match effect:
			"corruption_spike":
				if ChunkManager and ChunkManager.corruption_tracker:
					var cl = LevelManager.get_current_level() if LevelManager else null
					var level_id: int = cl.level_id if cl else 0
					ChunkManager.corruption_tracker.increase_corruption(level_id, value, 0.0)
			"mana_tax":
				# Handled by get_mana_tax_multiplier() during attack building
				pass
			"damage_penalty":
				# Handled by get_damage_multiplier() during attack building
				pass

static func get_mana_tax_multiplier(debuffs: Array, corruption: float, item_level: int) -> float:
	"""Get the total mana cost multiplier from on-use mana_tax debuffs.

	Returns:
		Multiplier (1.0 = no tax, 1.5 = 50% more mana cost, etc.)
	"""
	var multiplier = 1.0
	for debuff in debuffs:
		if debuff.get("category") != Category.ON_USE:
			continue
		if debuff.get("effect") != "mana_tax":
			continue
		var value = get_effective_value(debuff, corruption, item_level)
		multiplier += value
	return multiplier

static func get_damage_multiplier(debuffs: Array, corruption: float, item_level: int) -> float:
	"""Get the total damage multiplier from on-use damage_penalty debuffs.

	Returns:
		Multiplier (1.0 = no penalty, 0.7 = 30% less damage, etc.)
		Clamped to minimum 0.1 to prevent zero/negative damage.
	"""
	var multiplier = 1.0
	for debuff in debuffs:
		if debuff.get("category") != Category.ON_USE:
			continue
		if debuff.get("effect") != "damage_penalty":
			continue
		var value = get_effective_value(debuff, corruption, item_level)
		multiplier -= value
	return maxf(multiplier, 0.1)

# ============================================================================
# DESCRIPTION
# ============================================================================

static func get_debuff_descriptions(debuffs: Array, corruption: float, item_level: int, clearance_level: int) -> String:
	"""Get formatted description of all debuffs on an item.

	Clearance-gated: need clearance >= item_level/2 to see debuffs.
	(e.g., item level 3 needs clearance 2+, item level 5 needs clearance 3+)

	Args:
		debuffs: Array of debuff dictionaries
		corruption: Current corruption level
		item_level: Item's current level
		clearance_level: Player's clearance level

	Returns:
		Formatted debuff description string
	"""
	if debuffs.is_empty():
		return ""

	if clearance_level * 2 < item_level:
		return "\n[CORRUPT] ???"

	var lines: Array[String] = ["\n[CORRUPT] Debuffs:"]
	for debuff in debuffs:
		var value = get_effective_value(debuff, corruption, item_level)
		var debuff_name = debuff.get("name", "Unknown")
		var desc = debuff.get("description", "")

		var value_str: String
		match debuff.get("category"):
			Category.STAT:
				value_str = "-%d %s" % [int(value), debuff.get("stat", "")]
			Category.PER_TURN:
				var effect = debuff.get("effect", "")
				if effect == "corruption":
					value_str = "+%.3f/turn" % value
				else:
					value_str = "%.1f/turn" % value
			Category.ON_USE:
				var effect = debuff.get("effect", "")
				if effect == "mana_tax":
					value_str = "+%.0f%% mana cost" % (value * 100.0)
				elif effect == "damage_penalty":
					value_str = "-%.0f%% damage" % (value * 100.0)
				else:
					value_str = "+%.3f on attack" % value
			_:
				value_str = "%.2f" % value

		lines.append("  - %s: %s (%s)" % [debuff_name, desc, value_str])

	return "\n".join(lines)
