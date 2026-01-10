class_name EntityAI extends RefCounted
## Entity AI system - processes entity turns with sense/think/act pattern
##
## This is a static utility class that processes AI for WorldEntity objects.
## AI behavior is determined by entity_type via match statements.
##
## ARCHITECTURE:
## - WorldEntity holds all state (HP, position, AI state like cooldowns)
## - EntityAI provides behavior logic (what decisions to make)
## - Called once per turn by ChunkManager after player acts
##
## Sense → Think → Act Pattern:
## 1. SENSE: Gather information (player position, LOS, nearby entities)
## 2. THINK: Decide action (attack, move, wait, spawn)
## 3. ACT: Execute the chosen action

# ============================================================================
# ENTITY TYPE CONSTANTS
# ============================================================================

## Entity type IDs
const TYPE_DEBUG_ENEMY = "debug_enemy"
const TYPE_BACTERIA_SPAWN = "bacteria_spawn"
const TYPE_BACTERIA_BROOD_MOTHER = "bacteria_brood_mother"

## Sensing ranges (tiles)
const SENSE_RANGE_SPAWN = 80.0  # Bacteria Spawn can sense player from afar
const SENSE_RANGE_MOTHER = 32.0  # Brood Mother sense range (triggers 2 moves/turn)

## Attack ranges (tiles)
const ATTACK_RANGE_SPAWN = 1.5  # Melee range
const ATTACK_RANGE_MOTHER = 1.5  # Melee range

## Spawn cooldown for Brood Mother
const MOTHER_SPAWN_COOLDOWN = 10  # Turns between spawning minions

## Probability of holding position when in attack range (vs shuffling around)
const HOLD_POSITION_CHANCE = 0.6  # 60% chance to stay put, 40% to shuffle

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

static func process_entity_turn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Process one entity's turn using sense/think/act pattern

	Args:
		entity: WorldEntity to process
		player_pos: Current player grid position
		grid: Grid3D reference for spatial queries
	"""
	if entity.is_dead:
		return

	# Check must_wait BEFORE resetting turn state
	# This flag is set at end of previous turn, checked at start of this turn
	if entity.must_wait:
		entity.must_wait = false
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "%s at %s is waiting (post-attack/spawn cooldown)" % [entity.entity_type, entity.world_position])
		return

	# Reset turn state (moves_remaining, attack stats)
	_reset_turn_state(entity)

	# Tick cooldowns
	_tick_cooldowns(entity)

	# Route to type-specific AI
	match entity.entity_type:
		TYPE_DEBUG_ENEMY:
			_process_debug_enemy(entity, player_pos, grid)
		TYPE_BACTERIA_SPAWN:
			_process_bacteria_spawn(entity, player_pos, grid)
		TYPE_BACTERIA_BROOD_MOTHER:
			_process_bacteria_brood_mother(entity, player_pos, grid)
		_:
			# Unknown type - do nothing (stationary)
			pass

# ============================================================================
# TURN STATE MANAGEMENT
# ============================================================================

static func _reset_turn_state(entity: WorldEntity) -> void:
	"""Reset per-turn state based on entity type"""
	match entity.entity_type:
		TYPE_BACTERIA_SPAWN:
			entity.moves_remaining = 1
			entity.attack_damage = 3.0
			entity.attack_range = ATTACK_RANGE_SPAWN
		TYPE_BACTERIA_BROOD_MOTHER:
			# Will be set to 2 if player is nearby, otherwise 1
			entity.moves_remaining = 1
			entity.attack_damage = 8.0
			entity.attack_range = ATTACK_RANGE_MOTHER
		_:
			entity.moves_remaining = 0  # Debug enemies don't move

static func _tick_cooldowns(entity: WorldEntity) -> void:
	"""Decrement cooldowns at turn start"""
	if entity.attack_cooldown > 0:
		entity.attack_cooldown -= 1
	if entity.spawn_cooldown > 0:
		entity.spawn_cooldown -= 1

# ============================================================================
# DEBUG ENEMY AI (Stationary punching bag)
# ============================================================================

static func _process_debug_enemy(_entity: WorldEntity, _player_pos: Vector2i, _grid) -> void:
	"""Debug enemies do nothing - they just stand there"""
	pass

# ============================================================================
# BACTERIA SPAWN AI
# ============================================================================
## Behavior:
## - 1 move per turn
## - Can attack AND move on same turn
## - Must wait 1 turn after any turn with an attack
## - Detects player from afar (SENSE_RANGE_SPAWN tiles)
## - Swarms toward player

static func _process_bacteria_spawn(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Process Bacteria Spawn turn"""
	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE_SPAWN

	if can_sense_player:
		# Update last known position
		entity.last_seen_player_pos = player_pos

	# THINK & ACT: Try to attack if in range, then move
	var attacked = false

	# Try to attack if in range and off cooldown
	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			_execute_attack(entity, player_pos, grid)
			attacked = true
			entity.attack_cooldown = 1  # 1 turn cooldown
			entity.must_wait = true  # Must wait next turn after attacking
			Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s attacked, will wait next turn" % entity.entity_type)

	# If already in attack range, maybe hold position or shuffle around
	# Probabilistic behavior makes swarms feel more organic
	if distance_to_player <= entity.attack_range:
		if randf() < HOLD_POSITION_CHANCE:
			Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s holding position (in attack range)" % entity.entity_type)
			return
		else:
			# Shuffle around the player instead of moving toward them
			if entity.moves_remaining > 0:
				_shuffle_around_target(entity, player_pos, grid)
			return

	# Move toward player
	if entity.moves_remaining > 0 and entity.last_seen_player_pos != null:
		_move_toward_target(entity, entity.last_seen_player_pos, grid)

# ============================================================================
# BACTERIA BROOD MOTHER AI
# ============================================================================
## Behavior:
## - 2 moves per turn when player is nearby, 1 move otherwise
## - Wanders aimlessly when player not nearby
## - Spawns Bacteria Spawn minions (large cooldown, must wait after)
## - Doesn't wait after attacking
## - Only 1 move post-attack

static func _process_bacteria_brood_mother(entity: WorldEntity, player_pos: Vector2i, grid) -> void:
	"""Process Bacteria Brood Mother turn"""
	# SENSE: Can we see the player?
	var distance_to_player = entity.world_position.distance_to(player_pos)
	var can_sense_player = distance_to_player <= SENSE_RANGE_MOTHER

	if can_sense_player:
		entity.last_seen_player_pos = player_pos
		# 2 moves when player is nearby
		entity.moves_remaining = 2

	# THINK: Decide action priority
	# 1. Attack if in range
	# 2. Spawn minions if off cooldown
	# 3. Move toward player (if sensed) or wander

	var attacked = false

	# Try to attack
	if entity.attack_cooldown == 0 and distance_to_player <= entity.attack_range:
		if grid.has_line_of_sight(entity.world_position, player_pos):
			_execute_attack(entity, player_pos, grid)
			attacked = true
			entity.attack_cooldown = 2  # 2 turn cooldown
			entity.moves_remaining = 1  # Only 1 move post-attack
			Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Brood Mother attacked, 1 move remaining")

	# Try to spawn minions (if not attacked and off cooldown)
	if not attacked and entity.spawn_cooldown == 0 and can_sense_player:
		_spawn_minion(entity, grid)
		entity.spawn_cooldown = MOTHER_SPAWN_COOLDOWN
		entity.must_wait = true  # Must wait after spawning
		Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Brood Mother spawned minion, will wait next turn")
		return  # Don't move after spawning

	# If already in attack range, maybe hold position or shuffle around
	if distance_to_player <= entity.attack_range:
		if randf() < HOLD_POSITION_CHANCE:
			Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Brood Mother holding position (in attack range)")
			return
		else:
			# Shuffle around the player
			if entity.moves_remaining > 0:
				_shuffle_around_target(entity, player_pos, grid)
			return

	# Move toward player or wander
	while entity.moves_remaining > 0:
		if entity.last_seen_player_pos != null:
			var moved = _move_toward_target(entity, entity.last_seen_player_pos, grid)
			if not moved:
				break  # Can't move, stop trying
		else:
			var moved = _wander(entity, grid)
			if not moved:
				break

# ============================================================================
# ACTIONS
# ============================================================================

static func _execute_attack(entity: WorldEntity, target_pos: Vector2i, grid) -> void:
	"""Execute an attack against the player

	Args:
		entity: Attacking entity
		target_pos: Player position
		grid: Grid3D for VFX spawning
	"""
	# Get player reference to deal damage
	var player = grid.get_node_or_null("../Player3D")
	if not player:
		Log.warn(Log.Category.ENTITY, "EntityAI: Can't find player to attack")
		return

	# Deal damage via StatBlock
	if player.stats:
		player.stats.take_damage(entity.attack_damage)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "%s attacks player for %.0f damage" % [
			entity.entity_type, entity.attack_damage
		])

		# Spawn hit VFX on player position
		# Note: We spawn VFX at entity's position (attacker) for visual feedback
		if grid.entity_renderer:
			var emoji = _get_attack_emoji(entity.entity_type)
			# Spawn VFX at player position (the target)
			grid.entity_renderer.spawn_hit_vfx(target_pos, emoji, entity.attack_damage)

static func _get_attack_emoji(entity_type: String) -> String:
	"""Get attack emoji for entity type"""
	match entity_type:
		TYPE_BACTERIA_SPAWN:
			return "🦠"
		TYPE_BACTERIA_BROOD_MOTHER:
			return "🧫"
		_:
			return "💥"

static func _move_toward_target(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Move one step toward target using pathfinding with intelligent fallbacks

	Strategy:
	1. Try A* pathfinding to get optimal terrain path
	2. If next step blocked by entity, try sidestepping around it
	3. Fall back to greedy navigation if pathfinding unavailable

	The A* graph represents TERRAIN only (walls vs floors). Entity collision
	is checked at move time, allowing dynamic obstacle avoidance.

	Args:
		entity: Entity to move
		target_pos: Target position
		grid: Grid3D for walkability checks

	Returns:
		true if moved, false if couldn't move
	"""
	if entity.moves_remaining <= 0:
		return false

	var current_pos = entity.world_position

	# Already at target
	if current_pos == target_pos:
		return false

	# Try pathfinding first (autoload is named "Pathfinding" in project.godot)
	var pathfinder = grid.get_node_or_null("/root/Pathfinding")

	if pathfinder and pathfinder.has_point(current_pos):
		var path = pathfinder.find_path(current_pos, target_pos)

		if path.size() > 1:
			# Path[0] is current position, path[1] is next step
			var next_pos = Vector2i(int(path[1].x), int(path[1].y))

			# Try the optimal path step
			if _can_move_to(next_pos, grid):
				entity.move_to(next_pos)
				entity.moves_remaining -= 1
				return true

			# Path blocked by entity - try sidestepping to stay on path
			var sidestep_pos = _find_sidestep_toward_path(current_pos, path, grid)
			if sidestep_pos != Vector2i(-1, -1):
				entity.move_to(sidestep_pos)
				entity.moves_remaining -= 1
				return true

	# Fallback: greedy navigation (no path found or pathfinder unavailable)
	return _move_toward_target_greedy(entity, target_pos, grid)

static func _find_sidestep_toward_path(current_pos: Vector2i, path: PackedVector2Array, grid) -> Vector2i:
	"""Find a sidestep move that keeps us progressing toward the path goal

	When the optimal next step is blocked by an entity, look for alternative
	moves that either:
	1. Land on a later point in the path (skip ahead)
	2. Get us closer to the path's destination

	Args:
		current_pos: Current entity position
		path: The A* path we're trying to follow
		grid: Grid3D for move validation

	Returns:
		Valid sidestep position, or Vector2i(-1, -1) if none found
	"""
	if path.size() < 2:
		return Vector2i(-1, -1)

	var goal = Vector2i(int(path[path.size() - 1].x), int(path[path.size() - 1].y))

	# Convert path to set for quick lookup
	var path_positions: Dictionary = {}
	for i in range(path.size()):
		var p = Vector2i(int(path[i].x), int(path[i].y))
		path_positions[p] = i  # Store index for "progress" checking

	# Check all 8 directions, prefer ones on the path or closer to goal
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
		if not _can_move_to(test_pos, grid):
			continue

		var score = 0.0

		# Bonus for being on the path (and further along it)
		if path_positions.has(test_pos):
			score += 100.0 + path_positions[test_pos]  # Further along = better

		# Score by how much closer to goal we get
		var current_dist = current_pos.distance_to(goal)
		var new_dist = test_pos.distance_to(goal)
		score += (current_dist - new_dist) * 10.0  # Closer = positive score

		if score > best_score:
			best_score = score
			best_pos = test_pos

	# Only return if we found something that makes progress
	if best_score > 0:
		return best_pos

	return Vector2i(-1, -1)

static func _move_toward_target_greedy(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Move one step toward target using simple greedy navigation

	Uses direct movement toward target, trying cardinal directions first,
	then diagonals. Falls back to any valid direction if direct path blocked.

	Args:
		entity: Entity to move
		target_pos: Target position
		grid: Grid3D for walkability checks

	Returns:
		true if moved, false if couldn't move
	"""
	var current_pos = entity.world_position
	var diff = target_pos - current_pos

	# Build list of directions to try, prioritized by how much they reduce distance
	var directions: Array[Vector2i] = []

	# Primary direction (most direct path)
	var primary = Vector2i(signi(diff.x), signi(diff.y))
	if primary != Vector2i.ZERO:
		directions.append(primary)

	# Cardinal directions toward target
	if diff.x != 0:
		directions.append(Vector2i(signi(diff.x), 0))
	if diff.y != 0:
		directions.append(Vector2i(0, signi(diff.y)))

	# Diagonal alternatives
	if diff.x != 0 and diff.y != 0:
		directions.append(Vector2i(signi(diff.x), -signi(diff.y)))
		directions.append(Vector2i(-signi(diff.x), signi(diff.y)))

	# Perpendicular (sidestep to get around obstacles)
	if diff.x == 0:
		directions.append(Vector2i(1, signi(diff.y)))
		directions.append(Vector2i(-1, signi(diff.y)))
	if diff.y == 0:
		directions.append(Vector2i(signi(diff.x), 1))
		directions.append(Vector2i(signi(diff.x), -1))

	# Try each direction
	for dir in directions:
		var next_pos = current_pos + dir
		if _can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			return true

	return false  # Completely blocked

static func _shuffle_around_target(entity: WorldEntity, target_pos: Vector2i, grid) -> bool:
	"""Move to a random adjacent tile that stays in attack range of target

	Used when entity is already in attack range but wants to move around
	(makes swarms feel more organic/gross).

	Args:
		entity: Entity to move
		target_pos: Target to stay near (player position)
		grid: Grid3D for walkability checks

	Returns:
		true if moved, false if couldn't move
	"""
	if entity.moves_remaining <= 0:
		return false

	var current_pos = entity.world_position

	# Get all adjacent tiles (8-directional)
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1),
		Vector2i(1, -1), Vector2i(-1, -1)
	]
	directions.shuffle()

	# Try each direction, but only if it keeps us in attack range
	for dir in directions:
		var next_pos = current_pos + dir
		var distance_to_target = next_pos.distance_to(target_pos)

		# Only move if we stay in attack range
		if distance_to_target <= entity.attack_range and _can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "%s shuffled around player" % entity.entity_type)
			return true

	return false  # Couldn't find valid shuffle position

static func _wander(entity: WorldEntity, grid) -> bool:
	"""Move in a random walkable direction

	Args:
		entity: Entity to move
		grid: Grid3D for walkability checks

	Returns:
		true if moved, false if couldn't move
	"""
	if entity.moves_remaining <= 0:
		return false

	# Try random directions
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1),
		Vector2i(1, -1), Vector2i(-1, -1)
	]
	directions.shuffle()

	for dir in directions:
		var next_pos = entity.world_position + dir
		if _can_move_to(next_pos, grid):
			entity.move_to(next_pos)
			entity.moves_remaining -= 1
			return true

	return false  # Couldn't find a valid direction

static func _can_move_to(pos: Vector2i, grid) -> bool:
	"""Check if position is walkable and not occupied by another entity

	Args:
		pos: Position to check
		grid: Grid3D reference

	Returns:
		true if can move there
	"""
	# Check tile walkability
	if not grid.is_walkable(pos):
		return false

	# Check for other entities (entities block each other)
	if grid.entity_renderer and grid.entity_renderer.has_entity_at(pos):
		return false

	# Check for player
	var player = grid.get_node_or_null("../Player3D")
	if player and player.grid_position == pos:
		return false

	return true

static func _spawn_minion(entity: WorldEntity, grid) -> void:
	"""Spawn a Bacteria Spawn minion adjacent to the Brood Mother

	Args:
		entity: Brood Mother entity
		grid: Grid3D for spawn position validation
	"""
	# Find adjacent empty tile
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]
	directions.shuffle()

	for dir in directions:
		var spawn_pos = entity.world_position + dir
		if _can_move_to(spawn_pos, grid):
			# Create the minion
			var minion = WorldEntity.new(
				TYPE_BACTERIA_SPAWN,
				spawn_pos,
				20.0,  # Lower HP than player-spawned
				0
			)
			# Initialize AI state
			minion.attack_damage = 3.0
			minion.attack_range = ATTACK_RANGE_SPAWN

			# Add to the appropriate subchunk
			_add_entity_to_chunk(minion, grid)

			Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Brood Mother spawned minion at %s" % spawn_pos)
			return

	Log.msg(Log.Category.ENTITY, Log.Level.DEBUG, "Brood Mother couldn't spawn - no adjacent empty tiles")

static func _add_entity_to_chunk(entity: WorldEntity, grid) -> void:
	"""Add a newly spawned entity to the appropriate chunk/subchunk

	Args:
		entity: Entity to add
		grid: Grid3D reference
	"""
	# Use ChunkManager autoload to find the chunk
	var chunk = ChunkManager.get_chunk_at_tile(entity.world_position, 0)  # Level 0 for now
	if not chunk:
		Log.warn(Log.Category.ENTITY, "Can't spawn entity at %s - no chunk loaded" % entity.world_position)
		return

	# Find the subchunk
	var subchunk = chunk.get_sub_chunk_at_tile(entity.world_position)
	if not subchunk:
		Log.warn(Log.Category.ENTITY, "Can't spawn entity at %s - no subchunk found" % entity.world_position)
		return

	# Add to subchunk storage
	subchunk.add_world_entity(entity)

	# Create billboard immediately if renderer exists
	if grid.entity_renderer:
		grid.entity_renderer.add_entity_billboard(entity)
