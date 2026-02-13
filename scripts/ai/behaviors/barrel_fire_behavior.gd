class_name BarrelFireBehavior extends EntityBehavior
## Behavior for barrel fire entities — stationary light source

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 0

func process_turn(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	pass
