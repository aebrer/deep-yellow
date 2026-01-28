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

## Next available point ID (only used when free list is empty)
var next_id: int = 0

## Free list of recycled point IDs (CRITICAL: prevents unbounded memory growth)
## Without recycling, next_id grows forever as chunks load/unload, causing
## AStar2D internal arrays to grow without bound even if point count stays constant.
var free_ids: Array[int] = []

## Grid reference (set by Grid3D when ready)
var grid: Node = null

func _ready() -> void:
	pass


## Reset the pathfinding graph (for new run/scene reload)
func reset() -> void:
	"""Clear all pathfinding data for a fresh start"""
	astar.clear()
	pos_to_id.clear()
	id_to_pos.clear()
	next_id = 0
	free_ids.clear()
	grid = null


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

## Add all walkable tiles from a chunk to the graph
func _add_chunk_to_graph(chunk_pos: Vector2i) -> void:
	"""Add walkable tiles from a chunk to the navigation graph"""
	const CHUNK_SIZE := 128  # From Chunk.SIZE
	var chunk_world_offset := chunk_pos * CHUNK_SIZE

	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var local_pos := Vector2i(x, y)
			var world_pos := chunk_world_offset + local_pos

			# Check if tile is walkable (any floor type)
			if grid.has_method("get_tile_type"):
				if SubChunk.is_floor_type(grid.get_tile_type(world_pos)):
					_add_point(world_pos)
			elif grid.has_method("is_walkable"):
				if grid.is_walkable(world_pos):
					_add_point(world_pos)

## Add a single point to the graph
func _add_point(pos: Vector2i) -> void:
	"""Add a walkable tile position to the graph"""
	if pos_to_id.has(pos):
		return  # Already added

	# Recycle an ID from the free list if available, otherwise allocate new
	var point_id: int
	if not free_ids.is_empty():
		point_id = free_ids.pop_back()
	else:
		point_id = next_id
		next_id += 1

	astar.add_point(point_id, Vector2(pos.x, pos.y))
	pos_to_id[pos] = point_id
	id_to_pos[point_id] = pos

## Neighbor offsets (pre-allocated to avoid creating new Vector2i per call)
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),   # North
	Vector2i(0, 1),    # South
	Vector2i(-1, 0),   # West
	Vector2i(1, 0),    # East
	Vector2i(-1, -1),  # Northwest
	Vector2i(1, -1),   # Northeast
	Vector2i(-1, 1),   # Southwest
	Vector2i(1, 1)     # Southeast
]

## Connect a point to its walkable neighbors (8-directional)
func _connect_neighbors(pos: Vector2i, point_id: int) -> void:
	"""Connect a point to its 8-directional neighbors (diagonals have same cost)"""
	# Use pre-allocated offsets to avoid creating 8 Vector2i per call
	for offset in NEIGHBOR_OFFSETS:
		var neighbor_pos := pos + offset
		if pos_to_id.has(neighbor_pos):
			var neighbor_id: int = pos_to_id[neighbor_pos]
			# Bidirectional connection with cost 1.0 (uniform - diagonals same as cardinals)
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
		# Sample multiple points in the adjacent chunk for more reliable connectivity checking
		# Try center, and 4 quadrants (more robust than single center point)
		var sample_offsets := [
			Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2),      # Center
			Vector2i(CHUNK_SIZE / 4, CHUNK_SIZE / 4),      # Top-left quadrant
			Vector2i(3 * CHUNK_SIZE / 4, CHUNK_SIZE / 4),  # Top-right quadrant
			Vector2i(CHUNK_SIZE / 4, 3 * CHUNK_SIZE / 4),  # Bottom-left quadrant
			Vector2i(3 * CHUNK_SIZE / 4, 3 * CHUNK_SIZE / 4), # Bottom-right quadrant
		]

		var chunk_reachable := false
		for offset in sample_offsets:
			var sample_pos: Vector2i = adj_chunk * CHUNK_SIZE + offset

			# Find nearest walkable tile near this sample point
			var nearest: Vector2i = _find_nearest_walkable_near(sample_pos, 16)
			if nearest == Vector2i(-1, -1):
				continue  # No walkable tile near this sample point

			# Check if we can path from spawn to this point
			if are_positions_connected(pos, nearest):
				chunk_reachable = true
				break  # Found a reachable point in this chunk

		if chunk_reachable:
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

## Add a single walkable tile to the graph (for border hallway cutting)
func add_walkable_tile(world_pos: Vector2i) -> void:
	"""Add a single walkable tile to the navigation graph.

	Called when border hallway cutting creates new floor tiles in already-loaded
	chunks. This ensures entities spawned on those tiles can pathfind correctly.

	Args:
		world_pos: World grid position to add
	"""
	if pos_to_id.has(world_pos):
		return  # Already in graph

	_add_point(world_pos)

	# Connect to neighbors (must happen after point is added)
	if pos_to_id.has(world_pos):
		_connect_neighbors(world_pos, pos_to_id[world_pos])

# ============================================================================
# INCREMENTAL GRAPH UPDATES (for chunk load/unload)
# ============================================================================

func add_chunk(chunk: Chunk) -> void:
	"""Add walkable tiles from a chunk to the navigation graph

	Called when a chunk finishes loading. Adds all floor tiles and connects
	them to existing neighbors (including tiles from adjacent chunks).

	Args:
		chunk: The chunk that was just loaded
	"""
	if not grid:
		Log.warn(Log.Category.GRID, "PathfindingManager: No grid reference, cannot add chunk")
		return

	# Collect walkable positions in first pass, then connect in second pass
	# This avoids iterating over ALL tiles twice (only walkable tiles twice)
	var walkable_positions: Array[Vector2i] = []

	# Pre-calculate chunk offset once (avoid recalculating per tile)
	var chunk_offset: Vector2i = chunk.position * Chunk.SIZE

	# Add all walkable tiles from this chunk
	for subchunk in chunk.sub_chunks:
		# Pre-calculate subchunk offset once per subchunk
		var subchunk_offset: Vector2i = chunk_offset + subchunk.local_position * subchunk.SIZE

		for y in range(subchunk.SIZE):
			for x in range(subchunk.SIZE):
				var tile_type = subchunk.get_tile(Vector2i(x, y))
				if SubChunk.is_floor_type(tile_type):
					var world_pos: Vector2i = subchunk_offset + Vector2i(x, y)
					if not pos_to_id.has(world_pos):
						_add_point(world_pos)
						walkable_positions.append(world_pos)

	# Connect all new points to their neighbors (including cross-chunk connections)
	# Only iterate over walkable positions, not all 16k tiles
	for world_pos in walkable_positions:
		if pos_to_id.has(world_pos):
			_connect_neighbors(world_pos, pos_to_id[world_pos])

	# Note: Logging removed for performance - uncomment for debugging
	# var points_after := astar.get_point_count()
	# var points_added := points_after - points_before
	# Log.system("  Pathfinding: added %d points (total: %d, free IDs: %d, next_id: %d)" % [
	# 	points_added, points_after, free_ids.size(), next_id
	# ])

func remove_chunk(chunk: Chunk) -> void:
	"""Remove all tiles from a chunk from the navigation graph

	Called when a chunk is about to be unloaded. Removes points and their
	connections. Adjacent chunks remain connected to each other.

	Args:
		chunk: The chunk being unloaded
	"""
	# Collect all point IDs to remove (can't modify dict while iterating)
	var points_to_remove: Array[int] = []

	for subchunk in chunk.sub_chunks:
		for y in range(subchunk.SIZE):
			for x in range(subchunk.SIZE):
				var world_pos = chunk.position * Chunk.SIZE + subchunk.local_position * subchunk.SIZE + Vector2i(x, y)
				if pos_to_id.has(world_pos):
					points_to_remove.append(pos_to_id[world_pos])

	# Remove points (AStar2D automatically removes connections)
	# Add IDs to free list for recycling (CRITICAL: prevents unbounded growth)
	for point_id in points_to_remove:
		var pos = id_to_pos[point_id]
		astar.remove_point(point_id)
		pos_to_id.erase(pos)
		id_to_pos.erase(point_id)
		free_ids.append(point_id)  # Recycle this ID

	# Note: Logging removed for performance - uncomment for debugging
	# var build_time := Time.get_ticks_msec() - start_time
	# Log.system("Pathfinding: removed %d points from chunk %s (total: %d, free IDs: %d)" % [
	# 	removed_count, chunk.position, astar.get_point_count(), free_ids.size()
	# ])

func set_grid_reference(grid_ref: Node) -> void:
	"""Set the grid reference for walkability queries

	Args:
		grid_ref: Reference to Grid3D
	"""
	grid = grid_ref
