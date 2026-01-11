class_name ItemPool extends RefCounted
"""Manages a collection of item slots for a specific pool (BODY/MIND/NULL).

Each pool has a fixed number of slots (3 per pool).
Items execute in top-to-bottom order each turn.

Responsibilities:
- Add/remove items from slots
- Reorder items (for synergy optimization)
- Execute all items each turn (in order)
- Track enabled/disabled state per item
- Emit signals for UI updates

Usage:
	var body_pool = ItemPool.new(Item.PoolType.BODY, 3)
	body_pool.add_item(brass_knuckles, 0)
	body_pool.execute_turn(player, turn_number)
"""

# ============================================================================
# SIGNALS
# ============================================================================

signal item_added(item: Item, slot_index: int)
signal item_removed(item: Item, slot_index: int)
signal item_leveled_up(item: Item, slot_index: int, new_level: int)
signal item_reordered(from_index: int, to_index: int)
signal item_toggled(slot_index: int, enabled: bool)

# ============================================================================
# PROPERTIES
# ============================================================================

var pool_type: Item.PoolType
var max_slots: int
var items: Array[Item] = []  ## Items in each slot (null = empty)
var enabled: Array[bool] = []  ## Is each slot enabled? (for toggling items on/off)

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(type: Item.PoolType, slots: int):
	"""Initialize pool with type and slot count.

	Args:
		type: BODY, MIND, or NULL
		slots: Number of slots (3 per pool)
	"""
	pool_type = type
	max_slots = slots

	# Initialize arrays with nulls/defaults
	items.resize(max_slots)
	enabled.resize(max_slots)
	for i in range(max_slots):
		items[i] = null
		enabled[i] = true  # Enabled by default


# ============================================================================
# ITEM MANAGEMENT
# ============================================================================

func add_item(item: Item, slot_index: int, player: Player3D) -> bool:
	"""Add an item to a slot.

	If slot already occupied:
	- Same item ID → Level up existing item
	- Different item ID → Requires confirmation (handled by caller)

	Args:
		item: The item to add
		slot_index: Which slot (0 to max_slots-1)
		player: Player reference (for on_equip callback)

	Returns:
		true if item was added/leveled up successfully
	"""
	if slot_index < 0 or slot_index >= max_slots:
		Log.warn(Log.Category.SYSTEM, "Invalid slot index: %d" % slot_index)
		return false

	var existing = items[slot_index]

	if existing:
		# Slot occupied - check if same item
		if existing.item_id == item.item_id:
			# Same item - level up!
			existing.level_up()
			emit_signal("item_leveled_up", existing, slot_index, existing.level)
			Log.player("Leveled up %s to Level %d!" % [existing.item_name, existing.level])

			# Re-apply stat bonus (old bonus removed, new bonus applied)
			existing._remove_stat_bonus(player)
			existing._apply_stat_bonus(player)
			return true
		else:
			# Different item - caller must confirm overwrite
			Log.warn(Log.Category.SYSTEM, "Slot %d occupied by different item" % slot_index)
			return false
	else:
		# Slot empty - equip item
		items[slot_index] = item
		item.on_equip(player)
		emit_signal("item_added", item, slot_index)
		Log.player("Equipped %s to slot %d" % [item.item_name, slot_index])
		return true

func remove_item(slot_index: int, player: Player3D) -> Item:
	"""Remove an item from a slot.

	Args:
		slot_index: Which slot to clear
		player: Player reference (for on_unequip callback)

	Returns:
		The removed item (or null if slot was empty)
	"""
	if slot_index < 0 or slot_index >= max_slots:
		Log.warn(Log.Category.SYSTEM, "Invalid slot index: %d" % slot_index)
		return null

	var item = items[slot_index]
	if item:
		item.on_unequip(player)
		items[slot_index] = null
		emit_signal("item_removed", item, slot_index)
		Log.player("Unequipped %s from slot %d" % [item.item_name, slot_index])
		return item
	else:
		Log.warn(Log.Category.SYSTEM, "Slot %d is already empty" % slot_index)
		return null

func overwrite_item(slot_index: int, new_item: Item, player: Player3D) -> Item:
	"""Replace item in slot (destroying old item).

	Returns the old item (for logging/effects), but it should be destroyed.

	Args:
		slot_index: Which slot to overwrite
		new_item: New item to equip
		player: Player reference

	Returns:
		The destroyed item (or null if slot was empty)
	"""
	var old_item = remove_item(slot_index, player)
	add_item(new_item, slot_index, player)

	if old_item:
		Log.player("Destroyed %s (Level %d)" % [old_item.item_name, old_item.level])

	return old_item

func reorder(from_index: int, to_index: int) -> bool:
	"""Swap items between two slots.

	Args:
		from_index: Source slot
		to_index: Destination slot

	Returns:
		true if reordering succeeded
	"""
	if from_index < 0 or from_index >= max_slots:
		return false
	if to_index < 0 or to_index >= max_slots:
		return false

	# Swap items
	var temp = items[from_index]
	items[from_index] = items[to_index]
	items[to_index] = temp

	# Swap enabled states
	var temp_enabled = enabled[from_index]
	enabled[from_index] = enabled[to_index]
	enabled[to_index] = temp_enabled

	emit_signal("item_reordered", from_index, to_index)
	return true

func toggle_item(slot_index: int) -> bool:
	"""Enable/disable an item slot (for tactical control).

	Args:
		slot_index: Which slot to toggle

	Returns:
		New enabled state (true/false)
	"""
	if slot_index < 0 or slot_index >= max_slots:
		return false

	enabled[slot_index] = not enabled[slot_index]
	emit_signal("item_toggled", slot_index, enabled[slot_index])

	var item = items[slot_index]
	if item:
		var state = "enabled" if enabled[slot_index] else "disabled"
		Log.player("%s %s" % [item.item_name, state])

	return enabled[slot_index]

# ============================================================================
# TURN EXECUTION
# ============================================================================

func execute_turn(player: Player3D, turn_number: int) -> void:
	"""Execute all enabled items in this pool (top to bottom).

	Called each turn by Player3D after movement/actions.

	Args:
		player: Player entity
		turn_number: Global turn counter
	"""
	for i in range(max_slots):
		if items[i] and enabled[i]:
			items[i].on_turn(player, turn_number)

# ============================================================================
# QUERIES
# ============================================================================

func get_item(slot_index: int) -> Item:
	"""Get item at slot (or null if empty)."""
	if slot_index >= 0 and slot_index < max_slots:
		return items[slot_index]
	return null

func is_slot_empty(slot_index: int) -> bool:
	"""Check if slot is empty."""
	return get_item(slot_index) == null

func is_slot_enabled(slot_index: int) -> bool:
	"""Check if slot is enabled."""
	if slot_index >= 0 and slot_index < max_slots:
		return enabled[slot_index]
	return false

func get_first_empty_slot() -> int:
	"""Find first empty slot index (or -1 if all full)."""
	for i in range(max_slots):
		if items[i] == null:
			return i
	return -1

func get_item_count() -> int:
	"""Count how many items are equipped."""
	var count = 0
	for item in items:
		if item:
			count += 1
	return count

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	"""Debug representation."""
	var item_names = []
	for i in range(max_slots):
		if items[i]:
			var state = "ON" if enabled[i] else "OFF"
			item_names.append("%s (Lv%d, %s)" % [items[i].item_name, items[i].level, state])
		else:
			item_names.append("[empty]")

	return "ItemPool(%s): [%s]" % [
		Item.PoolType.keys()[pool_type],
		", ".join(item_names)
	]
