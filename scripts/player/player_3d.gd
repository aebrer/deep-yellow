class_name Player3D
extends CharacterBody3D
## 3D player controller for turn-based movement
##
## TURN-BASED: Player SNAPs to grid positions instantly.
## Each action advances the entire game state by one discrete turn.
## No smooth interpolation - this is Caves of Qud style!

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when action preview should update (for UI)
## actions: Array of Action objects that will execute next turn
## Note: Emitted by states (IdleState, LookModeState), connected in game_3d.gd
@warning_ignore("unused_signal")
signal action_preview_changed(actions: Array[Action])

# ============================================================================
# STATE
# ============================================================================

# Grid state (SAME AS 2D VERSION)
var grid_position: Vector2i = Vector2i(64, 64)
var pending_action = null
var turn_count: int = 0

# Node references
var grid: Grid3D = null
var move_indicator: Node3D = null  # Set by Game node
@onready var model: Node3D = $Model
@onready var state_machine = $InputStateMachine
@onready var camera_rig: TacticalCamera = $CameraRig

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Add to player group for obstruction detection
	add_to_group("player")

	# Grid reference will be set by Game node
	await get_tree().process_frame

	if grid:
		# Start at debug position
		grid_position = Vector2i(69, 1)

		# SNAP to grid position (turn-based = no smooth movement)
		update_visual_position()

		Log.system("Player3D ready at grid position: %s" % grid_position)

func _unhandled_input(event: InputEvent) -> void:
	# Delegate to state machine
	if state_machine:
		state_machine.handle_input(event)

func _process(delta: float) -> void:
	# Delegate to state machine
	if state_machine:
		state_machine.process_frame(delta)

# ============================================================================
# MOVEMENT (SAME API AS 2D VERSION)
# ============================================================================

func update_visual_position() -> void:
	"""Update 3D position to match grid position - SNAP instantly (turn-based!)"""
	if not grid:
		return

	var world_pos = grid.grid_to_world(grid_position)
	world_pos.y = 1.0  # Slightly above ground (adjusted for new cell size)

	# TURN-BASED: Snap instantly to grid position, no lerping
	global_position = world_pos

# ============================================================================
# MOVEMENT INDICATOR (3D)
# ============================================================================

func get_camera_forward_grid_direction() -> Vector2i:
	"""Get the grid direction the camera is facing (1 cell ahead)"""
	if not camera_rig:
		return Vector2i(0, 1)  # Default forward

	# Get camera yaw - this is the direction the camera is rotated
	# We want forward direction to rotate WITH the camera (same direction)
	var camera_yaw_deg = camera_rig.h_pivot.rotation_degrees.y

	# Negate to match rotation direction, then add 270° offset to go from "left" to "forward"
	# (180° was left, 270° is forward)
	var forward_yaw_deg = -camera_yaw_deg + 270.0
	var yaw_rad = deg_to_rad(forward_yaw_deg)

	# Convert angle directly to octant (no need to rotate a vector)
	# Normalize angle to 0-2π range for clean octant calculation
	var normalized_angle = fmod(yaw_rad, 2.0 * PI)
	if normalized_angle < 0:
		normalized_angle += 2.0 * PI

	var octant = int(round(normalized_angle / (PI / 4.0))) % 8

	var directions := [
		Vector2i(1, 0),   # 0: Right (0°)
		Vector2i(1, 1),   # 1: Down-Right (45°)
		Vector2i(0, 1),   # 2: Down (90°)
		Vector2i(-1, 1),  # 3: Down-Left (135°)
		Vector2i(-1, 0),  # 4: Left (180°)
		Vector2i(-1, -1), # 5: Up-Left (225°)
		Vector2i(0, -1),  # 6: Up (270°)
		Vector2i(1, -1)   # 7: Up-Right (315°)
	]

	return directions[octant]

func update_move_indicator() -> void:
	"""Show forward indicator 1 cell ahead in camera direction"""
	if not grid or not move_indicator:
		return

	# Show indicator 1 cell ahead in camera direction
	var forward_direction = get_camera_forward_grid_direction()
	var target_pos = grid_position + forward_direction

	# Check if target is valid
	if grid.is_walkable(target_pos):
		# Show indicator at target position
		var world_pos = grid.grid_to_world(target_pos)
		world_pos.y = 0.1  # Just above floor to prevent z-fighting
		move_indicator.global_position = world_pos
		move_indicator.visible = true
	else:
		# Target is blocked - hide indicator or show as red
		move_indicator.visible = false

func hide_move_indicator() -> void:
	"""Hide movement preview"""
	if move_indicator:
		move_indicator.visible = false
