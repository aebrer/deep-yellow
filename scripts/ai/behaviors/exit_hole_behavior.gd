class_name ExitHoleBehavior extends EntityBehavior
## Exit hole behavior - stationary environment entity, does nothing

func _init() -> void:
	skip_turn_processing = true
