extends PlayerInputState
## State for first-person examination mode
##
## Entered when player holds LT/RMB.
## Exits when player releases LT/RMB.
## Turn progression is PAUSED during look mode.

# NOTE: These will be initialized in enter() since they depend on player node
var first_person_camera: FirstPersonCamera = null
var tactical_camera: TacticalCamera = null
var examination_ui: ExaminationUI = null

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
	if not examination_ui:
		# Navigate up to scene root, then to UI/ExaminationUI
		var game_root = player.get_parent()  # Game node
		examination_ui = game_root.get_node_or_null("UI/ExaminationUI")

	if not first_person_camera:
		push_error("[LookModeState] FirstPersonCamera not found!")
		transition_to("IdleState")
		return

	if not tactical_camera:
		push_error("[LookModeState] TacticalCamera not found!")
		transition_to("IdleState")
		return

	Log.state("Entering Look Mode - switching to first-person camera")

	# Switch cameras
	tactical_camera.camera.current = false
	first_person_camera.activate()

	# Hide tactical UI elements
	if player.has_method("hide_move_indicator"):
		player.hide_move_indicator()

	# Show examination UI (crosshair)
	if examination_ui:
		examination_ui.show_crosshair()
	else:
		Log.warn(Log.Category.STATE, "ExaminationUI not found at path: /root/Game/UI/ExaminationUI")

func exit() -> void:
	super.exit()

	Log.state("Exiting Look Mode - switching to tactical camera")

	# Switch back to tactical camera
	if first_person_camera:
		first_person_camera.deactivate()
	if tactical_camera:
		tactical_camera.camera.current = true

	# Hide examination UI
	if examination_ui:
		examination_ui.hide_crosshair()
		examination_ui.hide_panel()

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

func process_frame(_delta: float) -> void:
	# Update raycast and examination target (now uses simple overlay system!)
	if first_person_camera:
		var new_target = first_person_camera.get_current_target()

		# Check if target changed
		var target_changed = (new_target != current_target)
		current_target = new_target

		# Update UI with target (or hide if nothing)
		if target_changed:
			if new_target:
				# Examine the target (entity or environment tile)
				KnowledgeDB.examine_entity(new_target.entity_id)
				if examination_ui:
					examination_ui.show_panel(new_target)
			else:
				# Looking at nothing
				if examination_ui:
					examination_ui.hide_panel()

# All target handling now unified - no special cases for grid tiles vs entities
