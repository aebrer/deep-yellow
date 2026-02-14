class_name LightFixtureBehavior extends EntityBehavior
## Behavior for stationary light fixtures (fluorescent lights, broken lights)
## Does nothing — purely environmental entities

func _init() -> void:
	skip_turn_processing = true
