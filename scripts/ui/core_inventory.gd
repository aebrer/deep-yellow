extends VBoxContainer
"""Core Inventory display panel with interactive elements.

Shows:
- BODY Pool (3 slots)
- MIND Pool (3 slots)
- NULL Pool (3 slots)
- LIGHT Pool (1 slot)

Each slot displays:
- [EMPTY] if no item
- Item Name (Lvl X) [ON/OFF] if item equipped

Supports two layout modes:
- VERTICAL: Pools stacked vertically (landscape mode)
- HORIZONTAL: Pools arranged side-by-side (portrait mode)

Tooltips show full clearance-based item descriptions.
Updates in real-time as items change.
"""

## Emitted when reorder state changes (for updating action preview UI)
signal reorder_state_changed(is_reordering: bool)

enum LayoutMode { VERTICAL, HORIZONTAL }
var current_layout: LayoutMode = LayoutMode.VERTICAL

var player: Player3D = null
var tooltip_slots: Array[Control] = []
var tooltip_texts: Dictionary = {}  # slot -> tooltip_text

# Reorder state (persistent across focus changes)
var reordering_slot: Control = null
var reordering_pool_type: Item.PoolType
var reordering_slot_index: int = -1

# Pool container references (VBoxContainer)
@onready var body_pool_section: VBoxContainer = $BodyPool
@onready var mind_pool_section: VBoxContainer = $MindPool
@onready var null_pool_section: VBoxContainer = $NullPool
@onready var light_pool_section: VBoxContainer = $LightPool

# Slot container references (HBoxContainer)
@onready var body_slot_0: HBoxContainer = %BodySlot0
@onready var body_slot_1: HBoxContainer = %BodySlot1
@onready var body_slot_2: HBoxContainer = %BodySlot2

@onready var mind_slot_0: HBoxContainer = %MindSlot0
@onready var mind_slot_1: HBoxContainer = %MindSlot1
@onready var mind_slot_2: HBoxContainer = %MindSlot2

@onready var null_slot_0: HBoxContainer = %NullSlot0
@onready var null_slot_1: HBoxContainer = %NullSlot1
@onready var null_slot_2: HBoxContainer = %NullSlot2

@onready var light_slot_0: HBoxContainer = %LightSlot0

# Examination panel reference (unified system)
var examination_panel: ExaminationPanel = null

func _ready():
	# Wait for player to be set by Game node
	await get_tree().process_frame

	# Setup hover/focus highlighting for all labels
	_setup_label_highlights()

	# Connect to pause manager to clear focus when unpausing
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

	if player:
		_connect_signals()
		_update_all_slots()
	else:
		Log.warn(Log.Category.SYSTEM, "CoreInventory: No player found")

func _unhandled_input(event: InputEvent) -> void:
	"""Handle B button to cancel reordering"""
	if not PauseManager or not PauseManager.is_paused:
		return

	# B button or ESC = cancel reorder
	if event.is_action_pressed("ui_cancel"):  # B button or ESC
		if reordering_slot:
			_cancel_reorder()
			get_viewport().set_input_as_handled()

func _get_examination_panel() -> void:
	"""Get the examination panel reference - called on-demand"""
	if examination_panel:
		return  # Already found

	var game_root = get_tree().root.get_node_or_null("Game")
	if not game_root:
		return

	var text_ui_overlay = game_root.get_node_or_null("TextUIOverlay")
	if text_ui_overlay:
		examination_panel = text_ui_overlay.get_node_or_null("ExaminationPanel")

func set_player(p: Player3D) -> void:
	"""Called by Game node to set player reference"""
	player = p
	if player:
		_connect_signals()
		_update_all_slots()

func _connect_signals() -> void:
	"""Connect to ItemPool signals for real-time updates"""
	if not player:
		return

	# BODY pool
	if player.body_pool:
		if not player.body_pool.item_added.is_connected(_on_item_added):
			player.body_pool.item_added.connect(_on_item_added.bind(Item.PoolType.BODY))
			player.body_pool.item_removed.connect(_on_item_removed.bind(Item.PoolType.BODY))
			player.body_pool.item_leveled_up.connect(_on_item_leveled_up.bind(Item.PoolType.BODY))
			player.body_pool.item_reordered.connect(_on_item_reordered.bind(Item.PoolType.BODY))
			player.body_pool.item_toggled.connect(_on_item_toggled.bind(Item.PoolType.BODY))

	# MIND pool
	if player.mind_pool:
		if not player.mind_pool.item_added.is_connected(_on_item_added):
			player.mind_pool.item_added.connect(_on_item_added.bind(Item.PoolType.MIND))
			player.mind_pool.item_removed.connect(_on_item_removed.bind(Item.PoolType.MIND))
			player.mind_pool.item_leveled_up.connect(_on_item_leveled_up.bind(Item.PoolType.MIND))
			player.mind_pool.item_reordered.connect(_on_item_reordered.bind(Item.PoolType.MIND))
			player.mind_pool.item_toggled.connect(_on_item_toggled.bind(Item.PoolType.MIND))

	# NULL pool
	if player.null_pool:
		if not player.null_pool.item_added.is_connected(_on_item_added):
			player.null_pool.item_added.connect(_on_item_added.bind(Item.PoolType.NULL))
			player.null_pool.item_removed.connect(_on_item_removed.bind(Item.PoolType.NULL))
			player.null_pool.item_leveled_up.connect(_on_item_leveled_up.bind(Item.PoolType.NULL))
			player.null_pool.item_reordered.connect(_on_item_reordered.bind(Item.PoolType.NULL))
			player.null_pool.item_toggled.connect(_on_item_toggled.bind(Item.PoolType.NULL))

	# LIGHT pool
	if player.light_pool:
		if not player.light_pool.item_added.is_connected(_on_item_added):
			player.light_pool.item_added.connect(_on_item_added.bind(Item.PoolType.LIGHT))
			player.light_pool.item_removed.connect(_on_item_removed.bind(Item.PoolType.LIGHT))
			player.light_pool.item_leveled_up.connect(_on_item_leveled_up.bind(Item.PoolType.LIGHT))
			player.light_pool.item_reordered.connect(_on_item_reordered.bind(Item.PoolType.LIGHT))
			player.light_pool.item_toggled.connect(_on_item_toggled.bind(Item.PoolType.LIGHT))

func _update_all_slots() -> void:
	"""Update all slot displays"""
	if not player:
		return

	_update_pool_slots(Item.PoolType.BODY)
	_update_pool_slots(Item.PoolType.MIND)
	_update_pool_slots(Item.PoolType.NULL)
	_update_pool_slots(Item.PoolType.LIGHT)

func _update_pool_slots(pool_type: Item.PoolType) -> void:
	"""Update all slots for a specific pool"""
	var pool = _get_pool(pool_type)
	if not pool:
		return

	var slot_containers = _get_slot_containers(pool_type)
	for i in range(slot_containers.size()):
		_update_slot(slot_containers[i], pool, i)

func _update_slot(slot: HBoxContainer, pool: ItemPool, slot_index: int) -> void:
	"""Update a single slot container (icon + label)"""
	if not slot or not pool:
		return

	var icon: TextureRect = slot.get_node("Icon")
	var label: Label = slot.get_node("Label")

	if not icon or not label:
		return

	var item = pool.items[slot_index] if slot_index < pool.items.size() else null

	if not item:
		icon.texture = null
		label.text = "<empty>"
		# Clear tooltip
		if slot in tooltip_texts:
			tooltip_texts.erase(slot)
	else:
		# Set icon texture from item
		icon.texture = item.ground_sprite

		# Set label text
		var enabled_text = "[ON]" if pool.enabled[slot_index] else "[OFF]"
		label.text = "%s (Lvl %d) %s" % [item.item_name, item.level, enabled_text]

		# Store tooltip with clearance-based description
		var clearance = player.stats.clearance_level if player.stats else 0
		tooltip_texts[slot] = item.get_description(clearance)

func _get_pool(pool_type: Item.PoolType) -> ItemPool:
	"""Get ItemPool reference by type"""
	if not player:
		return null

	match pool_type:
		Item.PoolType.BODY: return player.body_pool
		Item.PoolType.MIND: return player.mind_pool
		Item.PoolType.NULL: return player.null_pool
		Item.PoolType.LIGHT: return player.light_pool
		_: return null

func _get_slot_containers(pool_type: Item.PoolType) -> Array[HBoxContainer]:
	"""Get slot container references by pool type"""
	var slots: Array[HBoxContainer] = []
	match pool_type:
		Item.PoolType.BODY:
			slots = [body_slot_0, body_slot_1, body_slot_2]
		Item.PoolType.MIND:
			slots = [mind_slot_0, mind_slot_1, mind_slot_2]
		Item.PoolType.NULL:
			slots = [null_slot_0, null_slot_1, null_slot_2]
		Item.PoolType.LIGHT:
			slots = [light_slot_0]
	return slots

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_item_added(_item: Item, slot_index: int, pool_type: Item.PoolType) -> void:
	"""Update slot when item added"""
	var pool = _get_pool(pool_type)
	var slots = _get_slot_containers(pool_type)
	if slot_index < slots.size():
		_update_slot(slots[slot_index], pool, slot_index)

func _on_item_removed(_item: Item, slot_index: int, pool_type: Item.PoolType) -> void:
	"""Update slot when item removed"""
	var pool = _get_pool(pool_type)
	var slots = _get_slot_containers(pool_type)
	if slot_index < slots.size():
		_update_slot(slots[slot_index], pool, slot_index)

func _on_item_leveled_up(_item: Item, slot_index: int, _new_level: int, pool_type: Item.PoolType) -> void:
	"""Update slot when item levels up"""
	var pool = _get_pool(pool_type)
	var slots = _get_slot_containers(pool_type)
	if slot_index < slots.size():
		_update_slot(slots[slot_index], pool, slot_index)

func _on_item_reordered(_from_index: int, _to_index: int, pool_type: Item.PoolType) -> void:
	"""Update all slots in pool when items reordered"""
	_update_pool_slots(pool_type)

func _on_item_toggled(slot_index: int, _enabled: bool, pool_type: Item.PoolType) -> void:
	"""Update slot when enabled state changes"""
	var pool = _get_pool(pool_type)
	var slots = _get_slot_containers(pool_type)
	if slot_index < slots.size():
		_update_slot(slots[slot_index], pool, slot_index)

# ============================================================================
# HOVER/FOCUS HIGHLIGHTING
# ============================================================================

func _setup_label_highlights() -> void:
	"""Setup unified hover/focus system for all slot containers"""
	tooltip_slots = [
		body_slot_0, body_slot_1, body_slot_2,
		mind_slot_0, mind_slot_1, mind_slot_2,
		null_slot_0, null_slot_1, null_slot_2,
		light_slot_0
	]

	for slot in tooltip_slots:
		if slot:
			# Add to hud_focusable group (so PauseManager can find it)
			slot.add_to_group("hud_focusable")

			# Connect hover signals (always active)
			slot.mouse_entered.connect(_on_slot_hovered.bind(slot))
			slot.mouse_exited.connect(_on_slot_unhovered.bind(slot))

			# Connect focus signals (controller - only when paused)
			slot.focus_entered.connect(_on_slot_focused.bind(slot))
			slot.focus_exited.connect(_on_slot_unfocused.bind(slot))

			# Connect input signals for toggling items
			slot.gui_input.connect(_on_slot_input.bind(slot))

			# Make focusable immediately (controller navigation only works when paused)
			slot.focus_mode = Control.FOCUS_ALL

func _on_slot_hovered(slot: Control) -> void:
	"""Highlight slot on mouse hover"""
	_highlight_slot(slot)

func _on_slot_unhovered(slot: Control) -> void:
	"""Remove highlight when mouse leaves"""
	_unhighlight_slot(slot)

func _on_slot_focused(slot: Control) -> void:
	"""Highlight slot when focused (controller)"""
	_highlight_slot(slot)

func _on_slot_unfocused(slot: Control) -> void:
	"""Remove highlight when focus lost"""
	_unhighlight_slot(slot)

func _on_slot_input(event: InputEvent, slot: Control) -> void:
	"""Handle input events for slot (A/LMB=toggle, X/RMB=reorder)"""
	# Only handle input when paused
	if not PauseManager or not PauseManager.is_paused:
		return

	# Get slot index and pool type
	var slot_index = -1
	var pool_type: Item.PoolType

	# Find which slot this is
	if slot in [body_slot_0, body_slot_1, body_slot_2]:
		pool_type = Item.PoolType.BODY
		slot_index = [body_slot_0, body_slot_1, body_slot_2].find(slot)
	elif slot in [mind_slot_0, mind_slot_1, mind_slot_2]:
		pool_type = Item.PoolType.MIND
		slot_index = [mind_slot_0, mind_slot_1, mind_slot_2].find(slot)
	elif slot in [null_slot_0, null_slot_1, null_slot_2]:
		pool_type = Item.PoolType.NULL
		slot_index = [null_slot_0, null_slot_1, null_slot_2].find(slot)
	elif slot == light_slot_0:
		pool_type = Item.PoolType.LIGHT
		slot_index = 0
	else:
		return  # Unknown slot

	var pool = _get_pool(pool_type)
	if not pool or slot_index >= pool.items.size():
		return

	var item = pool.items[slot_index]

	# Allow interaction with empty slots only when reordering (for dropping)
	if not item and not reordering_slot:
		return  # Empty slot and not reordering, nothing to do

	# Handle mouse input
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# LMB = drop if reordering, otherwise toggle
			if reordering_slot:
				if reordering_slot == slot:
					_cancel_reorder()  # Click same slot = cancel
				else:
					_drop_reorder(slot, pool_type, slot_index)
			elif item:  # Only toggle if slot has an item
				_toggle_item(pool_type, slot_index)
			get_viewport().set_input_as_handled()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# RMB = pick up for reorder (or cancel if already reordering)
			if not reordering_slot and item:  # Only start reorder if slot has an item
				_start_reorder(slot, pool_type, slot_index)
			elif reordering_slot:
				_cancel_reorder()  # RMB while reordering = cancel
			get_viewport().set_input_as_handled()

	# Handle gamepad input
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A:
			# A button = drop if reordering, otherwise toggle
			if reordering_slot:
				if reordering_slot == slot:
					_cancel_reorder()  # Click same slot = cancel
				else:
					_drop_reorder(slot, pool_type, slot_index)
			elif item:  # Only toggle if slot has an item
				_toggle_item(pool_type, slot_index)
			get_viewport().set_input_as_handled()

		elif event.button_index == JOY_BUTTON_B:
			# B button = always cancel reorder if active
			if reordering_slot:
				_cancel_reorder()
				get_viewport().set_input_as_handled()

		elif event.button_index == JOY_BUTTON_X:
			# X button = pick up for reorder (or cancel if already reordering)
			if not reordering_slot and item:  # Only start reorder if slot has an item
				_start_reorder(slot, pool_type, slot_index)
			elif reordering_slot:
				_cancel_reorder()  # X while reordering = cancel
			get_viewport().set_input_as_handled()

func _highlight_slot(slot: Control) -> void:
	"""Apply visual highlight and show examination panel with item info"""
	var label = slot.get_node_or_null("Label")
	if not label:
		return

	# Don't change highlight if this is the reordering slot (preserve cyan)
	if slot == reordering_slot:
		return

	# Create a StyleBoxFlat for the background
	var style = StyleBoxFlat.new()

	# Use green highlight if we're in reorder mode (valid drop target)
	# Use yellow highlight otherwise (normal hover)
	if reordering_slot:
		style.bg_color = Color(0.5, 1.0, 0.5, 0.3)  # Green transparent
		style.border_color = Color(0.5, 1.0, 0.5, 0.8)  # Green border
	else:
		style.bg_color = Color(1.0, 1.0, 0.5, 0.3)  # Yellow transparent
		style.border_color = Color(1.0, 1.0, 0.5, 0.8)  # Yellow border

	style.set_border_width_all(2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2

	# Apply to the Label (HBoxContainer doesn't draw backgrounds)
	# Override BOTH normal and focus to disable Godot's built-in focus indicator
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_stylebox_override("focus", style)

	# Get examination panel and show item description if slot has item
	_get_examination_panel()
	if examination_panel and slot in tooltip_texts:
		# Directly set examination panel content with item info
		var item_name = label.text.split(" (")[0]  # Extract just the item name
		examination_panel.entity_name_label.text = item_name
		examination_panel.object_class_label.visible = false  # Hide class for items
		examination_panel.threat_level_label.visible = false  # Hide threat for items
		examination_panel.description_label.text = tooltip_texts[slot]
		examination_panel.panel.visible = true

func _unhighlight_slot(slot: Control) -> void:
	"""Remove visual highlight and hide examination panel"""
	# Don't remove highlight if this slot is currently being reordered
	if slot == reordering_slot:
		return

	# Remove styleboxes from the Label child
	var label = slot.get_node_or_null("Label")
	if label:
		label.remove_theme_stylebox_override("normal")
		label.remove_theme_stylebox_override("focus")

	# Hide examination panel
	if examination_panel:
		examination_panel.hide_panel()

func _start_reorder(slot: Control, pool_type: Item.PoolType, slot_index: int) -> void:
	"""Pick up item for reordering"""
	reordering_slot = slot
	reordering_pool_type = pool_type
	reordering_slot_index = slot_index

	# Visual feedback: cyan highlight to show item is being moved
	var label = slot.get_node_or_null("Label")
	if label:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 1.0, 1.0, 0.3)  # Cyan transparent
		style.border_color = Color(0.0, 1.0, 1.0, 0.8)  # Cyan border
		style.set_border_width_all(2)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		label.add_theme_stylebox_override("normal", style)
		label.add_theme_stylebox_override("focus", style)

	Log.system("Picked up item from slot %d in %s pool (press X/RMB to drop, B to cancel)" % [slot_index, Item.PoolType.keys()[pool_type]])

	# Emit signal to update action preview
	reorder_state_changed.emit(true)

func _toggle_item(pool_type: Item.PoolType, slot_index: int) -> void:
	"""Toggle an item ON/OFF (consumes a turn)"""
	if not player:
		return

	# Create toggle action
	var action = ToggleItemAction.new(pool_type, slot_index)

	if not action.can_execute(player):
		Log.warn(Log.Category.SYSTEM, "Cannot toggle item at slot %d" % slot_index)
		return

	# Set as pending action (like movement)
	player.pending_action = action
	player.return_state = "IdleState"

	# Unpause to allow execution
	if PauseManager:
		PauseManager.toggle_pause()

	# Transition to pre-turn state to execute the action
	if player.state_machine:
		player.state_machine.change_state("PreTurnState")

	Log.system("Queued toggle action for slot %d" % slot_index)

func _drop_reorder(target_slot: Control, target_pool_type: Item.PoolType, target_slot_index: int) -> void:
	"""Drop item at new position (reorder within same pool, consumes a turn)"""
	if not reordering_slot:
		return

	# Only allow reordering within the same pool
	if reordering_pool_type != target_pool_type:
		Log.warn(Log.Category.SYSTEM, "Cannot reorder items between different pools")
		_cancel_reorder()
		return

	if not player:
		_cancel_reorder()
		return

	# Create reorder action
	var action = ReorderItemAction.new(reordering_pool_type, reordering_slot_index, target_slot_index)

	if not action.can_execute(player):
		Log.warn(Log.Category.SYSTEM, "Cannot reorder items")
		_cancel_reorder()
		return

	# Set as pending action (like movement)
	player.pending_action = action
	player.return_state = "IdleState"

	# Cancel reorder UI state
	_cancel_reorder()

	# Unpause to allow execution
	if PauseManager:
		PauseManager.toggle_pause()

	# Transition to pre-turn state to execute the action
	if player.state_machine:
		player.state_machine.change_state("PreTurnState")

	Log.system("Queued reorder action from slot %d to %d" % [reordering_slot_index, target_slot_index])

func _cancel_reorder() -> void:
	"""Cancel current reorder operation"""
	if reordering_slot:
		# Remove reorder highlight
		var label = reordering_slot.get_node_or_null("Label")
		if label:
			label.remove_theme_stylebox_override("normal")
			label.remove_theme_stylebox_override("focus")
		Log.system("Cancelled reorder operation")

	reordering_slot = null
	reordering_slot_index = -1

	# Emit signal to update action preview
	reorder_state_changed.emit(false)

func _on_pause_toggled(is_paused: bool) -> void:
	"""Enable/disable focus and clear highlights based on pause state"""
	if is_paused:
		# Enable focus for gamepad navigation when paused
		for slot in tooltip_slots:
			if slot:
				slot.focus_mode = Control.FOCUS_ALL
				slot.mouse_filter = Control.MOUSE_FILTER_STOP  # Allow mouse hover

		# Emit signal to show pause controls in action preview
		reorder_state_changed.emit(false)
	else:
		# Cancel any ongoing reorder when unpausing
		if reordering_slot:
			_cancel_reorder()

		# Disable focus and mouse interaction when unpausing
		for slot in tooltip_slots:
			if slot:
				if slot.has_focus():
					slot.release_focus()
				slot.focus_mode = Control.FOCUS_NONE
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let mouse pass through!
				_unhighlight_slot(slot)

# ============================================================================
# LAYOUT MANAGEMENT
# ============================================================================

func set_layout_mode(mode: LayoutMode) -> void:
	"""Switch between vertical (landscape) and horizontal (portrait) layouts"""
	if current_layout == mode:
		return  # Already in this mode

	current_layout = mode

	match mode:
		LayoutMode.VERTICAL:
			_apply_vertical_layout()
		LayoutMode.HORIZONTAL:
			_apply_horizontal_layout()

func _apply_vertical_layout() -> void:
	"""Arrange pool sections vertically (landscape mode)"""
	# This is the default scene structure, so we just need to ensure
	# pool sections are children of this VBoxContainer in the correct order

	# Get spacer nodes
	var spacer1 = get_node_or_null("Spacer1")
	var spacer2 = get_node_or_null("Spacer2")
	var spacer3 = get_node_or_null("Spacer3")
	var spacer4 = get_node_or_null("Spacer4")

	# Ensure pool sections are direct children of this VBoxContainer
	_ensure_child(body_pool_section, 2)   # After title + spacer1
	_ensure_child(spacer2, 3) if spacer2 else null
	_ensure_child(mind_pool_section, 4)
	_ensure_child(spacer3, 5) if spacer3 else null
	_ensure_child(null_pool_section, 6)
	_ensure_child(spacer4, 7) if spacer4 else null
	_ensure_child(light_pool_section, 8)

	# Show spacers in vertical mode
	if spacer1: spacer1.visible = true
	if spacer2: spacer2.visible = true
	if spacer3: spacer3.visible = true
	if spacer4: spacer4.visible = true

func _apply_horizontal_layout() -> void:
	"""Arrange pool sections horizontally (portrait mode)"""
	# Hide spacers (don't make sense horizontally)
	var spacer1 = get_node_or_null("Spacer1")
	var spacer2 = get_node_or_null("Spacer2")
	var spacer3 = get_node_or_null("Spacer3")
	var spacer4 = get_node_or_null("Spacer4")

	if spacer1: spacer1.visible = false
	if spacer2: spacer2.visible = false
	if spacer3: spacer3.visible = false
	if spacer4: spacer4.visible = false

	# Create HBoxContainer if it doesn't exist
	var hbox = get_node_or_null("HorizontalContainer")
	if not hbox:
		hbox = HBoxContainer.new()
		hbox.name = "HorizontalContainer"
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hbox.add_theme_constant_override("separation", 10)
		add_child(hbox)

	# Move pool sections to HBoxContainer
	_ensure_child_of(body_pool_section, hbox, 0)
	_ensure_child_of(mind_pool_section, hbox, 1)
	_ensure_child_of(null_pool_section, hbox, 2)
	_ensure_child_of(light_pool_section, hbox, 3)

	# Make pool sections expand to fill available width
	body_pool_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mind_pool_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	null_pool_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	light_pool_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ensure_child(node: Node, index: int) -> void:
	"""Ensure node is a child of this container at the specified index"""
	if not node:
		return

	# Remove from current parent if different
	if node.get_parent() != self:
		if node.get_parent():
			node.get_parent().remove_child(node)
		add_child(node)

	# Move to correct position
	move_child(node, index)

func _ensure_child_of(node: Node, parent: Node, index: int) -> void:
	"""Ensure node is a child of the specified parent at the specified index"""
	if not node or not parent:
		return

	# Remove from current parent if different
	if node.get_parent() != parent:
		if node.get_parent():
			node.get_parent().remove_child(node)
		parent.add_child(node)

	# Move to correct position
	parent.move_child(node, index)
