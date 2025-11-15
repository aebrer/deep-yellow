class_name CorruptionTracker extends RefCounted
## Tracks per-level corruption escalation
##
## Corruption increases as chunks are loaded/explored, and modifies entity
## spawn probabilities. This creates escalating difficulty and forces the
## player to eventually find an exit before being overwhelmed.

# Per-level corruption values
var corruption_by_level: Dictionary = {}  # level_id (int) -> corruption (float)

# ============================================================================
# CORRUPTION MANAGEMENT
# ============================================================================

func increase_corruption(level_id: int, amount: float, max_value: float) -> void:
	"""Increase corruption for a level

	Args:
		level_id: Which Backrooms level (0, 1, 2...)
		amount: How much to increase (typically 0.1 per chunk)
		max_value: Maximum corruption value (typically 10.0)
	"""
	var current := corruption_by_level.get(level_id, 0.0)
	var new_value := minf(current + amount, max_value)
	corruption_by_level[level_id] = new_value

	Log.turn("Corruption increased on Level %d: %.2f (+%.2f)" % [
		level_id,
		new_value,
		amount
	])

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

# ============================================================================
# PROBABILITY CALCULATION
# ============================================================================

func calculate_spawn_probability(
	base_prob: float,
	multiplier: float,
	corruption: float
) -> float:
	"""Calculate final spawn probability with corruption modifier

	Formula: final_prob = base_prob × (1 + corruption × multiplier)

	Examples:
		- Positive multiplier: probability increases with corruption
		  base=0.05, mult=1.5, corruption=5
		  → 0.05 × (1 + 5×1.5) = 0.425 (42.5%)

		- Negative multiplier: probability decreases with corruption
		  base=0.05, mult=-0.3, corruption=5
		  → 0.05 × (1 + 5×-0.3) = 0.0125 (1.25%)

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
	Log.system("All corruption reset (new run)")

# ============================================================================
# DEBUG
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
