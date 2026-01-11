class_name WaitAction
extends Action
## Action for waiting/passing a turn without moving
##
## Usage:
##   var action = WaitAction.new()
##   if action.can_execute(player):
##       action.execute(player)

func _init() -> void:
	action_name = "Wait"

func can_execute(_player) -> bool:
	"""Waiting is always valid"""
	return true

func execute(player) -> void:
	"""Pass the turn without moving"""
	# Advance turn counter
	player.turn_count += 1

func get_preview_info(player) -> Dictionary:
	"""Get preview info for UI display"""
	return {
		"name": "Wait",
		"target": "(%d, %d)" % [player.grid_position.x, player.grid_position.y],
		"icon": "⏸",
		"cost": ""
	}
