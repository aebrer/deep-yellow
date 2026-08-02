extends Node

# Pathfinding helpers for player navigation

const TILE_FLOOR = 0
const TILE_WALL = 1
const TILE_CLOSED_DOOR = 2
const TILE_OPEN_DOOR = 3

var auto_exploring: bool = false

func is_tile_passable(tile_id: int) -> bool:
	match tile_id:
		TILE_WALL:
			return false
		TILE_CLOSED_DOOR:
			if auto_exploring:
				return true
			return false
		_:
			return true

func get_path(start: Vector2i, end: Vector2i) -> PackedVector2iArray:
	var path: PackedVector2iArray = []

	if not is_tile_passable(get_tile_at(start)) or not is_tile_passable(get_tile_at(end)):
		return path

	# BFS pathfinding
	var queue = [start]
	var visited = {start: null}

	while not queue.is_empty():
		var current = queue.pop_front()

		if current == end:
			break

		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor = current + dir
			if is_tile_in_bounds(neighbor) and not visited.has(neighbor) and is_tile_passable(get_tile_at(neighbor)):
				queue.append(neighbor)
				visited[neighbor] = current

	# Reconstruct path
	var node = end
	while node != start:
		path.append(node)
		node = visited.get(node, start)

	path.reverse()
	return path

func get_tile_at(pos: Vector2i) -> int:
	return 0

func is_tile_in_bounds(pos: Vector2i) -> bool:
	return true
