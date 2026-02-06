class_name MapMarkerPanel
extends VBoxContainer
## Left panel of map overlay — manage map markers
##
## "Place Marker Here" button at top, scrollable list of markers below.
## Selecting a marker shows Go To / Delete inline actions.
## Selecting a marker also highlights its position on the center map.

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 16
const FONT_SIZE_ENTRY := 13
const FONT_SIZE_BUTTON := 12

# ============================================================================
# SIGNALS
# ============================================================================

signal entry_selected(world_pos: Vector2i)
signal goto_requested(world_pos: Vector2i)

# ============================================================================
# STATE
# ============================================================================

var _player_ref: Node = null
var _entry_buttons: Array[Button] = []
var _selected_index: int = -1
var _gamepad_focus_idx: int = -1
var _scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _header_label: Label
var _place_button: Button
var _empty_label: Label
var _action_hbox: HBoxContainer = null  # Inline actions for selected marker

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_theme_constant_override("separation", 6)

	# Header
	_header_label = Label.new()
	_header_label.text = "MARKERS"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	_header_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	add_child(_header_label)

	# Place Marker button
	_place_button = Button.new()
	_place_button.text = "+ Place Marker Here"
	_place_button.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	_place_button.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))

	var place_style = StyleBoxFlat.new()
	place_style.bg_color = Color(0.1, 0.2, 0.12, 0.8)
	place_style.set_border_width_all(1)
	place_style.border_color = Color(0.3, 0.6, 0.35)
	place_style.content_margin_left = 8
	place_style.content_margin_right = 8
	place_style.content_margin_top = 5
	place_style.content_margin_bottom = 5
	_place_button.add_theme_stylebox_override("normal", place_style)

	var place_hover = place_style.duplicate()
	place_hover.bg_color = Color(0.15, 0.3, 0.17, 0.9)
	_place_button.add_theme_stylebox_override("hover", place_hover)

	var place_focus = place_style.duplicate()
	place_focus.bg_color = Color(0.12, 0.25, 0.14, 0.9)
	place_focus.set_border_width_all(2)
	place_focus.border_color = Color(0.3, 0.7, 0.4, 1.0)
	_place_button.add_theme_stylebox_override("focus", place_focus)

	_place_button.pressed.connect(_on_place_marker)
	add_child(_place_button)

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
	_list_vbox.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list_vbox)

	# Empty state
	_empty_label = Label.new()
	_empty_label.text = "No markers placed"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", FONT_SIZE_ENTRY)
	_empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	_list_vbox.add_child(_empty_label)

# ============================================================================
# PUBLIC API
# ============================================================================

func refresh(player: Node) -> void:
	"""Refresh marker list from MapMarkerManager."""
	_player_ref = player
	_selected_index = -1
	_rebuild_list()

func _rebuild_list() -> void:
	"""Rebuild the visual marker list."""
	# Clear existing entries
	for btn in _entry_buttons:
		btn.queue_free()
	_entry_buttons.clear()
	_gamepad_focus_idx = -1
	if _action_hbox:
		# remove_child immediately so it doesn't affect index calculations below
		_list_vbox.remove_child(_action_hbox)
		_action_hbox.queue_free()
		_action_hbox = null

	var level_id := _get_current_level_id()
	var marker_mgr = _get_marker_manager()
	if not marker_mgr:
		_empty_label.visible = true
		_update_place_button(0)
		return

	var markers: Array = marker_mgr.get_markers(level_id)

	if markers.is_empty():
		_empty_label.visible = true
		_update_place_button(0)
		return

	_empty_label.visible = false
	_update_place_button(markers.size())

	var player_pos: Vector2i = _player_ref.grid_position if _player_ref else Vector2i.ZERO

	for i in range(markers.size()):
		var marker: Dictionary = markers[i]
		var pos: Vector2i = marker["position"]
		var name_text: String = marker["name"]

		# Calculate distance
		var dist := Vector2(pos).distance_to(Vector2(player_pos))
		var dist_text := "%dm" % int(dist)

		var btn := Button.new()
		btn.text = "%s  [%s]" % [name_text, dist_text]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", FONT_SIZE_ENTRY)
		btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.12, 0.08, 0.6)
		style.set_border_width_all(0)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", style)

		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.15, 0.22, 0.15, 0.8)
		hover_style.set_border_width_all(1)
		hover_style.border_color = Color(0.3, 0.5, 0.35)
		hover_style.content_margin_left = 6
		hover_style.content_margin_right = 6
		hover_style.content_margin_top = 4
		hover_style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.add_theme_stylebox_override("focus", _create_focus_style())

		var idx := i
		btn.pressed.connect(func(): _on_marker_selected(idx))

		_list_vbox.add_child(btn)
		_entry_buttons.append(btn)

func _on_marker_selected(index: int) -> void:
	"""Handle clicking on a marker entry."""
	_selected_index = index

	# Highlight on map
	var level_id := _get_current_level_id()
	var marker_mgr = _get_marker_manager()
	if marker_mgr:
		var markers: Array = marker_mgr.get_markers(level_id)
		if index >= 0 and index < markers.size():
			var pos: Vector2i = markers[index]["position"]
			entry_selected.emit(pos)

	# Show inline actions
	_show_inline_actions(index)

func _show_inline_actions(index: int) -> void:
	"""Show Go To / Delete buttons for selected marker."""
	# Remove previous action bar immediately so it doesn't affect index calculations
	if _action_hbox:
		_list_vbox.remove_child(_action_hbox)
		_action_hbox.queue_free()
		_action_hbox = null

	# Insert action bar after the selected button
	if index < 0 or index >= _entry_buttons.size():
		return

	_action_hbox = HBoxContainer.new()
	_action_hbox.add_theme_constant_override("separation", 4)
	_action_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Go To button
	var goto_btn := Button.new()
	goto_btn.text = "Go To"
	goto_btn.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	goto_btn.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	goto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var goto_style = StyleBoxFlat.new()
	goto_style.bg_color = Color(0.1, 0.15, 0.2, 0.8)
	goto_style.set_border_width_all(1)
	goto_style.border_color = Color(0.3, 0.5, 0.7)
	goto_style.content_margin_left = 4
	goto_style.content_margin_right = 4
	goto_style.content_margin_top = 3
	goto_style.content_margin_bottom = 3
	goto_btn.add_theme_stylebox_override("normal", goto_style)

	var goto_hover = goto_style.duplicate()
	goto_hover.bg_color = Color(0.15, 0.22, 0.3, 0.9)
	goto_btn.add_theme_stylebox_override("hover", goto_hover)

	var goto_focus = goto_style.duplicate()
	goto_focus.set_border_width_all(2)
	goto_focus.border_color = Color(0.3, 0.7, 0.9, 1.0)
	goto_btn.add_theme_stylebox_override("focus", goto_focus)

	var idx := index
	goto_btn.pressed.connect(func(): _on_goto_marker(idx))
	_action_hbox.add_child(goto_btn)

	# Delete button
	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var del_style = StyleBoxFlat.new()
	del_style.bg_color = Color(0.2, 0.1, 0.1, 0.8)
	del_style.set_border_width_all(1)
	del_style.border_color = Color(0.5, 0.3, 0.3)
	del_style.content_margin_left = 4
	del_style.content_margin_right = 4
	del_style.content_margin_top = 3
	del_style.content_margin_bottom = 3
	delete_btn.add_theme_stylebox_override("normal", del_style)

	var del_hover = del_style.duplicate()
	del_hover.bg_color = Color(0.3, 0.12, 0.12, 0.9)
	delete_btn.add_theme_stylebox_override("hover", del_hover)

	var del_focus = del_style.duplicate()
	del_focus.set_border_width_all(2)
	del_focus.border_color = Color(0.7, 0.3, 0.3, 1.0)
	delete_btn.add_theme_stylebox_override("focus", del_focus)

	delete_btn.pressed.connect(func(): _on_delete_marker(idx))
	_action_hbox.add_child(delete_btn)

	# Insert after the selected button in the list
	var btn_index := _entry_buttons[index].get_index()
	_list_vbox.add_child(_action_hbox)
	_list_vbox.move_child(_action_hbox, btn_index + 1)

func _on_place_marker() -> void:
	"""Place a marker at player's current position."""
	if not _player_ref:
		return

	var level_id := _get_current_level_id()
	var marker_mgr = _get_marker_manager()
	if not marker_mgr:
		return

	var success: bool = marker_mgr.add_marker(_player_ref.grid_position, level_id)
	if success:
		Log.player("Marker placed")
		_rebuild_list()
		# Highlight new marker on map
		entry_selected.emit(_player_ref.grid_position)
	else:
		Log.player("Cannot place marker: limit reached (%d)" % 10)

func _on_goto_marker(index: int) -> void:
	"""Navigate to a marker using auto-explore."""
	var level_id := _get_current_level_id()
	var marker_mgr = _get_marker_manager()
	if not marker_mgr:
		return

	var markers: Array = marker_mgr.get_markers(level_id)
	if index >= 0 and index < markers.size():
		var pos: Vector2i = markers[index]["position"]
		goto_requested.emit(pos)

func _on_delete_marker(index: int) -> void:
	"""Delete a marker."""
	var level_id := _get_current_level_id()
	var marker_mgr = _get_marker_manager()
	if not marker_mgr:
		return

	marker_mgr.remove_marker(level_id, index)
	_selected_index = -1
	Log.player("Marker deleted")
	_rebuild_list()

# ============================================================================
# HELPERS
# ============================================================================

func _get_current_level_id() -> int:
	"""Get current level ID from LevelManager."""
	var current = LevelManager.get_current_level()
	return current.level_id if current else 0

func _get_marker_manager() -> Node:
	"""Get MapMarkerManager autoload."""
	return get_node_or_null("/root/MapMarkerManager")

func _update_place_button(marker_count: int) -> void:
	"""Update place button text and enabled state."""
	if marker_count >= 10:
		_place_button.text = "Marker limit reached (%d)" % 10
		_place_button.disabled = true
	else:
		_place_button.text = "+ Place Marker Here (%d/%d)" % [marker_count, 10]
		_place_button.disabled = false

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
	"""Activate focused entry. First A = select, second A on same = Go To."""
	if _gamepad_focus_idx < 0 or _gamepad_focus_idx >= _entry_buttons.size():
		return
	if _selected_index == _gamepad_focus_idx:
		# Already selected — trigger Go To
		_on_goto_marker(_gamepad_focus_idx)
	else:
		# Select this marker (highlight on map + show inline actions)
		_on_marker_selected(_gamepad_focus_idx)

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
	style.bg_color = Color(0.08, 0.12, 0.08, 0.6)
	style.set_border_width_all(0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _create_focus_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.18, 0.12, 0.8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.7, 0.4, 1.0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
