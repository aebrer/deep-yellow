class_name LevelUpPanel
extends Control
## Level-up perk selection UI
##
## Shows 3 random perk choices when player levels up.
## Pauses game and requires player to select one perk before continuing.
##
## Uses PauseManager pattern for consistent pause/unpause behavior

# ============================================================================
# PERK DEFINITIONS
# ============================================================================

enum PerkType {
	BODY_PLUS_1,
	MIND_PLUS_1,
	NULL_PLUS_1,
	HP_REGEN_PLUS_1,
	SANITY_REGEN_PLUS_1,
	MANA_REGEN_PLUS_1,
	CLEARANCE_PLUS_1,
	CORRUPTION_PLUS_5,
	CORRUPTION_MINUS_5,
}

const PERK_DATA: Dictionary = {
	PerkType.BODY_PLUS_1: {
		"name": "+1 BODY",
		"description": "Increases max HP by 10 and Strength by 1",
		"icon": "💪",
		"color": Color.ORANGE_RED,
	},
	PerkType.MIND_PLUS_1: {
		"name": "+1 MIND",
		"description": "Increases max Sanity by 10 and Perception by 1",
		"icon": "🧠",
		"color": Color.DEEP_SKY_BLUE,
	},
	PerkType.NULL_PLUS_1: {
		"name": "+1 NULL",
		"description": "Increases max Mana by 10, Anomaly by 1, and base mana regen",
		"icon": "✴️",
		"color": Color.MEDIUM_PURPLE,
	},
	PerkType.HP_REGEN_PLUS_1: {
		"name": "+HP Regen",
		"description": "Regenerate 0.3% of max HP each turn",
		"icon": "❤️‍🩹",
		"color": Color.LIGHT_CORAL,
	},
	PerkType.SANITY_REGEN_PLUS_1: {
		"name": "+Sanity Regen",
		"description": "Regenerate 0.3% of max Sanity each turn",
		"icon": "🧘",
		"color": Color.LIGHT_BLUE,
	},
	PerkType.MANA_REGEN_PLUS_1: {
		"name": "+1% Mana Regen",
		"description": "Regenerate additional 1% of max Mana each turn",
		"icon": "🔮",
		"color": Color.MEDIUM_ORCHID,
	},
	PerkType.CLEARANCE_PLUS_1: {
		"name": "+1 Clearance Level",
		"description": "Unlock higher-tier knowledge. +10% EXP from all sources!",
		"icon": "🔓",
		"color": Color.GOLD,
	},
	PerkType.CORRUPTION_PLUS_5: {
		"name": "+0.05 Corruption",
		"description": "Increase current level's corruption (more enemies, better loot)",
		"icon": "☠️",
		"color": Color.DARK_RED,
	},
	PerkType.CORRUPTION_MINUS_5: {
		"name": "-0.05 Corruption",
		"description": "Decrease current level's corruption (safer exploration)",
		"icon": "✨",
		"color": Color.LIGHT_GREEN,
	},
}

# ============================================================================
# CONSTANTS
# ============================================================================

const FONT_SIZE_HEADER := 24
const FONT_SIZE_LEVEL := 18
const FONT_SIZE_PERK_NAME := 16
const FONT_SIZE_PERK_DESC := 14

## Delay before accepting input (prevents accidental clicks from held buttons)
const INPUT_ACCEPT_DELAY := 0.5  # seconds

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var content_vbox: VBoxContainer
var perk_buttons: Array[Button] = []

## Font with emoji fallback (project default doesn't auto-apply to programmatic Labels)
var emoji_font: Font = null

# State
var player_ref: Player3D = null
var new_level: int = 0
var available_perks: Array[PerkType] = []
var _accepting_input: bool = false

## Queue of pending level-ups (for when player gains multiple levels at once)
## Each entry is a Dictionary: {"player": Player3D, "level": int}
var _pending_levelups: Array[Dictionary] = []

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Load emoji font (project setting doesn't auto-apply to programmatic Labels)
	emoji_font = load("res://assets/fonts/default_font.tres")

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_panel()

	visible = false

	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

func _build_panel() -> void:
	"""Build centered perk selection panel"""
	panel = PanelContainer.new()
	panel.name = "LevelUpPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	panel.custom_minimum_size = Vector2(450, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(1, 0.84, 0, 1)  # Gold border for level up
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)

	content_vbox = VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.add_theme_constant_override("separation", 12)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content_vbox)

# ============================================================================
# PUBLIC API
# ============================================================================

func show_level_up(player: Player3D, level: int) -> void:
	"""Display level-up perk selection UI

	If a level-up dialog is already showing, queue this one for later.

	Args:
		player: Player reference
		level: New level reached
	"""
	Log.system("show_level_up: Level %d (visible=%s, queue_size=%d)" % [level, visible, _pending_levelups.size()])

	# If already showing, queue this level-up for later
	if visible:
		_pending_levelups.append({"player": player, "level": level})
		Log.system("Queued level-up for Level %d (queue size: %d)" % [level, _pending_levelups.size()])
		return

	# Show immediately
	_show_level_up_immediate(player, level)

func _show_level_up_immediate(player: Player3D, level: int) -> void:
	"""Actually display the level-up UI (called when not already showing)"""
	player_ref = player
	new_level = level

	# Select 3 random perks
	available_perks = _select_random_perks(3)

	# Rebuild content
	_rebuild_content()

	# Update panel position
	_update_panel_position()

	# Show panel and pause game
	visible = true
	_accepting_input = false

	await get_tree().process_frame

	if PauseManager:
		PauseManager.toggle_pause()

# ============================================================================
# INTERNAL
# ============================================================================

func _select_random_perks(count: int) -> Array[PerkType]:
	"""Select N random unique perks from the pool using weighted selection.

	Clearance is intentionally rare since it boosts ALL EXP gains (+10%/level).
	"""
	# Define weights for each perk type (higher = more common)
	var perk_weights: Dictionary = {
		PerkType.BODY_PLUS_1: 10,
		PerkType.MIND_PLUS_1: 10,
		PerkType.NULL_PLUS_1: 10,
		PerkType.HP_REGEN_PLUS_1: 8,
		PerkType.SANITY_REGEN_PLUS_1: 8,
		PerkType.MANA_REGEN_PLUS_1: 8,
		PerkType.CLEARANCE_PLUS_1: 2,  # Rare - very powerful
		PerkType.CORRUPTION_PLUS_5: 6,
		PerkType.CORRUPTION_MINUS_5: 6,
	}

	# Build weighted pool
	var weighted_pool: Array[PerkType] = []
	for perk_type in PerkType.values():
		var weight = perk_weights.get(perk_type, 5)  # Default weight 5
		for _i in range(weight):
			weighted_pool.append(perk_type as PerkType)

	# Select unique perks using weighted random
	var selected: Array[PerkType] = []
	while selected.size() < count and weighted_pool.size() > 0:
		var idx = randi() % weighted_pool.size()
		var picked = weighted_pool[idx]

		# Only add if not already selected
		if not selected.has(picked):
			selected.append(picked)

		# Remove ALL instances of this perk from pool (to avoid duplicates)
		weighted_pool = weighted_pool.filter(func(p): return p != picked)

	return selected

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

	var max_height: float = viewport_rect.size.y * 0.9
	var panel_size: Vector2 = panel.size
	if panel_size.y > max_height:
		panel_size.y = max_height
		panel.size = panel_size

	var center_x: float = viewport_rect.position.x + (viewport_rect.size.x - panel_size.x) / 2.0
	var center_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0

	panel.position = Vector2(center_x, center_y)

func _rebuild_content() -> void:
	"""Rebuild UI content for current level-up"""
	# Clear old content (use queue_free to avoid freeing locked objects)
	for child in content_vbox.get_children():
		if child is Button and child.has_focus():
			child.release_focus()
		if child.is_in_group("hud_focusable"):
			child.remove_from_group("hud_focusable")
		child.queue_free()
	perk_buttons.clear()

	# Header
	var header = Label.new()
	header.text = "LEVEL UP!"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color.GOLD)
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(header)

	# Level info
	var level_label = Label.new()
	level_label.text = "You reached Level %d" % new_level
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_LEVEL))
	level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		level_label.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(level_label)

	# Separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 12)
	content_vbox.add_child(separator)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Choose a perk:"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_PERK_DESC))
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	if emoji_font:
		instructions.add_theme_font_override("font", emoji_font)
	content_vbox.add_child(instructions)

	# Perk buttons
	for perk_type in available_perks:
		var button = _create_perk_button(perk_type)
		content_vbox.add_child(button)
		perk_buttons.append(button)

func _create_perk_button(perk_type: PerkType) -> Button:
	"""Create a styled button for a perk"""
	var data = PERK_DATA[perk_type]

	var button = Button.new()
	button.text = "%s %s\n%s" % [data["icon"], data["name"], data["description"]]
	button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_PERK_NAME))
	button.add_theme_color_override("font_color", data["color"])
	if emoji_font:
		button.add_theme_font_override("font", emoji_font)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): _on_perk_selected(perk_type))

	# Transparent normal style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	normal_style.set_border_width_all(0)

	# Yellow focus style
	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(1.0, 1.0, 0.5, 0.3)
	focus_style.border_color = Color(1.0, 1.0, 0.5, 0.8)
	focus_style.set_border_width_all(2)
	focus_style.content_margin_left = 8
	focus_style.content_margin_right = 8
	focus_style.content_margin_top = 8
	focus_style.content_margin_bottom = 8

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)

	button.add_to_group("hud_focusable")

	return button

func _on_perk_selected(perk_type: PerkType) -> void:
	"""Apply the selected perk and close the panel"""
	if not visible or not _accepting_input:
		return

	Log.player("Selected perk: %s" % PERK_DATA[perk_type]["name"])

	_apply_perk(perk_type)
	_close_panel()

func _apply_perk(perk_type: PerkType) -> void:
	"""Apply the perk effects to the player"""
	if not player_ref or not player_ref.stats:
		Log.error(Log.Category.SYSTEM, "Cannot apply perk - no player stats!")
		return

	var stats = player_ref.stats

	match perk_type:
		PerkType.BODY_PLUS_1:
			stats.body += 1
			# Heal the gained HP
			stats.current_hp = stats.max_hp

		PerkType.MIND_PLUS_1:
			stats.mind += 1
			# Restore the gained sanity
			stats.current_sanity = stats.max_sanity

		PerkType.NULL_PLUS_1:
			stats.null_stat += 1
			# Restore the gained mana
			stats.current_mana = stats.max_mana

		PerkType.HP_REGEN_PLUS_1:
			stats.hp_regen_percent += 0.3  # ~0.3% per perk (weak, stacks over time)

		PerkType.SANITY_REGEN_PLUS_1:
			stats.sanity_regen_percent += 0.3  # ~0.3% per perk

		PerkType.MANA_REGEN_PLUS_1:
			stats.mana_regen_percent += 1.0

		PerkType.CLEARANCE_PLUS_1:
			stats.increase_clearance()

		PerkType.CORRUPTION_PLUS_5:
			_modify_corruption(0.05)

		PerkType.CORRUPTION_MINUS_5:
			_modify_corruption(-0.05)

func _modify_corruption(delta: float) -> void:
	"""Modify corruption of current level by a flat amount (corruption is unbounded: 0.0, 0.5, 1.0, ...)"""
	if not ChunkManager or not ChunkManager.corruption_tracker:
		Log.error(Log.Category.SYSTEM, "Cannot modify corruption - no ChunkManager!")
		return

	# Get current level (assume level 0 for now, could be tracked elsewhere)
	var current_level_id: int = 0  # TODO: Get actual current level from player/game state

	var current_corruption: float = ChunkManager.corruption_tracker.get_corruption(current_level_id)
	var new_corruption: float = maxf(0.0, current_corruption + delta)

	ChunkManager.corruption_tracker.set_corruption(current_level_id, new_corruption)
	Log.player("Corruption changed: %.2f → %.2f (%+.2f)" % [current_corruption, new_corruption, delta])

func _close_panel() -> void:
	"""Hide panel and either show next queued level-up or unpause game"""
	visible = false

	# Check for queued level-ups
	if _pending_levelups.size() > 0:
		var next_levelup = _pending_levelups.pop_front()
		Log.system("Processing queued level-up: Level %d (%d remaining)" % [
			next_levelup["level"],
			_pending_levelups.size()
		])
		# Defer showing next level-up to allow current button to finish its callback
		# This prevents "Object is locked" errors from freeing buttons mid-signal
		call_deferred("_show_level_up_immediate", next_levelup["player"], next_levelup["level"])
		return

	# No more queued level-ups, unpause game
	if PauseManager:
		PauseManager.toggle_pause()

func _on_pause_toggled(is_paused: bool) -> void:
	"""Update button focus when pause state changes"""
	if not visible:
		return

	if is_paused:
		for button in perk_buttons:
			button.focus_mode = Control.FOCUS_ALL
			button.mouse_filter = Control.MOUSE_FILTER_STOP

		# Set up focus neighbors for stick navigation
		_setup_focus_neighbors()

		# Only grab focus if using controller (mouse users don't need focus indicator)
		if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
			if perk_buttons.size() > 0:
				perk_buttons[0].grab_focus()

		# Enable input acceptance after delay (prevents accidental activation
		# from held buttons like RT)
		_accepting_input = false
		get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
			func(): _accepting_input = true if visible else false
		)
	else:
		_accepting_input = false
		for button in perk_buttons:
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _setup_focus_neighbors() -> void:
	"""Set up focus neighbors for left stick navigation"""
	for i in range(perk_buttons.size()):
		var button = perk_buttons[i]
		# Vertical navigation
		if i > 0:
			button.focus_neighbor_top = perk_buttons[i - 1].get_path()
		if i < perk_buttons.size() - 1:
			button.focus_neighbor_bottom = perk_buttons[i + 1].get_path()
		# Wrap around
		if i == 0:
			button.focus_neighbor_top = perk_buttons[perk_buttons.size() - 1].get_path()
		if i == perk_buttons.size() - 1:
			button.focus_neighbor_bottom = perk_buttons[0].get_path()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad inputs"""
	if not visible or not _accepting_input:
		return

	if event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A and event.pressed:
			var focused = get_viewport().gui_get_focus_owner()
			if focused and focused is Button and focused in perk_buttons:
				focused.pressed.emit()
				get_viewport().set_input_as_handled()
			return

func _process(_delta: float) -> void:
	"""Handle RT/A button activation"""
	if not visible or not _accepting_input:
		return

	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and focused in perk_buttons:
			focused.pressed.emit()
			return

	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and focused in perk_buttons:
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
