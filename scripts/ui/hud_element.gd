class_name HUDElement extends Control
"""Base class for interactive HUD elements.

Add to "hud_focusable" group to make it navigable when paused.

Usage:
	extends HUDElement

	func activate():
		super.activate()  # Call base implementation
		# Custom activation logic here

IMPORTANT: Tooltips on Child Labels
	Labels ignore mouse events by default. To enable tooltips:
	1. Add tooltip_text to the label
	2. Set mouse_filter = 0 (MOUSE_FILTER_STOP) in the .tscn file
	Example:
		[node name="HPLabel" type="Label"]
		mouse_filter = 0
		tooltip_text = "Health Points..."

Signals:
	element_activated() - When clicked or A button pressed
	element_hovered() - When mouse enters (paused only)

Visual States:
	- Normal: Default appearance
	- Hovered: Mouse over (paused only)
	- Focused: Controller/keyboard focus
"""

signal element_activated()
signal element_hovered()

var is_hovered: bool = false
var is_focused: bool = false

func _ready():
	# Make focusable
	focus_mode = Control.FOCUS_ALL

	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

	# Add to focusable group
	add_to_group("hud_focusable")

func _on_mouse_entered():
	"""Mouse hover - only when paused."""
	if PauseManager.is_paused:
		is_hovered = true
		PauseManager.set_hud_focus(self)
		emit_signal("element_hovered")
		_update_visual_state()

func _on_mouse_exited():
	is_hovered = false
	_update_visual_state()

func _on_focus_entered():
	"""Controller/keyboard focus."""
	is_focused = true
	_update_visual_state()

func _on_focus_exited():
	is_focused = false
	_update_visual_state()

func _gui_input(event):
	"""Handle activation (click or A button)."""
	if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		if PauseManager.is_paused:
			activate()
			get_viewport().set_input_as_handled()

func activate():
	"""Override in subclasses for custom behavior."""
	emit_signal("element_activated")

func _update_visual_state():
	"""Override to show focus/hover state.

	Example implementation:
		if is_focused or is_hovered:
			$Background.modulate = Color(1.2, 1.2, 1.2, 1.0)  # Highlight
		else:
			$Background.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal
	"""
	# Default implementation: simple modulation
	if is_focused or is_hovered:
		modulate = Color(1.2, 1.2, 1.2, 1.0)  # Highlight
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal
