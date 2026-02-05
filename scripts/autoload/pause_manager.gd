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
"""

signal pause_toggled(is_paused: bool)


var is_paused: bool = false
var current_focus: Control = null
var focusable_elements: Array[Control] = []
var last_hud_focus: Control = null  # Remembers last focused HUD element for manual pause

func _ready():
	# Don't pause the entire tree - just the 3D viewport
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	# MMB (middle mouse button) toggles pause - check in _input before scene tree consumes it
	# This is useful on web where ESC in fullscreen exits fullscreen first
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		toggle_pause(false)  # Mouse triggered
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event):
	# ESC (keyboard via ui_cancel) or START (controller via pause action) toggles pause
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		# Check if this was triggered by a gamepad button
		var from_gamepad = event is InputEventJoypadButton
		toggle_pause(from_gamepad)
		get_viewport().set_input_as_handled()
		return

	# Left stick (ui_up/down/left/right) handling:
	# - When paused: used for HUD navigation (vertical only, horizontal via mouse)
	# - When unpaused: consume to prevent Godot's built-in focus system from firing
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		if is_paused:
			# Vertical HUD navigation with left stick
			if event.is_action_pressed("ui_up") and not Input.is_action_pressed("ui_down"):
				if InputManager and InputManager.is_action_just_pressed("ui_up"):
					navigate_hud(Vector2i(0, -1))
			elif event.is_action_pressed("ui_down") and not Input.is_action_pressed("ui_up"):
				if InputManager and InputManager.is_action_just_pressed("ui_down"):
					navigate_hud(Vector2i(0, 1))
		# Always consume left stick input to block Godot's built-in focus navigation
		get_viewport().set_input_as_handled()

func toggle_pause(from_gamepad: bool = false):
	"""Toggle pause state.

	Args:
		from_gamepad: True if triggered by a gamepad button (for focus grabbing)
	"""
	is_paused = not is_paused
	emit_signal("pause_toggled", is_paused)

	if is_paused:
		_enter_hud_mode(from_gamepad)
	else:
		_exit_hud_mode()

func set_pause(paused: bool) -> void:
	"""Set pause state directly (safe for popups that need to ensure paused state).

	Unlike toggle_pause(), this is idempotent - calling set_pause(true) when
	already paused does nothing, which is the correct behavior for popups.
	"""
	if is_paused == paused:
		return  # Already in desired state

	is_paused = paused
	emit_signal("pause_toggled", is_paused)

	if is_paused:
		_enter_hud_mode()
	else:
		_exit_hud_mode()

func _enter_hud_mode(from_gamepad: bool = false):
	"""Enable HUD interaction mode (turn-based games don't pause processing).

	Args:
		from_gamepad: True if pause was triggered by a gamepad button
	"""
	# For turn-based games, we DON'T disable Game3D processing
	# The game world only advances on player actions, so "pause" just means:
	# - Mouse visible for UI interaction
	# - HUD elements focusable
	# - State machine keeps running so inventory actions can execute turns

	# Show mouse cursor for HUD interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Register focusable HUD elements
	_refresh_focusable_elements()

	# Auto-grab focus for controller users on manual pause (not popup-triggered)
	# Popups (LevelUpPanel, ItemSlotSelectionPanel) handle their own focus
	# Use from_gamepad (the actual trigger) rather than current_input_device (can be stale)
	if from_gamepad:
		if not _is_popup_visible():
			_grab_hud_focus()

func _exit_hud_mode():
	"""Exit HUD interaction mode, return to camera control."""
	# Save current focus as last HUD focus BEFORE changing mouse mode
	# (Changing to MOUSE_MODE_CAPTURED clears focus!)
	# Use viewport's focus owner, but fallback to our tracked current_focus
	# (gui_get_focus_owner can return null even when we have focus tracked)
	var focused = get_viewport().gui_get_focus_owner()
	if not focused and current_focus and is_instance_valid(current_focus):
		focused = current_focus
	if focused:
		_update_last_hud_focus(focused)

	# Capture mouse for camera control (this clears focus)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Clear our tracked focus
	if current_focus:
		current_focus.release_focus()
	current_focus = null

func _refresh_focusable_elements():
	"""Find all HUD elements that can be focused."""
	# Disconnect old focus signals
	for element in focusable_elements:
		if is_instance_valid(element) and element.focus_entered.is_connected(_on_element_focus_entered):
			element.focus_entered.disconnect(_on_element_focus_entered)

	focusable_elements.clear()

	# Find all nodes in "hud_focusable" group
	for node in get_tree().get_nodes_in_group("hud_focusable"):
		if node is Control and _is_truly_visible(node):
			focusable_elements.append(node)
			# Connect to focus_entered to track focus changes from Godot's built-in navigation
			if not node.focus_entered.is_connected(_on_element_focus_entered):
				node.focus_entered.connect(_on_element_focus_entered.bind(node))

	# Sort by position (top to bottom, left to right)
	focusable_elements.sort_custom(_sort_by_position)

func _is_truly_visible(node: Control) -> bool:
	"""Check if a node and all its ancestors are visible.

	A node can have visible=true but still be hidden if any parent is invisible.
	"""
	var current = node
	while current:
		if current is CanvasItem and not current.visible:
			return false
		current = current.get_parent()
	return true

func _on_element_focus_entered(element: Control):
	"""Called when any focusable element gains focus (from Godot's built-in navigation)."""
	current_focus = element
	_update_last_hud_focus(element)

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
	element.grab_focus()
	# Remember this as last HUD focus (if it's not a popup button)
	_update_last_hud_focus(element)

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

func _is_popup_visible() -> bool:
	"""Check if any popup panel is currently visible (LevelUpPanel, ItemSlotSelectionPanel)."""
	# Check for LevelUpPanel
	for node in get_tree().get_nodes_in_group("hud_focusable"):
		var parent = node.get_parent()
		while parent:
			if parent.get_class() == "Control":
				# Check if this is a popup panel by class_name
				var script = parent.get_script()
				if script:
					var script_path = script.resource_path
					if "level_up_panel" in script_path or "item_slot_selection_panel" in script_path or "settings_panel" in script_path:
						if parent.visible:
							return true
			parent = parent.get_parent()
	return false

func _grab_hud_focus():
	"""Grab focus on last HUD element or first available (for manual controller pause)."""
	if focusable_elements.is_empty():
		return

	# Try to restore last HUD focus if it's still valid and visible
	if last_hud_focus and is_instance_valid(last_hud_focus) and last_hud_focus.visible:
		if last_hud_focus in focusable_elements:
			set_hud_focus(last_hud_focus)
			return

	# Otherwise focus first element
	set_hud_focus(focusable_elements[0])

func _update_last_hud_focus(element: Control):
	"""Update last_hud_focus if this is a HUD element (not a popup button)."""
	# Check if this element belongs to a popup
	var parent = element.get_parent()
	while parent:
		var script = parent.get_script()
		if script:
			var script_path = script.resource_path
			if "level_up_panel" in script_path or "item_slot_selection_panel" in script_path or "settings_panel" in script_path:
				# This is a popup button, don't remember it
				return
		parent = parent.get_parent()

	# It's a regular HUD element, remember it
	last_hud_focus = element
