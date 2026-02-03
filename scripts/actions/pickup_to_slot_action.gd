class_name PickupToSlotAction extends Action
## Action for equipping a picked-up item to a specific slot
##
## This action is queued after the player selects a slot in the pickup UI.
## It handles equipping to empty slots, leveling up duplicates, or overwriting.

var item: Item  ## The item being picked up
var pool_type: Item.PoolType  ## Which pool (BODY/MIND/NULL)
var slot_index: int  ## Target slot (0-N)
var action_type: int  ## ActionType enum value (equip/combine/overwrite)
var world_position: Vector2i  ## Item's world position (for removal)

func _init(picked_item: Item, target_pool: Item.PoolType, target_slot: int, type: int, pos: Vector2i):
	"""Initialize pickup to slot action

	Args:
		picked_item: Item resource to equip
		target_pool: Pool type (BODY/MIND/NULL)
		target_slot: Slot index (0-N)
		type: ActionType (EQUIP_EMPTY, COMBINE_LEVEL_UP, OVERWRITE)
		pos: World position of item
	"""
	item = picked_item
	pool_type = target_pool
	slot_index = target_slot
	action_type = type
	world_position = pos

func can_execute(player: Player3D) -> bool:
	"""Check if pickup to slot is valid

	Returns:
		true if player has the pool and slot is valid
	"""
	if not player:
		return false

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return false

	if slot_index < 0 or slot_index >= pool.max_slots:
		return false

	return true

func execute(player: Player3D) -> void:
	"""Execute pickup to slot

	This performs the actual equip/level-up/overwrite and removes the item from the world.
	"""
	if not can_execute(player):
		Log.warn(Log.Category.ACTION, "Cannot execute pickup to slot")
		return

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return

	# Perform the appropriate action
	match action_type:
		0:  # EQUIP_EMPTY
			pool.add_item(item, slot_index, player)
			Log.player("Equipped %s to slot %d" % [item.item_name, slot_index + 1])

		1:  # COMBINE_LEVEL_UP
			var existing_item = pool.get_item(slot_index)
			if existing_item:
				# Additive combining: incoming item's level is added to existing
				existing_item.level_up(item.level)
				pool.emit_signal("item_leveled_up", existing_item, slot_index, existing_item.level)

				# Re-apply stat bonus
				existing_item._remove_stat_bonus(player)
				existing_item._apply_stat_bonus(player)

				Log.player("Combined %s (+%d) - now Level %d!" % [item.item_name, item.level, existing_item.level])

		2:  # OVERWRITE
			pool.overwrite_item(slot_index, item, player)
			Log.player("Equipped %s to slot %d (overwriting previous item)" % [item.item_name, slot_index + 1])

	# Remove item from world
	Action._remove_item_from_world(player, world_position)

	# Increment turn count (this is a turn action)
	player.turn_count += 1

func get_description() -> String:
	"""Human-readable description for UI

	Returns:
		Action description string
	"""
	return "Pick up %s to slot %d" % [item.item_name if item else "Unknown", slot_index + 1]
