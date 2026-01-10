class_name AttackPreviewAction
extends Action
## Informational action for displaying attack previews in action preview UI
##
## This is not an executable action - it's only used for UI display purposes.
## Shows attack type, damage, and target count for attacks that WILL fire.

const _AttackTypes = preload("res://scripts/combat/attack_types.gd")

var attack_type: int  # AttackTypes.Type enum
var attack_name: String
var attack_emoji: String
var damage: float
var target_count: int
var mana_cost: float

func _init(type: int, name: String, emoji: String, dmg: float, targets: int, cost: float) -> void:
	action_name = "AttackPreview"
	attack_type = type
	attack_name = name
	attack_emoji = emoji
	damage = dmg
	target_count = targets
	mana_cost = cost

func can_execute(_player) -> bool:
	return false  # Never executable - display only

func execute(_player) -> void:
	pass  # No-op - this is display-only

func get_preview_info(_player) -> Dictionary:
	# Use attack emoji (may be customized by items)
	var icon = attack_emoji if attack_emoji else "⚔️"

	# Build target info: "X target(s) for Y dmg"
	var target_str = "%d target%s for %.0f dmg" % [
		target_count,
		"s" if target_count > 1 else "",
		damage
	]

	# Cost display for NULL attacks
	var cost_str = ""
	if mana_cost > 0:
		cost_str = "%.0f mana" % mana_cost

	return {
		"name": attack_name,
		"target": target_str,
		"icon": icon,
		"cost": cost_str
	}
