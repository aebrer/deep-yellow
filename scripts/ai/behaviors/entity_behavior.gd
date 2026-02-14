class_name EntityBehavior extends RefCounted
## Base class for entity behaviors
##
## Each entity type has its own behavior class that defines:
## - How it takes damage (with special immunities/vulnerabilities)
## - How it processes its turn (AI logic)
## - Entity-specific constants (sense range, attack damage, etc.)
##
## This is stateless logic - all state lives in WorldEntity.
## Behaviors are resolved by entity_type string, so chunk serialization
## is unaffected.

## If true, this entity is skipped entirely during turn processing.
## Use for stationary environmental entities that never act (lights,
## vending machines, exit holes). Set in subclass _init().
var skip_turn_processing: bool = false

# ============================================================================
# TURN PROCESSING
# ============================================================================

func reset_turn_state(entity: WorldEntity) -> void:
	"""Reset per-turn state. Override in subclasses."""
	entity.moves_remaining = 0

func process_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Process entity's turn. Override in subclasses."""
	pass

# ============================================================================
# DAMAGE HANDLING
# ============================================================================

func take_damage(entity: WorldEntity, amount: float, tags: Array = []) -> void:
	"""Apply damage to entity. Override for special handling.

	Default behavior: subtract damage from HP, die at 0.

	Args:
		entity: Entity taking damage
		amount: Damage amount
		tags: Attack tags (e.g., ["physical", "melee"], ["sound", "psychic"])
	"""
	if entity.is_dead:
		return

	entity.current_hp = max(0.0, entity.current_hp - amount)

	if entity.current_hp <= 0 and not entity.is_dead:
		entity.is_dead = true
		entity.died.emit(entity)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "WorldEntity '%s' at %s died" % [entity.entity_type, entity.world_position])

# ============================================================================
# SHARED UTILITIES (available to all behaviors)
# ============================================================================

## Probability of holding position when in attack range (vs shuffling around)
const HOLD_POSITION_CHANCE = 0.6

func can_move_to(pos: Vector2i, grid) -> bool:
	"""Check if position is walkable and not occupied"""
	if not grid:
		return false

	if not grid.is_walkable(pos):
		return false

	if grid.entity_renderer and grid.entity_renderer.has_entity_at(pos):
		return false

	var player = grid.get_node_or_null("../Player3D")
	if player and player.grid_position == pos:
		return false

	return true

func move_toward_target(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Move one step toward target using pathfinding with fallbacks"""
	if entity.moves_remaining <= 0:
		return false

	var current_pos = entity.world_position
	if current_pos == target_pos:
		return false

	# Try pathfinding first
	var pathfinder = grid.get_node_or_null("/root/Pathfinding")

	if not pathfinder or not pathfinder.has_point(current_pos):
		return _move_toward_target_greedy(entity, target_pos, grid)

	var path = pathfinder.find_path(current_pos, target_pos)

	if path.size() <= 1:
		return _move_toward_target_greedy(entity, target_pos, grid)

	var next_pos = Vector2i(int(path[1].x), int(path[1].y))

	if can_move_to(next_pos, grid):
		entity.move_to(next_pos)
		entity.moves_remaining -= 1
		return true

	# Try sidestepping if next A* position is blocked
	var sidestep_pos = _find_sidestep_toward_path(current_pos, path, grid)
	if sidestep_pos != Vector2i(-1, -1):
		entity.move_to(sidestep_pos)
		entity.moves_remaining -= 1
		return true

	# Fallback: greedy navigation
	return _move_toward_target_greedy(entity, target_pos, grid)

func _find_sidestep_toward_path(current_pos: Vector2i, path: PackedVector2Array, grid) -> Vector2i:
	"""Find a sidestep move that keeps us progressing toward the path goal"""
	if path.size() < 2:
		return Vector2i(-1, -1)

	var goal = Vector2i(int(path[path.size() - 1].x), int(path[path.size() - 1].y))

	var path_positions: Dictionary = {}
	for i in range(path.size()):
		var p = Vector2i(int(path[i].x), int(path[i].y))
		path_positions[p] = i

	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1),
		Vector2i(1, -1), Vector2i(-1, -1)
	]

	var best_pos = Vector2i(-1, -1)
	var best_score = -999999.0

	for dir in directions:
		var test_pos = current_pos + dir
		if not can_move_to(test_pos, grid):
			continue

		var score = 0.0

		if path_positions.has(test_pos):
			score += 100.0 + path_positions[test_pos]

		var current_dist = current_pos.distance_to(goal)
		var new_dist = test_pos.distance_to(goal)
		score += (current_dist - new_dist) * 10.0

		if score > best_score:
			best_score = score
			best_pos = test_pos

	if best_score > 0:
		return best_pos

	return Vector2i(-1, -1)

func _move_toward_target_greedy(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Simple greedy navigation toward target"""
	var current_pos = entity.world_position
	var diff = target_pos - current_pos

	var directions: Array[Vector2i] = []

	var primary = Vector2i(signi(diff.x), signi(diff.y))
	if primary != Vector2i.ZERO:
		directions.append(primary)

	if diff.x != 0:
		directions.append(Vector2i(signi(diff.x), 0))
	if diff.y != 0:
		directions.append(Vector2i(0, signi(diff.y)))

	if diff.x != 0 and diff.y != 0:
		directions.append(Vector2i(signi(diff.x), -signi(diff.y)))
		directions.append(Vector2i(-signi(diff.x), signi(diff.y)))

	if diff.x == 0:
		directions.append(Vector2i(1, signi(diff.y)))
		directions.append(Vector2i(-1, signi(diff.y)))
	if diff.y == 0:
		directions.append(Vector2i(signi(diff.x), 1))
		directions.append(Vector2i(signi(diff.x), -1))

	for dir in directions:
		var next_pos = current_pos + dir
		if can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			return true

	return false

func shuffle_around_target(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Move to random adjacent tile staying in attack range"""
	if entity.moves_remaining <= 0:
		return false

	var current_pos = entity.world_position
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1),
		Vector2i(1, -1), Vector2i(-1, -1)
	]
	directions.shuffle()

	for dir in directions:
		var next_pos = current_pos + dir
		var distance_to_target = next_pos.distance_to(target_pos)

		if distance_to_target <= entity.attack_range and can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			return true

	return false

func wander(entity: WorldEntity, grid) -> bool:
	"""Move in a random walkable direction"""
	if entity.moves_remaining <= 0:
		return false

	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1),
		Vector2i(1, -1), Vector2i(-1, -1)
	]
	directions.shuffle()

	for dir in directions:
		var next_pos = entity.world_position + dir
		if can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			return true

	return false

func execute_attack(entity: WorldEntity, target_pos: Vector2i, grid) -> void:
	"""Execute a melee attack against the player"""
	if not grid:
		return

	var player = grid.get_node_or_null("../Player3D")
	if not player:
		return

	if player.stats:
		player.stats.take_damage(entity.attack_damage)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "%s attacks player for %.0f damage" % [
			entity.entity_type, entity.attack_damage
		])

		if grid.entity_renderer:
			var emoji = get_attack_emoji()
			grid.entity_renderer.spawn_hit_vfx(target_pos, emoji, entity.attack_damage)

func get_attack_emoji() -> String:
	"""Override in subclasses for entity-specific emoji"""
	return "💥"
