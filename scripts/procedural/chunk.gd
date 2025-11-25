class_name Chunk extends RefCounted
## Represents a 128×128 tile chunk containing 64 sub-chunks
##
## Chunks are the primary unit of world generation and loading.
## Each chunk contains an 8×8 grid of 16×16 sub-chunks.

# Constants
const SIZE := 128
const SUB_CHUNK_SIZE := 16
const SUB_CHUNKS_PER_SIDE := 8  # 128 / 16 = 8

# Position and identification
var position: Vector2i  # Chunk coordinates (not tile coordinates)
var level_id: int = 0  # Which Backrooms level (0, 1, 2...)
var island_id: int = -1  # Which maze island (-1 = not assigned)

# Data
var sub_chunks: Array[SubChunk] = []  # 64 sub-chunks (8×8 grid)
var metadata: Dictionary = {}  # Light positions, decorations, etc.

# State
var state: State = State.UNGENERATED

enum State {
	UNGENERATED,
	GENERATING,
	LOADED,
	UNLOADING,
}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	# Initialize 64 sub-chunks (8×8 grid)
	for sy in range(SUB_CHUNKS_PER_SIDE):
		for sx in range(SUB_CHUNKS_PER_SIDE):
			var sub := SubChunk.new()
			sub.local_position = Vector2i(sx, sy)
			# World position will be set when chunk position is assigned
			sub_chunks.append(sub)

func initialize(chunk_pos: Vector2i, level: int) -> void:
	"""Initialize chunk with position and level"""
	position = chunk_pos
	level_id = level

	# Update sub-chunk world positions
	for sub in sub_chunks:
		sub.world_position = position * SIZE + sub.local_position * SUB_CHUNK_SIZE

# ============================================================================
# SUB-CHUNK ACCESS
# ============================================================================

func get_sub_chunk(local_pos: Vector2i) -> SubChunk:
	"""Get sub-chunk at local position (0-7, 0-7)

	Returns null if out of bounds.
	"""
	if not _is_sub_chunk_in_bounds(local_pos):
		return null

	var index := local_pos.y * SUB_CHUNKS_PER_SIDE + local_pos.x
	return sub_chunks[index]

func get_sub_chunk_at_tile(tile_pos: Vector2i) -> SubChunk:
	"""Get sub-chunk containing a specific world tile position

	Returns null if tile is not in this chunk.
	"""
	# Convert world tile to local tile within chunk
	var local_tile := tile_pos - (position * SIZE)

	# Convert local tile to sub-chunk position
	var sub_local := Vector2i(
		local_tile.x / SUB_CHUNK_SIZE,
		local_tile.y / SUB_CHUNK_SIZE
	)

	return get_sub_chunk(sub_local)

# ============================================================================
# TILE ACCESS
# ============================================================================

func get_tile(tile_pos: Vector2i) -> int:
	"""Get tile at world position

	Returns -1 if position is not in this chunk.
	"""
	var sub := get_sub_chunk_at_tile(tile_pos)
	if not sub:
		return -1

	# Convert world tile to local tile within sub-chunk
	var local_tile := tile_pos - (position * SIZE)
	var sub_local_tile := Vector2i(
		posmod(local_tile.x, SUB_CHUNK_SIZE),
		posmod(local_tile.y, SUB_CHUNK_SIZE)
	)

	return sub.get_tile(sub_local_tile)

func set_tile(tile_pos: Vector2i, tile_type: int) -> void:
	"""Set tile at world position"""
	var sub := get_sub_chunk_at_tile(tile_pos)
	if not sub:
		return

	var local_tile := tile_pos - (position * SIZE)
	var sub_local_tile := Vector2i(
		local_tile.x % SUB_CHUNK_SIZE,
		local_tile.y % SUB_CHUNK_SIZE
	)

	sub.set_tile(sub_local_tile, tile_type)

func get_tile_at_layer(tile_pos: Vector2i, layer: int) -> int:
	"""Get tile at world position and layer

	Args:
		tile_pos: World tile position
		layer: 0 = floor/walls, 1 = ceilings

	Returns:
		Tile type or -1 if invalid
	"""
	var sub := get_sub_chunk_at_tile(tile_pos)
	if not sub:
		return -1

	var local_tile := tile_pos - (position * SIZE)
	var sub_local_tile := Vector2i(
		posmod(local_tile.x, SUB_CHUNK_SIZE),
		posmod(local_tile.y, SUB_CHUNK_SIZE)
	)

	return sub.get_tile_at_layer(sub_local_tile, layer)

func set_tile_at_layer(tile_pos: Vector2i, layer: int, tile_type: int) -> void:
	"""Set tile at world position and layer

	Args:
		tile_pos: World tile position
		layer: 0 = floor/walls, 1 = ceilings
		tile_type: TileType value
	"""
	var sub := get_sub_chunk_at_tile(tile_pos)
	if not sub:
		return

	var local_tile := tile_pos - (position * SIZE)
	var sub_local_tile := Vector2i(
		local_tile.x % SUB_CHUNK_SIZE,
		local_tile.y % SUB_CHUNK_SIZE
	)

	sub.set_tile_at_layer(sub_local_tile, layer, tile_type)

func is_walkable(tile_pos: Vector2i) -> bool:
	"""Check if tile at world position is walkable"""
	var sub := get_sub_chunk_at_tile(tile_pos)
	if not sub:
		return false

	var local_tile := tile_pos - (position * SIZE)
	var sub_local_tile := Vector2i(
		posmod(local_tile.x, SUB_CHUNK_SIZE),
		posmod(local_tile.y, SUB_CHUNK_SIZE)
	)

	return sub.is_walkable(sub_local_tile)

# ============================================================================
# UTILITY
# ============================================================================

func get_walkable_count() -> int:
	"""Count total walkable tiles in this chunk"""
	var count := 0
	for sub in sub_chunks:
		count += sub.get_walkable_count()
	return count

func get_entity_count() -> int:
	"""Count total entities in this chunk"""
	var count := 0
	for sub in sub_chunks:
		count += sub.entities.size()
	return count

func _is_sub_chunk_in_bounds(pos: Vector2i) -> bool:
	"""Check if sub-chunk position is within bounds"""
	return pos.x >= 0 and pos.x < SUB_CHUNKS_PER_SIDE and \
		   pos.y >= 0 and pos.y < SUB_CHUNKS_PER_SIDE

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	return "Chunk(pos=%s, level=%d, island=%d, walkable=%d, entities=%d)" % [
		position,
		level_id,
		island_id,
		get_walkable_count(),
		get_entity_count()
	]
