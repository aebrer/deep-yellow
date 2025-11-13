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
	"""Check if movement is valid (not wall, in bounds)"""
	# Calculate target position
	var target_pos = player.grid_position + direction

	# Check bounds
	var grid_size = player.grid.grid_size
	if target_pos.x < 0 or target_pos.x >= grid_size.x:
		return false
	if target_pos.y < 0 or target_pos.y >= grid_size.y:
		return false

	# Check if tile is walkable
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
