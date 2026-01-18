class_name DebugEnemyBehavior extends EntityBehavior
## Debug enemy behavior - stationary punching bag for testing

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 0

func process_turn(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	# Debug enemies do nothing - they just stand there
	pass
