class_name BacteriaMotherloadBehavior extends EntityBehavior
## Bacteria Motherload behavior
##
## Dangerous spawner enemy:
## - 2 moves per turn when player is nearby, 1 move otherwise
## - Wanders aimlessly when player not nearby
## - Spawns Bacteria Spawn minions (large cooldown, must wait after)
## - Doesn't wait after attacking
## - Only 1 move post-attack

const SENSE_RANGE: float = 32.0
const ATTACK_RANGE: float = 1.5
const ATTACK_DAMAGE: float = 4.0
const SPAWN_COOLDOWN: int = 10

func reset_turn_state(entity: WorldEntity) -> void:
	# Will be set to 2 if player is nearby, otherwise 1
	entity.moves_remaining = 1
	entity.attack_damage = ATTACK_DAMAGE
	entity.attack_range = ATTACK_RANGE

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE

	if can_sense_player:
		entity.last_seen_player_pos = player_pos
		entity.moves_remaining = 2  # 2 moves when player is nearby

	var attacked = false

	# Try to attack
	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			execute_attack(entity, player_pos, grid)
			attacked = true
			entity.attack_cooldown = 2
			entity.moves_remaining = 1  # Only 1 move post-attack

	# Try to spawn minions (if not attacked and off cooldown)
	if not attacked and entity.spawn_cooldown == 0 and can_sense_player:
		_spawn_minion(entity, grid)
		entity.spawn_cooldown = SPAWN_COOLDOWN
		entity.must_wait = true
		return  # Don't move after spawning

	# If already in attack range, maybe hold position or shuffle around
	if distance_to_player <= entity.attack_range:
		if randf() < HOLD_POSITION_CHANCE:
			return
		else:
			if entity.moves_remaining > 0:
				shuffle_around_target(entity, player_pos, grid)
			return

	# Move toward player or wander
	while entity.moves_remaining > 0:
		if entity.last_seen_player_pos != null:
			var moved = move_toward_target(entity, entity.last_seen_player_pos, grid)
			if not moved:
				break
		else:
			var moved = wander(entity, grid)
			if not moved:
				break

func _spawn_minion(entity: WorldEntity, grid) -> void:
	"""Spawn a Bacteria Spawn adjacent to the Motherload"""
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]
	directions.shuffle()

	for dir in directions:
		var spawn_pos = entity.world_position + dir
		if can_move_to(spawn_pos, grid):
			var spawn = WorldEntity.new(
				"bacteria_spawn",
				spawn_pos,
				100.0,
				0
			)

			if _add_entity_to_chunk(spawn, grid):
				Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Motherload spawned bacteria at %s" % spawn_pos)
			return

func _add_entity_to_chunk(entity: WorldEntity, grid) -> bool:
	"""Add a newly spawned entity to the appropriate chunk/subchunk"""
	var chunk = ChunkManager.get_chunk_at_tile(entity.world_position, 0)
	if not chunk:
		Log.warn(Log.Category.ENTITY, "Can't spawn entity at %s - no chunk loaded" % entity.world_position)
		return false

	var subchunk = chunk.get_sub_chunk_at_tile(entity.world_position)
	if not subchunk:
		Log.warn(Log.Category.ENTITY, "Can't spawn entity at %s - no subchunk found" % entity.world_position)
		return false

	subchunk.add_world_entity(entity)

	if grid.entity_renderer:
		grid.entity_renderer.add_entity_billboard(entity)

	return true

func get_attack_emoji() -> String:
	return "🧫"
