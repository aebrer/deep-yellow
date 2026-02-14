class_name VendingMachineAction extends Action
## Action for interacting with a vending machine entity
##
## Blocks player movement (stays in place) and opens the vending machine UI.
## The vending machine offers 2-5 random items for purchase at a cost of
## permanent max stat reduction (HP, Sanity, or Mana).

var target_position: Vector2i  ## Position of the vending machine
var entity: WorldEntity  ## The vending machine entity

func _init(pos: Vector2i, p_entity: WorldEntity):
	action_name = "VendingMachine"
	target_position = pos
	entity = p_entity

func can_execute(player: Player3D) -> bool:
	"""Vending machine interaction is always valid if entity exists"""
	if not player or not entity:
		return false
	# Must be adjacent to the vending machine
	var distance = player.grid_position.distance_to(target_position)
	return distance <= 1.5

func execute(player: Player3D) -> void:
	"""Open vending machine UI (does NOT move player)"""
	if not can_execute(player):
		return

	# Get or create the vending machine panel
	var panel = _get_vending_panel(player)
	if not panel:
		Log.warn(Log.Category.ACTION, "Failed to get vending machine panel")
		return

	# Show the vending machine UI
	panel.show_vending_machine(player, target_position, entity)

func _get_vending_panel(player: Player3D) -> VendingMachinePanel:
	"""Get or create the vending machine panel UI"""
	if not player:
		return null

	var ui = player.get_node_or_null("/root/Game/VendingMachinePanel")
	if ui:
		return ui

	var game_node = player.get_node_or_null("/root/Game")
	if not game_node:
		Log.warn(Log.Category.ACTION, "Cannot find Game node to attach vending UI")
		return null

	ui = VendingMachinePanel.new()
	ui.name = "VendingMachinePanel"
	game_node.add_child(ui)
	return ui
func get_description() -> String:
	return "Use Vending Machine"
