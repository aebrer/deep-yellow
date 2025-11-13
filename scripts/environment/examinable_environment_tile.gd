class_name ExaminableEnvironmentTile
extends StaticBody3D
## Invisible examination area for environment tiles (walls/floors/ceilings)
##
## Uses StaticBody3D (not Area3D) so raycasts can detect it.
## Positioned at same world location as GridMap visual tile.
##
## This is part of the examination overlay system - separate from GridMap rendering.
## GridMap handles visuals, these StaticBody3D nodes handle examination interaction.

var examinable: Examinable = null

func setup(tile_type: String, entity_id_param: String, grid_pos: Vector2i, world_pos: Vector3) -> void:
	"""Initialize this examination tile

	Args:
		tile_type: "wall", "floor", or "ceiling"
		entity_id_param: KnowledgeDB lookup ID (e.g., "level_0_wall")
		grid_pos: Grid coordinates (for debugging/tracking)
		world_pos: 3D world position for placement
	"""
	name = "Exam_%s_%d_%d" % [tile_type, grid_pos.x, grid_pos.y]
	global_position = world_pos

	# Create Examinable component as child
	examinable = Examinable.new()
	examinable.entity_id = entity_id_param
	examinable.entity_type = Examinable.EntityType.ENVIRONMENT
	add_child(examinable)

	# Collision layer for examination (layer 4 = bit 8)
	# Separate from GridMap movement collision (layer 2)
	collision_layer = 8
	collision_mask = 0
