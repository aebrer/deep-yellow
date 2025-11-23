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

	var pool = _get_pool(player)
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

	var pool = _get_pool(player)
	if not pool:
		return

	# Toggle the item
	pool.toggle_item(slot_index)

	var item = pool.items[slot_index]
	var item_name = item.item_name if item else "Unknown"
	var state = "ON" if pool.enabled[slot_index] else "OFF"

	Log.turn("Toggled %s to %s" % [item_name, state])

func get_preview_info(player) -> Dictionary:
	var pool = _get_pool(player)
	if not pool or slot_index >= pool.items.size():
		return {
			"name": "Toggle Item",
			"target": "",
			"icon": "⚡",
			"cost": ""
		}

	var item = pool.items[slot_index]
	if not item:
		return {
			"name": "Toggle Item",
			"target": "",
			"icon": "⚡",
			"cost": ""
		}

	var new_state = "OFF" if pool.enabled[slot_index] else "ON"

	return {
		"name": "Toggle",
		"target": "%s → %s" % [item.item_name, new_state],
		"icon": "⚡",
		"cost": ""
	}

func _get_pool(player) -> ItemPool:
	"""Get the pool from the player based on pool_type"""
	match pool_type:
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
