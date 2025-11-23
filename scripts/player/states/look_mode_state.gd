extends PlayerInputState
## State for first-person examination mode
##
## Entered when player holds LT/RMB.
## Exits when player releases LT/RMB.
## Turn progression is PAUSED during look mode.

# NOTE: These will be initialized in enter() since they depend on player node
var first_person_camera: FirstPersonCamera = null
var tactical_camera: TacticalCamera = null
var examination_crosshair: ExaminationCrosshair = null  # In viewport (can have effects)
var examination_panel: ExaminationPanel = null  # In main viewport (clean text)

var current_target: Examinable = null
var current_grid_tile: Dictionary = {}  # For grid tile examination

func _init() -> void:
	state_name = "LookModeState"

# ============================================================================
# STATE LIFECYCLE
# ============================================================================

func enter() -> void:
	super.enter()

	# Get camera and UI references (can't use @onready in state nodes)
	if not first_person_camera:
		first_person_camera = player.get_node_or_null("FirstPersonCamera")
	if not tactical_camera:
		tactical_camera = player.get_node_or_null("CameraRig")

	# Get split examination UI components
	if not examination_crosshair:
		var game_3d = player.get_parent()
		examination_crosshair = game_3d.get_node_or_null("ViewportUILayer/ExaminationCrosshair")
	if not examination_panel:
		examination_panel = get_node_or_null("/root/Game/TextUIOverlay/ExaminationPanel")
		if examination_panel:
			Log.system("ExaminationPanel found at /root/Game/TextUIOverlay/ExaminationPanel")
		else:
			Log.warn(Log.Category.STATE, "ExaminationPanel NOT found at /root/Game/TextUIOverlay/ExaminationPanel")

	if not first_person_camera:
		push_error("[LookModeState] FirstPersonCamera not found!")
		transition_to("IdleState")
		return

	if not tactical_camera:
		push_error("[LookModeState] TacticalCamera not found!")
		transition_to("IdleState")
		return

	Log.state("Entering Look Mode - switching to first-person camera")

	# Capture mouse for camera control (standard FPS controls)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch cameras (activate() handles rotation sync)
	tactical_camera.camera.current = false
	first_person_camera.activate()

	# Hide tactical UI elements
	if player.has_method("hide_move_indicator"):
		player.hide_move_indicator()

	# Show examination crosshair (in viewport, can have effects)
	if examination_crosshair:
		examination_crosshair.show_crosshair()
	else:
		Log.warn(Log.Category.STATE, "ExaminationCrosshair not found in ViewportUILayer")

	# Update action preview to show wait action
	_update_action_preview()

func exit() -> void:
	super.exit()

	Log.state("Exiting Look Mode - switching to tactical camera")

	# Recapture mouse for tactical camera control (unless paused)
	if not PauseManager.is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch back to tactical camera (deactivate() handles rotation sync)
	if first_person_camera:
		first_person_camera.deactivate()
	if tactical_camera:
		tactical_camera.camera.current = true

	# Hide examination UI components
	if examination_crosshair:
		examination_crosshair.hide_crosshair()
	if examination_panel:
		examination_panel.hide_panel()

	# Restore tactical UI
	if player.has_method("update_move_indicator"):
		player.update_move_indicator()

	# Clear current target
	current_target = null

# ============================================================================
# INPUT HANDLING
# ============================================================================

func handle_input(event: InputEvent) -> void:
	# Exit look mode when trigger released
	if event.is_action_released("look_mode"):
		transition_to("IdleState")
		return

	# Block all other inputs while in look mode
	# (Camera rotation handled by FirstPersonCamera directly)
	# (RT/LMB handled in process_frame via InputManager)

func process_frame(_delta: float) -> void:
	# Check if look mode button released
	# InputManager.is_action_pressed handles: LT trigger, RMB
	if InputManager and not InputManager.is_action_pressed("look_mode"):
		Log.system("[LookModeState] Look button released - transitioning to IdleState")
		transition_to("IdleState")
		return

	# Handle RT/LMB for wait action (using InputManager for proper action tracking)
	if InputManager and InputManager.is_action_just_pressed("move_confirm"):
		_execute_wait_action()
		return

	# Update raycast and examination target (uses examination overlay system)
	if not first_person_camera:
		return

	var new_target = first_person_camera.get_current_target()

	# Check if target changed
	var target_changed = (new_target != current_target)
	current_target = new_target

	# Update UI with target (or hide if nothing)
	if target_changed:
		if new_target:
			# Examine the target - route to correct examination function based on entity_type
			if new_target.entity_type == Examinable.EntityType.ENVIRONMENT:
				# Extract simple type from "level_0_floor" → "floor"
				var env_type = new_target.entity_id.replace("level_0_", "")
				KnowledgeDB.examine_environment(env_type)
			else:
				# Entities, items, hazards
				KnowledgeDB.examine_entity(new_target.entity_id)

			if examination_panel:
				# Log.system("Showing examination panel")  # Too verbose
				examination_panel.show_panel(new_target)
			else:
				Log.warn(Log.Category.STATE, "Cannot show panel - examination_panel is null")
		else:
			# Looking at nothing
			# Log.trace(Log.Category.STATE, "Looking at nothing")  # Too verbose
			if examination_panel:
				examination_panel.hide_panel()

# ============================================================================
# ACTIONS
# ============================================================================

func _execute_wait_action() -> void:
	"""Execute a wait action (pass turn without moving) while staying in look mode"""
	var wait_action = WaitAction.new()

	Log.turn("[Look Mode] Player waiting (passing turn)")

	# Execute the wait action directly (stay in look mode, don't transition)
	if wait_action.can_execute(player):
		wait_action.execute(player)

		# TODO: Process enemy turns when enemy system is implemented
		# TODO: Process environmental effects when physics system is implemented

		Log.turn("===== TURN %d COMPLETE (from Look Mode) =====" % player.turn_count)

func _update_action_preview() -> void:
	"""Update action preview with wait action"""
	if not player:
		return

	# In look mode, player will wait (pass turn) when clicking RT/LMB
	var preview_action = WaitAction.new()

	# Emit preview signal with typed array
	var actions: Array[Action] = [preview_action]
	player.action_preview_changed.emit(actions)

# All target handling now unified - no special cases for grid tiles vs entities
