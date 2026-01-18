class_name BacteriaSpawnBehavior extends EntityBehavior
## Bacteria Spawn behavior
##
## Simple swarming enemy:
## - 1 move per turn
## - Can attack AND move on same turn
## - Must wait 1 turn after any turn with an attack
## - Detects player from afar (80 tiles)
## - Swarms toward player

const SENSE_RANGE: float = 80.0
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: float = 1.0

func reset_turn_state(entity: WorldEntity) -> void:
	entity.moves_remaining = 1
	entity.attack_damage = ATTACK_DAMAGE
	entity.attack_range = ATTACK_RANGE

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE

	if can_sense_player:
		entity.last_seen_player_pos = player_pos

	# Try to attack if in range and off cooldown
	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			execute_attack(entity, player_pos, grid)
			entity.attack_cooldown = 1
			entity.must_wait = true

	# If already in attack range, maybe hold position or shuffle around
	if distance_to_player <= entity.attack_range:
		if randf() < HOLD_POSITION_CHANCE:
			return
		else:
			if entity.moves_remaining > 0:
				shuffle_around_target(entity, player_pos, grid)
			return

	# Move toward player
	if entity.moves_remaining > 0 and entity.last_seen_player_pos != null:
		move_toward_target(entity, entity.last_seen_player_pos, grid)

func get_attack_emoji() -> String:
	return "🦠"
