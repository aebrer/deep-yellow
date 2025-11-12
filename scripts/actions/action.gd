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
