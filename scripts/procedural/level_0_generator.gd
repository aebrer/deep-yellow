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
# MAZE GENERATION - ROOM-BASED RECURSIVE BACKTRACKING
# ============================================================================

# Room-based maze generation constants
const ROOM_SIZE := 8  # Each "room" is 8×8 tiles
const MAZE_SIZE := 16  # 128÷8 = 16×16 maze grid (256 rooms per chunk)
const HALLWAY_WIDTH := 3  # Hallways are 3 tiles wide

func generate_chunk(chunk: Chunk, world_seed: int) -> void:
	"""Generate Level 0 chunk using room-based recursive backtracking

	Creates rooms connected by hallways:
	- Each "room" is 8×8 tiles
	- Maze operates on 16×16 grid of rooms (256 total)
	- Hallways are 3 tiles wide between rooms
	- Classic Backrooms aesthetic: rooms + corridors
	"""
	var rng := create_seeded_rng(chunk, world_seed)

	# Phase 1: Fill chunk with walls (default state)
	_fill_with_walls(chunk)

	# Phase 2: Carve maze using room-based recursive backtracking
	_carve_maze_rooms(chunk, rng)

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

func _carve_maze_rooms(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Carve maze using room-based recursive backtracking

	Algorithm:
	1. Start at random room position (16×16 grid)
	2. Mark current room as visited
	3. Carve out room (8×8 tiles)
	4. Choose random unvisited neighbor
	5. Carve hallway to neighbor (3 tiles wide)
	6. Recursively visit neighbor
	7. Backtrack when stuck

	This creates a perfect maze with rooms and hallways.
	"""
	var visited: Dictionary = {}  # Vector2i → bool
	var start_room := Vector2i(
		rng.randi_range(0, MAZE_SIZE - 1),
		rng.randi_range(0, MAZE_SIZE - 1)
	)

	_carve_from_room(chunk, start_room, visited, rng)

	# Ensure chunk edges have hallways for inter-chunk connections
	_create_edge_connections_rooms(chunk, rng)

func _carve_from_room(
	chunk: Chunk,
	room_pos: Vector2i,
	visited: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	"""Recursively carve maze from room position

	Modified recursive backtracking for Backrooms aesthetic:
	1. Mark current room as visited (but DON'T carve it fully)
	2. Carve small 3×3 area at room center (junction point)
	3. For each unvisited neighbor (in random order):
	   - Carve narrow hallway to neighbor (3 tiles wide)
	   - Recursively visit neighbor
	4. Backtrack when stuck

	This creates narrow corridors with lots of walls, not open rooms.
	"""
	visited[room_pos] = true

	# Carve small 3×3 junction at room center (not full 8×8 room)
	_carve_junction(chunk, room_pos)

	# Get unvisited neighbors in random order
	var neighbors := _get_shuffled_room_neighbors(room_pos, visited, rng)

	for neighbor in neighbors:
		if not visited.get(neighbor, false):
			# Carve hallway between rooms (3 tiles wide)
			_carve_hallway(chunk, room_pos, neighbor)

			# Recursively visit neighbor
			_carve_from_room(chunk, neighbor, visited, rng)

func _carve_junction(chunk: Chunk, room_pos: Vector2i) -> void:
	"""Carve small 3×3 junction at room center (not full room)

	Creates intersection points where hallways meet, without carving
	large open rooms. This gives the Backrooms narrow corridor aesthetic.
	"""
	var room_center := room_pos * ROOM_SIZE + Vector2i(ROOM_SIZE / 2, ROOM_SIZE / 2)

	# Carve 3×3 area centered on room position
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tile_pos := room_center + Vector2i(dx, dy)
			_set_tile_in_chunk(chunk, tile_pos, SubChunk.TileType.FLOOR)

func _carve_room(chunk: Chunk, room_pos: Vector2i) -> void:
	"""Carve an 8×8 tile room (DEPRECATED - use _carve_junction for narrow hallways)"""
	var tile_start := room_pos * ROOM_SIZE

	for dy in range(ROOM_SIZE):
		for dx in range(ROOM_SIZE):
			var tile_pos := tile_start + Vector2i(dx, dy)
			_set_tile_in_chunk(chunk, tile_pos, SubChunk.TileType.FLOOR)

func _carve_hallway(chunk: Chunk, from_room: Vector2i, to_room: Vector2i) -> void:
	"""Carve 3-tile-wide hallway between two adjacent rooms

	Hallways connect the center of each room with straight corridors.
	"""
	var dir := to_room - from_room
	var from_center := from_room * ROOM_SIZE + Vector2i(ROOM_SIZE / 2, ROOM_SIZE / 2)
	var to_center := to_room * ROOM_SIZE + Vector2i(ROOM_SIZE / 2, ROOM_SIZE / 2)

	if dir.x != 0:  # Horizontal hallway
		var y_center := from_center.y
		var x_start := mini(from_center.x, to_center.x)
		var x_end := maxi(from_center.x, to_center.x)

		# Carve 3 tiles wide (center + 1 above + 1 below)
		for x in range(x_start, x_end + 1):
			_set_tile_in_chunk(chunk, Vector2i(x, y_center - 1), SubChunk.TileType.FLOOR)
			_set_tile_in_chunk(chunk, Vector2i(x, y_center), SubChunk.TileType.FLOOR)
			_set_tile_in_chunk(chunk, Vector2i(x, y_center + 1), SubChunk.TileType.FLOOR)

	else:  # Vertical hallway
		var x_center := from_center.x
		var y_start := mini(from_center.y, to_center.y)
		var y_end := maxi(from_center.y, to_center.y)

		# Carve 3 tiles wide (center + 1 left + 1 right)
		for y in range(y_start, y_end + 1):
			_set_tile_in_chunk(chunk, Vector2i(x_center - 1, y), SubChunk.TileType.FLOOR)
			_set_tile_in_chunk(chunk, Vector2i(x_center, y), SubChunk.TileType.FLOOR)
			_set_tile_in_chunk(chunk, Vector2i(x_center + 1, y), SubChunk.TileType.FLOOR)

func _get_shuffled_room_neighbors(
	room_pos: Vector2i,
	_visited: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	"""Get neighboring room positions in random order"""
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
		var neighbor := room_pos + dir

		# Check if neighbor is within maze bounds
		if neighbor.x >= 0 and neighbor.x < MAZE_SIZE and \
		   neighbor.y >= 0 and neighbor.y < MAZE_SIZE:
			neighbors.append(neighbor)

	return neighbors

func _create_edge_connections_rooms(chunk: Chunk, _rng: RandomNumberGenerator) -> void:
	"""Create hallways at chunk edges for inter-chunk connections

	Uses deterministic pattern based on chunk position to ensure
	neighboring chunks have matching hallways.
	"""
	# Create hallways at regular intervals on chunk edges
	# This ensures adjacent chunks align perfectly

	# Top and bottom edges
	for room_x in range(MAZE_SIZE):
		# Deterministic pattern: every 4th room gets edge hallway
		var world_x := chunk.position.x * MAZE_SIZE + room_x
		if world_x % 4 == 0:
			# Top edge hallway
			_carve_edge_hallway_vertical(chunk, room_x, 0)
			# Bottom edge hallway
			_carve_edge_hallway_vertical(chunk, room_x, MAZE_SIZE - 1)

	# Left and right edges
	for room_y in range(MAZE_SIZE):
		# Deterministic pattern: every 4th room gets edge hallway
		var world_y := chunk.position.y * MAZE_SIZE + room_y
		if world_y % 4 == 0:
			# Left edge hallway
			_carve_edge_hallway_horizontal(chunk, 0, room_y)
			# Right edge hallway
			_carve_edge_hallway_horizontal(chunk, MAZE_SIZE - 1, room_y)

func _carve_edge_hallway_horizontal(chunk: Chunk, room_x: int, room_y: int) -> void:
	"""Carve horizontal hallway at room edge (for left/right chunk boundaries)"""
	var center_tile := Vector2i(room_x * ROOM_SIZE + ROOM_SIZE / 2, room_y * ROOM_SIZE + ROOM_SIZE / 2)

	# Carve 3 tiles wide across entire room width
	for dx in range(ROOM_SIZE):
		var x := room_x * ROOM_SIZE + dx
		_set_tile_in_chunk(chunk, Vector2i(x, center_tile.y - 1), SubChunk.TileType.FLOOR)
		_set_tile_in_chunk(chunk, Vector2i(x, center_tile.y), SubChunk.TileType.FLOOR)
		_set_tile_in_chunk(chunk, Vector2i(x, center_tile.y + 1), SubChunk.TileType.FLOOR)

func _carve_edge_hallway_vertical(chunk: Chunk, room_x: int, room_y: int) -> void:
	"""Carve vertical hallway at room edge (for top/bottom chunk boundaries)"""
	var center_tile := Vector2i(room_x * ROOM_SIZE + ROOM_SIZE / 2, room_y * ROOM_SIZE + ROOM_SIZE / 2)

	# Carve 3 tiles wide across entire room height
	for dy in range(ROOM_SIZE):
		var y := room_y * ROOM_SIZE + dy
		_set_tile_in_chunk(chunk, Vector2i(center_tile.x - 1, y), SubChunk.TileType.FLOOR)
		_set_tile_in_chunk(chunk, Vector2i(center_tile.x, y), SubChunk.TileType.FLOOR)
		_set_tile_in_chunk(chunk, Vector2i(center_tile.x + 1, y), SubChunk.TileType.FLOOR)

func _set_tile_in_chunk(chunk: Chunk, tile_pos: Vector2i, tile_type: SubChunk.TileType) -> void:
	"""Helper: Set tile at absolute chunk tile coordinate

	Converts chunk-local tile coordinates (0-127) to sub-chunk + local coordinates.
	"""
	# Calculate which sub-chunk contains this tile
	var sub_pos := Vector2i(tile_pos.x / SubChunk.SIZE, tile_pos.y / SubChunk.SIZE)

	# Calculate tile position within that sub-chunk
	var local_pos := Vector2i(
		posmod(tile_pos.x, SubChunk.SIZE),
		posmod(tile_pos.y, SubChunk.SIZE)
	)

	var sub := chunk.get_sub_chunk(sub_pos)
	if sub:
		sub.set_tile(local_pos, tile_type)

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "Level0Generator(Recursive Backtracking Maze)"
