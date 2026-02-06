class_name EnemyListPanel
extends VBoxContainer
## Right panel of map overlay — shows nearby entities
##
## Lists entities within perception range, sorted by distance.
## Examined entities show name + threat level; unexamined show "Unknown Entity".
## Selecting an entry highlights its position on the center map.

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 16
const FONT_SIZE_ENTRY := 13
const FONT_SIZE_DETAIL := 11

## Threat level display names
const THREAT_NAMES := {
	0: "Harmless",
	1: "Low",
	2: "Moderate",
	3: "Dangerous",
	4: "Elite",
	5: "Boss",
}

## Threat level colors
const THREAT_COLORS := {
	0: Color(0.5, 0.5, 0.5),  # Gray
	1: Color(0.5, 0.8, 0.5),  # Green
	2: Color(0.9, 0.9, 0.3),  # Yellow
	3: Color(0.9, 0.5, 0.2),  # Orange
	4: Color(0.9, 0.2, 0.2),  # Red
	5: Color(0.8, 0.2, 0.8),  # Purple
}

# ============================================================================
# SIGNALS
# ============================================================================

signal entry_selected(world_pos: Vector2i)

# ============================================================================
# STATE
# ============================================================================

var _entries: Array[Dictionary] = []  # Cached entity data for current view
var _entry_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _header_label: Label
var _empty_label: Label
var _gamepad_focus_idx: int = -1

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_theme_constant_override("separation", 6)

	# Header
	_header_label = Label.new()
	_header_label.text = "NEARBY"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	_header_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	add_child(_header_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	add_child(sep)

	# Scrollable list
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list_vbox)

	# Empty state label
	_empty_label = Label.new()
	_empty_label.text = "No entities nearby"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", FONT_SIZE_ENTRY)
	_empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	_list_vbox.add_child(_empty_label)

# ============================================================================
# PUBLIC API
# ============================================================================

func refresh(player: Node, grid: Node) -> void:
	"""Refresh the entity list based on current game state."""
	_entries.clear()

	if not player or not grid or not grid.entity_renderer:
		_rebuild_list()
		return

	# Get perception range
	var perception_range: float = 15.0
	if player.stats:
		perception_range = 15.0 + (player.stats.perception * 5.0)

	var player_pos: Vector2i = player.grid_position

	# Get all entity positions (not just hostile)
	var entity_positions = grid.entity_renderer.get_all_entity_positions()

	for entity_pos in entity_positions:
		var entity = grid.entity_renderer.get_entity_at(entity_pos)
		if not entity:
			continue

		var distance: float = Vector2(entity_pos).distance_to(Vector2(player_pos))
		if distance > perception_range:
			continue

		# Check if this entity has been examined
		var entity_key := "entity:%s" % entity.entity_type
		var is_examined: bool = KnowledgeDB.examined_at_clearance.has(entity_key)

		# Also check environment key for objects
		if not is_examined:
			var env_key := "environment:%s" % entity.entity_type
			is_examined = KnowledgeDB.examined_at_clearance.has(env_key)

		var entry := {}
		entry["position"] = entity_pos
		entry["distance"] = distance
		entry["hostile"] = entity.hostile
		entry["is_exit"] = entity.is_exit
		entry["examined"] = is_examined

		if is_examined and EntityRegistry.has_entity(entity.entity_type):
			var info = EntityRegistry.get_info(entity.entity_type, KnowledgeDB.clearance_level)
			entry["name"] = info.get("name", entity.entity_type)
			entry["threat_level"] = info.get("threat_level", 1)
		else:
			entry["name"] = "Unknown Entity" if not is_examined else entity.entity_type
			entry["threat_level"] = -1  # Unknown

		_entries.append(entry)

	# Sort by distance (nearest first)
	_entries.sort_custom(func(a, b): return a["distance"] < b["distance"])

	_rebuild_list()

func _rebuild_list() -> void:
	"""Rebuild the visual list from cached entries."""
	# Clear existing buttons
	for btn in _entry_buttons:
		btn.queue_free()
	_entry_buttons.clear()

	if _entries.is_empty():
		_empty_label.visible = true
		return

	_empty_label.visible = false

	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", FONT_SIZE_ENTRY)

		# Build display text
		var name_text: String = entry["name"]
		var dist_text := "%dm" % int(entry["distance"])
		var threat_text := ""

		if entry["is_exit"]:
			threat_text = "Exit"
			btn.add_theme_color_override("font_color", Color(0.85, 0.75, 0.0))
		elif not entry["hostile"]:
			threat_text = "Neutral"
			btn.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
		elif entry["threat_level"] >= 0:
			var tl: int = entry["threat_level"]
			threat_text = THREAT_NAMES.get(tl, "?")
			btn.add_theme_color_override("font_color", THREAT_COLORS.get(tl, Color.WHITE))
		else:
			threat_text = "??"
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

		btn.text = "%s  [%s]  %s" % [name_text, dist_text, threat_text]

		# Flat style
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.6)
		style.set_border_width_all(0)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", style)

		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
		hover_style.set_border_width_all(1)
		hover_style.border_color = Color(0.4, 0.4, 0.6)
		hover_style.content_margin_left = 6
		hover_style.content_margin_right = 6
		hover_style.content_margin_top = 4
		hover_style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style = hover_style.duplicate()
		pressed_style.bg_color = Color(0.15, 0.15, 0.25, 0.9)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.add_theme_stylebox_override("focus", _create_focus_style())

		var entry_pos: Vector2i = entry["position"]
		btn.pressed.connect(func(): entry_selected.emit(entry_pos))

		_list_vbox.add_child(btn)
		_entry_buttons.append(btn)

# ============================================================================
# GAMEPAD NAVIGATION
# ============================================================================

func get_entry_count() -> int:
	return _entry_buttons.size()

func gamepad_navigate(direction: int) -> void:
	"""Navigate entries by direction (-1 = up, +1 = down)."""
	if _entry_buttons.is_empty():
		return
	var new_idx: int
	if _gamepad_focus_idx < 0:
		new_idx = 0 if direction > 0 else _entry_buttons.size() - 1
	else:
		new_idx = clampi(_gamepad_focus_idx + direction, 0, _entry_buttons.size() - 1)
	_set_gamepad_focus(new_idx)

func gamepad_activate() -> void:
	"""Activate the focused entry (same as clicking it)."""
	if _gamepad_focus_idx >= 0 and _gamepad_focus_idx < _entry_buttons.size():
		_entry_buttons[_gamepad_focus_idx].pressed.emit()

func clear_gamepad_focus() -> void:
	"""Remove gamepad focus visual."""
	if _gamepad_focus_idx >= 0 and _gamepad_focus_idx < _entry_buttons.size():
		_entry_buttons[_gamepad_focus_idx].add_theme_stylebox_override("normal", _create_normal_style())
	_gamepad_focus_idx = -1

func _set_gamepad_focus(index: int) -> void:
	"""Set visual gamepad focus on an entry."""
	# Clear previous focus
	if _gamepad_focus_idx >= 0 and _gamepad_focus_idx < _entry_buttons.size():
		_entry_buttons[_gamepad_focus_idx].add_theme_stylebox_override("normal", _create_normal_style())

	_gamepad_focus_idx = index

	# Apply focus style and grab Godot GUI focus so A/Enter activates the button
	if index >= 0 and index < _entry_buttons.size():
		_entry_buttons[index].add_theme_stylebox_override("normal", _create_focus_style())
		_entry_buttons[index].grab_focus()
		_scroll.ensure_control_visible(_entry_buttons[index])

func _create_normal_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.6)
	style.set_border_width_all(0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _create_focus_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25, 0.8)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.5, 0.9, 1.0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
