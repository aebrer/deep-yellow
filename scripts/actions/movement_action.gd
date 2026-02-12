class_name MovementAction
extends Action
## Action for moving the player in a direction
##
## Usage:
##   var action = MovementAction.new(Vector2i(1, 0))  # Move right
##   if action.can_execute(player):
##       action.execute(player)

## Direction to move (grid coordinates)
var direction: Vector2i

func _init(dir: Vector2i) -> void:
	direction = dir
	action_name = "Move(%d, %d)" % [dir.x, dir.y]

func can_execute(player) -> bool:
	"""Check if movement is valid (not wall, in bounds). Pure check — no side effects.

	For procedural generation, Grid3D handles infinite world bounds.
	For static levels, Grid3D checks against grid_size.
	Closed doors count as walkable (they'll be opened in execute).
	"""
	# Calculate target position
	var target_pos = player.grid_position + direction

	# Check if tile is walkable or a closed door (doors are opened during execute)
	if not player.grid.is_walkable(target_pos):
		if not player.grid.is_closed_door(target_pos):
			return false

	# Diagonal wall gap check: block only when BOTH adjacent cardinals are walls
	# (entities don't fully block a tile visually, so allow squeezing past them)
	if abs(direction.x) == 1 and abs(direction.y) == 1:
		var adj_x: Vector2i = player.grid_position + Vector2i(direction.x, 0)
		var adj_y: Vector2i = player.grid_position + Vector2i(0, direction.y)
		var gm: GridMap = player.grid.grid_map
		var x_is_floor := Grid3D.is_floor_tile(gm.get_cell_item(Vector3i(adj_x.x, 0, adj_x.y)))
		var y_is_floor := Grid3D.is_floor_tile(gm.get_cell_item(Vector3i(adj_y.x, 0, adj_y.y)))
		if not x_is_floor and not y_is_floor:
			return false

	return true

func execute(player) -> void:
	"""Execute the movement, opening any closed door at the target first."""
	if not can_execute(player):
		push_warning("MovementAction.execute() called but movement is invalid!")
		return

	# Open closed door at target if needed (before moving)
	var target_pos = player.grid_position + direction
	if player.grid.is_closed_door(target_pos):
		player.grid.toggle_door(target_pos)

	var old_pos = player.grid_position

	# Update player grid position
	player.grid_position += direction

	# Update visual position and camera
	player.update_visual_position()

	# Auto-close: if the tile we just left is an open door, close it behind us
	var old_tile: int = player.grid._get_subchunk_tile_type(old_pos)
	if SubChunk.is_door_open(old_tile):
		player.grid.toggle_door(old_pos)

	# Advance turn counter
	player.turn_count += 1

func get_preview_info(player) -> Dictionary:
	"""Get preview info for UI display"""
	var target_pos = player.grid_position + direction

	return {
		"name": "Move Forward",
		"target": "(%d, %d)" % [target_pos.x, target_pos.y],
		"icon": "→",
		"cost": ""
	}
