class_name ItemStatusAction
extends Action
## Informational action for displaying item status in action preview UI
##
## Shows items that have reactive effects or cooldowns.
## Examples:
## - "Protective Ward READY (5 mana)" - shield ready to block
## - "Lucky Reset 3 → 2" - cooldown ticking down
##
## Displayed at bottom of preview, similar to attack cooldowns.

enum StatusType {
	READY,      # Item effect is ready to trigger (e.g., shield ready)
	COOLDOWN,   # Item is on cooldown
}

var item_name: String
var status_type: StatusType
var cooldown_current: int  # Current cooldown (for COOLDOWN type)
var cooldown_after: int    # Cooldown after tick (for COOLDOWN type)
var mana_cost: float       # Mana cost when triggered (for READY type)
var description: String    # Optional description

func _init(
	name: String,
	type: StatusType,
	cd_current: int = 0,
	cd_after: int = 0,
	cost: float = 0.0,
	desc: String = ""
) -> void:
	action_name = "ItemStatus"
	item_name = name
	status_type = type
	cooldown_current = cd_current
	cooldown_after = cd_after
	mana_cost = cost
	description = desc

func can_execute(_player) -> bool:
	return false  # Never executable - display only

func execute(_player) -> void:
	pass  # No-op - this is display-only

func get_preview_info(_player) -> Dictionary:
	match status_type:
		StatusType.READY:
			# Show ready status with shield/checkmark icon
			var cost_str = "(%.0f mana)" % mana_cost if mana_cost > 0 else ""
			return {
				"name": item_name,
				"target": "READY %s" % cost_str,
				"icon": "🛡",  # Shield emoji for protection ready
				"cost": ""
			}
		StatusType.COOLDOWN:
			# Show cooldown countdown like attacks
			return {
				"name": item_name,
				"target": "%d → %d" % [cooldown_current, cooldown_after],
				"icon": "🕐",
				"cost": ""
			}

	# Fallback
	return {
		"name": item_name,
		"target": description,
		"icon": "📦",
		"cost": ""
	}
