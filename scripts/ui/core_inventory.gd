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

Tooltips show full clearance-based item descriptions.
Updates in real-time as items change.
"""

var player: Player3D = null
var tooltip_slots: Array[Control] = []
var tooltip_texts: Dictionary = {}  # slot -> tooltip_text

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

# Tooltip overlay (shared with StatsPanel)
var tooltip_panel: PanelContainer = null
var tooltip_label: Label = null

func _ready():
	# Wait for player to be set by Game node
	await get_tree().process_frame

	# Get tooltip overlay from game root (shared with StatsPanel)
	_get_tooltip_overlay()

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

func _get_tooltip_overlay() -> void:
	"""Get the shared tooltip overlay (created by StatsPanel)"""
	var game_root = get_tree().root.get_node_or_null("Game")
	if not game_root:
		return

	tooltip_panel = game_root.get_node_or_null("StatsTooltipOverlay")
	if tooltip_panel:
		tooltip_label = tooltip_panel.get_child(0) if tooltip_panel.get_child_count() > 0 else null

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

func _highlight_slot(slot: Control) -> void:
	"""Apply visual highlight and show tooltip (unified for mouse and controller)"""
	# Only highlight if slot has an item
	var label = slot.get_node_or_null("Label")
	if not label or label.text == "<empty>":
		return

	# Create a StyleBoxFlat for the background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 0.5, 0.3)  # Yellow transparent
	style.border_color = Color(1.0, 1.0, 0.5, 0.8)  # Yellow border
	style.set_border_width_all(2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2

	# Override BOTH normal and focus to disable Godot's built-in focus indicator
	slot.add_theme_stylebox_override("panel", style)

	# Show tooltip in overlay
	if tooltip_panel and tooltip_label and slot in tooltip_texts:
		tooltip_label.text = tooltip_texts[slot]
		tooltip_panel.visible = true

func _unhighlight_slot(slot: Control) -> void:
	"""Remove visual highlight and hide tooltip"""
	slot.remove_theme_stylebox_override("panel")

	# Hide tooltip overlay
	if tooltip_panel:
		tooltip_panel.visible = false

func _on_pause_toggled(is_paused: bool) -> void:
	"""Enable/disable focus and clear highlights based on pause state"""
	if is_paused:
		# Enable focus for gamepad navigation when paused
		for slot in tooltip_slots:
			if slot:
				slot.focus_mode = Control.FOCUS_ALL
				slot.mouse_filter = Control.MOUSE_FILTER_STOP  # Allow mouse hover
	else:
		# Disable focus and mouse interaction when unpausing
		for slot in tooltip_slots:
			if slot:
				if slot.has_focus():
					slot.release_focus()
				slot.focus_mode = Control.FOCUS_NONE
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let mouse pass through!
				_unhighlight_slot(slot)
