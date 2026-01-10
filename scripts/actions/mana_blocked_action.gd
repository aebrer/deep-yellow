class_name ManaBlockedAction
extends Action
## Informational action for displaying mana-blocked effects in action preview UI
##
## Shows items or attacks that cannot trigger due to insufficient mana.
## Displayed with 🚫 prohibited emoji to indicate blocked status.

var effect_name: String
var mana_cost: float
var current_mana: float
var mana_after_regen: float

func _init(name: String, cost: float, current: float, after_regen: float) -> void:
	action_name = "ManaBlocked"
	effect_name = name
	mana_cost = cost
	current_mana = current
	mana_after_regen = after_regen

func can_execute(_player) -> bool:
	return false  # Never executable - display only

func execute(_player) -> void:
	pass  # No-op - this is display-only

func get_preview_info(_player) -> Dictionary:
	# Show current mana vs needed
	var target_str = "need %.0f mana (have %.0f)" % [mana_cost, current_mana]

	return {
		"name": effect_name,
		"target": target_str,
		"icon": "🚫",
		"cost": ""
	}
