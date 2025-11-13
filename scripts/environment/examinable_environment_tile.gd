class_name ExaminableEnvironmentTile
extends Examinable
## Invisible examination area for environment tiles (walls/floors/ceilings)
##
## Inherits from Examinable (which extends Area3D).
## Positioned at same world location as GridMap visual tile.
##
## This is part of the examination overlay system - separate from GridMap rendering.
## GridMap handles visuals, these Area3D nodes handle examination interaction.

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

	# Configure Examinable properties (inherited from parent)
	entity_id = entity_id_param
	entity_type = Examinable.EntityType.ENVIRONMENT

	# Collision layer for examination (layer 4 = bit 8)
	# Separate from GridMap movement collision (layer 2)
	collision_layer = 8
	collision_mask = 0

	Log.system("Created examinable tile: %s at %s (grid: %s)" % [entity_id, world_pos, grid_pos])
