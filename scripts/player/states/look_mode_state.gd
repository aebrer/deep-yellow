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
	# Update raycast and examination target (includes grid tiles!)
	if first_person_camera:
		var new_target = first_person_camera.get_current_target_or_grid()

		# Check if target changed
		var target_changed = false
		if new_target is Examinable:
			target_changed = (new_target != current_target)
			current_target = new_target
			current_grid_tile = {}
		elif new_target is Dictionary:
			# Grid tile
			target_changed = (new_target != current_grid_tile)
			current_grid_tile = new_target
			current_target = null
		else:
			# Nothing
			target_changed = (current_target != null or not current_grid_tile.is_empty())
			current_target = null
			current_grid_tile = {}

		if target_changed:
			_on_target_changed(new_target)

		# Update ExaminationUI based on current target
		if examination_ui:
			if current_target:
				examination_ui.show_panel(current_target)
			elif not current_grid_tile.is_empty():
				examination_ui.show_panel_for_grid_tile(current_grid_tile)
			else:
				examination_ui.hide_panel()

# ============================================================================
# TARGET HANDLING
# ============================================================================

func _on_target_changed(new_target: Variant) -> void:
	"""Called when raycast target changes (Examinable or grid tile)"""
	if new_target is Examinable:
		Log.trace(Log.Category.STATE, "Looking at entity: %s" % new_target.entity_id)

		# Update ExaminationUI
		if examination_ui:
			examination_ui.set_target(new_target)

		# Increment discovery level on first examination
		KnowledgeDB.examine_entity(new_target.entity_id)

	elif new_target is Dictionary and new_target.get("type") == "grid_tile":
		# Grid tile examination
		var entity_id = _get_entity_id_for_tile(new_target.tile_type)
		Log.trace(Log.Category.STATE, "Looking at grid tile: %s" % entity_id)

		# Increment discovery level for tile type
		KnowledgeDB.examine_entity(entity_id)

	else:
		Log.trace(Log.Category.STATE, "No target in view")

		# Clear ExaminationUI
		if examination_ui:
			examination_ui.clear_target()

func _get_entity_id_for_tile(tile_type: int) -> String:
	"""Map GridMap tile type to entity ID"""
	# TileType enum: FLOOR = 0, WALL = 1, CEILING = 2
	match tile_type:
		0:  # FLOOR
			return "level_0_floor"
		1:  # WALL
			return "level_0_wall"
		2:  # CEILING
			return "level_0_ceiling"
		_:
			return "unknown_tile"
