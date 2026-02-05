class_name VendingMachinePanel
extends Control
## Vending machine UI panel for purchasing items at a stat cost
##
## Shows 2-5 randomly generated items with costs in permanent max stat reduction.
## Items persist per vending machine position (session-scoped).
## Purchased items show as "OUT OF STOCK".
##
## Cost formula:
##   base_cost = rarity_base_cost[rarity]
##   final_cost = base_cost * (1 + corruption * 0.5)
##   stat = random choice of HP, Sanity, or Mana (per item, fixed at generation)

# ============================================================================
# CONSTANTS
# ============================================================================

## Base font sizes (scaled by UIScaleManager)
const FONT_SIZE_HEADER := 20
const FONT_SIZE_ITEM_NAME := 16
const FONT_SIZE_INFO := 14

## Delay before accepting input (prevents accidental clicks)
const INPUT_ACCEPT_DELAY := 0.5

## Base cost per rarity tier (in max stat points)
## Minimum 20 for commons — vending machines are expensive
const RARITY_BASE_COST = {
	ItemRarity.Tier.DEBUG: 1,
	ItemRarity.Tier.COMMON: 20,
	ItemRarity.Tier.UNCOMMON: 30,
	ItemRarity.Tier.RARE: 45,
	ItemRarity.Tier.EPIC: 65,
	ItemRarity.Tier.LEGENDARY: 90,
	ItemRarity.Tier.ANOMALY: 120,
}

## Stat names for cost display
const STAT_NAMES = ["HP", "Sanity", "Mana"]
const STAT_MODIFIER_NAMES = ["hp", "sanity", "mana"]

## Item count probabilities: index = (count - 2), value = cumulative weight
## 2 items: 40%, 3 items: 30%, 4 items: 20%, 5 items: 10%
const ITEM_COUNT_WEIGHTS = [40, 30, 20, 10]

# ============================================================================
# STATIC STATE - persists across panel open/close per vending machine
# ============================================================================

## Stores generated vending machine inventories per world position
## Key: Vector2i (world pos), Value: Array of {item: Item, rarity: Tier, cost: int, stat_index: int, purchased: bool}
static var _machine_inventories: Dictionary = {}

# ============================================================================
# NODE REFERENCES
# ============================================================================

var panel: PanelContainer
var content_vbox: VBoxContainer
var item_buttons: Array[Button] = []
var cancel_button: Button = null
var emoji_font: Font = null

# State
var player_ref: Player3D = null
var machine_position: Vector2i = Vector2i.ZERO
var machine_entity: WorldEntity = null
var _accepting_input: bool = false

func _ready() -> void:
	emoji_font = load("res://assets/fonts/default_font.tres")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	visible = false

	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

func _build_panel() -> void:
	"""Build centered vending machine panel"""
	panel = PanelContainer.new()
	panel.name = "VendingPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	panel.custom_minimum_size = Vector2(450, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(0.6, 0.8, 1.0, 1.0)  # Blue-white border (machine aesthetic)
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
	content_vbox.add_theme_constant_override("separation", 10)
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content_vbox)

# ============================================================================
# PUBLIC API
# ============================================================================

func show_vending_machine(player: Player3D, position: Vector2i, entity: WorldEntity) -> void:
	"""Display vending machine UI"""
	player_ref = player
	machine_position = position
	machine_entity = entity

	# Generate inventory if first visit to this machine
	if not _machine_inventories.has(position):
		_generate_inventory(player, position)

	_rebuild_content()
	_update_panel_position()

	visible = true
	_accepting_input = false

	await get_tree().process_frame

	if PauseManager:
		PauseManager.set_pause(true)

# ============================================================================
# INVENTORY GENERATION
# ============================================================================

func _generate_inventory(player: Player3D, position: Vector2i) -> void:
	"""Generate random items for this vending machine using forced spawn rules"""
	# Roll item count: 2-5 with decreasing odds
	var item_count = _roll_item_count()

	# Get available items from current level
	var available_items: Array[Item] = []
	if player.grid and player.grid.current_level:
		available_items = player.grid.current_level.permitted_items

	if available_items.is_empty():
		_machine_inventories[position] = []
		return

	# Get corruption for cost scaling
	var corruption = 0.0
	if player.grid and player.grid.current_level:
		var level_id = player.grid.current_level.level_id
		if ChunkManager and ChunkManager.corruption_tracker:
			corruption = ChunkManager.corruption_tracker.get_corruption(level_id)

	# Generate items using weighted rarity selection (same as forced item spawns)
	var inventory: Array = []
	for i in range(item_count):
		var entry = _roll_item(available_items, corruption)
		if entry:
			inventory.append(entry)

	_machine_inventories[position] = inventory

func _roll_item_count() -> int:
	"""Roll for 2-5 items with decreasing odds"""
	var total_weight = 0
	for w in ITEM_COUNT_WEIGHTS:
		total_weight += w

	var roll = randi() % total_weight
	var cumulative = 0
	for i in range(ITEM_COUNT_WEIGHTS.size()):
		cumulative += ITEM_COUNT_WEIGHTS[i]
		if roll < cumulative:
			return i + 2  # 2-5

	return 2  # Fallback

func _roll_item(available_items: Array[Item], corruption: float) -> Dictionary:
	"""Roll a single item using corruption-weighted rarity probabilities"""
	var rarity_order = [
		ItemRarity.Tier.DEBUG,
		ItemRarity.Tier.ANOMALY,
		ItemRarity.Tier.LEGENDARY,
		ItemRarity.Tier.EPIC,
		ItemRarity.Tier.RARE,
		ItemRarity.Tier.UNCOMMON,
		ItemRarity.Tier.COMMON
	]

	# Build weighted pool (same logic as ItemSpawner.spawn_forced_item)
	var weighted_pool: Array[Dictionary] = []
	var total_weight: float = 0.0

	for rarity in rarity_order:
		var items_of_rarity: Array[Item] = []
		for item in available_items:
			if item.rarity == rarity:
				items_of_rarity.append(item)

		if items_of_rarity.is_empty():
			continue

		var base_prob = ItemRarity.get_base_probability(rarity)
		var corruption_mult = ItemRarity.get_corruption_multiplier(rarity)
		var rarity_weight = base_prob * (1.0 + corruption * corruption_mult)
		if rarity_weight <= 0:
			continue

		var per_item_weight = rarity_weight / items_of_rarity.size()
		for item in items_of_rarity:
			weighted_pool.append({"item": item, "weight": per_item_weight, "rarity": rarity})
			total_weight += per_item_weight

	if total_weight <= 0:
		return {}

	# Weighted random selection
	var roll = randf() * total_weight
	var cumulative: float = 0.0
	var selected = weighted_pool[0]
	for entry in weighted_pool:
		cumulative += entry.weight
		if roll <= cumulative:
			selected = entry
			break

	var rarity = selected.rarity

	# Random stat type for this item's cost
	var stat_index = randi() % 3  # 0=HP, 1=Sanity, 2=Mana

	# Roll corruption-scaled item level (same formula as ItemSpawner._roll_item_level)
	var duped_item = selected.item.duplicate_item()
	if corruption > 0.0:
		var steps = corruption / ItemSpawner.CORRUPTION_PER_LEVEL_STEP
		var guaranteed = int(steps)
		var remainder = steps - guaranteed
		if randf() < remainder:
			guaranteed += 1
		if guaranteed > 0:
			duped_item.level = 1 + guaranteed

	# Roll for corruption
	if corruption > 0.0:
		var corrupt_chance = 1.0 - exp(-corruption * 0.5)
		if randf() < corrupt_chance:
			duped_item.corrupted = true
			duped_item.starts_enabled = false
			duped_item.corruption_debuffs.append(CorruptionDebuffs.roll_debuff())

	# Calculate cost (scales with rarity, corruption, and item level)
	var base_cost = RARITY_BASE_COST.get(rarity, 5)
	# Level scaling: +10% per level above 1 (level 2 = 1.1x, level 3 = 1.2x, etc.)
	var level_multiplier = 1.0 + (duped_item.level - 1) * 0.1
	var final_cost = int(ceil(base_cost * (1.0 + corruption * 0.5) * level_multiplier))
	final_cost = max(1, final_cost)

	return {
		"item": duped_item,
		"rarity": rarity,
		"cost": final_cost,
		"stat_index": stat_index,
		"purchased": false,
	}

# ============================================================================
# UI BUILDING
# ============================================================================

func _rebuild_content() -> void:
	"""Rebuild UI content for current vending machine"""
	var vbox = content_vbox
	for child in vbox.get_children():
		if child is Button and child.has_focus():
			child.release_focus()
		if child.is_in_group("hud_focusable"):
			child.remove_from_group("hud_focusable")
		child.free()
	item_buttons.clear()

	# Header
	var header = Label.new()
	header.text = "VENDING MACHINE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_HEADER))
	header.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	if emoji_font:
		header.add_theme_font_override("font", emoji_font)
	vbox.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Items cost permanent max stat reduction."
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subheader.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	subheader.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	if emoji_font:
		subheader.add_theme_font_override("font", emoji_font)
	vbox.add_child(subheader)

	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 12)
	vbox.add_child(separator1)

	# Item buttons
	var inventory = _machine_inventories.get(machine_position, [])

	if inventory.is_empty():
		var empty_label = Label.new()
		empty_label.text = "[ MACHINE EMPTY ]"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		if emoji_font:
			empty_label.add_theme_font_override("font", emoji_font)
		vbox.add_child(empty_label)
	else:
		for i in range(inventory.size()):
			var entry = inventory[i]
			var button = _create_item_button(i, entry)
			vbox.add_child(button)
			item_buttons.append(button)

	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 12)
	vbox.add_child(separator2)

	# Cancel button
	cancel_button = Button.new()
	cancel_button.text = "Walk Away (Cancel)"
	cancel_button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		cancel_button.add_theme_font_override("font", emoji_font)
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.add_to_group("hud_focusable")
	_style_button(cancel_button)
	vbox.add_child(cancel_button)

func _create_item_button(index: int, entry: Dictionary) -> Button:
	"""Create a button for a vending machine item slot"""
	var button = Button.new()
	var item: Item = entry.item
	var rarity = entry.rarity
	var cost = entry.cost
	var stat_index = entry.stat_index
	var purchased = entry.purchased

	if purchased:
		button.text = "[ OUT OF STOCK ]"
		button.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		button.disabled = true
	else:
		var rarity_name = ItemRarity.get_rarity_name(rarity)
		var stat_name = STAT_NAMES[stat_index]
		var can_afford = _can_afford(cost, stat_index)
		button.text = "%s Lv%d (%s) — Cost: -%d max %s" % [item.get_display_name(), item.level, rarity_name, cost, stat_name]
		if can_afford:
			button.add_theme_color_override("font_color", ItemRarity.get_color(rarity))
		else:
			button.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
			button.disabled = true
		button.pressed.connect(func(): _on_item_selected(index))

	button.add_theme_font_size_override("font_size", _get_font_size(FONT_SIZE_INFO))
	if emoji_font:
		button.add_theme_font_override("font", emoji_font)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(button)
	button.add_to_group("hud_focusable")
	return button

func _style_button(button: Button) -> void:
	"""Apply transparent normal / yellow focus styles"""
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	normal_style.set_border_width_all(0)

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(1.0, 1.0, 0.5, 0.3)
	focus_style.border_color = Color(1.0, 1.0, 0.5, 0.8)
	focus_style.set_border_width_all(2)
	focus_style.content_margin_left = 4
	focus_style.content_margin_right = 4
	focus_style.content_margin_top = 2
	focus_style.content_margin_bottom = 2

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", focus_style)

# ============================================================================
# ITEM PURCHASE
# ============================================================================

func _on_item_selected(index: int) -> void:
	"""Handle item purchase from vending machine"""
	if not visible or not _accepting_input:
		return

	var inventory = _machine_inventories.get(machine_position, [])
	if index < 0 or index >= inventory.size():
		return

	var entry = inventory[index]
	if entry.purchased:
		return

	var item: Item = entry.item
	var cost: int = entry.cost
	var stat_index: int = entry.stat_index
	var stat_mod_name = STAT_MODIFIER_NAMES[stat_index]
	var stat_display = STAT_NAMES[stat_index]

	# Affordability check
	if not _can_afford(cost, stat_index):
		Log.player("Can't afford %s (need %d max %s) — come back later" % [item.get_display_name(), cost, stat_display])
		return

	# Apply permanent max stat reduction
	var modifier = StatModifier.new(
		stat_mod_name,
		-float(cost),
		StatModifier.ModifierType.ADD,
		"Vending Machine",
		-1  # Permanent
	)
	player_ref.stats.add_modifier(modifier)

	# Clamp current resources to new max
	_clamp_current_stats(player_ref)

	# Mark as purchased
	entry.purchased = true

	# Give item to player via slot selection UI (same as pickup)
	_give_item_to_player(item, player_ref)

	Log.player("Purchased %s from vending machine (-%d max %s)" % [item.get_display_name(), cost, stat_display])

	# Close panel (item slot selection will open if needed)
	_close_panel()

func _can_afford(cost: int, stat_index: int) -> bool:
	"""Check if the player's current max stat can cover the cost"""
	if not player_ref or not player_ref.stats:
		return false
	var current_max: float
	match stat_index:
		0: current_max = player_ref.stats.max_hp
		1: current_max = player_ref.stats.max_sanity
		2: current_max = player_ref.stats.max_mana
		_: return false
	return current_max >= cost

func _clamp_current_stats(player: Player3D) -> void:
	"""Clamp current HP/Sanity/Mana to new maximums after stat reduction"""
	var stats = player.stats
	if stats.current_hp > stats.max_hp:
		stats.current_hp = stats.max_hp
	if stats.current_sanity > stats.max_sanity:
		stats.current_sanity = stats.max_sanity
	if stats.current_mana > stats.max_mana:
		stats.current_mana = stats.max_mana

func _give_item_to_player(item: Item, player: Player3D) -> void:
	"""Open the item slot selection panel for the purchased item"""
	var pool = Action._get_pool_by_type(player, item.pool_type)
	if not pool:
		Log.warn(Log.Category.ACTION, "No pool found for purchased item type")
		return

	# Get or create slot selection UI
	var slot_ui = player.get_node_or_null("/root/Game/ItemSlotSelectionPanel")
	if not slot_ui:
		var game_node = player.get_node_or_null("/root/Game")
		if not game_node:
			return
		slot_ui = ItemSlotSelectionPanel.new()
		slot_ui.name = "ItemSlotSelectionPanel"
		game_node.add_child(slot_ui)

	# Use Vector2i(-1, -1) as position since this isn't a ground pickup
	slot_ui.show_slot_selection(item, pool, player, Vector2i(-1, -1))

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

	var max_height: float = viewport_rect.size.y * 0.8
	var panel_size: Vector2 = panel.size
	if panel_size.y > max_height:
		panel_size.y = max_height
		panel.size = panel_size

	var center_x: float = viewport_rect.position.x + (viewport_rect.size.x - panel_size.x) / 2.0
	var center_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0
	panel.position = Vector2(center_x, center_y)

# ============================================================================
# CLOSE / CANCEL
# ============================================================================

func _on_cancel_pressed() -> void:
	"""Walk away from vending machine"""
	if not _accepting_input:
		return
	Log.player("Walked away from vending machine")
	_close_panel()

func _close_panel() -> void:
	"""Hide panel and unpause game"""
	visible = false
	if PauseManager:
		PauseManager.set_pause(false)

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _on_pause_toggled(is_paused: bool) -> void:
	"""Update button focus when pause state changes"""
	if not visible:
		return

	if is_paused:
		for button in item_buttons:
			button.focus_mode = Control.FOCUS_ALL
			button.mouse_filter = Control.MOUSE_FILTER_STOP

		if cancel_button:
			cancel_button.focus_mode = Control.FOCUS_ALL
			cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP

		if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
			# Focus first non-purchased item, or cancel
			var focused = false
			for button in item_buttons:
				if not button.disabled:
					button.grab_focus()
					focused = true
					break
			if not focused and cancel_button:
				cancel_button.grab_focus()

		_accepting_input = false
		get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
			func(): _accepting_input = true if visible else false
		)
	else:
		_accepting_input = false
		for button in item_buttons:
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if cancel_button:
			cancel_button.focus_mode = Control.FOCUS_NONE
			cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad-specific inputs"""
	if not visible or not _accepting_input:
		return

	if event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A and event.pressed:
			var focused = get_viewport().gui_get_focus_owner()
			if focused and focused is Button:
				if focused in item_buttons or focused == cancel_button:
					focused.pressed.emit()
					get_viewport().set_input_as_handled()
			return

		if event.button_index == JOY_BUTTON_B and event.pressed:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
		return

func _process(_delta: float) -> void:
	"""Handle RT/A button activation of focused button"""
	if not visible or not _accepting_input:
		return

	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and (focused in item_buttons or focused == cancel_button):
			focused.pressed.emit()
			return

	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused is Button and (focused in item_buttons or focused == cancel_button):
			focused.pressed.emit()
			return

# ============================================================================
# UI SCALING
# ============================================================================

func _get_font_size(base_size: int) -> int:
	if UIScaleManager:
		return UIScaleManager.get_scaled_font_size(base_size)
	return base_size
