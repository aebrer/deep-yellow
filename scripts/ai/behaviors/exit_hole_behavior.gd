class_name ExitHoleBehavior extends EntityBehavior
## Exit hole behavior - stationary environment entity, does nothing

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 0

func process_turn(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	# Exit holes don't move or act
	pass
