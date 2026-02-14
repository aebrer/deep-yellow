class_name ReorderItemAction
extends Action
## Action for reordering items within a pool
##
## This action consumes a turn, just like movement.
## When executed, it moves an item from one slot to another within the same pool.

var pool_type: Item.PoolType
var from_index: int
var to_index: int

func _init(p_pool_type: Item.PoolType, p_from_index: int, p_to_index: int) -> void:
	action_name = "ReorderItem"
	pool_type = p_pool_type
	from_index = p_from_index
	to_index = p_to_index

func can_execute(player) -> bool:
	# Check if player has the pool
	if not player:
		return false

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return false

	# Check if indices are valid
	if from_index < 0 or from_index >= pool.items.size():
		return false
	if to_index < 0 or to_index >= pool.items.size():
		return false

	# Check if source slot has an item
	var item = pool.items[from_index]
	if not item:
		return false  # Can't reorder empty slot

	return true

func execute(player) -> void:
	if not player:
		return

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return

	# Get item name before reordering (for logging)
	var item = pool.items[from_index]
	var item_name = item.item_name if item else "Unknown"

	# Reorder the items
	pool.reorder(from_index, to_index)

	# Advance turn counter (this action consumes a turn)
	player.turn_count += 1

	Log.turn("Turn %d: Reordered %s from slot %d to slot %d in %s pool" % [
		player.turn_count,
		item_name,
		from_index,
		to_index,
		Item.PoolType.keys()[pool_type]
	])
