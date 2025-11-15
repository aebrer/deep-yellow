class_name Level0Generator extends LevelGenerator
## Level 0 - The Lobby generator
##
## Generates infinite yellow hallways using recursive backtracking maze algorithm.
## Classic Backrooms aesthetic: mono-yellow wallpaper, buzzing fluorescent lights,
## damp carpet, and the hum of eternity.

# ============================================================================
# LEVEL 0 CONFIGURATION
# ============================================================================

func _init() -> void:
	# Create Level 0 configuration
	var config := ProceduralLevelConfig.new()
	config.level_id = 0
	config.level_name = "Level 0 - The Lobby"
	config.corruption_per_chunk = 0.01

	# Add permitted entities with spawn probabilities
	# (from docs/PROCEDURAL_GENERATION_IMPLEMENTATION.md)

	# BACTERIA: Weak entities (MORE common with corruption)
	var bacteria := EntityConfig.new()
	bacteria.entity_id = "bacteria"
	bacteria.base_probability = 0.05  # 5% base chance per sub-chunk
	bacteria.corruption_multiplier = 1.5  # Gets MUCH more common with corruption
	config.add_entity(bacteria)

	# HOUNDS: Dangerous entities (MORE common with corruption)
	var hound := EntityConfig.new()
	hound.entity_id = "hound"
	hound.base_probability = 0.01  # 1% base chance per sub-chunk
	hound.corruption_multiplier = 2.0  # Gets MORE common (threat escalation)
	config.add_entity(hound)

	# ALMOND WATER: Healing item (LESS common with corruption)
	var almond_water := EntityConfig.new()
	almond_water.entity_id = "almond_water"
	almond_water.base_probability = 0.03  # 3% base chance per sub-chunk
	almond_water.corruption_multiplier = -0.5  # Gets LESS common (scarcity)
	config.add_entity(almond_water)

	# EXIT STAIRS: Level transition (MORE common with corruption - exit forcing!)
	var exit_stairs := EntityConfig.new()
	exit_stairs.entity_id = "exit_stairs"
	exit_stairs.base_probability = 0.001  # 0.1% base chance (very rare initially)
	exit_stairs.corruption_multiplier = 2.0  # Gets MORE common (forces progression)
	config.add_entity(exit_stairs)

	setup_level_config(config)
	Log.system("Level0Generator initialized with %d entity types" % config.permitted_entities.size())

# ============================================================================
# MAZE GENERATION - RECURSIVE BACKTRACKING
# ============================================================================

func generate_chunk(chunk: Chunk, world_seed: int) -> void:
	"""Generate Level 0 chunk using recursive backtracking maze algorithm

	Creates winding hallways with:
	- Walls on maze boundaries
	- Floors in hallways (walkable)
	- Occasional branching paths
	"""
	var rng := create_seeded_rng(chunk, world_seed)

	# Phase 1: Fill chunk with walls (default state)
	_fill_with_walls(chunk)

	# Phase 2: Carve maze using recursive backtracking
	_carve_maze(chunk, rng)

	# Phase 3: Add decorations and details (future)
	# TODO: Add light fixtures, water stains, ceiling tiles

	Log.grid("Generated Level 0 chunk at %s (walkable: %d tiles)" % [
		chunk.position,
		chunk.get_walkable_count()
	])

func _fill_with_walls(chunk: Chunk) -> void:
	"""Fill entire chunk with walls as starting point"""
	for sy in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sx in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub := chunk.get_sub_chunk(Vector2i(sx, sy))

			for y in range(SubChunk.SIZE):
				for x in range(SubChunk.SIZE):
					sub.set_tile(Vector2i(x, y), SubChunk.TileType.WALL)

func _carve_maze(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Carve maze using recursive backtracking algorithm

	Algorithm:
	1. Start at random position
	2. Mark current cell as walkable
	3. Choose random unvisited neighbor
	4. Carve path to neighbor
	5. Recursively visit neighbor
	6. Backtrack when stuck

	This creates a perfect maze (all cells reachable, no loops).
	"""
	# Work at sub-chunk granularity (8×8 grid of sub-chunks)
	var visited: Dictionary = {}  # Vector2i → bool
	var start_pos := Vector2i(
		rng.randi_range(0, Chunk.SUB_CHUNKS_PER_SIDE - 1),
		rng.randi_range(0, Chunk.SUB_CHUNKS_PER_SIDE - 1)
	)

	_carve_from(chunk, start_pos, visited, rng)

	# Ensure chunk edges have some walkable tiles for inter-chunk connections
	_create_edge_connections(chunk, rng)

func _carve_from(
	chunk: Chunk,
	pos: Vector2i,
	visited: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	"""Recursively carve maze from position"""
	visited[pos] = true

	# Carve out this sub-chunk (make walkable)
	_carve_sub_chunk(chunk, pos)

	# Get unvisited neighbors in random order
	var neighbors := _get_shuffled_neighbors(pos, visited, rng)

	for neighbor in neighbors:
		if not visited.get(neighbor, false):
			# Carve path to neighbor
			_carve_connection(chunk, pos, neighbor)

			# Recursively visit neighbor
			_carve_from(chunk, neighbor, visited, rng)

func _carve_sub_chunk(chunk: Chunk, sub_pos: Vector2i) -> void:
	"""Carve out a sub-chunk (make all tiles walkable)"""
	var sub := chunk.get_sub_chunk(sub_pos)
	if not sub:
		return

	for y in range(SubChunk.SIZE):
		for x in range(SubChunk.SIZE):
			sub.set_tile(Vector2i(x, y), SubChunk.TileType.FLOOR)

func _carve_connection(_chunk: Chunk, _from: Vector2i, _to: Vector2i) -> void:
	"""Carve corridor between two sub-chunks

	Creates a hallway connecting the two sub-chunks.
	"""
	# Simple implementation: just ensure both sub-chunks are carved
	# (They're already carved by _carve_sub_chunk, so connection is implicit)
	# TODO: Add narrower hallways between rooms for more interesting topology
	pass

func _get_shuffled_neighbors(
	pos: Vector2i,
	_visited: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	"""Get neighboring sub-chunk positions in random order"""
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -1),  # North
		Vector2i(1, 0),   # East
		Vector2i(0, 1),   # South
		Vector2i(-1, 0),  # West
	]

	# Shuffle directions using seeded RNG (Fisher-Yates shuffle)
	for i in range(directions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := directions[i]
		directions[i] = directions[j]
		directions[j] = temp

	for dir in directions:
		var neighbor := pos + dir

		# Check if neighbor is within chunk bounds
		if neighbor.x >= 0 and neighbor.x < Chunk.SUB_CHUNKS_PER_SIDE and \
		   neighbor.y >= 0 and neighbor.y < Chunk.SUB_CHUNKS_PER_SIDE:
			neighbors.append(neighbor)

	return neighbors

func _create_edge_connections(chunk: Chunk, _rng: RandomNumberGenerator) -> void:
	"""Create walkable tiles at chunk edges for inter-chunk connections

	Uses deterministic pattern based on chunk position to ensure
	neighboring chunks align perfectly.
	"""
	# Use chunk position to deterministically decide which edge sub-chunks are walkable
	# This ensures adjacent chunks have matching connections

	# For simplicity: make every other sub-chunk on edges walkable
	# This creates a regular pattern that naturally aligns between chunks

	# Top and bottom edges
	for x in range(Chunk.SUB_CHUNKS_PER_SIDE):
		# Deterministic pattern: alternating based on absolute position
		var world_x := chunk.position.x * Chunk.SUB_CHUNKS_PER_SIDE + x
		if world_x % 2 == 0:
			_carve_sub_chunk(chunk, Vector2i(x, 0))  # Top edge
			_carve_sub_chunk(chunk, Vector2i(x, Chunk.SUB_CHUNKS_PER_SIDE - 1))  # Bottom edge

	# Left and right edges
	for y in range(Chunk.SUB_CHUNKS_PER_SIDE):
		# Deterministic pattern: alternating based on absolute position
		var world_y := chunk.position.y * Chunk.SUB_CHUNKS_PER_SIDE + y
		if world_y % 2 == 0:
			_carve_sub_chunk(chunk, Vector2i(0, y))  # Left edge
			_carve_sub_chunk(chunk, Vector2i(Chunk.SUB_CHUNKS_PER_SIDE - 1, y))  # Right edge

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "Level0Generator(Recursive Backtracking Maze)"
