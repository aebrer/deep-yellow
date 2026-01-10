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
	CEILING = 4,  # Added for multi-layer support (ceilings at layer Y=1)
}

# Position
var local_position: Vector2i  # Position within parent chunk (0-7, 0-7)
var world_position: Vector2i  # Absolute tile position in world

# Data
var tile_data: Array[Array] = []  # 16×16 tile types (layer 0)
var ceiling_data: Array[Array] = []  # 16×16 ceiling tiles (layer 1)
var world_items: Array[Dictionary] = []  # Serialized WorldItem data (persists across chunk load/unload)
var world_entities: Array[WorldEntity] = []  # WorldEntity objects (persist across chunk load/unload)

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	# Initialize 16×16 grid with walls (layer 0)
	for y in range(SIZE):
		var row: Array[int] = []
		for x in range(SIZE):
			row.append(TileType.WALL)
		tile_data.append(row)

	# Initialize ceiling layer (layer 1) - empty by default
	for y in range(SIZE):
		var row: Array[int] = []
		for x in range(SIZE):
			row.append(-1)  # -1 = no ceiling tile
		ceiling_data.append(row)

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

func get_tile_at_layer(local_pos: Vector2i, layer: int) -> int:
	"""Get tile type at local position and layer

	Args:
		local_pos: Position within sub-chunk (0-15, 0-15)
		layer: 0 = floor/walls, 1 = ceilings

	Returns:
		Tile type or -1 if invalid/empty
	"""
	if not _is_in_bounds(local_pos):
		return -1

	if layer == 0:
		return tile_data[local_pos.y][local_pos.x]
	elif layer == 1:
		return ceiling_data[local_pos.y][local_pos.x]
	else:
		return -1

func set_tile_at_layer(local_pos: Vector2i, layer: int, tile_type: int) -> void:
	"""Set tile type at local position and layer

	Args:
		local_pos: Position within sub-chunk (0-15, 0-15)
		layer: 0 = floor/walls, 1 = ceilings
		tile_type: TileType value
	"""
	if not _is_in_bounds(local_pos):
		return

	if layer == 0:
		tile_data[local_pos.y][local_pos.x] = tile_type
	elif layer == 1:
		ceiling_data[local_pos.y][local_pos.x] = tile_type

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
# WORLD ITEM MANAGEMENT
# ============================================================================

func add_world_item(world_item_data: Dictionary) -> void:
	"""Add serialized world item data to this sub-chunk

	Args:
		world_item_data: Serialized WorldItem (from WorldItem.to_dict())
	"""
	world_items.append(world_item_data)

func remove_world_item(world_position: Vector2i) -> bool:
	"""Remove world item at position (when picked up)

	Args:
		world_position: World tile coordinates

	Returns:
		true if item was found and removed
	"""
	for i in range(world_items.size()):
		var item_data = world_items[i]
		var pos_data = item_data.get("world_position", {"x": 0, "y": 0})
		var item_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

		if item_pos == world_position:
			world_items.remove_at(i)
			return true

	return false

func get_world_items_in_subchunk() -> Array[Dictionary]:
	"""Get all world items in this sub-chunk

	Returns:
		Array of serialized WorldItem data
	"""
	return world_items.duplicate()

# ============================================================================
# WORLD ENTITY MANAGEMENT
# ============================================================================

func add_world_entity(entity: WorldEntity) -> void:
	"""Add a WorldEntity to this sub-chunk

	Args:
		entity: WorldEntity object to store
	"""
	world_entities.append(entity)

func remove_world_entity(world_position: Vector2i) -> bool:
	"""Remove world entity at position (when killed/despawned)

	Args:
		world_position: World tile coordinates

	Returns:
		true if entity was found and removed
	"""
	for i in range(world_entities.size()):
		if world_entities[i].world_position == world_position:
			world_entities.remove_at(i)
			return true
	return false

func get_entity_at(world_position: Vector2i) -> WorldEntity:
	"""Get entity at world position

	Args:
		world_position: World tile coordinates

	Returns:
		WorldEntity at position, or null if none
	"""
	for entity in world_entities:
		if entity.world_position == world_position:
			return entity
	return null

func get_living_entities() -> Array[WorldEntity]:
	"""Get all living (non-dead) entities in this sub-chunk

	Returns:
		Array of WorldEntity objects that are alive
	"""
	var living: Array[WorldEntity] = []
	for entity in world_entities:
		if not entity.is_dead:
			living.append(entity)
	return living

# ============================================================================
# UTILITY
# ============================================================================

func _to_string() -> String:
	return "SubChunk(local=%s, world=%s, walkable=%d, items=%d, entities=%d)" % [
		local_position,
		world_position,
		get_walkable_count(),
		world_items.size(),
		world_entities.size()
	]
