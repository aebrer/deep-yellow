extends Node
## Pathfinding manager using AStar2D for turn-based grid navigation
##
## Provides pathfinding for:
## - Entity AI (enemies chase player)
## - Spawn point validation (can reach chunk edges)
## - Connectivity checking (chunk traversability)
## - Future features (ability targeting, hints)

## AStar2D instance for pathfinding
var astar := AStar2D.new()

## Mapping from grid position to AStar point ID
var pos_to_id: Dictionary = {}  # Vector2i -> int

## Mapping from AStar point ID to grid position
var id_to_pos: Dictionary = {}  # int -> Vector2i

## Next available point ID
var next_id: int = 0

## Grid reference (set by Grid3D when ready)
var grid: Node = null

func _ready() -> void:
	Log.system("PathfindingManager initialized")

## Build navigation graph from walkable tiles in a chunk
func build_navigation_graph(chunk_positions: Array, grid_ref: Node) -> void:
	"""Build AStar2D graph from walkable tiles in specified chunks

	Args:
		chunk_positions: Array of Vector2i chunk positions to include
		grid_ref: Reference to Grid3D for tile queries
	"""
	grid = grid_ref

	# Clear existing graph
	astar.clear()
	pos_to_id.clear()
	id_to_pos.clear()
	next_id = 0

	var start_time := Time.get_ticks_msec()

	# Add all walkable tiles as points
	for chunk_pos in chunk_positions:
		_add_chunk_to_graph(chunk_pos)

	# Connect adjacent walkable tiles
	for point_id in astar.get_point_ids():
		var pos: Vector2i = id_to_pos[point_id]
		_connect_neighbors(pos, point_id)

	var build_time := Time.get_ticks_msec() - start_time
	Log.system("PathfindingManager: Built graph with %d points in %dms" % [astar.get_point_count(), build_time])

## Add all walkable tiles from a chunk to the graph
func _add_chunk_to_graph(chunk_pos: Vector2i) -> void:
	"""Add walkable tiles from a chunk to the navigation graph"""
	const CHUNK_SIZE := 128  # From Chunk.SIZE
	var chunk_world_offset := chunk_pos * CHUNK_SIZE

	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var local_pos := Vector2i(x, y)
			var world_pos := chunk_world_offset + local_pos

			# Check if tile is walkable (FLOOR = 0)
			if grid.has_method("get_tile_type"):
				if grid.get_tile_type(world_pos) == 0:  # FLOOR
					_add_point(world_pos)
			elif grid.has_method("is_walkable"):
				if grid.is_walkable(world_pos):
					_add_point(world_pos)

## Add a single point to the graph
func _add_point(pos: Vector2i) -> void:
	"""Add a walkable tile position to the graph"""
	if pos_to_id.has(pos):
		return  # Already added

	var point_id := next_id
	next_id += 1

	astar.add_point(point_id, Vector2(pos.x, pos.y))
	pos_to_id[pos] = point_id
	id_to_pos[point_id] = pos

## Connect a point to its walkable neighbors (4-directional)
func _connect_neighbors(pos: Vector2i, point_id: int) -> void:
	"""Connect a point to its 4-directional neighbors"""
	var neighbors := [
		pos + Vector2i(0, -1),  # North
		pos + Vector2i(0, 1),   # South
		pos + Vector2i(-1, 0),  # West
		pos + Vector2i(1, 0)    # East
	]

	for neighbor_pos in neighbors:
		if pos_to_id.has(neighbor_pos):
			var neighbor_id: int = pos_to_id[neighbor_pos]
			# Bidirectional connection with cost 1.0 (uniform grid)
			if not astar.are_points_connected(point_id, neighbor_id):
				astar.connect_points(point_id, neighbor_id, true)

## Find path from start to goal
func find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	"""Find shortest path between two grid positions

	Returns:
		PackedVector2Array of positions (empty if no path exists)
	"""
	if not pos_to_id.has(from) or not pos_to_id.has(to):
		return PackedVector2Array()  # One or both positions not walkable

	var from_id: int = pos_to_id[from]
	var to_id: int = pos_to_id[to]

	var path := astar.get_point_path(from_id, to_id)

	# Convert Vector2 back to Vector2i for grid coordinates
	var grid_path := PackedVector2Array()
	for point in path:
		grid_path.append(point)

	return grid_path

## Check if two positions are connected (reachable)
func are_positions_connected(from: Vector2i, to: Vector2i) -> bool:
	"""Check if there's a path between two positions"""
	if not pos_to_id.has(from) or not pos_to_id.has(to):
		return false

	var from_id: int = pos_to_id[from]
	var to_id: int = pos_to_id[to]

	# AStar2D doesn't have direct connectivity check, so get path
	var path := astar.get_id_path(from_id, to_id)
	return path.size() > 0

## Get distance between two positions (in tiles)
func get_path_distance(from: Vector2i, to: Vector2i) -> float:
	"""Get path distance between two positions

	Returns:
		Distance in tiles, or -1 if no path exists
	"""
	if not pos_to_id.has(from) or not pos_to_id.has(to):
		return -1.0

	var from_id: int = pos_to_id[from]
	var to_id: int = pos_to_id[to]

	var path := astar.get_id_path(from_id, to_id)
	if path.size() == 0:
		return -1.0

	# Path includes start and end, so distance is path.size() - 1
	return float(path.size() - 1)

## Check if a position can reach adjacent chunks (better than edge checking for mazes)
func can_reach_chunk_edges(pos: Vector2i, chunk_pos: Vector2i, min_adjacent: int = 2) -> bool:
	"""Check if spawn position can reach adjacent chunks (better for maze-like levels)

	Instead of checking edges (which might be walled off), checks if spawn can reach
	neighboring chunks. This ensures player isn't stuck in an isolated dead-end.

	Args:
		pos: Grid position to test
		chunk_pos: Current chunk position
		min_adjacent: Minimum adjacent chunks that must be reachable (default 2/4)

	Returns:
		true if position can reach at least min_adjacent neighboring chunks
	"""
	const CHUNK_SIZE := 128

	# First check: spawn must be walkable itself (not in a wall)
	if not pos_to_id.has(pos):
		return false

	# Define adjacent chunk positions (N, S, W, E)
	var adjacent_chunks := [
		chunk_pos + Vector2i(0, -1),  # North
		chunk_pos + Vector2i(0, 1),   # South
		chunk_pos + Vector2i(-1, 0),  # West
		chunk_pos + Vector2i(1, 0)    # East
	]

	# Count how many adjacent chunks are reachable
	var reachable_count := 0

	for adj_chunk in adjacent_chunks:
		# Sample a point near the center of the adjacent chunk
		var adj_center: Vector2i = adj_chunk * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)

		# Find nearest walkable tile in that chunk (within 32 tiles of center)
		var nearest: Vector2i = _find_nearest_walkable_near(adj_center, 32)
		if nearest == Vector2i(-1, -1):
			continue  # No walkable tile in this adjacent chunk (might not be loaded yet)

		# Check if we can path from spawn to this adjacent chunk
		if are_positions_connected(pos, nearest):
			reachable_count += 1

	return reachable_count >= min_adjacent

## Find nearest walkable tile on a chunk edge
func _find_nearest_walkable_on_edge(sample: Vector2i, chunk_offset: Vector2i, size: int) -> Vector2i:
	"""Find nearest walkable tile on chunk edge near sample point"""
	# Determine which edge we're on
	var local := sample - chunk_offset

	# Search along the edge for a walkable tile
	if local.y == 0:  # North edge
		for x in range(size):
			var test_pos := chunk_offset + Vector2i(x, 0)
			if pos_to_id.has(test_pos):
				return test_pos
	elif local.y == size - 1:  # South edge
		for x in range(size):
			var test_pos := chunk_offset + Vector2i(x, size - 1)
			if pos_to_id.has(test_pos):
				return test_pos
	elif local.x == 0:  # West edge
		for y in range(size):
			var test_pos := chunk_offset + Vector2i(0, y)
			if pos_to_id.has(test_pos):
				return test_pos
	elif local.x == size - 1:  # East edge
		for y in range(size):
			var test_pos := chunk_offset + Vector2i(size - 1, y)
			if pos_to_id.has(test_pos):
				return test_pos

	return Vector2i(-1, -1)  # No walkable tile found on edge

## Find nearest walkable tile near a position (spiral search)
func _find_nearest_walkable_near(center: Vector2i, max_radius: int) -> Vector2i:
	"""Find nearest walkable tile within max_radius of center using spiral search"""
	# Check center first
	if pos_to_id.has(center):
		return center

	# Spiral search outward from center
	for radius in range(1, max_radius + 1):
		# Check all tiles at this radius (Manhattan distance)
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) + abs(dy) != radius:
					continue  # Only check tiles exactly at this radius

				var test_pos := center + Vector2i(dx, dy)
				if pos_to_id.has(test_pos):
					return test_pos

	return Vector2i(-1, -1)  # No walkable tile found within radius

## Get all points in the graph (for debugging)
func get_point_count() -> int:
	"""Get number of walkable points in the graph"""
	return astar.get_point_count()

## Check if a position is in the graph
func has_point(pos: Vector2i) -> bool:
	"""Check if a position is walkable and in the graph"""
	return pos_to_id.has(pos)
