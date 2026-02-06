extends Node
## Map Marker Manager — persistent marker data for map overlay
##
## Stores player-placed map markers per level. Markers persist across
## chunk load/unload but are cleared on new run.

# ============================================================================
# CONSTANTS
# ============================================================================

const MAX_MARKERS_PER_LEVEL := 10

# ============================================================================
# STATE
# ============================================================================

## {level_id: Array[{name: String, position: Vector2i}]}
var markers: Dictionary = {}

# ============================================================================
# PUBLIC API
# ============================================================================

func add_marker(position: Vector2i, level_id: int) -> bool:
	"""Add a marker at the given position. Returns false if at limit."""
	if not markers.has(level_id):
		markers[level_id] = []

	var level_markers: Array = markers[level_id]
	if level_markers.size() >= MAX_MARKERS_PER_LEVEL:
		return false

	var marker_num := level_markers.size() + 1
	level_markers.append({
		"name": "Marker %d" % marker_num,
		"position": position,
	})
	return true

func remove_marker(level_id: int, index: int) -> void:
	"""Remove a marker by index."""
	if not markers.has(level_id):
		return
	var level_markers: Array = markers[level_id]
	if index >= 0 and index < level_markers.size():
		level_markers.remove_at(index)

func get_markers(level_id: int) -> Array:
	"""Get all markers for a level. Returns empty array if none."""
	return markers.get(level_id, [])

func get_marker_count(level_id: int) -> int:
	"""Get number of markers on a level."""
	return markers.get(level_id, []).size()

func reset() -> void:
	"""Clear all markers (called on new run)."""
	markers.clear()
