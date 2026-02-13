class_name LightFixtureBehavior extends EntityBehavior
## Behavior for stationary light fixtures (fluorescent lights, broken lights)
## Does nothing — purely environmental entities

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 0

func process_turn(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	pass
