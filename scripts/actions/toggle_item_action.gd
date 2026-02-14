class_name ToggleItemAction
extends Action
## Action for toggling an item ON/OFF in a pool
##
## This action consumes a turn, just like movement.
## When executed, it toggles the item at the specified slot in the specified pool.

var pool_type: Item.PoolType
var slot_index: int

func _init(p_pool_type: Item.PoolType, p_slot_index: int) -> void:
	action_name = "ToggleItem"
	pool_type = p_pool_type
	slot_index = p_slot_index

func can_execute(player) -> bool:
	# Check if player has the pool
	if not player:
		return false

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return false

	# Check if slot has an item
	if slot_index < 0 or slot_index >= pool.items.size():
		return false

	var item = pool.items[slot_index]
	if not item:
		return false  # Can't toggle empty slot

	return true

func execute(player) -> void:
	if not player:
		return

	var pool = Action._get_pool_by_type(player, pool_type)
	if not pool:
		return

	# Toggle the item (pass player for corruption on_enable/on_disable)
	pool.toggle_item(slot_index, player)

	var item = pool.items[slot_index]
	var item_name = item.get_display_name() if item else "Unknown"
	var state = "ON" if pool.enabled[slot_index] else "OFF"

	# Advance turn counter (this action consumes a turn)
	player.turn_count += 1

	Log.turn("Turn %d: Toggled %s to %s" % [player.turn_count, item_name, state])
