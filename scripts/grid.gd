class_name Grid
extends Node2D
## Grid management - handles map data and tile rendering
##
## Manages:
## - Grid data (walkable tiles, walls, etc.)
## - Viewport culling (only render visible tiles)
## - Tile rendering with ASCII/emoji placeholders

const TILE_SIZE := 32  # pixels per tile
const RENDER_DISTANCE := 20  # Only render tiles within this distance

## Grid size in tiles
var grid_size: Vector2i

## Grid data - 2D array (0 = floor, 1 = wall)
var data: Array[Array] = []

## Rendered tiles cache
var rendered_tiles: Dictionary = {}  # Vector2i -> Label

## Container for tile nodes
@onready var tile_container: Node2D = $TileContainer

func _ready() -> void:
	if not has_node("TileContainer"):
		var container = Node2D.new()
		container.name = "TileContainer"
		add_child(container)

func initialize(size: Vector2i) -> void:
	"""Initialize grid with given size"""
	grid_size = size
	data = []

	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			# Walls on edges, floor elsewhere
			if x == 0 or x == grid_size.x - 1 or y == 0 or y == grid_size.y - 1:
				row.append(1)  # Wall
			else:
				row.append(0)  # Floor
		data.append(row)

	# Add some test walls
	if grid_size.x > 20 and grid_size.y > 20:
		data[10][10] = 1
		data[10][11] = 1
		if grid_size.x > 100:
			data[50][50] = 1
			data[100][100] = 1

	print("[Grid] Initialized: %d x %d" % [grid_size.x, grid_size.y])

func is_in_bounds(pos: Vector2i) -> bool:
	"""Check if position is within grid bounds"""
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y

func is_walkable(pos: Vector2i) -> bool:
	"""Check if position is walkable (not wall, in bounds)"""
	if not is_in_bounds(pos):
		return false
	return data[pos.y][pos.x] == 0

func render_around_position(center_pos: Vector2i) -> void:
	"""Render tiles around a center position (viewport culling)"""
	var half_dist := RENDER_DISTANCE / 2

	# Calculate visible bounds
	var min_x := maxi(0, center_pos.x - half_dist)
	var max_x := mini(grid_size.x - 1, center_pos.x + half_dist)
	var min_y := maxi(0, center_pos.y - half_dist)
	var max_y := mini(grid_size.y - 1, center_pos.y + half_dist)

	# Remove tiles that are now out of range
	var tiles_to_remove: Array[Vector2i] = []
	for tile_pos in rendered_tiles.keys():
		if tile_pos.x < min_x or tile_pos.x > max_x or tile_pos.y < min_y or tile_pos.y > max_y:
			tiles_to_remove.append(tile_pos)

	for tile_pos in tiles_to_remove:
		rendered_tiles[tile_pos].queue_free()
		rendered_tiles.erase(tile_pos)

	# Add new tiles that are now in range
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile_pos := Vector2i(x, y)
			if tile_pos in rendered_tiles:
				continue  # Already rendered

			_create_tile(tile_pos)

func _create_tile(tile_pos: Vector2i) -> void:
	"""Create a single tile at position"""
	var tile_label := Label.new()
	tile_label.position = Vector2(tile_pos.x * TILE_SIZE, tile_pos.y * TILE_SIZE)
	tile_label.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Set tile appearance based on type
	if data[tile_pos.y][tile_pos.x] == 1:  # Wall
		tile_label.text = "█"
		tile_label.modulate = Color(0.3, 0.3, 0.2)  # Brownish yellow (Backrooms aesthetic)
	else:  # Floor
		tile_label.text = "·"
		tile_label.modulate = Color(0.6, 0.6, 0.4)

	tile_container.add_child(tile_label)
	rendered_tiles[tile_pos] = tile_label

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid coordinates to world coordinates"""
	return Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
