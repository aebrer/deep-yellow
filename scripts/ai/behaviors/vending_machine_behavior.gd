class_name VendingMachineBehavior extends EntityBehavior
## Vending machine behavior - stationary interactable, does nothing

func _init() -> void:
	skip_turn_processing = true
