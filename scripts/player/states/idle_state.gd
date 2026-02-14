extends PlayerInputState
## Idle State - Waiting for player input
##
## This is the default resting state. Handles:
## - Forward movement with RT/LMB (in camera look direction)
## - Wait action with RMB/LT (pass turn)
## - Camera toggle with C/SELECT (FPV ↔ Tactical)
##
## FPV is the default camera mode. Examination is active in FPV mode.

const _AutoExploreState = preload("res://scripts/player/states/auto_explore_state.gd")
const _MapOverlayPanel = preload("res://scripts/ui/map_overlay_panel.gd")

# ============================================================================
# CAMERA MODE
# ============================================================================

enum CameraMode { FPV, TACTICAL }
var camera_mode: CameraMode = CameraMode.FPV  # FPV is default!

# Camera and UI references (initialized in enter())
var first_person_camera: FirstPersonCamera = null
var tactical_camera: TacticalCamera = null
var examination_crosshair: ExaminationCrosshair = null
var examination_panel: ExaminationPanel = null

# Examination state (FPV only)
var current_target: Examinable = null

# ============================================================================
# HOLD-TO-REPEAT SYSTEM (RT/LMB for move, LT/RMB for wait)
# ============================================================================

# Move (RT/LMB) hold state
var rt_held: bool = false
var rt_hold_time: float = 0.0
var rt_repeat_timer: float = 0.0

# Wait (LT/RMB) hold state
var lt_held: bool = false
var lt_hold_time: float = 0.0
var lt_repeat_timer: float = 0.0

## Blocked movement tracking (prevent spam)
var last_blocked_direction: Vector2i = Vector2i(-999, -999)

# Repeat timing configuration
const INITIAL_DELAY: float = 0.3
const REPEAT_INTERVAL_START: float = 0.25
const REPEAT_INTERVAL_MIN: float = 0.08
const RAMP_TIME: float = 2.0

# ============================================================================
# STATE LIFECYCLE
# ============================================================================

func _init() -> void:
	state_name = "IdleState"

func enter() -> void:
	super.enter()

	# Initialize camera and UI references
	_init_camera_refs()

	# Only apply camera mode on first entry (not after every turn)
	# Check if cameras are already in the correct state
	if first_person_camera and not first_person_camera.active and camera_mode == CameraMode.FPV:
		# First entry - need to activate FPV
		_apply_camera_mode()
	elif tactical_camera and not tactical_camera.camera.current and camera_mode == CameraMode.TACTICAL:
		# First entry in tactical mode
		_apply_camera_mode()
	# Otherwise cameras are already in correct state, don't reset them

	# Check if RT/Click is already being held (from previous state)
	var rt_currently_held = InputManager.is_action_pressed("move_confirm")
	if rt_currently_held and rt_held:
		# Continue the hold timer
		pass
	else:
		# Fresh entry or RT released - reset
		rt_held = false
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0

	# Check if LT/RMB is already being held (from previous state)
	var lt_currently_held = InputManager.is_action_pressed("wait_action")
	if lt_currently_held and lt_held:
		# Continue the hold timer
		pass
	else:
		# Fresh entry or LT released - reset
		lt_held = false
		lt_hold_time = 0.0
		lt_repeat_timer = 0.0

func exit() -> void:
	super.exit()
	# Note: We don't switch cameras on exit - camera mode persists

func _init_camera_refs() -> void:
	"""Initialize camera and UI references (can't use @onready in state nodes)"""
	if not player:
		return

	if not first_person_camera:
		first_person_camera = player.get_node_or_null("FirstPersonCamera")
	if not tactical_camera:
		tactical_camera = player.get_node_or_null("CameraRig")

	# Get examination UI components
	if not examination_crosshair:
		var game_3d = player.get_parent()
		if game_3d:
			examination_crosshair = game_3d.get_node_or_null("ViewportUILayer/ExaminationCrosshair")
	if not examination_panel:
		examination_panel = get_node_or_null("/root/Game/MarginContainer/HBoxContainer/RightSide/MarginContainer/VBoxContainer/ExaminationPanel")

	if not first_person_camera:
		push_error("[IdleState] FirstPersonCamera not found!")
	if not tactical_camera:
		push_error("[IdleState] TacticalCamera not found!")

# ============================================================================
# CAMERA MODE MANAGEMENT
# ============================================================================

func _toggle_camera() -> void:
	"""Toggle between FPV and Tactical camera modes"""
	if camera_mode == CameraMode.FPV:
		camera_mode = CameraMode.TACTICAL
		Log.state("Camera toggled to TACTICAL")
	else:
		camera_mode = CameraMode.FPV
		Log.state("Camera toggled to FPV")

	_apply_camera_mode()

func _apply_camera_mode() -> void:
	"""Apply the current camera mode settings"""
	match camera_mode:
		CameraMode.FPV:
			_enter_fpv_mode()
		CameraMode.TACTICAL:
			_enter_tactical_mode()

func _enter_fpv_mode() -> void:
	"""Switch to first-person view mode"""
	# Capture mouse for FPS-style camera control
	if not PauseManager.is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch cameras
	if tactical_camera:
		tactical_camera.camera.current = false
	if first_person_camera:
		first_person_camera.activate()

	# Hide move indicator in FPV
	if player and player.has_method("hide_move_indicator"):
		player.hide_move_indicator()

	# Show examination crosshair
	if examination_crosshair:
		examination_crosshair.show_crosshair()

	# Disable proximity fade (see-through-walls breaks FPV immersion)
	if player and player.grid:
		player.grid.set_proximity_fade_enabled(false)

func _enter_tactical_mode() -> void:
	"""Switch to tactical (third-person) view mode"""
	# Keep mouse captured for tactical camera control
	if not PauseManager.is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Switch cameras
	if first_person_camera:
		first_person_camera.deactivate()
	if tactical_camera:
		tactical_camera.camera.current = true

	# Show move indicator in tactical
	if player and player.has_method("update_move_indicator"):
		player.update_move_indicator()

	# Hide examination UI
	if examination_crosshair:
		examination_crosshair.hide_crosshair()
	if examination_panel:
		examination_panel.hide_panel()

	# Clear examination target
	current_target = null

	# Enable proximity fade (see-through-walls is useful in tactical view)
	if player and player.grid:
		player.grid.set_proximity_fade_enabled(true)

# ============================================================================
# INPUT HANDLING
# ============================================================================

func handle_input(_event: InputEvent) -> void:
	# All input handling is done in process_frame for consistency
	# This ensures single-trigger behavior and hold-to-repeat support
	pass

func process_frame(delta: float) -> void:
	if not InputManager:
		return

	# Skip input for one frame if requested (prevents UI button from triggering movement)
	if player and player.suppress_input_next_frame:
		player.suppress_input_next_frame = false
		_update_visuals()
		return

	# Update visuals based on camera mode
	_update_visuals()

	# Check for "Go To" target from map overlay
	if player and player.goto_target != Vector2i(-999999, -999999):
		transition_to("AutoExploreState")
		return

	# Check for auto-explore toggle (skip if just cancelled on this frame)
	if Input.is_action_just_pressed("auto_explore"):
		if _AutoExploreState.cancelled_on_frame != Engine.get_process_frames():
			transition_to("AutoExploreState")
			return

	# Check for map overlay toggle (skip if overlay was just closed this frame)
	if Input.is_action_just_pressed("open_map"):
		if _MapOverlayPanel.closed_on_frame != Engine.get_process_frames():
			var game_node = get_node_or_null("/root/Game")
			if game_node and game_node.map_overlay_panel:
				game_node.map_overlay_panel.show_overlay(player, player.grid)
		return

	# Check for camera toggle (use Godot's native check - doesn't need InputManager synthesis)
	if Input.is_action_just_pressed("toggle_camera"):
		_toggle_camera()
		return

	# Check for wait action (RMB/LT) - initial press
	if InputManager.is_action_just_pressed("wait_action"):
		_execute_wait_action()
		lt_held = true
		lt_hold_time = 0.0
		lt_repeat_timer = 0.0
		return

	# Handle RT/LMB for movement (hold-to-repeat)
	if InputManager.is_action_just_pressed("move_confirm"):
		_move_forward()
		rt_held = true
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0
		return

	# Track RT/Click hold state for repeat
	var rt_is_down = InputManager.is_action_pressed("move_confirm")

	if rt_is_down and rt_held:
		# RT/Click is being held - update repeat system
		rt_hold_time += delta
		rt_repeat_timer += delta

		# Calculate current repeat interval (ramps from START to MIN)
		var ramp_progress = clampf(rt_hold_time / RAMP_TIME, 0.0, 1.0)
		var current_interval = lerp(REPEAT_INTERVAL_START, REPEAT_INTERVAL_MIN, ramp_progress)

		# Check if we should trigger a repeat
		var should_repeat = false
		if rt_hold_time < INITIAL_DELAY:
			should_repeat = false
		elif rt_repeat_timer >= current_interval:
			should_repeat = true
			rt_repeat_timer = 0.0

		if should_repeat:
			_move_forward()
			return
	elif not rt_is_down:
		# RT/Click released
		rt_held = false
		rt_hold_time = 0.0
		rt_repeat_timer = 0.0
		last_blocked_direction = Vector2i(-999, -999)

	# Track LT/RMB hold state for wait repeat
	var lt_is_down = InputManager.is_action_pressed("wait_action")

	if lt_is_down and lt_held:
		# LT/RMB is being held - update repeat system
		lt_hold_time += delta
		lt_repeat_timer += delta

		# Calculate current repeat interval (ramps from START to MIN)
		var ramp_progress = clampf(lt_hold_time / RAMP_TIME, 0.0, 1.0)
		var current_interval = lerp(REPEAT_INTERVAL_START, REPEAT_INTERVAL_MIN, ramp_progress)

		# Check if we should trigger a repeat
		var should_repeat = false
		if lt_hold_time < INITIAL_DELAY:
			should_repeat = false
		elif lt_repeat_timer >= current_interval:
			should_repeat = true
			lt_repeat_timer = 0.0

		if should_repeat:
			_execute_wait_action()
			return
	elif not lt_is_down:
		# LT/RMB released
		lt_held = false
		lt_hold_time = 0.0
		lt_repeat_timer = 0.0

	# FPV-specific: Update examination target
	if camera_mode == CameraMode.FPV:
		_update_examination_target()

func _update_visuals() -> void:
	"""Update visual elements based on camera mode"""
	if camera_mode == CameraMode.TACTICAL:
		# Update move indicator in tactical mode
		if player:
			player.update_move_indicator()

# ============================================================================
# EXAMINATION (FPV ONLY)
# ============================================================================

func _update_examination_target() -> void:
	"""Update raycast and examination target in FPV mode"""
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
				KnowledgeDB.examine_environment(new_target.entity_id)
			elif new_target.entity_type == Examinable.EntityType.ITEM:
				# Items - need to get rarity for correct EXP reward
				var item = KnowledgeDB._get_item_by_id(new_target.entity_id)
				if item:
					var rarity_name = ItemRarity.RARITY_NAMES[item.rarity].to_lower()
					KnowledgeDB.examine_item(new_target.entity_id, rarity_name)
				else:
					# Fallback if item not found
					KnowledgeDB.examine_item(new_target.entity_id, "common")
			else:
				# Entities, hazards, objects
				var is_object = new_target.entity_type == Examinable.EntityType.ENTITY_NEUTRAL
				KnowledgeDB.examine_entity(new_target.entity_id, is_object)

			if examination_panel:
				examination_panel.show_panel(new_target)
		else:
			# Looking at nothing
			if examination_panel:
				examination_panel.hide_panel()

# ============================================================================
# ACTIONS
# ============================================================================

func _move_forward() -> void:
	"""Move forward in camera direction (or pick up item if present)"""
	if not player:
		return

	# Get forward direction from camera
	var forward_direction = Vector2i.ZERO
	if player.has_method("get_camera_forward_grid_direction"):
		forward_direction = player.get_camera_forward_grid_direction()

	if forward_direction == Vector2i.ZERO:
		return

	# Check if there's an item or vending machine at the target position
	var target_position = player.grid_position + forward_direction
	var item_at_target = _get_item_at_position(target_position)
	var entity_at_target = _get_vending_machine_at_position(target_position)

	# Check for vending machine first (blocks movement, opens UI without consuming a turn)
	if entity_at_target:
		var vm_action = VendingMachineAction.new(target_position, entity_at_target)
		if vm_action.can_execute(player):
			vm_action.execute(player)
			return

	# Create appropriate action (pickup or movement)
	var action: Action
	if item_at_target:
		action = PickupItemAction.new(target_position, item_at_target)
	else:
		action = MovementAction.new(forward_direction)

	# Execute action
	if action.can_execute(player):
		player.pending_action = action
		player.return_state = "IdleState"  # Return here after turn completes
		last_blocked_direction = Vector2i(-999, -999)  # Reset blocked tracking on success
		transition_to("PreTurnState")
	else:
		# Only warn on initial press, not during hold-to-repeat
		if not rt_held:
			Log.warn(Log.Category.MOVEMENT, "Cannot move forward - blocked!")

func _execute_wait_action() -> void:
	"""Execute a wait action (pass turn without moving)"""
	var wait_action = WaitAction.new()

	if wait_action.can_execute(player):
		player.pending_action = wait_action
		player.return_state = "IdleState"  # Return here after turn completes
		transition_to("PreTurnState")

# ============================================================================
# POSITION HELPERS
# ============================================================================

func _get_item_at_position(grid_pos: Vector2i) -> Dictionary:
	"""Check if there's an item at the given grid position"""
	if not player or not player.grid or not player.grid.item_renderer:
		return {}

	return player.grid.item_renderer.get_item_at(grid_pos)

func _get_vending_machine_at_position(grid_pos: Vector2i) -> WorldEntity:
	"""Check if there's a vending machine entity at the given grid position"""
	if not player or not player.grid:
		return null

	var entity = player.grid.get_entity_at(grid_pos)
	if entity and entity.entity_type == "vending_machine" and entity.is_alive():
		return entity
	return null
