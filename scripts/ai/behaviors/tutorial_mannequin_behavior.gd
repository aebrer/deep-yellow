class_name TutorialMannequinBehavior extends EntityBehavior
## Tutorial mannequin behavior - stationary target for teaching combat

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 0

func process_turn(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	# Mannequins do nothing - they just stand there
	pass
