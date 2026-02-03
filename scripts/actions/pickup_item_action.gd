class_name PickupItemAction extends Action
## Action for picking up an item from the ground
##
## Walks to item position and shows slot selection UI.
## If player chooses a slot with the same item, it levels up.
## If player chooses a slot with a different item, it overwrites (with confirmation).

var target_position: Vector2i  ## Grid position of the item
var item_data: Dictionary  ## Serialized WorldItem data from ItemRenderer

func _init(pos: Vector2i, data: Dictionary):
	"""Initialize pickup action

	Args:
		pos: Grid position of the item to pick up
		data: Serialized WorldItem data (has item_id, level, rarity, etc.)
	"""
	target_position = pos
	item_data = data

func can_execute(player: Player3D) -> bool:
	"""Check if pickup is valid

	Returns:
		true if player can reach the item
	"""
	if not player or not player.grid:
		return false

	# Check if target position is adjacent or same tile
	var player_pos = player.grid_position
	var distance = player_pos.distance_to(target_position)

	# Must be on same tile or adjacent (within 1.5 tiles)
	if distance > 1.5:
		Log.warn(Log.Category.ACTION, "Item too far away: distance=%.2f" % distance)
		return false

	# Check if walkable (in case item is on wall somehow)
	if not player.grid.is_walkable(target_position):
		Log.warn(Log.Category.ACTION, "Cannot pick up item on unwalkable tile")
		return false

	return true

func execute(player: Player3D) -> void:
	"""Execute pickup - move to item and show slot selection UI

	This action:
	1. Moves player to item position (if not already there)
	2. Shows slot selection UI
	3. On slot selection, adds item to that slot
	4. Removes item billboard from world
	"""
	if not can_execute(player):
		Log.warn(Log.Category.ACTION, "Cannot execute pickup")
		return

	# Move to item position if not already there
	if player.grid_position != target_position:
		var old_pos = player.grid_position
		player.grid_position = target_position
		player.update_visual_position()

	# Show pickup UI (pauses game and lets player choose slot)
	_show_pickup_ui(player)

func _show_pickup_ui(player: Player3D) -> void:
	"""Show UI for choosing which slot to equip item to

	Args:
		player: Player reference
	"""
	# Get item resource from item_id
	var item_id = item_data.get("item_id", "")
	var item = _get_item_by_id(item_id, player)

	if not item:
		Log.warn(Log.Category.ACTION, "Failed to find item resource for ID: %s" % item_id)
		return

	# Set item level from world data
	var world_level = item_data.get("level", 1)
	item.level = world_level

	# Restore corruption state from world data
	if item_data.get("corrupted", false):
		item.corrupted = true
		item.starts_enabled = false
		item.corruption_debuffs = item_data.get("corruption_debuffs", []).duplicate(true)

	# Get the appropriate pool based on item type
	var pool = _get_pool_for_item(item, player)
	if not pool:
		Log.warn(Log.Category.ACTION, "No pool found for item type")
		return

	# Get or create slot selection UI
	var slot_ui = _get_slot_selection_ui(player)
	if not slot_ui:
		Log.warn(Log.Category.ACTION, "Failed to get slot selection UI")
		return

	# Show UI - it will handle the pickup internally
	slot_ui.show_slot_selection(item, pool, player, target_position)

func _get_item_by_id(item_id: String, player: Player3D) -> Item:
	"""Look up Item resource by item_id from current level

	Args:
		item_id: Unique item identifier
		player: Player reference (to get current level)

	Returns:
		Item resource or null if not found
	"""
	if not player or not player.grid or not player.grid.current_level:
		return null

	# Search through permitted items in level config
	for item in player.grid.current_level.permitted_items:
		if item.item_id == item_id:
			# Duplicate the item so each pickup is independent
			return item.duplicate_item()

	return null

func _get_pool_for_item(item: Item, player: Player3D) -> ItemPool:
	"""Get the appropriate ItemPool for this item type

	Args:
		item: The item to find a pool for
		player: Player reference

	Returns:
		ItemPool or null if invalid type
	"""
	return Action._get_pool_by_type(player, item.pool_type)

func _find_item_in_pool(item_id: String, pool: ItemPool) -> int:
	"""Find slot index of item with matching ID in pool

	Args:
		item_id: Item ID to search for
		pool: Pool to search in

	Returns:
		Slot index (0-N) or -1 if not found
	"""
	for i in range(pool.max_slots):
		var item = pool.get_item(i)
		if item and item.item_id == item_id:
			return i
	return -1

func _get_slot_selection_ui(player: Player3D) -> ItemSlotSelectionPanel:
	"""Get or create the slot selection UI

	Args:
		player: Player reference (to access scene tree)

	Returns:
		ItemSlotSelectionPanel instance or null if failed
	"""
	if not player:
		return null

	# Try to find existing UI in the scene tree
	var ui = player.get_node_or_null("/root/Game/ItemSlotSelectionPanel")

	if ui:
		return ui

	# UI doesn't exist - create it
	var game_node = player.get_node_or_null("/root/Game")
	if not game_node:
		Log.warn(Log.Category.ACTION, "Cannot find Game node to attach slot UI")
		return null

	# Create and add UI
	ui = ItemSlotSelectionPanel.new()
	ui.name = "ItemSlotSelectionPanel"
	game_node.add_child(ui)

	return ui

func get_preview_info(player) -> Dictionary:
	"""Get preview info for UI display

	Returns:
		Dictionary with name, target, icon, cost
	"""
	# Look up item resource to get display name
	var item_id = item_data.get("item_id", "")
	var item = _get_item_by_id(item_id, player)
	if item and item_data.get("corrupted", false):
		item.corrupted = true
	var item_name = item.get_display_name() if item else "Unknown Item"

	return {
		"name": "Pick up",
		"target": item_name,
		"icon": "📦",
		"cost": ""
	}

func get_description() -> String:
	"""Human-readable description for UI

	Returns:
		Action description string
	"""
	var item_name = item_data.get("item_name", "Unknown Item")
	return "Pick up %s" % item_name
