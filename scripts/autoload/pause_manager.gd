extends Node
"""Manages game pause and HUD interaction mode.

Handles:
- ESC/START to pause game viewport
- Mouse/controller navigation of HUD when paused
- Input mode switching (gameplay vs HUD interaction)

Usage:
	PauseManager.toggle_pause()
	PauseManager.is_paused  # Query current state

Signals:
	pause_toggled(is_paused: bool) - When pause state changes
	hud_focus_changed(focused_element: Control) - When HUD focus changes
"""

signal pause_toggled(is_paused: bool)
signal hud_focus_changed(focused_element: Control)

var is_paused: bool = false
var current_focus: Control = null
var focusable_elements: Array[Control] = []

func _ready():
	# Don't pause the entire tree - just the 3D viewport
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event):
	# ESC (keyboard via ui_cancel) or START (controller via pause action) toggles pause
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return

	# Handle controller UI navigation when paused (use just_pressed for debouncing)
	if is_paused:
		if event.is_action_pressed("ui_up") and not Input.is_action_pressed("ui_down"):
			# Only navigate if this is a fresh press (use InputManager for debouncing)
			if InputManager and InputManager.is_action_just_pressed("ui_up"):
				navigate_hud(Vector2i(0, -1))
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down") and not Input.is_action_pressed("ui_up"):
			if InputManager and InputManager.is_action_just_pressed("ui_down"):
				navigate_hud(Vector2i(0, 1))
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_left") and not Input.is_action_pressed("ui_right"):
			if InputManager and InputManager.is_action_just_pressed("ui_left"):
				navigate_hud(Vector2i(-1, 0))
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right") and not Input.is_action_pressed("ui_left"):
			if InputManager and InputManager.is_action_just_pressed("ui_right"):
				navigate_hud(Vector2i(1, 0))
				get_viewport().set_input_as_handled()

func toggle_pause():
	"""Toggle pause state."""
	is_paused = not is_paused
	emit_signal("pause_toggled", is_paused)

	if is_paused:
		_enter_hud_mode()
	else:
		_exit_hud_mode()

func _enter_hud_mode():
	"""Pause gameplay viewport, enable HUD interaction."""
	# Pause the 3D viewport (inside SubViewport)
	# Search for SubViewport dynamically (works in both portrait and landscape layouts)
	var subviewport = _find_subviewport()
	if subviewport:
		var game_3d = subviewport.get_node_or_null("Game3D")
		if game_3d:
			Log.system("PauseManager: Found game_3d node '%s', disabling..." % game_3d.name)
			game_3d.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			Log.warn(Log.Category.SYSTEM, "PauseManager: Game3D node not found in SubViewport!")
	else:
		Log.warn(Log.Category.SYSTEM, "PauseManager: SubViewport not found!")

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Register focusable HUD elements
	_refresh_focusable_elements()
	Log.system("PauseManager: Found %d focusable elements" % focusable_elements.size())
	for i in range(min(3, focusable_elements.size())):
		Log.system("  - Element %d: %s" % [i, focusable_elements[i].name])

	# NOTE: Focus is player-determined, not auto-grabbed by PauseManager
	# Individual UI panels (CoreInventory, ItemSlotSelectionPanel) handle their own focus
	# Auto-grabbing focus here caused race conditions with panel focus management

	Log.system("Entered HUD interaction mode (paused)")

func _exit_hud_mode():
	"""Resume gameplay viewport, disable HUD interaction."""
	# Resume the 3D viewport (inside SubViewport)
	var subviewport = _find_subviewport()
	if subviewport:
		var game_3d = subviewport.get_node_or_null("Game3D")
		if game_3d:
			Log.system("PauseManager: Found game_3d node '%s' for resume, enabling..." % game_3d.name)
			game_3d.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			Log.warn(Log.Category.SYSTEM, "PauseManager: Game3D node not found in SubViewport on resume!")
	else:
		Log.warn(Log.Category.SYSTEM, "PauseManager: SubViewport not found on resume!")

	# Capture mouse for camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Clear focus
	if current_focus:
		current_focus.release_focus()
	current_focus = null

	Log.system("Resumed gameplay (unpaused)")

func _find_subviewport() -> SubViewport:
	"""Find the game SubViewport dynamically (works in portrait and landscape layouts)"""
	# Search for SubViewportContainer anywhere in the tree
	var root = get_tree().root
	var containers = _find_nodes_by_type(root, "SubViewportContainer")

	for container in containers:
		for child in container.get_children():
			if child is SubViewport:
				return child

	return null

func _find_nodes_by_type(node: Node, type_name: String) -> Array:
	"""Recursively find all nodes of a specific type"""
	var result = []

	if node.get_class() == type_name:
		result.append(node)

	for child in node.get_children():
		result.append_array(_find_nodes_by_type(child, type_name))

	return result

func _refresh_focusable_elements():
	"""Find all HUD elements that can be focused."""
	focusable_elements.clear()

	# Find all nodes in "hud_focusable" group
	for node in get_tree().get_nodes_in_group("hud_focusable"):
		if node is Control and node.visible:
			focusable_elements.append(node)

	# Sort by position (top to bottom, left to right)
	focusable_elements.sort_custom(_sort_by_position)

func _sort_by_position(a: Control, b: Control) -> bool:
	"""Sort controls by visual position."""
	var pos_a = a.global_position
	var pos_b = b.global_position

	# Top to bottom first
	if abs(pos_a.y - pos_b.y) > 10:
		return pos_a.y < pos_b.y

	# Then left to right
	return pos_a.x < pos_b.x

func set_hud_focus(element: Control):
	"""Focus a HUD element."""
	if current_focus:
		current_focus.release_focus()

	current_focus = element
	Log.system("PauseManager: Calling grab_focus() on '%s'" % element.name)
	element.grab_focus()
	Log.system("PauseManager: Element has focus = %s" % element.has_focus())
	emit_signal("hud_focus_changed", element)

func navigate_hud(direction: Vector2i):
	"""Navigate HUD with controller (up/down/left/right)."""
	if not is_paused or focusable_elements.is_empty():
		return

	var current_index = focusable_elements.find(current_focus)
	if current_index == -1:
		current_index = 0

	# Simple vertical navigation for now
	if direction.y != 0:
		current_index += direction.y
		current_index = clamp(current_index, 0, focusable_elements.size() - 1)
		set_hud_focus(focusable_elements[current_index])
