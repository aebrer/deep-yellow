class_name SmilerBehavior extends EntityBehavior
## Smiler behavior - psychological horror enemy
##
## - Does NOT attack (sanity damage only)
## - Moves 5 tiles at once, but only every 4th turn (teleport)
## - Tries to maintain ~5 tile distance from player (stalking)
## - Only takes damage from "sound" tagged attacks (instant kill)
## - Immune to all other damage types

const SENSE_RANGE: float = 20.0
const PREFERRED_DISTANCE: float = 5.0
const MOVE_DISTANCE: int = 5
const MOVE_COOLDOWN: int = 4

func reset_turn_state(entity: WorldEntity) -> void:
	# Smiler doesn't attack but tracks move cooldown via spawn_cooldown
	entity.moves_remaining = 0
	entity.attack_damage = 0.0
	entity.attack_range = 0.0

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE

	if can_sense_player:
		entity.last_seen_player_pos = player_pos

	# Check if this is a movement turn (every 4th turn)
	# We use spawn_cooldown to track movement cooldown
	if entity.spawn_cooldown == 0:
		# This is a movement turn - teleport!
		if entity.last_seen_player_pos != null:
			_teleport(entity, entity.last_seen_player_pos, grid)
		# Reset cooldown
		entity.spawn_cooldown = MOVE_COOLDOWN
	else:
		# Not a movement turn - just watch
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Smiler at %s watches... (%d turns until teleport)" % [entity.world_position, entity.spawn_cooldown])

func take_damage(entity: WorldEntity, amount: float, tags: Array = []) -> void:
	"""Smiler only takes damage from 'sound' tagged attacks - instant kill"""
	if entity.is_dead:
		return

	if "sound" in tags:
		# Sound attack - instant kill regardless of HP
		entity.current_hp = 0.0
		entity.is_dead = true
		entity.died.emit(entity)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Smiler at %s dispersed by sound! 😱" % entity.world_position)
	else:
		# Non-sound attack - no effect
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Smiler at %s immune to non-sound attack" % entity.world_position)

func _teleport(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Teleport Smiler to maintain preferred distance from player

	Finds a position ~5 tiles from player that is:
	1. Within 5 tiles of current position (teleport range)
	2. Walkable
	3. Approximately at preferred distance from player
	"""
	var current_pos = entity.world_position
	var best_pos = current_pos
	var best_score = -999999.0

	# Search for good teleport destinations within MOVE_DISTANCE
	for dx in range(-MOVE_DISTANCE, MOVE_DISTANCE + 1):
		for dy in range(-MOVE_DISTANCE, MOVE_DISTANCE + 1):
			var test_pos = current_pos + Vector2i(dx, dy)

			if test_pos == current_pos:
				continue

			# Must be within teleport range (circular, not square)
			if current_pos.distance_to(test_pos) > MOVE_DISTANCE:
				continue

			if not can_move_to(test_pos, grid):
				continue

			# Score based on how close to preferred distance from player
			var dist_to_player = test_pos.distance_to(player_pos)
			var distance_error = abs(dist_to_player - PREFERRED_DISTANCE)

			# Lower error = better score
			var score = -distance_error * 10.0

			# Small random factor for variety
			score += randf() * 2.0

			if score > best_score:
				best_score = score
				best_pos = test_pos

	# Teleport to best position
	if best_pos != current_pos:
		entity.move_to(best_pos)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Smiler teleports from %s to %s (dist to player: %.1f)" % [
			current_pos, best_pos, best_pos.distance_to(player_pos)
		])
