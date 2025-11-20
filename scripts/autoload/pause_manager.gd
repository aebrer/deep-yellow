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
	# Pause the 3D viewport (not the entire tree)
	var game_3d = get_tree().get_first_node_in_group("game_3d_viewport")
	if game_3d:
		Log.system("PauseManager: Found game_3d node '%s', disabling..." % game_3d.name)
		game_3d.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		Log.warn(Log.Category.SYSTEM, "PauseManager: game_3d_viewport node NOT FOUND!")

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Register focusable HUD elements
	_refresh_focusable_elements()
	Log.system("PauseManager: Found %d focusable elements" % focusable_elements.size())
	for i in range(min(3, focusable_elements.size())):
		Log.system("  - Element %d: %s" % [i, focusable_elements[i].name])

	# Focus first element (only for controller, not mouse)
	if focusable_elements.size() > 0:
		if InputManager and InputManager.current_input_device == InputManager.InputDevice.GAMEPAD:
			Log.system("PauseManager: Focusing first element '%s' (controller mode)" % focusable_elements[0].name)
			set_hud_focus(focusable_elements[0])
		else:
			Log.system("PauseManager: Skipping auto-focus (mouse/keyboard mode)")
	else:
		Log.warn(Log.Category.SYSTEM, "PauseManager: No focusable elements found!")

	Log.system("Entered HUD interaction mode (paused)")

func _exit_hud_mode():
	"""Resume gameplay viewport, disable HUD interaction."""
	# Resume the 3D viewport
	var game_3d = get_tree().get_first_node_in_group("game_3d_viewport")
	if game_3d:
		Log.system("PauseManager: Found game_3d node '%s' for resume, enabling..." % game_3d.name)
		game_3d.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		Log.warn(Log.Category.SYSTEM, "PauseManager: game_3d_viewport node NOT FOUND on resume!")

	# Capture mouse for camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Clear focus
	if current_focus:
		current_focus.release_focus()
	current_focus = null

	Log.system("Resumed gameplay (unpaused)")

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
