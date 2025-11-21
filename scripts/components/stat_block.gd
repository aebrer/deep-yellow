class_name StatBlock extends RefCounted
"""Runtime stat management with modifier system and caching.

Handles:
- Base stats (BODY, MIND, NULL)
- Derived stats (HP, Sanity, Mana, STRENGTH, PERCEPTION, ANOMALY)
- Modifier system (equipment, buffs, debuffs)
- Current resource pools (HP, Sanity, Mana)
- EXP and Clearance level progression
- Percentage-based scaling: effective = base × (1 + stat/100)

Usage:
	var stats = StatBlock.new(player_template)
	stats.add_modifier(StatModifier.new("hp", 20, StatModifier.ModifierType.ADD, "Leather Armor"))
	stats.take_damage(15)
	stats.gain_exp(100)
"""

# ============================================================================
# SIGNALS
# ============================================================================

signal stat_changed(stat_name: String, old_value: float, new_value: float)
signal resource_changed(resource_name: String, current: float, maximum: float)
signal modifier_added(modifier: StatModifier)
signal modifier_removed(modifier: StatModifier)
signal exp_gained(amount: int, new_total: int)
signal level_increased(old_level: int, new_level: int)  # Auto-increases, triggers perk selection
signal clearance_increased(old_level: int, new_level: int)  # Manual only, unlocks knowledge
signal entity_died(cause: String)

# ============================================================================
# BASE STATS
# ============================================================================

var body: int = 5:
	set(value):
		var old = body
		body = max(0, value)
		_invalidate_cache()
		emit_signal("stat_changed", "body", old, body)

var mind: int = 5:
	set(value):
		var old = mind
		mind = max(0, value)
		_invalidate_cache()
		emit_signal("stat_changed", "mind", old, mind)

var null_stat: int = 0:
	set(value):
		var old = null_stat
		null_stat = max(0, value)
		_invalidate_cache()
		emit_signal("stat_changed", "null", old, null_stat)

# ============================================================================
# DIRECT BONUSES (from template)
# ============================================================================

var bonus_hp: float = 0.0
var bonus_sanity: float = 0.0
var bonus_mana: float = 0.0
var bonus_strength: float = 0.0
var bonus_perception: float = 0.0
var bonus_anomaly: float = 0.0

# ============================================================================
# CURRENT RESOURCE POOLS
# ============================================================================

var current_hp: float = 0.0:
	set(value):
		current_hp = clamp(value, 0.0, max_hp)
		emit_signal("resource_changed", "hp", current_hp, max_hp)
		if current_hp <= 0.0:
			emit_signal("entity_died", "hp_depleted")

var current_sanity: float = 0.0:
	set(value):
		current_sanity = clamp(value, 0.0, max_sanity)
		emit_signal("resource_changed", "sanity", current_sanity, max_sanity)
		if current_sanity <= 0.0:
			emit_signal("entity_died", "sanity_depleted")

var current_mana: float = 0.0:
	set(value):
		current_mana = clamp(value, 0.0, max_mana)
		emit_signal("resource_changed", "mana", current_mana, max_mana)

# ============================================================================
# PROGRESSION (Player only)
# ============================================================================
# Two separate progression systems:
#
# LEVEL (auto-progression):
#   - Increases automatically when EXP threshold reached
#   - Triggers perk selection popup
#   - Does NOT affect EXP gain
#
# CLEARANCE (manual choice):
#   - Only increases when chosen as a perk
#   - Unlocks knowledge/entity information in KnowledgeDB
#   - Multiplies ALL EXP gains (×1 at CL0, ×2 at CL1, ×3 at CL2, etc.)
#   - "Glass cannon" build: faster scaling but must spend perk slots
#
# Example: At Clearance 2, examining floor gives 10 base → 30 EXP (10×3)
# ============================================================================

var exp: int = 0
var level: int = 0  # Auto-increases when EXP threshold met → triggers perk selection
var clearance_level: int = 0  # Manual only (via perk choice) → unlocks knowledge + EXP multiplier

# ============================================================================
# MODIFIER SYSTEM
# ============================================================================

var modifiers: Array[StatModifier] = []

# ============================================================================
# CACHE INVALIDATION
# ============================================================================

var _cache: Dictionary = {}
var _cache_dirty: Dictionary = {
	"hp": true,
	"sanity": true,
	"mana": true,
	"strength": true,
	"perception": true,
	"anomaly": true,
}

# ============================================================================
# COMPUTED PROPERTIES (with caching)
# ============================================================================

var max_hp: float:
	get:
		if _cache_dirty["hp"]:
			_cache["hp"] = _calculate_stat("hp", body, 10.0, bonus_hp)
			_cache_dirty["hp"] = false
		return _cache["hp"]

var max_sanity: float:
	get:
		if _cache_dirty["sanity"]:
			_cache["sanity"] = _calculate_stat("sanity", mind, 10.0, bonus_sanity)
			_cache_dirty["sanity"] = false
		return _cache["sanity"]

var max_mana: float:
	get:
		if _cache_dirty["mana"]:
			_cache["mana"] = _calculate_stat("mana", null_stat, 10.0, bonus_mana)
			_cache_dirty["mana"] = false
		return _cache["mana"]

var strength: float:
	get:
		if _cache_dirty["strength"]:
			_cache["strength"] = _calculate_stat("strength", body, 1.0, bonus_strength)
			_cache_dirty["strength"] = false
		return _cache["strength"]

var perception: float:
	get:
		if _cache_dirty["perception"]:
			_cache["perception"] = _calculate_stat("perception", mind, 1.0, bonus_perception)
			_cache_dirty["perception"] = false
		return _cache["perception"]

var anomaly: float:
	get:
		if _cache_dirty["anomaly"]:
			_cache["anomaly"] = _calculate_stat("anomaly", null_stat, 1.0, bonus_anomaly)
			_cache_dirty["anomaly"] = false
		return _cache["anomaly"]

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(template: StatTemplate = null):
	"""Initialize from template or use defaults."""
	if template:
		body = template.base_body
		mind = template.base_mind
		null_stat = template.base_null

		bonus_hp = template.bonus_hp
		bonus_sanity = template.bonus_sanity
		bonus_mana = template.bonus_mana
		bonus_strength = template.bonus_strength
		bonus_perception = template.bonus_perception
		bonus_anomaly = template.bonus_anomaly

		exp = template.starting_exp
		clearance_level = template.starting_clearance

	# Initialize current resources to max
	_invalidate_cache()
	current_hp = max_hp
	current_sanity = max_sanity
	current_mana = max_mana

# ============================================================================
# STAT CALCULATION (with modifiers)
# ============================================================================

func _calculate_stat(stat_name: String, base_stat: int, multiplier: float, direct_bonus: float = 0.0) -> float:
	"""Calculate effective stat with modifiers.

	Formula:
	1. base = (base_stat × multiplier) + direct_bonus + ADD modifiers
	2. effective = base × (1 + base_stat/100)  [percentage scaling]
	3. effective = effective × MULTIPLY modifiers

	Example (BODY=5, bonus_hp=0, Armor+20):
	1. base = (5 × 10) + 0 + 20 = 70
	2. effective = 70 × 1.05 = 73.5
	3. effective = 73.5 (no multiply modifiers)
	"""
	# Step 1: Calculate base with ADD modifiers
	var base = (base_stat * multiplier) + direct_bonus

	for mod in modifiers:
		if mod.stat_name == stat_name and mod.type == StatModifier.ModifierType.ADD:
			base += mod.value

	# Step 2: Apply percentage scaling
	var effective = base * (1.0 + base_stat / 100.0)

	# Step 3: Apply MULTIPLY modifiers
	for mod in modifiers:
		if mod.stat_name == stat_name and mod.type == StatModifier.ModifierType.MULTIPLY:
			effective *= mod.value

	return round(effective)  # Round to int for cleaner display

# ============================================================================
# MODIFIER MANAGEMENT
# ============================================================================

func add_modifier(modifier: StatModifier) -> void:
	"""Add a stat modifier (equipment, buff, etc.)."""
	modifiers.append(modifier)
	_invalidate_cache()
	emit_signal("modifier_added", modifier)
	Log.system("Added modifier: %s" % str(modifier))

func remove_modifier(unique_id: String) -> bool:
	"""Remove a modifier by unique ID. Returns true if found."""
	for i in range(modifiers.size()):
		if modifiers[i].unique_id == unique_id:
			var removed = modifiers[i]
			modifiers.remove_at(i)
			_invalidate_cache()
			emit_signal("modifier_removed", removed)
			Log.system("Removed modifier: %s" % str(removed))
			return true
	return false

func remove_modifiers_by_source(source: String) -> int:
	"""Remove all modifiers from a source (e.g., unequipping item). Returns count removed."""
	var count = 0
	for i in range(modifiers.size() - 1, -1, -1):  # Reverse iteration for safe removal
		if modifiers[i].source == source:
			var removed = modifiers[i]
			modifiers.remove_at(i)
			emit_signal("modifier_removed", removed)
			count += 1

	if count > 0:
		_invalidate_cache()
		Log.system("Removed %d modifiers from %s" % [count, source])

	return count

func tick_temporary_modifiers() -> void:
	"""Decrease duration of temporary modifiers, remove expired ones."""
	var expired: Array[StatModifier] = []

	for mod in modifiers:
		if mod.tick_duration():
			expired.append(mod)

	for mod in expired:
		modifiers.erase(mod)
		emit_signal("modifier_removed", mod)
		Log.system("Expired modifier: %s" % str(mod))

	if expired.size() > 0:
		_invalidate_cache()

func get_modifiers_for_stat(stat_name: String) -> Array[StatModifier]:
	"""Get all modifiers affecting a specific stat (for tooltip/breakdown)."""
	var result: Array[StatModifier] = []
	for mod in modifiers:
		if mod.stat_name == stat_name:
			result.append(mod)
	return result

# ============================================================================
# RESOURCE MANAGEMENT
# ============================================================================

func take_damage(amount: float) -> void:
	"""Reduce HP by amount."""
	var old_hp = current_hp
	current_hp -= amount
	Log.system("Took %.1f damage (%.1f → %.1f)" % [amount, old_hp, current_hp])

func heal(amount: float) -> void:
	"""Restore HP by amount (clamped to max)."""
	var old_hp = current_hp
	current_hp += amount
	Log.system("Healed %.1f HP (%.1f → %.1f)" % [amount, old_hp, current_hp])

func drain_sanity(amount: float) -> void:
	"""Reduce Sanity by amount."""
	var old_sanity = current_sanity
	current_sanity -= amount
	Log.system("Lost %.1f sanity (%.1f → %.1f)" % [amount, old_sanity, current_sanity])

func restore_sanity(amount: float) -> void:
	"""Restore Sanity by amount (clamped to max)."""
	var old_sanity = current_sanity
	current_sanity += amount
	Log.system("Restored %.1f sanity (%.1f → %.1f)" % [amount, old_sanity, current_sanity])

func consume_mana(amount: float) -> bool:
	"""Try to consume mana. Returns true if successful."""
	if current_mana >= amount:
		var old_mana = current_mana
		current_mana -= amount
		Log.system("Consumed %.1f mana (%.1f → %.1f)" % [amount, old_mana, current_mana])
		return true
	else:
		Log.system("Not enough mana (%.1f/%.1f)" % [current_mana, amount])
		return false

func restore_mana(amount: float) -> void:
	"""Restore Mana by amount (clamped to max)."""
	var old_mana = current_mana
	current_mana += amount
	Log.system("Restored %.1f mana (%.1f → %.1f)" % [amount, old_mana, current_mana])

# ============================================================================
# PROGRESSION
# ============================================================================

func gain_exp(amount: int) -> void:
	"""Add EXP with Clearance multiplier. Check for level up.

	IMPORTANT: EXP gain scales with CLEARANCE, not Level!
	This is intentional - Clearance is the "glass cannon" build choice.
	Higher Clearance = faster scaling but must be chosen via perks.

	Formula: EXP gained = base_amount × (clearance_level + 1)
	  Clearance 0: ×1
	  Clearance 1: ×2
	  Clearance 2: ×3
	  etc.
	"""
	var multiplied = amount * (clearance_level + 1)
	exp += multiplied
	emit_signal("exp_gained", multiplied, exp)
	Log.player("Gained %d EXP (×%d = %d total, now %d)" % [amount, clearance_level + 1, multiplied, exp])

	_check_level_up()

func _check_level_up() -> void:
	"""Check if player has enough EXP to level up (triggers perk selection)."""
	var required = _exp_for_level(level + 1)

	while exp >= required:
		var old_level = level
		level += 1
		emit_signal("level_increased", old_level, level)
		Log.system("Level Up! %d → %d (choose a perk!)" % [old_level, level])

		# Check next level
		required = _exp_for_level(level + 1)

func _exp_for_level(target_level: int) -> int:
	"""Calculate EXP required for a given Level.

	Formula: BASE × (level ^ EXPONENT)
	BASE = 100
	EXPONENT = 1.5

	Examples:
	  Level 1:  100 × (1^1.5) = 100
	  Level 2:  100 × (2^1.5) = 283
	  Level 5:  100 × (5^1.5) = 1118
	  Level 10: 100 × (10^1.5) = 3162
	"""
	const BASE = 100
	const EXPONENT = 1.5
	return int(BASE * pow(target_level, EXPONENT))

func exp_to_next_level() -> int:
	"""How much EXP needed for next Level."""
	return _exp_for_level(level + 1) - exp

func increase_clearance() -> void:
	"""Manually increase Clearance (called when player chooses Clearance perk)."""
	var old_clearance = clearance_level
	clearance_level += 1
	emit_signal("clearance_increased", old_clearance, clearance_level)
	Log.system("Clearance increased! %d → %d (knowledge unlocked)" % [old_clearance, clearance_level])

# ============================================================================
# UTILITY
# ============================================================================

func _invalidate_cache() -> void:
	"""Mark all cached stats as dirty."""
	for key in _cache_dirty.keys():
		_cache_dirty[key] = true

func get_stat_breakdown(stat_name: String) -> Dictionary:
	"""Get detailed breakdown of a stat for tooltips.

	Returns:
	{
		"base": 50.0,
		"percentage_bonus": 5.0,
		"modifiers": [
			{"source": "Leather Armor", "value": 20.0, "type": "ADD"},
			{"source": "Rage Potion", "value": 1.5, "type": "MULTIPLY"}
		],
		"final": 78.75
	}
	"""
	var breakdown = {
		"base": 0.0,
		"percentage_bonus": 0.0,
		"modifiers": [],
		"final": 0.0
	}

	# Determine base stat and multiplier
	var base_stat = 0
	var multiplier = 0.0
	var direct_bonus = 0.0

	match stat_name:
		"hp":
			base_stat = body
			multiplier = 10.0
			direct_bonus = bonus_hp
		"sanity":
			base_stat = mind
			multiplier = 10.0
			direct_bonus = bonus_sanity
		"mana":
			base_stat = null_stat
			multiplier = 10.0
			direct_bonus = bonus_mana
		"strength":
			base_stat = body
			multiplier = 1.0
			direct_bonus = bonus_strength
		"perception":
			base_stat = mind
			multiplier = 1.0
			direct_bonus = bonus_perception
		"anomaly":
			base_stat = null_stat
			multiplier = 1.0
			direct_bonus = bonus_anomaly

	# Calculate base (before percentage)
	var base = (base_stat * multiplier) + direct_bonus

	# Add ADD modifiers to base
	for mod in modifiers:
		if mod.stat_name == stat_name and mod.type == StatModifier.ModifierType.ADD:
			base += mod.value
			breakdown["modifiers"].append({
				"source": mod.source,
				"value": mod.value,
				"type": "ADD"
			})

	breakdown["base"] = base
	breakdown["percentage_bonus"] = base_stat

	# Apply percentage scaling
	var effective = base * (1.0 + base_stat / 100.0)

	# Apply MULTIPLY modifiers
	for mod in modifiers:
		if mod.stat_name == stat_name and mod.type == StatModifier.ModifierType.MULTIPLY:
			effective *= mod.value
			breakdown["modifiers"].append({
				"source": mod.source,
				"value": mod.value,
				"type": "MULTIPLY"
			})

	breakdown["final"] = round(effective)

	return breakdown

func _to_string() -> String:
	"""Debug representation."""
	return "StatBlock(BODY:%d MIND:%d NULL:%d | HP:%.0f/%.0f SAN:%.0f/%.0f MANA:%.0f/%.0f | STR:%.0f PER:%.0f ANOM:%.0f | EXP:%d Lv:%d CL:%d | Mods:%d)" % [
		body, mind, null_stat,
		current_hp, max_hp,
		current_sanity, max_sanity,
		current_mana, max_mana,
		strength, perception, anomaly,
		exp, level, clearance_level,
		modifiers.size()
	]
