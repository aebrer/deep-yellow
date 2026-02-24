class_name Level0Generator extends LevelGenerator
## Level 0 - The Lobby generator
##
## Generates infinite yellow hallways using room+corridor maze algorithm.
## Ported from Python implementation that targets 68-75% floor density.
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

# ============================================================================
# MAZE GENERATION - ROOM + CORRIDOR ALGORITHM (PORTED FROM PYTHON)
# ============================================================================

# Generation strategies
enum Strategy {
	ROOM_FOCUSED,   # More rooms, fewer maze corridors (20% probability)
	MAZE_FOCUSED,   # Fewer rooms, more maze corridors (50% probability)
	HYBRID          # Mix of both (30% probability)
}

# Tile types (SubChunk.TileType values for generation)
const FLOOR := 0
const WALL := 1

# Floor percentage targets (from approved Python mazes)
const MIN_FLOOR_PCT := 0.68  # 68% floor minimum
const MAX_FLOOR_PCT := 0.75  # 75% floor maximum

func generate_chunk(chunk: Chunk, world_seed: int) -> void:
	"""Generate Level 0 chunk using room+corridor algorithm (ported from Python)

	Algorithm:
	1. Start with all walls
	2. Choose generation strategy based on weighted random
	3. Generate rooms and corridors based on strategy
	4. Ensure floor percentage is 68-75%
	5. Apply to chunk

	Uses world-space seeding for deterministic generation across chunk boundaries.
	Much faster than cell-by-cell WFC (~10-20ms vs 200ms).
	"""
	var start_time := Time.get_ticks_usec()

	# Initialize grid (all walls)
	var grid: Array = []
	grid.resize(Chunk.SIZE)
	for y in range(Chunk.SIZE):
		var row: Array = []
		row.resize(Chunk.SIZE)
		for x in range(Chunk.SIZE):
			row[x] = WALL
		grid[y] = row

	# Room storage for corridor connections (local variable to avoid race conditions)
	var rooms: Array = []  # Array of Vector4(center_x, center_y, width, height)

	# Create RNG seeded with chunk world position
	var rng := RandomNumberGenerator.new()
	var chunk_world_offset := chunk.position * Chunk.SIZE
	var chunk_seed := hash(Vector3i(chunk_world_offset.x, chunk_world_offset.y, world_seed))
	rng.seed = chunk_seed

	# Choose generation strategy (weights from Python: 0.2, 0.5, 0.3)
	var strategy_roll := rng.randf()
	var strategy: Strategy
	if strategy_roll < 0.2:
		strategy = Strategy.ROOM_FOCUSED
	elif strategy_roll < 0.7:  # 0.2 + 0.5
		strategy = Strategy.MAZE_FOCUSED
	else:
		strategy = Strategy.HYBRID

	var time_after_init := Time.get_ticks_usec()

	# Generate maze based on strategy
	match strategy:
		Strategy.ROOM_FOCUSED:
			var num_rooms := rng.randi_range(10, 18)
			_generate_varied_rooms(grid, num_rooms, rng, rooms)
			_connect_rooms_naturally(grid, rng, rooms)
			_add_random_corridors(grid, 0.1, rng)

		Strategy.MAZE_FOCUSED:
			_generate_maze_base(grid, rng)
			var num_rooms := rng.randi_range(4, 8)
			_carve_rooms_in_maze(grid, num_rooms, rng)

		Strategy.HYBRID:
			var num_rooms := rng.randi_range(6, 12)
			_generate_varied_rooms(grid, num_rooms, rng, rooms)
			_fill_empty_areas_with_maze(grid, rng)

	var time_after_generation := Time.get_ticks_usec()

	# Ensure floor percentage is in target range
	_ensure_floor_percentage_range(grid, rng)

	var time_after_floor_pct := Time.get_ticks_usec()

	# Place doors in single-width hallways (before variant placement)
	_place_doors(grid, rng)

	# Place ceiling lights on walkable tiles
	_place_lights(grid, chunk, rng)

	# Apply to chunk (with variant placement)
	_apply_grid_to_chunk(grid, chunk, rng)

	var time_after_apply := Time.get_ticks_usec()

	# Calculate timing breakdown (in milliseconds)
	var total_time := (time_after_apply - start_time) / 1000.0
	var init_time := (time_after_init - start_time) / 1000.0
	var gen_time := (time_after_generation - time_after_init) / 1000.0
	var floor_pct_time := (time_after_floor_pct - time_after_generation) / 1000.0
	var apply_time := (time_after_apply - time_after_floor_pct) / 1000.0

# ============================================================================
# ROOM GENERATION
# ============================================================================

func _generate_varied_rooms(grid: Array, num_rooms: int, rng: RandomNumberGenerator, rooms: Array) -> void:
	"""Generate rooms of varying sizes (Backrooms style)"""
	for i in range(num_rooms):
		# Weighted room sizes (Python: 0.15, 0.35, 0.30, 0.15, 0.05)
		var size_roll := rng.randf()
		var width: int
		var height: int

		if size_roll < 0.15:  # tiny
			width = rng.randi_range(3, 6)
			height = rng.randi_range(3, 6)
		elif size_roll < 0.50:  # small (0.15 + 0.35)
			width = rng.randi_range(5, 10)
			height = rng.randi_range(5, 10)
		elif size_roll < 0.80:  # medium (0.15 + 0.35 + 0.30)
			width = rng.randi_range(8, 16)
			height = rng.randi_range(8, 16)
		elif size_roll < 0.95:  # large (0.15 + 0.35 + 0.30 + 0.15)
			width = rng.randi_range(12, 24)
			height = rng.randi_range(12, 24)
		else:  # huge
			width = rng.randi_range(20, 35)
			height = rng.randi_range(20, 35)

		# Random position
		var max_x := maxi(3, Chunk.SIZE - width - 2)
		var max_y := maxi(3, Chunk.SIZE - height - 2)
		var x := rng.randi_range(2, max_x)
		var y := rng.randi_range(2, max_y)

		# Carve room
		for ry in range(y, y + height):
			for rx in range(x, x + width):
				if ry >= 0 and ry < Chunk.SIZE and rx >= 0 and rx < Chunk.SIZE:
					grid[ry][rx] = FLOOR

		# Store room center for corridor connections
		var center := Vector4(x + width / 2, y + height / 2, width, height)
		rooms.append(center)

func _carve_rooms_in_maze(grid: Array, num_rooms: int, rng: RandomNumberGenerator) -> void:
	"""Carve rooms into existing maze structure"""
	for i in range(num_rooms):
		var width := rng.randi_range(5, 15)
		var height := rng.randi_range(5, 15)

		var max_x := maxi(3, Chunk.SIZE - width - 2)
		var max_y := maxi(3, Chunk.SIZE - height - 2)
		var x := rng.randi_range(2, max_x)
		var y := rng.randi_range(2, max_y)

		# Carve room
		for ry in range(y, y + height):
			for rx in range(x, x + width):
				if ry >= 0 and ry < Chunk.SIZE and rx >= 0 and rx < Chunk.SIZE:
					grid[ry][rx] = FLOOR

# ============================================================================
# CORRIDOR GENERATION
# ============================================================================

func _connect_rooms_naturally(grid: Array, rng: RandomNumberGenerator, rooms: Array) -> void:
	"""Connect rooms with natural-feeling L-shaped corridors"""
	if rooms.size() < 2:
		return

	# Connect sequential rooms
	for i in range(rooms.size() - 1):
		var room1: Vector4 = rooms[i]
		var room2: Vector4 = rooms[i + 1]
		_carve_corridor(grid, int(room1.x), int(room1.y), int(room2.x), int(room2.y), rng)

	# Add extra connections for loops
	var extra := mini(5, rooms.size() / 3)
	for i in range(extra):
		var idx1 := rng.randi_range(0, rooms.size() - 1)
		var idx2 := rng.randi_range(0, rooms.size() - 1)
		if idx1 != idx2:
			var room1: Vector4 = rooms[idx1]
			var room2: Vector4 = rooms[idx2]
			_carve_corridor(grid, int(room1.x), int(room1.y), int(room2.x), int(room2.y), rng)

func _carve_corridor(grid: Array, x1: int, y1: int, x2: int, y2: int, rng: RandomNumberGenerator) -> void:
	"""Carve L-shaped corridor with varied width (1-3 tiles, heavily favor narrow)"""
	# Corridor width (Python weights: 0.7, 0.25, 0.05)
	var width_roll := rng.randf()
	var width: int
	if width_roll < 0.7:
		width = 1
	elif width_roll < 0.95:  # 0.7 + 0.25
		width = 2
	else:
		width = 3

	# L-shaped: horizontal then vertical, or vertical then horizontal
	if rng.randf() < 0.5:
		# Horizontal first
		var x_start := mini(x1, x2)
		var x_end := maxi(x1, x2)
		for x in range(x_start, x_end + 1):
			for w in range(width):
				var cy := y1 + w
				if cy >= 0 and cy < Chunk.SIZE and x >= 0 and x < Chunk.SIZE:
					grid[cy][x] = FLOOR

		# Then vertical
		var y_start := mini(y1, y2)
		var y_end := maxi(y1, y2)
		for y in range(y_start, y_end + 1):
			for w in range(width):
				var cx := x2 + w
				if y >= 0 and y < Chunk.SIZE and cx >= 0 and cx < Chunk.SIZE:
					grid[y][cx] = FLOOR
	else:
		# Vertical first
		var y_start := mini(y1, y2)
		var y_end := maxi(y1, y2)
		for y in range(y_start, y_end + 1):
			for w in range(width):
				var cx := x1 + w
				if y >= 0 and y < Chunk.SIZE and cx >= 0 and cx < Chunk.SIZE:
					grid[y][cx] = FLOOR

		# Then horizontal
		var x_start := mini(x1, x2)
		var x_end := maxi(x1, x2)
		for x in range(x_start, x_end + 1):
			for w in range(width):
				var cy := y2 + w
				if cy >= 0 and cy < Chunk.SIZE and x >= 0 and x < Chunk.SIZE:
					grid[cy][x] = FLOOR

func _add_random_corridors(grid: Array, density: float, rng: RandomNumberGenerator) -> void:
	"""Add random corridors to increase connectivity"""
	var num_corridors := int(Chunk.SIZE * Chunk.SIZE * density / 20)

	for i in range(num_corridors):
		var x1 := rng.randi_range(0, Chunk.SIZE - 1)
		var y1 := rng.randi_range(0, Chunk.SIZE - 1)
		var x2 := rng.randi_range(0, Chunk.SIZE - 1)
		var y2 := rng.randi_range(0, Chunk.SIZE - 1)

		_carve_corridor(grid, x1, y1, x2, y2, rng)

# ============================================================================
# MAZE BASE GENERATION
# ============================================================================

func _generate_maze_base(grid: Array, rng: RandomNumberGenerator) -> void:
	"""Generate maze using recursive backtracking (classic algorithm)"""
	var visited: Dictionary = {}  # Vector2i -> bool
	var stack: Array = []  # Array of Vector2i

	# Start from random position (on even grid for cleaner maze)
	var start_x := rng.randi_range(0, 63) * 2
	var start_y := rng.randi_range(0, 63) * 2

	var start_pos := Vector2i(start_x, start_y)
	stack.append(start_pos)
	visited[start_pos] = true
	grid[start_y][start_x] = FLOOR

	# Directions (step by 2 for wall-path-wall pattern)
	var directions := [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]

	while stack.size() > 0:
		var current: Vector2i = stack[stack.size() - 1]

		# Find unvisited neighbors
		var neighbors: Array = []
		for dir in directions:
			var next: Vector2i = current + dir
			if next.x >= 0 and next.x < Chunk.SIZE and next.y >= 0 and next.y < Chunk.SIZE:
				if not visited.has(next):
					neighbors.append([next, dir])

		if neighbors.size() > 0:
			# Pick random neighbor
			var choice: Array = neighbors[rng.randi_range(0, neighbors.size() - 1)]
			var next := choice[0] as Vector2i
			var dir := choice[1] as Vector2i

			# Carve path to neighbor and the wall between
			grid[next.y][next.x] = FLOOR
			var between := current + dir / 2
			grid[between.y][between.x] = FLOOR

			visited[next] = true
			stack.append(next)
		else:
			# Backtrack
			stack.pop_back()

func _fill_empty_areas_with_maze(grid: Array, rng: RandomNumberGenerator) -> void:
	"""Fill large wall regions with mini maze corridors"""
	# Scan in 16×16 regions
	for region_y in range(0, Chunk.SIZE, 16):
		for region_x in range(0, Chunk.SIZE, 16):
			# Count floor tiles in region
			var floor_count := 0
			for y in range(region_y, mini(region_y + 16, Chunk.SIZE)):
				for x in range(region_x, mini(region_x + 16, Chunk.SIZE)):
					if grid[y][x] == FLOOR:
						floor_count += 1

			# If mostly walls, carve some mini corridors
			if floor_count < 20 and rng.randf() < 0.4:
				_carve_mini_maze(grid, region_x, region_y, 16, 16, rng)

func _carve_mini_maze(grid: Array, start_x: int, start_y: int, width: int, height: int, rng: RandomNumberGenerator) -> void:
	"""Carve small random corridors in a region"""
	var num_corridors := rng.randi_range(4, 10)

	for i in range(num_corridors):
		var x := start_x + rng.randi_range(0, width - 1)
		var y := start_y + rng.randi_range(0, height - 1)
		var length := rng.randi_range(2, 6)

		# Random direction (horizontal or vertical)
		if rng.randf() < 0.5:
			# Horizontal
			for dx in range(length):
				var cx := x + dx
				if cx >= 0 and cx < Chunk.SIZE and y >= 0 and y < Chunk.SIZE:
					grid[y][cx] = FLOOR
		else:
			# Vertical
			for dy in range(length):
				var cy := y + dy
				if x >= 0 and x < Chunk.SIZE and cy >= 0 and cy < Chunk.SIZE:
					grid[cy][x] = FLOOR

# ============================================================================
# FLOOR PERCENTAGE ENFORCEMENT
# ============================================================================

func _ensure_floor_percentage_range(grid: Array, rng: RandomNumberGenerator) -> void:
	"""Ensure floor percentage is within 68-75% range"""
	var floor_count := 0
	var total := Chunk.SIZE * Chunk.SIZE

	# Count current floor tiles
	for y in range(Chunk.SIZE):
		for x in range(Chunk.SIZE):
			if grid[y][x] == FLOOR:
				floor_count += 1

	var current_pct := float(floor_count) / float(total)

	if current_pct < MIN_FLOOR_PCT:
		# Too dense - add more floor tiles
		var needed := int((MIN_FLOOR_PCT - current_pct) * total)
		for i in range(needed):
			var x := rng.randi_range(1, Chunk.SIZE - 2)
			var y := rng.randi_range(1, Chunk.SIZE - 2)

			# Carve small corridor
			var length := rng.randi_range(2, 5)
			if rng.randf() < 0.5:
				for dx in range(length):
					var cx := x + dx
					if cx < Chunk.SIZE:
						grid[y][cx] = FLOOR
			else:
				for dy in range(length):
					var cy := y + dy
					if cy < Chunk.SIZE:
						grid[cy][x] = FLOOR

	elif current_pct > MAX_FLOOR_PCT:
		# Too sparse - add wall chunks
		var needed := int((current_pct - MAX_FLOOR_PCT) * total)
		for i in range(needed):
			var x := rng.randi_range(1, Chunk.SIZE - 2)
			var y := rng.randi_range(1, Chunk.SIZE - 2)

			if grid[y][x] == FLOOR:
				grid[y][x] = WALL

				# Sometimes add adjacent walls for structure
				if rng.randf() < 0.3:
					var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
					for dir in dirs:
						var nx: int = x + dir.x
						var ny: int = y + dir.y
						if nx >= 0 and nx < Chunk.SIZE and ny >= 0 and ny < Chunk.SIZE:
							if grid[ny][nx] == FLOOR:
								grid[ny][nx] = WALL
								break

# ============================================================================
# DOOR PLACEMENT
# ============================================================================

## Door spawn probability per eligible hallway tile
const DOOR_SPAWN_CHANCE := 0.30  # 30% per eligible tile
## Minimum distance between doors (in tiles)
const DOOR_MIN_SPACING := 8
## Margin from chunk edges (avoid doors right at borders where hallway cutting happens)
const DOOR_EDGE_MARGIN := 3

func _place_doors(grid: Array, rng: RandomNumberGenerator) -> void:
	"""Place closed doors in single-width hallways.

	A tile is eligible for a door if:
	- It is a FLOOR tile
	- It has walls on BOTH sides of one perpendicular axis (single-width corridor)
	- It has floor on at least one side of the parallel axis (not a dead end)
	- It is not too close to chunk edges (where border hallways get cut)
	- It is not too close to another door
	"""
	var door_positions: Array[Vector2i] = []

	for y in range(DOOR_EDGE_MARGIN, Chunk.SIZE - DOOR_EDGE_MARGIN):
		for x in range(DOOR_EDGE_MARGIN, Chunk.SIZE - DOOR_EDGE_MARGIN):
			if grid[y][x] != FLOOR:
				continue

			# Check for single-width horizontal hallway:
			# walls above and below, floor left or right
			var is_horizontal: bool = (
				y > 0 and y < Chunk.SIZE - 1
				and grid[y - 1][x] == WALL and grid[y + 1][x] == WALL
				and (x > 0 and grid[y][x - 1] == FLOOR or x < Chunk.SIZE - 1 and grid[y][x + 1] == FLOOR)
			)

			# Check for single-width vertical hallway:
			# walls left and right, floor above or below
			var is_vertical: bool = (
				x > 0 and x < Chunk.SIZE - 1
				and grid[y][x - 1] == WALL and grid[y][x + 1] == WALL
				and (y > 0 and grid[y - 1][x] == FLOOR or y < Chunk.SIZE - 1 and grid[y + 1][x] == FLOOR)
			)

			if not is_horizontal and not is_vertical:
				continue

			# Check no adjacent door in cardinal directions (prevents door clusters)
			var has_adjacent_door := false
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx >= 0 and nx < Chunk.SIZE and ny >= 0 and ny < Chunk.SIZE:
					if SubChunk.is_door_type(grid[ny][nx]):
						has_adjacent_door = true
						break
			if has_adjacent_door:
				continue

			# Check minimum spacing from existing doors
			var too_close := false
			var pos := Vector2i(x, y)
			for door_pos in door_positions:
				if abs(pos.x - door_pos.x) + abs(pos.y - door_pos.y) < DOOR_MIN_SPACING:
					too_close = true
					break
			if too_close:
				continue

			# Roll for door placement
			if rng.randf() < DOOR_SPAWN_CHANCE:
				grid[y][x] = SubChunk.TileType.WALL_DOOR_A_CLOSED
				door_positions.append(pos)


# ============================================================================
# LIGHT PLACEMENT
# ============================================================================

## Spacing between ceiling lights (in tiles). Lights are placed on a grid
## with this interval, then randomly offset and filtered to walkable tiles.
## 5 tiles = 10 world units between lights. With range 12, adjacent lights
## overlap significantly for dense fluorescent coverage.
const LIGHT_SPACING := 5
## Random offset range for light positions (prevents perfectly regular grid)
const LIGHT_JITTER := 1

func _place_lights(grid: Array, chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Place fluorescent ceiling light entities on walkable floor tiles.

	Uses a regular grid with jitter for natural-looking coverage.
	Each light gets a unique entropy-locked personality from its world position.
	"""
	var chunk_world := chunk.position * Chunk.SIZE
	var light_count := 0

	for gy in range(LIGHT_SPACING / 2, Chunk.SIZE, LIGHT_SPACING):
		for gx in range(LIGHT_SPACING / 2, Chunk.SIZE, LIGHT_SPACING):
			# Apply random jitter
			var x: int = clampi(gx + rng.randi_range(-LIGHT_JITTER, LIGHT_JITTER), 0, Chunk.SIZE - 1)
			var y: int = clampi(gy + rng.randi_range(-LIGHT_JITTER, LIGHT_JITTER), 0, Chunk.SIZE - 1)

			if grid[y][x] != FLOOR:
				continue

			var world_pos := Vector2i(x, y) + chunk_world

			var light_entity := WorldEntity.new("fluorescent_light", world_pos, 99999.0, 0)
			EntityRegistry.apply_defaults(light_entity)
			LightFixtureBehavior.setup_flicker(light_entity)

			var sc := chunk.get_sub_chunk(Vector2i(x / SubChunk.SIZE, y / SubChunk.SIZE))
			if sc:
				sc.add_world_entity(light_entity)
				light_count += 1


# ============================================================================
# GRID APPLICATION
# ============================================================================

## Variant placement probabilities
const FLOOR_PUDDLE_CHANCE := 0.001
const FLOOR_CARDBOARD_CHANCE := 0.0005
const WALL_CRACKED_CHANCE := 0.002
const WALL_HOLE_CHANCE := 0.0003
const WALL_MOULDY_CHANCE := 0.001
const CEILING_STAIN_CHANCE := 0.001
const CEILING_HOLE_CHANCE := 0.0003

func _apply_grid_to_chunk(grid: Array, chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Apply generated grid to chunk tiles (layer 0 = floor/wall, layer 1 = ceiling)

	⚠️ PERFORMANCE CRITICAL - DO NOT "REFACTOR" WITHOUT BENCHMARKING ⚠️

	This function is highly optimized to avoid coordinate conversion overhead.
	Uses DIRECT sub-chunk access instead of chunk.set_tile(world_pos) to eliminate
	65,536+ coordinate calculations per chunk (local→world→sub-local conversions).

	BEFORE optimization: 43-47ms (78% of generation time!)
	AFTER optimization: 14-16ms (3x speedup)

	Why this pattern works:
	- Iterates over 8×8 sub-chunk grid directly
	- Uses sub-local coordinates (0-15) without any world coordinate math
	- Avoids get_sub_chunk_at_tile() lookups (16,384 times!)
	- Each sub_chunk.set_tile() is a direct array access

	If you think this looks "messy" compared to chunk.set_tile(world_pos),
	remember: the "clean" version was 3x slower and caused frame hitches.
	"""
	const FLOOR := 0
	const WALL := 1
	const CEILING := 2  # SubChunk.TileType.CEILING
	const FLOOR_PUDDLE := 10  # SubChunk.TileType.FLOOR_PUDDLE
	const FLOOR_CARDBOARD := 11
	const WALL_CRACKED := 20
	const WALL_HOLE := 21
	const WALL_MOULDY := 22
	const CEILING_STAIN := 30
	const CEILING_HOLE := 31
	const SUB_CHUNK_SIZE := 16
	const SUB_CHUNKS_PER_SIDE := 8

	# Iterate over 8×8 grid of sub-chunks
	for sub_y in range(SUB_CHUNKS_PER_SIDE):
		for sub_x in range(SUB_CHUNKS_PER_SIDE):
			var sub_chunk := chunk.sub_chunks[sub_y * SUB_CHUNKS_PER_SIDE + sub_x]

			# Iterate over 16×16 tiles in this sub-chunk
			for tile_y in range(SUB_CHUNK_SIZE):
				for tile_x in range(SUB_CHUNK_SIZE):
					# Calculate position in full grid
					var grid_x := sub_x * SUB_CHUNK_SIZE + tile_x
					var grid_y := sub_y * SUB_CHUNK_SIZE + tile_y
					var tile_type: int = grid[grid_y][grid_x]

					# Randomly replace some tiles with variants
					if tile_type == FLOOR:
						var roll := rng.randf()
						if roll < FLOOR_PUDDLE_CHANCE:
							tile_type = FLOOR_PUDDLE
						elif roll < FLOOR_PUDDLE_CHANCE + FLOOR_CARDBOARD_CHANCE:
							tile_type = FLOOR_CARDBOARD
					elif tile_type == WALL:
						var roll := rng.randf()
						if roll < WALL_CRACKED_CHANCE:
							tile_type = WALL_CRACKED
						elif roll < WALL_CRACKED_CHANCE + WALL_HOLE_CHANCE:
							tile_type = WALL_HOLE
						elif roll < WALL_CRACKED_CHANCE + WALL_HOLE_CHANCE + WALL_MOULDY_CHANCE:
							tile_type = WALL_MOULDY

					# Direct sub-chunk tile access (no coordinate conversion!)
					var sub_local := Vector2i(tile_x, tile_y)
					sub_chunk.set_tile(sub_local, tile_type)

					# Set ceiling above floor tiles (all floor variants get ceilings)
					if tile_type == FLOOR or (tile_type >= 10 and tile_type <= 19):
						var ceiling_type := CEILING
						var ceil_roll := rng.randf()
						if ceil_roll < CEILING_STAIN_CHANCE:
							ceiling_type = CEILING_STAIN
						elif ceil_roll < CEILING_STAIN_CHANCE + CEILING_HOLE_CHANCE:
							ceiling_type = CEILING_HOLE
						sub_chunk.set_tile_at_layer(sub_local, 1, ceiling_type)
