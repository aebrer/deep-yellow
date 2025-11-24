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
		Log.movement("Moved to item at %s (from %s)" % [target_position, old_pos])

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

	# Get the appropriate pool based on item type
	var pool = _get_pool_for_item(item, player)
	if not pool:
		Log.warn(Log.Category.ACTION, "No pool found for item type")
		return

	# Check if player already has this item (for level-up)
	var existing_slot = _find_item_in_pool(item.item_id, pool)

	if existing_slot != -1:
		# Player already has this item - level it up automatically
		var existing_item = pool.get_item(existing_slot)
		if existing_item:
			existing_item.level_up()
			pool.emit_signal("item_leveled_up", existing_item, existing_slot, existing_item.level)

			# Re-apply stat bonus
			existing_item._remove_stat_bonus(player)
			existing_item._apply_stat_bonus(player)

			Log.player("Picked up %s - leveled up to Level %d!" % [item.item_name, existing_item.level])

			# Remove item from world
			_remove_item_from_world(player)
			return

	# Player doesn't have this item - need to choose a slot
	# For now, auto-equip to first empty slot (TODO: show UI)
	var empty_slot = pool.get_first_empty_slot()

	if empty_slot != -1:
		# Empty slot available - equip there
		pool.add_item(item, empty_slot, player)
		Log.player("Picked up %s and equipped to slot %d" % [item.item_name, empty_slot])
		_remove_item_from_world(player)
	else:
		# No empty slots - need to show UI to choose which to overwrite
		# TODO: Implement slot selection UI
		Log.player("Inventory full! Drop an item first (UI TODO)")

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
	match item.pool_type:
		Item.PoolType.BODY:
			return player.body_pool
		Item.PoolType.MIND:
			return player.mind_pool
		Item.PoolType.NULL:
			return player.null_pool
		Item.PoolType.LIGHT:
			return player.light_pool
		_:
			return null

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

func _remove_item_from_world(player: Player3D) -> void:
	"""Remove item billboard from world after pickup

	Args:
		player: Player reference (to access grid/item_renderer)
	"""
	if not player or not player.grid or not player.grid.item_renderer:
		return

	player.grid.item_renderer.remove_item_at(target_position)

	# Also mark as picked up in chunk data (ChunkManager is an autoload singleton)
	if ChunkManager and ChunkManager.has_method("get_chunk_at_world_position"):
		var chunk = ChunkManager.get_chunk_at_world_position(target_position)
		if chunk:
			_mark_item_picked_up_in_chunk(chunk, target_position)

func _mark_item_picked_up_in_chunk(chunk: Chunk, world_pos: Vector2i) -> void:
	"""Mark item as picked up in SubChunk data (for persistence)

	Args:
		chunk: Chunk containing the item
		world_pos: World position of the item
	"""
	for subchunk in chunk.sub_chunks:
		for item_data_ref in subchunk.world_items:
			var pos_data = item_data_ref.get("world_position", {})
			var item_world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			if item_world_pos == world_pos:
				item_data_ref["picked_up"] = true
				Log.grid("Marked item at %s as picked up in chunk data" % world_pos)
				return

func get_description() -> String:
	"""Human-readable description for UI

	Returns:
		Action description string
	"""
	var item_name = item_data.get("item_name", "Unknown Item")
	return "Pick up %s" % item_name
