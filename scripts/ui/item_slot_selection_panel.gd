class_name ItemSlotSelectionPanel
extends Control
## Item slot selection UI for pickup interactions
##
## Shows all slots in the appropriate pool and allows player to:
## - Equip to empty slot
## - Combine with same item (level up)
## - Overwrite different item
## - Cancel (leave on ground)
##
## Uses PauseManager pattern for consistent pause/unpause behavior

# ============================================================================
# CONSTANTS
# ============================================================================

enum ActionType {
	EQUIP_EMPTY,      ## Equip to empty slot
	COMBINE_LEVEL_UP, ## Combine with existing item (level up)
	OVERWRITE         ## Replace existing item
}

## Base font sizes (scaled by UIScaleManager)
const FONT_SIZE_HEADER := 20
const FONT_SIZE_ITEM_NAME := 16
const FONT_SIZE_INFO := 14

## Delay before accepting input (prevents accidental clicks from held buttons)
const INPUT_ACCEPT_DELAY := 0.5  # seconds

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var content_vbox: VBoxContainer
var slot_buttons: Array[Button] = []
var cancel_button: Button = null

## Font with emoji fallback (project default doesn't auto-apply to programmatic Labels)
var emoji_font: Font = null

# State
var current_item: Item = null
var current_pool: ItemPool = null
var current_pool_type: Item.PoolType = Item.PoolType.BODY
var player_ref: Player3D = null
var item_position: Vector2i = Vector2i.ZERO  ## World position of item being picked up
var _accepting_input: bool = false  ## Only accept button presses after panel fully set up

func _ready() -> void:
	# Load emoji font (project setting doesn't auto-apply to programmatic Labels)
	emoji_font = load("res://assets/fonts/default_font.tres")

	# Fill screen for centering
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input when hidden

	_build_panel()

	# Hide by default
	visible = false

	# Connect to PauseManager for focus control
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

func _build_panel() -> void:
	"""Build centered slot selection panel"""
	panel = PanelContainer.new()
	panel.name = "SlotSelectionPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS  # Process when paused
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture mouse events
	add_child(panel)

	# Panel will be positioned by _update_panel_position
	# Width fixed, height auto-sizes based on content (capped at max)
	panel.custom_minimum_size = Vector2(400, 0)  # Min width only, height auto

	# Style panel (SCP aesthetic)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)

	# Content container (rebuilt each time we show)
	content_vbox = VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.add_theme_constant_override("separation", 12)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content_vbox)

func show_slot_selection(item: Item, pool: ItemPool, player: Player3D, position: Vector2i) -> void:
	"""Display slot selection UI for picked up item

	Args:
		item: Item being picked up
		pool: Player's ItemPool for this item type
		player: Player reference
		position: World position of item (for removal after pickup)
	"""

	current_item = item
	current_pool = pool
	current_pool_type = pool.pool_type
	player_ref = player
	item_position = position

	# Rebuild content
	_rebuild_content()

	# Update panel position to ensure it's centered
	_update_panel_position()

	# Show panel and pause game via PauseManager
	visible = true
	_accepting_input = false  # Block input until after focus is set

	# CRITICAL FIX: Wait one frame before pausing to ensure destruction completes
	# Even though we use free() instead of queue_free(), this provides extra safety
	await get_tree().process_frame

	if PauseManager:
		PauseManager.toggle_pause()

func _update_panel_position() -> void:
	"""Update panel position to center it on game viewport (SubViewportContainer)"""
	if not panel:
		return

	# Get game viewport rect (SubViewportContainer bounds)
	var game_ref = get_node_or_null("/root/Game")
	var viewport_rect: Rect2
	if game_ref and game_ref.has_method("get_game_viewport_rect"):
		viewport_rect = game_ref.get_game_viewport_rect()
	else:
		# Fallback to full viewport
		viewport_rect = get_viewport_rect()

	# Let panel auto-size, then center it
	# Reset size to let it calculate natural size from content
	panel.reset_size()

	# Wait a frame for size to be calculated, then center
	await get_tree().process_frame

	# Get actual panel size (clamped to viewport if too large)
	var max_height: float = viewport_rect.size.y * 0.8  # Max 80% of viewport height
	var panel_size: Vector2 = panel.size
	if panel_size.y > max_height:
		panel_size.y = max_height
		panel.size = panel_size

	# Center the panel within the game viewport
	var center_x: float = viewport_rect.position.x + (viewport_rect.size.x - panel_size.x) / 2.0
	var center_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0

	panel.position = Vector2(center_x, center_y)

func _rebuild_content() -> void:
	"""Rebuild UI content for current item/pool"""

	# Clear old content - CRITICAL: Remove from group and destroy immediately
	var vbox = content_vbox
	for child in vbox.get_children():
		# Release focus from old buttons before deleting
		if child is Button and child.has_focus():
			child.release_focus()

		# CRITICAL FIX: Remove from hud_focusable group BEFORE destruction
		# This prevents PauseManager from finding stale buttons
		if child.is_in_group("hud_focusable"):
			child.remove_from_group("hud_focusable")

		# CRITICAL FIX: Use free() instead of queue_free() for immediate destruction
		# queue_free() is deferred until end of frame, leaving old buttons in scene tree
		# Old buttons would still be found by PauseManager and get focused, causing autocombine
		child.free()
	slot_buttons.clear()


	# Header
	var header = Label.new()
	header.text = "ITEM ACQUISITION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	vbox.add_child(header)

	# Item info
	var item_name_label = Label.new()
	item_name_label.text = "Item: %s (Level %d)" % [current_item.item_name, current_item.level]
	item_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_name_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_ITEM_NAME))
	item_name_label.add_theme_color_override("font_color", ItemRarity.get_color(current_item.rarity))
	if emoji_font:
		item_name_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(item_name_label)

	# Pool type
	var pool_label = Label.new()
	pool_label.text = "Pool: %s" % Item.PoolType.keys()[current_pool.pool_type]
	pool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pool_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	pool_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	if emoji_font:
		pool_label.add_theme_font_override("font", emoji_font)
	vbox.add_child(pool_label)

	# Separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 12)
	vbox.add_child(separator1)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Select a slot to equip this item:"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	instructions.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if emoji_font:
		instructions.add_theme_font_override("font", emoji_font)
	vbox.add_child(instructions)

	# Slot buttons
	for slot_idx in range(current_pool.max_slots):
		var slot_button = _create_slot_button(slot_idx)
		vbox.add_child(slot_button)
		slot_buttons.append(slot_button)

	# Separator
	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 12)
	vbox.add_child(separator2)

	# Cancel button
	cancel_button = Button.new()
	cancel_button.text = "Leave on Ground (Cancel)"
	cancel_button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		cancel_button.add_theme_font_override("font", emoji_font)
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.add_to_group("hud_focusable")
	vbox.add_child(cancel_button)

func _create_slot_button(slot_index: int) -> Button:
	"""Create button for a specific slot

	Args:
		slot_index: Slot index (0-N)

	Returns:
		Configured button
	"""
	var existing_item = current_pool.get_item(slot_index)
	var button = Button.new()

	if not existing_item:
		# Empty slot
		button.text = "Slot %d: [EMPTY]" % (slot_index + 1)
		button.add_theme_color_override("font_color", Color.GREEN)
		button.pressed.connect(func(): _on_slot_selected(slot_index, ActionType.EQUIP_EMPTY))
	elif existing_item.item_id == current_item.item_id:
		# Same item - can combine to level up
		button.text = "Slot %d: %s (Lv %d) → COMBINE (Lv %d)" % [
			slot_index + 1,
			existing_item.item_name,
			existing_item.level,
			existing_item.level + 1
		]
		button.add_theme_color_override("font_color", Color.CYAN)
		button.pressed.connect(func(): _on_slot_selected(slot_index, ActionType.COMBINE_LEVEL_UP))
	else:
		# Different item - can overwrite
		button.text = "Slot %d: %s (Lv %d) → OVERWRITE with %s" % [
			slot_index + 1,
			existing_item.item_name,
			existing_item.level,
			current_item.item_name
		]
		button.add_theme_color_override("font_color", Color.ORANGE_RED)
		button.pressed.connect(func(): _on_slot_selected(slot_index, ActionType.OVERWRITE))

	button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		button.add_theme_font_override("font", emoji_font)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Create transparent normal state (no background when not focused)
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	normal_style.set_border_width_all(0)  # No border

	# Create custom yellow highlight style (when focused)
	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(1.0, 1.0, 0.5, 0.3)  # Yellow transparent background
	focus_style.border_color = Color(1.0, 1.0, 0.5, 0.8)  # Yellow border
	focus_style.set_border_width_all(2)
	focus_style.content_margin_left = 4
	focus_style.content_margin_right = 4
	focus_style.content_margin_top = 2
	focus_style.content_margin_bottom = 2

	# Override BOTH normal and focus styleboxes to disable Godot's default gray indicator
	# Normal: Fully transparent (invisible when not focused)
	# Focus: Yellow highlight (visible when focused)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)

	# Add to focusable group for PauseManager pattern
	button.add_to_group("hud_focusable")

	return button

func _on_slot_selected(slot_index: int, action_type: ActionType) -> void:
	"""Handle slot selection - queues PickupToSlotAction for execution

	Args:
		slot_index: Selected slot
		action_type: What action to perform
	"""
	# Ignore if panel not ready (prevents queued-for-deletion buttons from firing)
	if not visible or not _accepting_input:
		return

	# Create action to execute the pickup
	var action = PickupToSlotAction.new(current_item, current_pool_type, slot_index, action_type, item_position)

	# Queue action for execution via state machine
	player_ref.pending_action = action
	player_ref.return_state = "IdleState"

	# Close panel (will unpause via PauseManager)
	_close_panel()

	# Trigger state machine to execute the action
	player_ref.state_machine.change_state("PreTurnState")

func _on_cancel_pressed() -> void:
	"""Handle cancel button press - leave item on ground"""
	Log.player("Left item on ground")
	_close_panel()

func _close_panel() -> void:
	"""Hide panel and unpause game via PauseManager"""
	visible = false
	if PauseManager:
		PauseManager.toggle_pause()

func _on_pause_toggled(is_paused: bool) -> void:
	"""Update button focus when pause state changes"""
	if not visible:
		return

	if is_paused:
		# Enable focus when paused
		for button in slot_buttons:
			button.focus_mode = Control.FOCUS_ALL
			button.mouse_filter = Control.MOUSE_FILTER_STOP

		if cancel_button:
			cancel_button.focus_mode = Control.FOCUS_ALL
			cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP

		# Only grab focus if using controller (mouse users don't need focus indicator)
		if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
			if slot_buttons.size() > 0:
				slot_buttons[0].grab_focus()
			elif cancel_button:
				cancel_button.grab_focus()

		# Enable input acceptance after delay (prevents accidental activation
		# from held buttons like RT when picking up items)
		_accepting_input = false
		get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
			func(): _accepting_input = true if visible else false
		)
	else:
		# Disable input acceptance when unpausing
		_accepting_input = false
		# Disable focus when unpausing
		for button in slot_buttons:
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if cancel_button:
			cancel_button.focus_mode = Control.FOCUS_NONE
			cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad-specific inputs (A/B buttons)"""
	if not visible or not _accepting_input:
		return

	if event is InputEventJoypadButton:
		# A button to activate focused button
		if event.button_index == JOY_BUTTON_A and event.pressed:
			var focused = get_viewport().gui_get_focus_owner()
			# CRITICAL: Only activate if focused button is in our panel
			# This prevents activating old buttons that are being destroyed
			if focused and focused is Button:
				if focused in slot_buttons or focused == cancel_button:
					focused.pressed.emit()
					get_viewport().set_input_as_handled()
			return

		# B button to cancel (industry standard)
		if event.button_index == JOY_BUTTON_B and event.pressed:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
			return

	# ESC or pause action to cancel
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
		return

func _process(_delta: float) -> void:
	"""Handle RT/A button activation of focused button"""
	if not visible or not _accepting_input:
		return

	# Check for move_confirm (RT/A/Space/LMB via InputManager)
	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		# CRITICAL: Only activate if focused button is in our current slot_buttons array
		# This prevents activating old buttons that are being queue_free()'d
		if focused and focused is Button and focused in slot_buttons:
			focused.pressed.emit()
			return

	# Also check ui_accept (standard Godot action for button activation)
	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		# CRITICAL: Only activate if focused button is in our current slot_buttons array
		if focused and focused is Button and focused in slot_buttons:
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

