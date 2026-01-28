class_name CodexPanel
extends Control
## Codex panel - shows all examined subjects with progressive revelation
##
## Full-screen overlay popup (like LevelUpPanel) accessed from the settings
## panel's "Codex" button. Shows all entities, items, and environment objects
## the player has examined, organized by category.
##
## Two-pane layout:
##   Left: Category list with entry buttons (scrollable)
##   Right: Detail view showing selected entry's full info
##
## Entries only appear after first examination (from KnowledgeDB).
## Info shown matches current clearance level, with [REDACTED] placeholders
## for higher-clearance info that exists but isn't unlocked yet.

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 20
const FONT_SIZE_CATEGORY := 16
const FONT_SIZE_ENTRY := 14
const FONT_SIZE_DETAIL := 13
const FONT_SIZE_DETAIL_HEADER := 16
const FONT_SIZE_BACK := 14

const PANEL_WIDTH := 600.0

## Delay before accepting input
const INPUT_ACCEPT_DELAY := 0.3

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when codex panel is closed (so settings panel can re-show)
signal codex_closed

# ============================================================================
# CATEGORIES
# ============================================================================

## Display order and labels for codex categories
const CATEGORIES := {
	"entity": "Threats",
	"environment": "Environment",
	"item": "Items",
}

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var content_vbox: VBoxContainer
var entry_buttons: Array[Button] = []
var back_button: Button = null

## Left pane: scrollable entry list
var entry_scroll: ScrollContainer = null
var entry_list_vbox: VBoxContainer = null

## Right pane: detail view
var detail_vbox: VBoxContainer = null
var detail_name_label: Label = null
var detail_class_label: Label = null
var detail_description_label: Label = null

## Font with emoji fallback
var emoji_font: Font = null

# State
var _accepting_input: bool = false
var _selected_key: String = ""  # Currently selected subject key (e.g., "entity:smiler")

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	emoji_font = load("res://assets/fonts/default_font.tres")

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_panel()

	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_panel() -> void:
	"""Build the codex panel UI"""
	panel = PanelContainer.new()
	panel.name = "CodexPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(0.4, 0.7, 1.0, 1)  # Blue border for codex
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	content_vbox = VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.add_theme_constant_override("separation", 8)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content_vbox)

# ============================================================================
# PUBLIC API
# ============================================================================

func show_codex() -> void:
	"""Show the codex panel"""
	_rebuild_content()
	_update_panel_position()

	visible = true
	_accepting_input = false

	await get_tree().process_frame
	_update_panel_position()

	await get_tree().process_frame

	# Enable focus on all entry buttons + back button
	_enable_focus()

	# Input accept delay
	get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
		func(): _accepting_input = true if visible else false
	)

func hide_codex() -> void:
	"""Hide the codex panel"""
	visible = false
	_accepting_input = false
	_disable_focus()
	codex_closed.emit()

# ============================================================================
# CONTENT BUILDING
# ============================================================================

func _rebuild_content() -> void:
	"""Rebuild the full codex content"""
	# Clear old content
	for child in content_vbox.get_children():
		if child is Button and child.has_focus():
			child.release_focus()
		if child.is_in_group("hud_focusable"):
			child.remove_from_group("hud_focusable")
		child.queue_free()
	entry_buttons.clear()
	_selected_key = ""

	# Header
	var header = Label.new()
	header.text = "CODEX"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(header)

	# Clearance level display
	var cl_label = Label.new()
	cl_label.text = "Clearance Level: %d" % KnowledgeDB.clearance_level
	cl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
	cl_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	if emoji_font:
		cl_label.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(cl_label)

	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	content_vbox.add_child(sep)

	# Two-pane layout: entries on left, detail on right
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(hbox)

	# Left pane: entry list (scrollable)
	entry_scroll = ScrollContainer.new()
	entry_scroll.custom_minimum_size = Vector2(200, 300)
	entry_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entry_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(entry_scroll)

	entry_list_vbox = VBoxContainer.new()
	entry_list_vbox.add_theme_constant_override("separation", 2)
	entry_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry_scroll.add_child(entry_list_vbox)

	# Vertical separator
	var vsep = VSeparator.new()
	vsep.add_theme_constant_override("separation", 4)
	hbox.add_child(vsep)

	# Right pane: detail view
	var detail_scroll = ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(300, 300)
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(detail_scroll)

	detail_vbox = VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 6)
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_vbox)

	# Build detail placeholder
	_build_detail_placeholder()

	# Populate entry list from KnowledgeDB
	_populate_entries()

	# Separator before back button
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 8)
	content_vbox.add_child(sep2)

	# Back button
	back_button = Button.new()
	back_button.text = "Back"
	back_button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_BACK))
	if emoji_font:
		back_button.add_theme_font_override("font", emoji_font)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_on_back_pressed)
	_apply_button_styles(back_button)
	back_button.add_to_group("hud_focusable")
	content_vbox.add_child(back_button)

func _build_detail_placeholder() -> void:
	"""Show placeholder text in detail pane"""
	for child in detail_vbox.get_children():
		child.queue_free()

	var placeholder = Label.new()
	placeholder.text = "Select an entry to view details"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
	placeholder.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	if emoji_font:
		placeholder.add_theme_font_override("font", emoji_font)
	detail_vbox.add_child(placeholder)

func _populate_entries() -> void:
	"""Populate the entry list from KnowledgeDB examined subjects"""
	var examined: Dictionary = KnowledgeDB.examined_at_clearance

	if examined.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No subjects examined yet.\nExamine entities and items\nin the world to fill the codex."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTRY))
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		if emoji_font:
			empty_label.add_theme_font_override("font", emoji_font)
		entry_list_vbox.add_child(empty_label)
		return

	# Group subjects by category
	var grouped: Dictionary = {}  # category_key -> Array of subject_keys
	for key in examined.keys():
		var parts = key.split(":")
		if parts.size() < 2:
			continue
		var category = parts[0]
		if not grouped.has(category):
			grouped[category] = []
		grouped[category].append(key)

	# Display in category order
	for category_key in CATEGORIES.keys():
		if not grouped.has(category_key):
			continue

		var subjects: Array = grouped[category_key]
		if subjects.is_empty():
			continue

		# Category header
		var cat_label = Label.new()
		cat_label.text = CATEGORIES[category_key].to_upper()
		cat_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_CATEGORY))
		cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		if emoji_font:
			cat_label.add_theme_font_override("font", emoji_font)
		entry_list_vbox.add_child(cat_label)

		# Sort subjects alphabetically by display name
		subjects.sort_custom(func(a, b): return _get_subject_name(a) < _get_subject_name(b))

		# Entry buttons
		for subject_key in subjects:
			var display_name = _get_subject_name(subject_key)
			var button = Button.new()
			button.text = display_name
			button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ENTRY))
			if emoji_font:
				button.add_theme_font_override("font", emoji_font)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_on_entry_selected.bind(subject_key))
			button.focus_entered.connect(_on_entry_selected.bind(subject_key))
			_apply_entry_styles(button)
			button.add_to_group("hud_focusable")
			entry_list_vbox.add_child(button)
			entry_buttons.append(button)

func _get_subject_name(subject_key: String) -> String:
	"""Get display name for a subject key"""
	var parts = subject_key.split(":")
	if parts.size() < 2:
		return subject_key

	var category = parts[0]
	var subject_id = parts[1]

	if category == "entity" or category == "environment":
		if EntityRegistry.has_entity(subject_id):
			var info = EntityRegistry.get_info(subject_id, KnowledgeDB.clearance_level)
			return info.get("name", subject_id)

	if category == "item":
		var info = KnowledgeDB.get_entity_info(subject_id)
		return info.get("name", subject_id)

	return subject_id.replace("_", " ").capitalize()

# ============================================================================
# DETAIL VIEW
# ============================================================================

func _on_entry_selected(subject_key: String) -> void:
	"""Show detail view for selected entry"""
	_selected_key = subject_key

	# Update button highlight
	for button in entry_buttons:
		_apply_entry_styles(button)

	# Get info
	var parts = subject_key.split(":")
	if parts.size() < 2:
		return

	var subject_id = parts[1]
	var info: Dictionary = KnowledgeDB.get_entity_info(subject_id)

	# Clear detail pane
	for child in detail_vbox.get_children():
		child.queue_free()

	# Name
	var name_label = Label.new()
	name_label.text = info.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL_HEADER))
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	if emoji_font:
		name_label.add_theme_font_override("font", emoji_font)
	detail_vbox.add_child(name_label)

	# Classification & Threat
	var class_text = info.get("object_class", "Unknown")
	var threat_name = info.get("threat_level_name", "")
	if not threat_name.is_empty():
		class_text += "  |  %s" % threat_name

	var class_label = Label.new()
	class_label.text = class_text
	class_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
	var threat_level: int = info.get("threat_level", 0)
	class_label.add_theme_color_override("font_color", _get_threat_color(threat_level))
	if emoji_font:
		class_label.add_theme_font_override("font", emoji_font)
	detail_vbox.add_child(class_label)

	# Item rarity (if item)
	if info.get("is_item", false):
		var rarity_label = Label.new()
		var rarity_name = info.get("rarity_name", "Common")
		var rarity_color = info.get("rarity_color", Color.WHITE)
		rarity_label.text = "Rarity: %s" % rarity_name
		rarity_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
		rarity_label.add_theme_color_override("font_color", rarity_color)
		if emoji_font:
			rarity_label.add_theme_font_override("font", emoji_font)
		detail_vbox.add_child(rarity_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	detail_vbox.add_child(sep)

	# Description
	var desc_label = Label.new()
	desc_label.text = info.get("description", "No information available.")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		desc_label.add_theme_font_override("font", emoji_font)
	detail_vbox.add_child(desc_label)

	# Redacted info hint (if higher clearance would reveal more)
	_add_redacted_hints(subject_key, info)

func _add_redacted_hints(subject_key: String, info: Dictionary) -> void:
	"""Show [REDACTED] placeholders for info available at higher clearance"""
	var parts = subject_key.split(":")
	if parts.size() < 2:
		return

	var category = parts[0]
	var subject_id = parts[1]

	# Only show redacted hints for entities/environment (items don't have clearance_info array)
	if category != "entity" and category != "environment":
		return

	if not EntityRegistry.has_entity(subject_id):
		return

	# Check if there's info at higher clearance levels
	var current_cl = KnowledgeDB.clearance_level
	var has_redacted := false

	for cl in range(current_cl + 1, 6):
		var higher_info = EntityRegistry.get_info(subject_id, cl)
		var higher_desc: String = higher_info.get("description", "")
		var current_desc: String = info.get("description", "")
		if higher_desc.length() > current_desc.length():
			has_redacted = true
			break

	if has_redacted:
		var sep = HSeparator.new()
		sep.add_theme_constant_override("separation", 6)
		detail_vbox.add_child(sep)

		var redacted = Label.new()
		redacted.text = "[REDACTED — CLEARANCE LEVEL %d REQUIRED]" % (current_cl + 1)
		redacted.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		redacted.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_DETAIL))
		redacted.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 0.7))
		if emoji_font:
			redacted.add_theme_font_override("font", emoji_font)
		detail_vbox.add_child(redacted)

# ============================================================================
# STYLING
# ============================================================================

func _apply_button_styles(button: Button) -> void:
	"""Apply consistent button styling (matching settings panel pattern)"""
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(0.3, 0.5, 0.8, 0.3)
	focus_style.border_color = Color(0.4, 0.7, 1.0, 0.8)
	focus_style.set_border_width_all(2)
	focus_style.content_margin_left = 8
	focus_style.content_margin_right = 8
	focus_style.content_margin_top = 6
	focus_style.content_margin_bottom = 6

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color(0.6, 0.6, 0.6, 1.0)
	hover_style.content_margin_left = 8
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 6
	hover_style.content_margin_bottom = 6

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("hover", hover_style)

func _apply_entry_styles(button: Button) -> void:
	"""Apply compact entry button styling"""
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	normal_style.set_border_width_all(0)
	normal_style.content_margin_left = 6
	normal_style.content_margin_right = 6
	normal_style.content_margin_top = 3
	normal_style.content_margin_bottom = 3

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(0.3, 0.5, 0.8, 0.3)
	focus_style.border_color = Color(0.4, 0.7, 1.0, 0.8)
	focus_style.set_border_width_all(1)
	focus_style.content_margin_left = 6
	focus_style.content_margin_right = 6
	focus_style.content_margin_top = 3
	focus_style.content_margin_bottom = 3

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	hover_style.set_border_width_all(0)
	hover_style.content_margin_left = 6
	hover_style.content_margin_right = 6
	hover_style.content_margin_top = 3
	hover_style.content_margin_bottom = 3

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("hover", hover_style)

func _get_threat_color(threat_level: int) -> Color:
	"""Get color for threat level display"""
	match threat_level:
		0: return Color(0.5, 0.5, 0.5)      # Gray (environment/debug)
		1: return Color(0.7, 0.7, 0.7)      # White (weak)
		2: return Color(0.3, 0.7, 1.0)      # Blue (moderate)
		3: return Color(1.0, 0.8, 0.2)      # Yellow (dangerous)
		4: return Color(1.0, 0.4, 0.1)      # Orange (elite)
		5: return Color(1.0, 0.1, 0.1)      # Red (boss)
	return Color.WHITE

# ============================================================================
# PANEL POSITIONING
# ============================================================================

func _update_panel_position() -> void:
	"""Center panel on game viewport"""
	if not panel:
		return

	var game_ref = get_node_or_null("/root/Game")
	var viewport_rect: Rect2
	if game_ref and game_ref.has_method("get_game_viewport_rect"):
		viewport_rect = game_ref.get_game_viewport_rect()
	else:
		viewport_rect = get_viewport_rect()

	panel.reset_size()

	await get_tree().process_frame

	var max_height: float = viewport_rect.size.y * 0.85
	var panel_size: Vector2 = panel.size
	if panel_size.y > max_height:
		panel_size.y = max_height
		panel.size = panel_size

	var center_x: float = viewport_rect.position.x + (viewport_rect.size.x - panel_size.x) / 2.0
	var center_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0

	panel.position = Vector2(center_x, center_y)

# ============================================================================
# NAVIGATION
# ============================================================================

func _on_back_pressed() -> void:
	"""Close codex panel"""
	if not _accepting_input:
		return
	hide_codex()

func _enable_focus() -> void:
	"""Enable focus on all interactive controls"""
	for button in entry_buttons:
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP

	if back_button:
		back_button.focus_mode = Control.FOCUS_ALL
		back_button.mouse_filter = Control.MOUSE_FILTER_STOP

	_setup_focus_neighbors()

	# Grab focus for controller users
	if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
		if entry_buttons.size() > 0:
			entry_buttons[0].grab_focus()
		elif back_button:
			back_button.grab_focus()

func _disable_focus() -> void:
	"""Disable focus on all interactive controls"""
	for button in entry_buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if back_button:
		back_button.focus_mode = Control.FOCUS_NONE
		back_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _setup_focus_neighbors() -> void:
	"""Set up focus neighbors for controller navigation"""
	# Build full focusable list: entry buttons + back button
	var all_focusable: Array[Control] = []
	for button in entry_buttons:
		all_focusable.append(button)
	if back_button:
		all_focusable.append(back_button)

	for i in range(all_focusable.size()):
		var control = all_focusable[i]
		if i > 0:
			control.focus_neighbor_top = all_focusable[i - 1].get_path()
		if i < all_focusable.size() - 1:
			control.focus_neighbor_bottom = all_focusable[i + 1].get_path()
		# Wrap around
		if i == 0:
			control.focus_neighbor_top = all_focusable[all_focusable.size() - 1].get_path()
		if i == all_focusable.size() - 1:
			control.focus_neighbor_bottom = all_focusable[0].get_path()

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad button presses"""
	if not visible or not _accepting_input:
		return

	if event is InputEventJoypadButton and event.pressed:
		# B button = back
		if event.button_index == JOY_BUTTON_B:
			hide_codex()
			get_viewport().set_input_as_handled()
			return

		# A button = select focused
		if event.button_index == JOY_BUTTON_A:
			var focused = get_viewport().gui_get_focus_owner()
			if focused and focused is Button:
				focused.pressed.emit()
				get_viewport().set_input_as_handled()
			return

func _process(_delta: float) -> void:
	"""Handle RT/A button activation"""
	if not visible or not _accepting_input:
		return

	# ESC to close
	if Input.is_action_just_pressed("ui_cancel"):
		hide_codex()
		return

	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button:
			focused.pressed.emit()
			return

	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button:
			focused.pressed.emit()
			return

# ============================================================================
# UI SCALING
# ============================================================================

func _get_font_size(base_size: int) -> int:
	"""Get font size scaled by UIScaleManager"""
	if UIScaleManager:
		return UIScaleManager.get_scaled_font_size(base_size)
	return base_size
