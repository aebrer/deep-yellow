extends Node
## Tracks which tiles the player has perceived (been within perception range of)
##
## Used by auto-explore to determine which tiles still need to be visited.
## Tiles are marked as explored when the player is within perception range.
## Uses BFS on PathfindingManager's walkable graph to find nearest unexplored tile.

## Explored tiles: Vector2i → true
var explored_tiles: Dictionary = {}

## Sentinel value for "no unexplored tile found"
const NO_TARGET := Vector2i(-1, -1)

## Mark all walkable tiles within perception range of player position as explored
func mark_explored(player_pos: Vector2i, perception_range: float) -> void:
	var range_int := int(perception_range)
	for dy in range(-range_int, range_int + 1):
		for dx in range(-range_int, range_int + 1):
			var pos := player_pos + Vector2i(dx, dy)
			if explored_tiles.has(pos):
				continue
			# Only mark if within circular range and walkable
			if Vector2(dx, dy).length() <= perception_range:
				if Pathfinding.has_point(pos):
					explored_tiles[pos] = true

## Find the nearest unexplored walkable tile using BFS on the pathfinding graph.
## Prefers tiles in the player's current chunk before exploring other chunks.
func find_nearest_unexplored(from: Vector2i) -> Vector2i:
	if not Pathfinding.has_point(from):
		return NO_TARGET

	# Two-pass BFS: first within current chunk, then unrestricted
	var player_chunk := Vector2i(
		floori(float(from.x) / Chunk.SIZE),
		floori(float(from.y) / Chunk.SIZE)
	)

	# Pass 1: BFS restricted to current chunk
	var result := _bfs_find_unexplored(from, player_chunk)
	if result != NO_TARGET:
		return result

	# Pass 2: Unrestricted BFS (cross chunk boundaries)
	return _bfs_find_unexplored(from, Vector2i(-999999, -999999))

func _bfs_find_unexplored(from: Vector2i, restrict_chunk: Vector2i) -> Vector2i:
	"""BFS for nearest unexplored tile. If restrict_chunk is a valid chunk,
	only expand within that chunk. Use an impossible value to disable restriction."""
	var unrestricted := (restrict_chunk == Vector2i(-999999, -999999))

	var queue: Array[Vector2i] = [from]
	var visited: Dictionary = {from: true}

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		# Check if this tile is unexplored
		if not explored_tiles.has(current):
			# In restricted mode, only return tiles in the target chunk
			if unrestricted:
				return current
			var tile_chunk := Vector2i(
				floori(float(current.x) / Chunk.SIZE),
				floori(float(current.y) / Chunk.SIZE)
			)
			if tile_chunk == restrict_chunk:
				return current

		# Expand neighbors using pathfinding graph's neighbor offsets
		for offset in Pathfinding.NEIGHBOR_OFFSETS:
			var neighbor := current + offset
			if visited.has(neighbor):
				continue
			if not Pathfinding.has_point(neighbor):
				continue

			# In restricted mode, don't expand into other chunks
			if not unrestricted:
				var neighbor_chunk := Vector2i(
					floori(float(neighbor.x) / Chunk.SIZE),
					floori(float(neighbor.y) / Chunk.SIZE)
				)
				if neighbor_chunk != restrict_chunk:
					continue

			# Diagonal wall-gap check (same as pathfinding)
			if abs(offset.x) == 1 and abs(offset.y) == 1:
				var has_x := Pathfinding.has_point(current + Vector2i(offset.x, 0))
				var has_y := Pathfinding.has_point(current + Vector2i(0, offset.y))
				if not has_x and not has_y:
					continue

			visited[neighbor] = true
			queue.append(neighbor)

	return NO_TARGET

## Check if a position has been explored
func is_explored(pos: Vector2i) -> bool:
	return explored_tiles.has(pos)

## Reset all exploration data (called on level change)
func reset() -> void:
	explored_tiles.clear()
