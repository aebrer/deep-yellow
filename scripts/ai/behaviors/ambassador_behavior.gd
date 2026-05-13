class_name AmbassadorBehavior extends EntityBehavior
## Rare, elusive Poolrooms entity. Passive first pass.

const SENSE_RANGE: float = 18.0

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 1
	entity.attack_damage = 0.0
	entity.attack_range = 0.0

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	var distance_to_player := entity.world_position.distance_to(player_pos)
	if distance_to_player <= SENSE_RANGE:
		_move_away_from_player(entity, player_pos, grid)
	else:
		wander(entity, grid)

func _move_away_from_player(entity: WorldEntity, player_pos: Vector2i, grid) -> bool:
	if entity.moves_remaining <= 0:
		return false

	var best_pos := Vector2i(-1, -1)
	var best_dist := entity.world_position.distance_to(player_pos)
	var directions := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	directions.shuffle()

	for dir in directions:
		var test_pos: Vector2i = entity.world_position + dir
		if not can_move_to(test_pos, grid):
			continue
		var dist: float = test_pos.distance_to(player_pos)
		if dist > best_dist:
			best_dist = dist
			best_pos = test_pos

	if best_pos != Vector2i(-1, -1):
		entity.move_to(best_pos)
		entity.moves_remaining -= 1
		return true

	return false
