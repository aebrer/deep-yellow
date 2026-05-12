class_name Level1Generator extends LevelGenerator
## Level 1 - The Poolrooms generator
##
## First-pass basin/channel generator. This intentionally avoids the Level 0
## room/maze grammar: broad shallow basins, blocked deep pockets, narrow tile
## ledges, pillars, and cool irregular light pools.

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
	"""Generate a deterministic Poolrooms chunk."""
	var rng := RandomNumberGenerator.new()
	var chunk_world_offset := chunk.position * Chunk.SIZE
	rng.seed = hash(Vector3i(chunk_world_offset.x, chunk_world_offset.y, world_seed + 10101))

	_fill_walls(chunk)
	_carve_primary_channels(chunk)
	_carve_basins(chunk, rng)
	_carve_walkway_network(chunk, rng)
	_add_pillars_and_broken_ledges(chunk, rng)
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

func _carve_rect(chunk: Chunk, x1: int, y1: int, x2: int, y2: int, tile_type: int) -> void:
	for y in range(maxi(1, y1), mini(Chunk.SIZE - 1, y2)):
		for x in range(maxi(1, x1), mini(Chunk.SIZE - 1, x2)):
			_set_floor_with_ceiling(chunk, Vector2i(x, y), tile_type)

func _carve_primary_channels(chunk: Chunk) -> void:
	# Guaranteed cross-chunk shallow-water connectivity. ChunkManager's level-aware
	# border pass reinforces these without cutting dry Level 0-style hallways.
	_carve_rect(chunk, 0, 58, Chunk.SIZE, 70, SHALLOW_WATER)
	_carve_rect(chunk, 58, 0, 70, Chunk.SIZE, SHALLOW_WATER)

	# Narrow tiled service ledges alongside the water channels.
	_carve_rect(chunk, 0, 55, Chunk.SIZE, 58, FLOOR)
	_carve_rect(chunk, 0, 70, Chunk.SIZE, 73, FLOOR)
	_carve_rect(chunk, 55, 0, 58, Chunk.SIZE, FLOOR)
	_carve_rect(chunk, 70, 0, 73, Chunk.SIZE, FLOOR)

func _carve_basins(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	var basin_count := rng.randi_range(5, 8)
	for _i in range(basin_count):
		var width := rng.randi_range(14, 34)
		var height := rng.randi_range(12, 30)
		var x := rng.randi_range(4, Chunk.SIZE - width - 5)
		var y := rng.randi_range(4, Chunk.SIZE - height - 5)

		# Walkable water basin.
		_carve_rect(chunk, x, y, x + width, y + height, SHALLOW_WATER)

		# Ceramic rim around parts of the basin.
		if rng.randf() < 0.75:
			_carve_rect(chunk, x - 2, y - 2, x + width + 2, y + 1, FLOOR)
		if rng.randf() < 0.75:
			_carve_rect(chunk, x - 2, y + height - 1, x + width + 2, y + height + 2, FLOOR)
		if rng.randf() < 0.75:
			_carve_rect(chunk, x - 2, y - 2, x + 1, y + height + 2, FLOOR)
		if rng.randf() < 0.75:
			_carve_rect(chunk, x + width - 1, y - 2, x + width + 2, y + height + 2, FLOOR)

		# Sudden deep pocket: blocked/hazardous for this PR's first pass.
		if width >= 18 and height >= 16:
			var deep_margin := rng.randi_range(4, 7)
			_carve_rect(chunk, x + deep_margin, y + deep_margin, x + width - deep_margin, y + height - deep_margin, DEEP_WATER)

func _carve_walkway_network(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	# Broken tiled causeways that cut across water at irregular intervals.
	for _i in range(rng.randi_range(7, 11)):
		var horizontal := rng.randf() < 0.5
		var width := rng.randi_range(2, 4)
		if horizontal:
			var y := rng.randi_range(8, Chunk.SIZE - 9)
			_carve_rect(chunk, 4, y, Chunk.SIZE - 4, y + width, FLOOR)
		else:
			var x := rng.randi_range(8, Chunk.SIZE - 9)
			_carve_rect(chunk, x, 4, x + width, Chunk.SIZE - 4, FLOOR)

func _add_pillars_and_broken_ledges(chunk: Chunk, rng: RandomNumberGenerator) -> void:
	for _i in range(rng.randi_range(35, 55)):
		var pos := Vector2i(rng.randi_range(4, Chunk.SIZE - 5), rng.randi_range(4, Chunk.SIZE - 5))
		var tile := _get_tile_local(chunk, pos)
		if tile == SHALLOW_WATER or tile == FLOOR:
			_set_tile_local(chunk, pos, WALL)
			_set_tile_at_layer_local(chunk, pos, 1, -1)

	# A few stair-like descents: dry tile stepping into shallow water.
	for _i in range(rng.randi_range(4, 7)):
		var pos := Vector2i(rng.randi_range(8, Chunk.SIZE - 12), rng.randi_range(8, Chunk.SIZE - 12))
		_carve_rect(chunk, pos.x, pos.y, pos.x + 3, pos.y + 2, FLOOR)
		_carve_rect(chunk, pos.x + 3, pos.y, pos.x + 7, pos.y + 2, SHALLOW_WATER)

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
	# Guarantee one explicit Poolrooms -> Lobby route in the origin chunk.
	if chunk.position != Vector2i(0, 0):
		return

	var stair_pos := _find_nearest_walkable_local(chunk, Vector2i(32, 32), 48)
	if stair_pos == Vector2i(-1, -1):
		return

	_set_floor_with_ceiling(chunk, stair_pos, EXIT_STAIRS)
	_add_exit_entity(chunk, stair_pos, "poolrooms_to_lobby_stairs")

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
