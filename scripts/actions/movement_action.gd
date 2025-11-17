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
	"""Check if movement is valid (not wall, in bounds)

	For procedural generation, Grid3D handles infinite world bounds.
	For static levels, Grid3D checks against grid_size.
	"""
	# Calculate target position
	var target_pos = player.grid_position + direction

	# Check if tile is walkable (Grid3D handles bounds checking)
	if not player.grid.is_walkable(target_pos):
		return false

	return true

func execute(player) -> void:
	"""Execute the movement"""
	if not can_execute(player):
		push_warning("MovementAction.execute() called but movement is invalid!")
		return

	var old_pos = player.grid_position

	# Update player grid position
	player.grid_position += direction

	# Update visual position and camera
	player.update_visual_position()

	# Advance turn counter
	player.turn_count += 1

	Log.action("Turn %d: Moved %s | grid(%d,%d) → (%d,%d) | world(X%+d, Z%+d)" % [
		player.turn_count,
		direction,
		old_pos.x, old_pos.y,
		player.grid_position.x, player.grid_position.y,
		direction.x, direction.y
	])

func get_preview_info(player) -> Dictionary:
	"""Get preview info for UI display"""
	var target_pos = player.grid_position + direction

	return {
		"name": "Move Forward",
		"target": "(%d, %d)" % [target_pos.x, target_pos.y],
		"icon": "→",
		"cost": ""
	}
