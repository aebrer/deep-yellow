extends Node
## Manages chunk loading, unloading, and corruption escalation
##
## ChunkManager is an autoload singleton that handles:
## - Loading chunks near the player
## - Unloading distant chunks to save memory
## - Tracking corruption per level
## - Coordinating with generators and spawners
## - Providing chunk query API

# Constants
const CHUNK_SIZE := 128
const ACTIVE_RADIUS := 3  # Chunks to keep loaded around player
const GENERATION_RADIUS := 5  # Chunks to pre-generate
const UNLOAD_RADIUS := 8  # Chunks beyond this distance are candidates for unloading
const MAX_LOADED_CHUNKS := 50  # Hard limit to prevent memory issues

# State
var loaded_chunks: Dictionary = {}  # Vector3i(x, y, level) -> Chunk
var generating_chunks: Array[Vector3i] = []  # Chunks queued for generation
var world_seed: int = 0

# Systems (will be initialized when available)
var corruption_tracker: CorruptionTracker
# var island_manager: IslandManager  # TODO: Phase 5
# var entity_spawner: EntitySpawner  # TODO: Phase 4
# var level_generator_factory: LevelGeneratorFactory  # TODO: Phase 2

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Initialize corruption tracker
	corruption_tracker = CorruptionTracker.new()

	# Generate world seed
	world_seed = randi()

	Log.system("ChunkManager initialized (seed: %d)" % world_seed)

func _process(_delta: float) -> void:
	# Update chunks around player
	_update_chunks_around_player()

	# Process generation queue
	_process_generation_queue()

	# Unload distant chunks
	_unload_distant_chunks()

# ============================================================================
# CHUNK LOADING
# ============================================================================

func _update_chunks_around_player() -> void:
	"""Queue chunks for loading near player"""
	# TODO: Get player position from Player singleton (when it exists)
	# For now, use a placeholder position
	var player_tile := Vector2i(64, 64)  # Center of world
	var player_level := 0  # Level 0 for now

	var player_chunk := tile_to_chunk(player_tile)

	# Queue generation for nearby chunks
	for y in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
		for x in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
			var chunk_pos := player_chunk + Vector2i(x, y)
			var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, player_level)

			# Skip if already loaded or queued
			if chunk_key in loaded_chunks or chunk_key in generating_chunks:
				continue

			generating_chunks.append(chunk_key)

func _process_generation_queue() -> void:
	"""Generate one chunk per frame to avoid stuttering"""
	if generating_chunks.is_empty():
		return

	var chunk_key: Vector3i = generating_chunks.pop_front()
	var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
	var level_id: int = chunk_key.z

	var chunk := _generate_chunk(chunk_pos, level_id)
	loaded_chunks[chunk_key] = chunk

	# TODO: Notify Grid to render it (Phase 8)
	# if has_node("/root/Game/Grid"):
	#     get_node("/root/Game/Grid").load_chunk(chunk)

	Log.grid("Loaded chunk %s on Level %d (corruption: %.2f)" % [
		chunk_pos,
		level_id,
		corruption_tracker.get_corruption(level_id)
	])

func _generate_chunk(chunk_pos: Vector2i, level_id: int) -> Chunk:
	"""Generate a new chunk

	For Phase 1, this creates a placeholder chunk with walls on edges.
	Later phases will use LevelGenerator for actual maze generation.
	"""
	var chunk := Chunk.new()
	chunk.initialize(chunk_pos, level_id)
	chunk.state = Chunk.State.GENERATING

	# Phase 1: Simple placeholder generation (walls on edges, floor in middle)
	_generate_placeholder_chunk(chunk)

	# TODO: Phase 3 - Use LevelGenerator
	# var generator: LevelGenerator = level_generator_factory.get_generator(level_id)
	# generator.generate_chunk(chunk, world_seed)

	# TODO: Phase 4 - Spawn entities
	# var level_config := generator.get_level_config()
	# entity_spawner.spawn_entities_in_chunk(chunk, level_config)

	# Increase corruption AFTER chunk is generated
	# TODO: Phase 3 - Get corruption config from level generator
	# For now, use hardcoded values (0.01 per chunk, no max)
	corruption_tracker.increase_corruption(level_id, 0.01, 0.0)

	chunk.state = Chunk.State.LOADED
	return chunk

func _generate_placeholder_chunk(chunk: Chunk) -> void:
	"""Generate simple placeholder chunk (Phase 1 only)

	Creates walls on edges, floor in middle.
	"""
	for sy in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sx in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub := chunk.get_sub_chunk(Vector2i(sx, sy))

			for y in range(SubChunk.SIZE):
				for x in range(SubChunk.SIZE):
					# Calculate absolute position within chunk
					var chunk_x := sx * SubChunk.SIZE + x
					var chunk_y := sy * SubChunk.SIZE + y

					# Walls on edges, floor in middle
					var is_edge := chunk_x == 0 or chunk_x == Chunk.SIZE - 1 or \
								   chunk_y == 0 or chunk_y == Chunk.SIZE - 1

					if is_edge:
						sub.set_tile(Vector2i(x, y), SubChunk.TileType.WALL)
					else:
						sub.set_tile(Vector2i(x, y), SubChunk.TileType.FLOOR)

# ============================================================================
# CHUNK UNLOADING
# ============================================================================

func _unload_distant_chunks() -> void:
	"""Unload chunks far from player"""
	if loaded_chunks.size() <= MAX_LOADED_CHUNKS:
		return

	# TODO: Get player position from Player singleton
	var player_tile := Vector2i(64, 64)
	var player_level := 0

	var player_chunk := tile_to_chunk(player_tile)

	var chunks_to_unload: Array[Vector3i] = []

	for chunk_key in loaded_chunks.keys():
		var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
		var chunk_level: int = chunk_key.z

		# Only unload chunks on current level
		if chunk_level != player_level:
			continue

		var distance := player_chunk.distance_to(chunk_pos)
		if distance > UNLOAD_RADIUS:
			chunks_to_unload.append(chunk_key)

	# Unload chunks (TODO: sort by last access time)
	for chunk_key in chunks_to_unload:
		_unload_chunk(chunk_key)

		# Stop if we're back under limit
		if loaded_chunks.size() <= MAX_LOADED_CHUNKS * 0.8:
			break

func _unload_chunk(chunk_key: Vector3i) -> void:
	"""Unload a chunk from memory"""
	var _chunk: Chunk = loaded_chunks[chunk_key]

	# TODO: Phase 7 - Save chunk state if modified (entities killed, items taken)

	# TODO: Phase 8 - Remove from render
	# if has_node("/root/Game/Grid"):
	#     get_node("/root/Game/Grid").unload_chunk(chunk)

	# Remove from memory
	loaded_chunks.erase(chunk_key)

	Log.grid("Unloaded chunk %s" % Vector2i(chunk_key.x, chunk_key.y))

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	"""Convert tile position to chunk position

	Example:
		tile (100, 50) → chunk (0, 0)  # 100/128=0, 50/128=0
		tile (150, 200) → chunk (1, 1)  # 150/128=1, 200/128=1
		tile (-10, -10) → chunk (-1, -1)  # Negative tiles work too
	"""
	return Vector2i(
		floori(float(tile_pos.x) / CHUNK_SIZE),
		floori(float(tile_pos.y) / CHUNK_SIZE)
	)

func chunk_to_world(chunk_pos: Vector2i) -> Vector2i:
	"""Convert chunk position to world tile position (chunk origin)

	Example:
		chunk (0, 0) → tile (0, 0)
		chunk (1, 1) → tile (128, 128)
		chunk (-1, -1) → tile (-128, -128)
	"""
	return chunk_pos * CHUNK_SIZE

func tile_to_local(tile_pos: Vector2i) -> Vector2i:
	"""Convert tile position to local chunk position (0-127)

	Example:
		tile (100, 50) → local (100, 50)
		tile (150, 200) → local (22, 72)  # 150%128=22, 200%128=72
	"""
	return Vector2i(
		posmod(tile_pos.x, CHUNK_SIZE),
		posmod(tile_pos.y, CHUNK_SIZE)
	)

# ============================================================================
# PUBLIC API
# ============================================================================

func get_chunk_at_tile(tile_pos: Vector2i, level_id: int) -> Chunk:
	"""Get chunk containing a tile

	Returns null if chunk is not loaded.
	"""
	var chunk_pos := tile_to_chunk(tile_pos)
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
	return loaded_chunks.get(chunk_key, null)

func get_chunk_at_position(chunk_pos: Vector2i, level_id: int) -> Chunk:
	"""Get chunk at chunk coordinates

	Returns null if chunk is not loaded.
	"""
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
	return loaded_chunks.get(chunk_key, null)

func is_tile_walkable(tile_pos: Vector2i, level_id: int) -> bool:
	"""Check if tile is walkable

	Returns false if chunk is not loaded.
	"""
	var chunk := get_chunk_at_tile(tile_pos, level_id)
	if not chunk:
		return false

	return chunk.is_walkable(tile_pos)

func get_tile_type(tile_pos: Vector2i, level_id: int) -> int:
	"""Get tile type at position

	Returns -1 if chunk is not loaded.
	"""
	var chunk := get_chunk_at_tile(tile_pos, level_id)
	if not chunk:
		return -1

	return chunk.get_tile(tile_pos)

# ============================================================================
# RUN MANAGEMENT
# ============================================================================

func start_new_run(new_seed: int = -1) -> void:
	"""Start a new run, clear all state

	Args:
		new_seed: World seed (-1 for random)
	"""
	if new_seed == -1:
		world_seed = randi()
	else:
		world_seed = new_seed

	loaded_chunks.clear()
	generating_chunks.clear()
	corruption_tracker.reset_all()

	Log.system("New run started (seed: %d)" % world_seed)

# ============================================================================
# DEBUG
# ============================================================================

func get_loaded_chunk_count() -> int:
	"""Get number of currently loaded chunks"""
	return loaded_chunks.size()

func get_corruption(level_id: int) -> float:
	"""Get current corruption for a level"""
	return corruption_tracker.get_corruption(level_id)
