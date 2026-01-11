class_name Action
extends RefCounted
## Base class for all player actions (Command Pattern)
##
## Actions represent discrete game actions that can be:
## - Validated before execution (can_execute)
## - Executed on a player (execute)
## - Replayed for AI/replays
## - Undone (future: undo support)
##
## Usage:
##   var action = MovementAction.new(Vector2i(1, 0))
##   if action.can_execute(player):
##       action.execute(player)

## Action name for debugging
var action_name: String = "BaseAction"

## Check if this action can be executed in current game state
## Override in subclasses to add validation logic
func can_execute(_player) -> bool:
	push_warning("Action.can_execute() not implemented for: " + action_name)
	return false

## Execute this action on the player
## Override in subclasses to implement action behavior
func execute(_player) -> void:
	push_warning("Action.execute() not implemented for: " + action_name)

## Get a string representation of this action for debugging
func _to_string() -> String:
	return "[Action: %s]" % action_name

## Get preview information for UI display
## Override in subclasses to provide action-specific preview data
## Returns dict with keys: name (String), target (String), icon (String), cost (String)
func get_preview_info(_player) -> Dictionary:
	return {
		"name": action_name,
		"target": "",
		"icon": "?",
		"cost": ""
	}

# ============================================================================
# SHARED HELPER METHODS
# ============================================================================

## Get ItemPool from player by pool type
## Used by actions that need to access specific pools (BODY, MIND, NULL)
static func _get_pool_by_type(player, pool_type: int) -> ItemPool:
	"""Get the appropriate ItemPool from player based on pool type

	Args:
		player: Player reference
		pool_type: Item.PoolType enum value

	Returns:
		ItemPool or null if invalid type
	"""
	match pool_type:
		Item.PoolType.BODY:
			return player.body_pool
		Item.PoolType.MIND:
			return player.mind_pool
		Item.PoolType.NULL:
			return player.null_pool
	return null

## Remove item billboard from world after pickup
## Handles both ItemRenderer removal and chunk data persistence
static func _remove_item_from_world(player, world_pos: Vector2i) -> void:
	"""Remove item from world visuals and mark as picked up in chunk data

	Args:
		player: Player reference (to access grid/item_renderer)
		world_pos: World position of the item to remove
	"""
	if not player or not player.grid or not player.grid.item_renderer:
		return

	# Remove visual billboard
	player.grid.item_renderer.remove_item_at(world_pos)

	# Mark as picked up in chunk data for persistence
	if ChunkManager and ChunkManager.has_method("get_chunk_at_world_position"):
		var chunk = ChunkManager.get_chunk_at_world_position(world_pos)
		if chunk:
			_mark_item_picked_up_in_chunk(chunk, world_pos)

## Mark item as picked up in SubChunk data for persistence
## Called by _remove_item_from_world() to update chunk data
static func _mark_item_picked_up_in_chunk(chunk: Chunk, world_pos: Vector2i) -> void:
	"""Mark item as picked up in SubChunk data

	Args:
		chunk: Chunk containing the item
		world_pos: World position of the item
	"""
	for subchunk in chunk.sub_chunks:
		for item_data_ref in subchunk.world_items:
			var pos_data = item_data_ref.get("world_position", {})
			var item_world_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

			if item_world_pos == world_pos:
				item_data_ref["picked_up"] = true
				return
