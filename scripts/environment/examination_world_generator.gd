class_name ExaminationWorldGenerator
extends Node
## Generates examination overlay for GridMap tiles
##
## Creates ExaminableEnvironmentTile nodes for walls, floors, ceilings.
## Coordinates with Grid3D to ensure spatial alignment.
##
## This separates examination detection (layer 4) from rendering (GridMap)
## and player movement collision (GridMap layer 2).

# Template scene for examination tiles
const EXAM_TILE_SCENE = preload("res://scenes/environment/examinable_environment_tile.tscn")

# Tile dimensions (match GridMap cell_size)
const TILE_SIZE = Vector2(2.0, 2.0)  # X, Z dimensions
const FLOOR_HEIGHT = 0.0
const WALL_HEIGHT = 2.0   # Center of wall (extends Y=0 to Y=4)
const CEILING_HEIGHT = 3.0  # Actual ceiling position

# Parent node for all examination tiles
var examination_world: Node3D

func generate_examination_layer(grid, parent: Node3D) -> void:
	"""Generate examination tiles for entire grid

	Args:
		grid: The Grid3D instance with GridMap data (untyped to avoid circular dependency)
		parent: Where to add examination tiles (usually root Game node)
	"""
	Log.system("Generating examination layer for %dx%d grid..." % [grid.grid_size.x, grid.grid_size.y])

	# Create container node
	examination_world = Node3D.new()
	examination_world.name = "ExaminationWorld"
	parent.add_child(examination_world)

	var tiles_created = 0

	# Iterate through grid data
	for y in range(grid.grid_size.y):
		for x in range(grid.grid_size.x):
			var grid_pos = Vector2i(x, y)
			var cell_3d = Vector3i(x, 0, y)  # Check Y=0 layer for floor/walls
			var cell_item = grid.grid_map.get_cell_item(cell_3d)

			# Create examination tile based on type
			match cell_item:
				Grid3D.TileType.FLOOR:
					_create_floor_tile(grid, grid_pos)
					tiles_created += 1
				Grid3D.TileType.WALL:
					_create_wall_tile(grid, grid_pos)
					tiles_created += 1

			# Check Y=1 layer for ceilings
			var ceiling_cell = Vector3i(x, 1, y)
			var ceiling_item = grid.grid_map.get_cell_item(ceiling_cell)
			if ceiling_item == Grid3D.TileType.CEILING:
				_create_ceiling_tile(grid, grid_pos)
				tiles_created += 1

	Log.system("Created %d examination tiles" % tiles_created)

func _create_floor_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
	"""Create examination area for floor tile"""
	var world_pos = grid.grid_to_world(grid_pos)
	world_pos.y = FLOOR_HEIGHT  # Floor at Y=0

	var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
	examination_world.add_child(tile)
	tile.setup("floor", "level_0_floor", grid_pos, world_pos)

	# Configure collision shape - thin horizontal slab
	var collision = tile.get_node("CollisionShape3D") as CollisionShape3D
	var shape = BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE.x, 0.1, TILE_SIZE.y)  # Very thin
	collision.shape = shape

func _create_wall_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
	"""Create examination area for wall tile"""
	var world_pos = grid.grid_to_world(grid_pos)
	world_pos.y = WALL_HEIGHT  # Wall center at Y=2

	var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
	examination_world.add_child(tile)
	tile.setup("wall", "level_0_wall", grid_pos, world_pos)

	# Configure collision shape - full wall height
	var collision = tile.get_node("CollisionShape3D") as CollisionShape3D
	var shape = BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE.x, 4.0, TILE_SIZE.y)  # Full height (Y=0 to Y=4)
	collision.shape = shape

func _create_ceiling_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
	"""Create examination area for ceiling tile"""
	var world_pos = grid.grid_to_world(grid_pos)
	world_pos.y = CEILING_HEIGHT  # Ceiling at Y=3

	var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
	examination_world.add_child(tile)
	tile.setup("ceiling", "level_0_ceiling", grid_pos, world_pos)

	# Configure collision shape - thin horizontal slab
	var collision = tile.get_node("CollisionShape3D") as CollisionShape3D
	var shape = BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE.x, 0.1, TILE_SIZE.y)  # Very thin
	collision.shape = shape
