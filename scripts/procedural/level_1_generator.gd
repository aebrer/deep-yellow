class_name Level1Generator extends LevelGenerator
## Level 1 - The Poolrooms generator
##
## Room-based architecture: tiled rooms divided by walls, some containing pools.
## Reads as a built environment (tiled area with pools) rather than open water.

const FLOOR := SubChunk.TileType.FLOOR
const WALL := SubChunk.TileType.WALL
const CEILING := SubChunk.TileType.CEILING
const EXIT_STAIRS := SubChunk.TileType.EXIT_STAIRS
const SHALLOW_WATER := SubChunk.TileType.FLOOR_SHALLOW_WATER
const DEEP_WATER := SubChunk.TileType.DEEP_WATER

func _init() -> void:
	var config := ProceduralLevelConfig.new()
	config.level_id = 1
	config.level_name = "Level 1 - The Poolrooms"
	config.corruption_per_chunk = 0.015
	setup_level_config(config)

func generate_chunk(chunk: Chunk, world_seed: int) -> void:
	"""Generate a deterministic Poolrooms chunk with room-based architecture."""
	var rng := RandomNumberGenerator.new()
	var chunk_world_offset := chunk.position * Chunk.SIZE
	rng.seed = hash(Vector3i(chunk_world_offset.x, chunk_world_offset.y, world_seed + 10101))

	_fill_walls(chunk)
	_build_room_grid(chunk, rng)
	_add_pool_barriers(chunk, rng)
	_add_pillars(chunk, rng)
	_add_irregular_lights(chunk, rng)
	_place_return_stairs(chunk, rng)

	chunk.state = Chunk.State.LOADED

func _fill_walls(chunk: Chunk) -> void:
	for y in range(Chunk.SIZE):
		for x in range(Chunk.SIZE):
			_set_tile_local(chunk, Vector2i(x, y), WALL)

func _world_from_local(chunk: Chunk, local_pos: Vector2i) -> Vector2i:
	return chunk.position * Chunk.SIZE + local_pos

func _get_tile_local(chunk: Chunk, local_pos: Vector2i) -> int:
	return chunk.get_tile(_world_from_local(chunk, local_pos))

func _set_tile_local(chunk: Chunk, local_pos: Vector2i, tile_type: int) -> void:
	chunk.set_tile(_world_from_local(chunk, local_pos), tile_type)

func _set_tile_at_layer_local(chunk: Chunk, local_pos: Vector2i, layer: int, tile_type: int) -> void:
	chunk.set_tile_at_layer(_world_from_local(chunk, local_pos), layer, tile_type)

func _set_floor_with_ceiling(chunk: Chunk, pos: Vector2i, tile_type: int) -> void:
	if pos.x < 0 or pos.x >= Chunk.SIZE or pos.y < 0 or pos.y >= Chunk.SIZE:
		return
	_set_tile_local(chunk, pos, tile_type)
	_set_tile_at_layer_local(chunk, pos, 1, CEILING)

# ============================================================================
# ROOM GRID ARCHITECTURE
# ============================================================================

func _build_room_grid(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Build a grid of rooms separated by wall dividers with doorways.

	Each room is a rectangular bay. Walls form the boundaries; doorways
	provide connectivity. Rooms are either dry tile floor or contain a pool.
	"""
	# Grid of bays: 4x4 to 6x6 rooms per chunk
	var grid_cols := rng.randi_range(4, 6)
	var grid_rows := rng.randi_range(4, 6)

	var margin := 2  # Wall buffer from chunk edge
	var avail_width := Chunk.SIZE - margin * 2
	var avail_height := Chunk.SIZE - margin * 2

	var col_width := avail_width / grid_cols
	var row_height := avail_height / grid_rows
	var wall_thickness := 1

	# Carve each room
	for row in range(grid_rows):
		for col in range(grid_cols):
			var room_x := margin + col * col_width
			var room_y := margin + row * row_height
			var room_w := col_width - wall_thickness
			var room_h := row_height - wall_thickness

			# Room type: 0 = dry floor, 1 = shallow pool room, 2 = deep pool room
			var room_type_roll := rng.randf()
			var room_type: int
			if room_type_roll < 0.45:
				room_type = 0  # Dry tile room
			elif room_type_roll < 0.85:
				room_type = 1  # Shallow pool
			else:
				room_type = 2  # Deep pool

			_carve_room(chunk, room_x, room_y, room_w, room_h, room_type, rng)

	# Carve doorways in the wall grid
	_carve_doorways(chunk, grid_cols, grid_rows, col_width, row_height, margin, wall_thickness, rng)

func _carve_room(chunk: Chunk, x: int, y: int, w: int, h: int, room_type: int, rng: RandomNumberGenerator) -> void:
	"""Carve a single room: dry floor or pool with surrounding deck."""
	match room_type:
		0:
			# Dry tile room
			_carve_rect(chunk, x, y, x + w, y + h, FLOOR)
		1:
			# Shallow pool room: floor deck around a water pool
			_carve_rect(chunk, x, y, x + w, y + h, FLOOR)
			if w >= 6 and h >= 6:
				var inset := rng.randi_range(1, 2)
				_carve_rect(chunk, x + inset, y + inset, x + w - inset, y + h - inset, SHALLOW_WATER)
		2:
			# Deep pool room: floor deck around deep water
			_carve_rect(chunk, x, y, x + w, y + h, FLOOR)
			if w >= 8 and h >= 8:
				var inset := rng.randi_range(2, 3)
				_carve_rect(chunk, x + inset, y + inset, x + w - inset, y + h - inset, SHALLOW_WATER)
				if w >= 12 and h >= 12:
					var deep_inset := inset + rng.randi_range(1, 2)
					_carve_rect(chunk, x + deep_inset, y + deep_inset, x + w - deep_inset, y + h - deep_inset, DEEP_WATER)

func _carve_doorways(chunk: Chunk, grid_cols: int, grid_rows: int, col_width: int, row_height: int, margin: int, wall_thickness: int, rng: RandomNumberGenerator) -> void:
	"""Cut doorways through the wall grid between adjacent rooms."""
	# Horizontal doorways (between columns)
	for row in range(grid_rows):
		for col in range(grid_cols - 1):
			# Wall position between col and col+1
			var wall_x := margin + (col + 1) * col_width - wall_thickness
			var room_y := margin + row * row_height
			var room_h := row_height - wall_thickness

			# doorway at a random position along the wall
			var door_y := room_y + rng.randi_range(1, maxi(1, room_h - 2))
			var door_height := rng.randi_range(1, 2)
			_carve_rect(chunk, wall_x, door_y, wall_x + wall_thickness, door_y + door_height, FLOOR)

	# Vertical doorways (between rows)
	for row in range(grid_rows - 1):
		for col in range(grid_cols):
			var room_x := margin + col * col_width
			var room_w := col_width - wall_thickness
			var wall_y := margin + (row + 1) * row_height - wall_thickness

			var door_x := room_x + rng.randi_range(1, maxi(1, room_w - 2))
			var door_width := rng.randi_range(1, 2)
			_carve_rect(chunk, door_x, wall_y, door_x + door_width, wall_y + wall_thickness, FLOOR)

func _carve_rect(chunk: Chunk, x1: int, y1: int, x2: int, y2: int, tile_type: int) -> void:
	for y in range(maxi(1, y1), mini(Chunk.SIZE - 1, y2)):
		for x in range(maxi(1, x1), mini(Chunk.SIZE - 1, x2)):
			_set_floor_with_ceiling(chunk, Vector2i(x, y), tile_type)

# ============================================================================
# POOL BARRIERS & ARCHITECTURE
# ============================================================================

func _add_pool_barriers(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Add partial wall barriers inside some pool rooms to create depth.

	This turns some pool rooms into multi-level spaces with raised walkways
	or dividing walls inside the water.
	"""
	for _i in range(rng.randi_range(2, 4)):
		var x := rng.randi_range(12, Chunk.SIZE - 20)
		var y := rng.randi_range(12, Chunk.SIZE - 20)
		var w := rng.randi_range(4, 10)
		var h := rng.randi_range(2, 3)

		# Only place if this area is currently water
		var all_water := true
		for dy in range(h):
			for dx in range(w):
				var tile := _get_tile_local(chunk, Vector2i(x + dx, y + dy))
				if tile != SHALLOW_WATER and tile != DEEP_WATER:
					all_water = false
					break
			if not all_water:
				break

		if all_water:
			for dy in range(h):
				for dx in range(w):
					_set_tile_local(chunk, Vector2i(x + dx, y + dy), WALL)
					_set_tile_at_layer_local(chunk, Vector2i(x + dx, y + dy), 1, -1)

# ============================================================================
# PILLARS
# ============================================================================

func _add_pillars(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	"""Place support pillars at floor intersections for architectural interest."""
	for _i in range(rng.randi_range(8, 16)):
		var pos := Vector2i(rng.randi_range(4, Chunk.SIZE - 5), rng.randi_range(4, Chunk.SIZE - 5))
		var tile := _get_tile_local(chunk, pos)
		if tile == FLOOR:
			_set_tile_local(chunk, pos, WALL)
			_set_tile_at_layer_local(chunk, pos, 1, -1)

# ============================================================================
# LIGHTS & STAIRS
# ============================================================================

func _add_irregular_lights(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	var chunk_world := chunk.position * Chunk.SIZE
	for _i in range(rng.randi_range(12, 20)):
		var local_pos := _find_random_walkable_local(chunk, rng)
		if local_pos == Vector2i(-1, -1):
			continue
		var world_pos := local_pos + chunk_world
		var light := WorldEntity.new("fluorescent_light", world_pos, 99999.0, 0)
		EntityRegistry.apply_defaults(light)
		LightFixtureBehavior.setup_flicker(light)
		var sc := chunk.get_sub_chunk(Vector2i(local_pos.x / SubChunk.SIZE, local_pos.y / SubChunk.SIZE))
		if sc:
			sc.add_world_entity(light)

func _place_return_stairs(chunk: Chunk, _rng: RandomNumberGenerator) -> void:
	if chunk.position != Vector2i(0, 0):
		return

	var stair_pos := _find_nearest_walkable_local(chunk, Vector2i(32, 32), 48)
	if stair_pos == Vector2i(-1, -1):
		return

	_set_floor_with_ceiling(chunk, stair_pos, EXIT_STAIRS)
	_add_exit_entity(chunk, stair_pos, "poolrooms_to_lobby_stairs")

# ============================================================================
# UTILITIES
# ============================================================================

func _find_random_walkable_local(chunk: Chunk, rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in range(80):
		var pos := Vector2i(rng.randi_range(2, Chunk.SIZE - 3), rng.randi_range(2, Chunk.SIZE - 3))
		if SubChunk.is_floor_type(_get_tile_local(chunk, pos)):
			return pos
	return Vector2i(-1, -1)

func _find_nearest_walkable_local(chunk: Chunk, center: Vector2i, max_radius: int) -> Vector2i:
	if SubChunk.is_floor_type(_get_tile_local(chunk, center)):
		return center

	for radius in range(1, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) + abs(dy) != radius:
					continue
				var pos := center + Vector2i(dx, dy)
				if pos.x < 1 or pos.x >= Chunk.SIZE - 1 or pos.y < 1 or pos.y >= Chunk.SIZE - 1:
					continue
				if SubChunk.is_floor_type(_get_tile_local(chunk, pos)):
					return pos

	return Vector2i(-1, -1)

func _add_exit_entity(chunk: Chunk, local_pos: Vector2i, entity_type: String) -> void:
	var world_pos := local_pos + chunk.position * Chunk.SIZE
	var exit_entity := WorldEntity.new(entity_type, world_pos, 99999.0, 0)
	EntityRegistry.apply_defaults(exit_entity)
	var sc := chunk.get_sub_chunk(Vector2i(local_pos.x / SubChunk.SIZE, local_pos.y / SubChunk.SIZE))
	if sc:
		sc.add_world_entity(exit_entity)
