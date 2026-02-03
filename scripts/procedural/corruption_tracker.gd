class_name CorruptionTracker extends RefCounted
## Tracks per-level corruption escalation
##
## IMPORTANT: Corruption is an UNBOUNDED scaling value (0.0, 0.01, 0.02, ..., 1.0, 2.0, ...).
## It is NOT a percentage and has NO upper limit.
##
## Corruption increases as new chunks are explored and modifies:
## - Entity spawn counts: BASE_ENTITIES_PER_CHUNK + int(corruption * ENTITIES_PER_CORRUPTION)
## - Entity type distribution: threat_level affects spawn weight scaling
## - Entity HP: base_hp * (1 + (corruption / 0.05) * hp_scale)
## - Entity damage: base_damage * (1 + (corruption / 0.05) * damage_scale)
## - Item spawn probabilities: via corruption_multiplier in ItemRarity
##
## Scaling uses 0.05 as the corruption step size. At corruption 0.25 (5 steps):
##   - HP: 100 * (1 + 5 * 0.1) = 150 HP (with hp_scale=0.1)
##   - Damage: 3 * (1 + 5 * 0.05) = 3.75 (with damage_scale=0.05)
##
## This creates escalating difficulty and forces the player to eventually
## find an exit before being overwhelmed.

signal corruption_changed(level_id: int, new_value: float)

# Per-level corruption values
var corruption_by_level: Dictionary = {}  # level_id (int) -> corruption (float)

# ============================================================================
# CORRUPTION MANAGEMENT
# ============================================================================

func increase_corruption(level_id: int, amount: float, max_value: float) -> void:
	"""Increase corruption for a level

	Args:
		level_id: Which Backrooms level (0, 1, 2...)
		amount: How much to increase (e.g., 0.01 per new chunk explored)
		max_value: Maximum corruption value (0.0 = no max, which is the default)
	"""
	var current: float = corruption_by_level.get(level_id, 0.0)
	var new_value := current + amount

	# Apply max if specified (0 = no max)
	if max_value > 0.0:
		new_value = minf(new_value, max_value)

	corruption_by_level[level_id] = new_value
	corruption_changed.emit(level_id, new_value)

func get_corruption(level_id: int) -> float:
	"""Get current corruption value for a level

	Returns 0.0 if level has not been visited yet.
	"""
	return corruption_by_level.get(level_id, 0.0)

func set_corruption(level_id: int, value: float) -> void:
	"""Directly set corruption value for a level

	Useful for testing or special events.
	"""
	corruption_by_level[level_id] = value
	corruption_changed.emit(level_id, value)

# ============================================================================
# PROBABILITY CALCULATION
# ============================================================================

func calculate_spawn_probability(
	base_prob: float,
	multiplier: float,
	corruption: float
) -> float:
	"""Calculate final spawn probability with corruption modifier

	Used by ItemSpawner for item rarity calculations.
	Formula: final_prob = base_prob × (1 + corruption × multiplier)

	Args:
		base_prob: Base spawn probability (0.0 to 1.0)
		multiplier: Corruption scaling factor (positive = more common, negative = rarer)
		corruption: Current corruption value (UNBOUNDED: 0.0, 0.5, 1.0, 2.0, ...)

	Examples (corruption is unbounded, not 0-1):
		- Positive multiplier: probability increases with corruption
		  base=0.05, mult=0.5, corruption=2.0
		  → 0.05 × (1 + 2.0×0.5) = 0.1 (10%)

		- Negative multiplier: probability decreases with corruption
		  base=0.05, mult=-0.3, corruption=2.0
		  → 0.05 × (1 + 2.0×-0.3) = 0.02 (2%)

	Result is clamped to [0.0, 1.0] range.
	"""
	var final := base_prob * (1.0 + corruption * multiplier)
	return clampf(final, 0.0, 1.0)

# ============================================================================
# RESET
# ============================================================================

func reset_level(level_id: int) -> void:
	"""Reset corruption for a specific level

	Useful if player somehow cleanses corruption or for special events.
	"""
	corruption_by_level.erase(level_id)
	Log.turn("Corruption reset on Level %d" % level_id)

func reset_all() -> void:
	"""Reset all corruption (new run)"""
	corruption_by_level.clear()

# ============================================================================
# UTILITY
# ============================================================================

func get_all_corruption_levels() -> Dictionary:
	"""Get copy of all corruption values (for debugging/UI)"""
	return corruption_by_level.duplicate()

func _to_string() -> String:
	var levels: Array[String] = []
	for level_id in corruption_by_level.keys():
		levels.append("Level %d: %.2f" % [level_id, corruption_by_level[level_id]])

	if levels.is_empty():
		return "CorruptionTracker(no corruption)"

	return "CorruptionTracker(%s)" % ", ".join(levels)
