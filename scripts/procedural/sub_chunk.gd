class_name SubChunk extends RefCounted
## Represents a 16×16 tile section within a chunk
##
## SubChunks are the fundamental unit of entity spawning and maze generation.
## Each 128×128 chunk contains 64 sub-chunks arranged in an 8×8 grid.

# Constants
const SIZE := 16

# Tile types
enum TileType {
	FLOOR = 0,
	WALL = 1,
	DOOR = 2,
	EXIT_STAIRS = 3,
}

# Position
var local_position: Vector2i  # Position within parent chunk (0-7, 0-7)
var world_position: Vector2i  # Absolute tile position in world

# Data
var tile_data: Array[Array] = []  # 16×16 tile types
var entities: Array[int] = []  # Entity IDs spawned in this sub-chunk

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	# Initialize 16×16 grid with walls
	for y in range(SIZE):
		var row: Array[int] = []
		for x in range(SIZE):
			row.append(TileType.WALL)
		tile_data.append(row)

# ============================================================================
# TILE ACCESS
# ============================================================================

func get_tile(local_pos: Vector2i) -> int:
	"""Get tile type at local position (0-15, 0-15)"""
	if not _is_in_bounds(local_pos):
		return -1
	return tile_data[local_pos.y][local_pos.x]

func set_tile(local_pos: Vector2i, tile_type: int) -> void:
	"""Set tile type at local position (0-15, 0-15)"""
	if not _is_in_bounds(local_pos):
		return
	tile_data[local_pos.y][local_pos.x] = tile_type

func is_walkable(local_pos: Vector2i) -> bool:
	"""Check if tile is walkable (floor or door)"""
	var tile := get_tile(local_pos)
	return tile == TileType.FLOOR or tile == TileType.DOOR or tile == TileType.EXIT_STAIRS

# ============================================================================
# UTILITY
# ============================================================================

func get_random_walkable_position(rng: RandomNumberGenerator) -> Vector2i:
	"""Get random walkable tile in this sub-chunk

	Returns Vector2i(-1, -1) if no walkable tiles found.
	"""
	var walkable: Array[Vector2i] = []

	for y in range(SIZE):
		for x in range(SIZE):
			if is_walkable(Vector2i(x, y)):
				walkable.append(Vector2i(x, y))

	if walkable.is_empty():
		return Vector2i(-1, -1)

	return walkable[rng.randi() % walkable.size()]

func get_walkable_count() -> int:
	"""Count walkable tiles in this sub-chunk"""
	var count := 0
	for y in range(SIZE):
		for x in range(SIZE):
			if is_walkable(Vector2i(x, y)):
				count += 1
	return count

func _is_in_bounds(pos: Vector2i) -> bool:
	"""Check if position is within sub-chunk bounds"""
	return pos.x >= 0 and pos.x < SIZE and pos.y >= 0 and pos.y < SIZE

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	return "SubChunk(local=%s, world=%s, walkable=%d)" % [
		local_position,
		world_position,
		get_walkable_count()
	]
