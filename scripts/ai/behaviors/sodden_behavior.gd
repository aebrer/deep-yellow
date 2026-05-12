class_name SoddenBehavior extends EntityBehavior
## Slow, tough Poolrooms melee threat.

const SENSE_RANGE: float = 42.0
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: float = 3.0

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 1
	entity.attack_damage = ATTACK_DAMAGE
	entity.attack_range = ATTACK_RANGE

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	var distance_to_player := entity.world_position.distance_to(player_pos)
	if distance_to_player <= SENSE_RANGE:
		entity.last_seen_player_pos = player_pos

	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			execute_attack(entity, player_pos, grid)
			entity.attack_cooldown = 2
			return

	if distance_to_player <= entity.attack_range:
		return

	if entity.last_seen_player_pos != null:
		move_toward_target(entity, entity.last_seen_player_pos, grid)
	else:
		wander(entity, grid)

func get_attack_emoji() -> String:
	return "💧"
