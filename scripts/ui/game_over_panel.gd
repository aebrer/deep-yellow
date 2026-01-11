extends Control
class_name GameOverPanel
## Game Over screen shown when player dies (HP or Sanity depleted)
##
## Displays:
## - Death cause (HP depleted / Sanity depleted)
## - Final stats (turns survived, level reached, EXP earned)
## - Restart button
##
## Uses PauseManager pattern for consistent pause/unpause behavior
## (same as ItemSlotSelectionPanel)

# ============================================================================
# SIGNALS
# ============================================================================

signal restart_requested

# ============================================================================
# UI REFERENCES
# ============================================================================

var panel: PanelContainer  ## Main panel (for positioning)
var cause_label: Label
var turns_label: Label
var level_label: Label
var exp_label: Label
var restart_button: Button

# ============================================================================
# STATE
# ============================================================================

var death_cause: String = ""
var final_turns: int = 0
var final_level: int = 0
var final_exp: int = 0
var _accepting_input: bool = false  ## Only accept button presses after panel fully set up

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Fill screen for centering (same as ItemSlotSelectionPanel)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input when hidden

	# Build UI programmatically
	_build_ui()

	# Start hidden
	visible = false

	# Ensure we're on top of everything
	z_index = 100

	# Process when paused (critical for input handling)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to PauseManager for focus control
	if PauseManager:
		PauseManager.pause_toggled.connect(_on_pause_toggled)

func _build_ui() -> void:
	"""Build the game over UI"""
	# Main panel (positioned manually, not with CenterContainer)
	panel = PanelContainer.new()
	panel.name = "GameOverPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS  # Process when paused
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture mouse events
	panel.custom_minimum_size = Vector2(400, 0)  # Min width only, height auto
	add_child(panel)

	# Style panel (SCP aesthetic, matching other panels)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.border_color = Color(1, 1, 1, 1)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", style)

	# Vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer1)

	# Death cause
	cause_label = Label.new()
	cause_label.text = "You have perished."
	cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cause_label.add_theme_font_size_override("font_size", 18)
	cause_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	vbox.add_child(cause_label)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)

	# Stats section
	var stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	vbox.add_child(stats_container)

	# Turns survived
	turns_label = Label.new()
	turns_label.text = "Turns Survived: 0"
	turns_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_container.add_child(turns_label)

	# Level reached
	level_label = Label.new()
	level_label.text = "Level Reached: 0"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_container.add_child(level_label)

	# Total EXP
	exp_label = Label.new()
	exp_label.text = "Total EXP: 0"
	exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_container.add_child(exp_label)

	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer3)

	# Restart button
	restart_button = Button.new()
	restart_button.text = "TRY AGAIN"
	restart_button.custom_minimum_size = Vector2(200, 40)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.process_mode = Node.PROCESS_MODE_ALWAYS  # Process when paused
	restart_button.pressed.connect(_on_restart_pressed)
	restart_button.add_to_group("hud_focusable")
	vbox.add_child(restart_button)

# ============================================================================
# PUBLIC API
# ============================================================================

func show_game_over(cause: String, turns: int, level: int, total_exp: int) -> void:
	"""Show the game over screen with final stats"""
	death_cause = cause
	final_turns = turns
	final_level = level
	final_exp = total_exp

	# Update labels
	match cause:
		"hp_depleted":
			cause_label.text = "your corpse will never leave the backrooms"
			cause_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		"sanity_depleted":
			cause_label.text = "thats not you in there anymore"
			cause_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.8))
		_:
			cause_label.text = "You have perished."

	turns_label.text = "Turns Survived: %d" % turns
	level_label.text = "Level Reached: %d" % level
	exp_label.text = "Total EXP: %d" % total_exp

	# Update panel position to center on game viewport
	_update_panel_position()

	# Show panel
	visible = true
	_accepting_input = false  # Block input until after focus is set

	# Pause game via PauseManager (this triggers _on_pause_toggled)
	if PauseManager:
		PauseManager.toggle_pause()
	else:
		# Fallback if PauseManager not available
		get_tree().paused = true
		restart_button.grab_focus()
		_accepting_input = true

	Log.system("Game Over: %s (Turns: %d, Level: %d, EXP: %d)" % [cause, turns, level, total_exp])

func _update_panel_position() -> void:
	"""Update panel position to center it on game viewport (SubViewportContainer)"""
	if not panel:
		return

	# Get game viewport rect (SubViewportContainer bounds)
	var game_ref = get_node_or_null("/root/Game")
	var viewport_rect: Rect2
	if game_ref and game_ref.has_method("get_game_viewport_rect"):
		viewport_rect = game_ref.get_game_viewport_rect()
	else:
		# Fallback to full viewport
		viewport_rect = get_viewport_rect()

	# Let panel auto-size, then center it
	panel.reset_size()

	# Wait a frame for size to be calculated, then center
	await get_tree().process_frame

	# Get actual panel size
	var panel_size: Vector2 = panel.size

	# Center the panel within the game viewport
	var center_x: float = viewport_rect.position.x + (viewport_rect.size.x - panel_size.x) / 2.0
	var center_y: float = viewport_rect.position.y + (viewport_rect.size.y - panel_size.y) / 2.0

	panel.position = Vector2(center_x, center_y)

# ============================================================================
# PAUSE MANAGER INTEGRATION
# ============================================================================

## Delay before accepting input (prevents accidental clicks from held buttons)
const INPUT_ACCEPT_DELAY := 0.5  # seconds

func _on_pause_toggled(is_paused: bool) -> void:
	"""Update button focus when pause state changes"""
	if not visible:
		return

	if is_paused:
		# Enable focus when paused
		restart_button.focus_mode = Control.FOCUS_ALL
		restart_button.mouse_filter = Control.MOUSE_FILTER_STOP

		# Always grab focus for game over (single button, always want it selected)
		restart_button.grab_focus()

		# Enable input acceptance after delay (prevents accidental activation
		# from held buttons like RT when player dies)
		_accepting_input = false
		get_tree().create_timer(INPUT_ACCEPT_DELAY).timeout.connect(
			func(): _accepting_input = visible
		)
	else:
		# Disable input acceptance when unpausing
		_accepting_input = false
		# Disable focus when unpausing
		restart_button.focus_mode = Control.FOCUS_NONE
		restart_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	"""Handle gamepad-specific inputs and block ALL input from reaching game"""
	if not visible:
		return

	# Handle A button for restart (only if accepting input)
	if _accepting_input and event is InputEventJoypadButton:
		if event.button_index == JOY_BUTTON_A and event.pressed:
			var focused = get_viewport().gui_get_focus_owner()
			if focused == restart_button:
				focused.pressed.emit()
				# Return immediately - scene may be reloading, viewport may be null
				return

	# Block ALL unhandled input events when game over panel is visible
	# This prevents controller/keyboard input from reaching the game
	var viewport = get_viewport()
	if viewport:
		viewport.set_input_as_handled()

func _process(_delta: float) -> void:
	"""Handle RT/A button activation of restart button"""
	if not visible or not _accepting_input:
		return

	# Check for move_confirm (RT/A/Space/LMB via InputManager)
	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused == restart_button:
			focused.pressed.emit()
			return

	# Also check ui_accept (standard Godot action for button activation)
	if Input.is_action_just_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused == restart_button:
			focused.pressed.emit()
			return

func _on_restart_pressed() -> void:
	"""Handle restart button press"""
	# Ignore if not accepting input
	if not _accepting_input:
		return

	Log.system("Restart requested")

	# Hide panel first
	visible = false

	# Unpause via PauseManager
	if PauseManager and PauseManager.is_paused:
		PauseManager.toggle_pause()
	else:
		get_tree().paused = false

	# Emit signal for game.gd to handle
	restart_requested.emit()

	# Reload the current scene
	get_tree().reload_current_scene()
