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

## Emitted when a turn completes (for turn-based systems like ChunkManager)
@warning_ignore("unused_signal")
signal turn_completed()

# ============================================================================
# STATE
# ============================================================================

# Grid state (SAME AS 2D VERSION)
var grid_position: Vector2i = Vector2i(64, 64)
var pending_action = null
var return_state: String = "IdleState"  # State to return to after turn completes
var turn_count: int = 0

# Stats (NEW)
var stats: StatBlock = null

# Item pools (4 pools: BODY, MIND, NULL, LIGHT)
var body_pool: ItemPool = null
var mind_pool: ItemPool = null
var null_pool: ItemPool = null
var light_pool: ItemPool = null

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

	# Initialize stats system
	_initialize_stats()

	# Grid reference will be set by Game node
	await get_tree().process_frame

	# CRITICAL: Wait for initial chunks to load before spawning
	# This ensures walkable_cells is populated and spawn position is valid
	if ChunkManager:
		Log.system("Player waiting for initial chunk load to complete...")
		await ChunkManager.initial_load_completed
		Log.system("Initial chunks loaded, proceeding with player spawn")

	if grid:
		# Build navigation graph for starting chunk (0,0) AND adjacent chunks
		# This allows spawn validation to check connectivity to neighboring chunks
		var starting_chunk := Vector2i(0, 0)
		var chunks_to_load := [
			starting_chunk,
			starting_chunk + Vector2i(0, -1),  # North
			starting_chunk + Vector2i(0, 1),   # South
			starting_chunk + Vector2i(-1, 0),  # West
			starting_chunk + Vector2i(1, 0)    # East
		]
		Pathfinding.build_navigation_graph(chunks_to_load, grid)

		# Find a spawn point that can reach at least 2/4 adjacent chunks
		# This ensures player isn't stuck in a dead-end or isolated area
		var spawn_found := false
		var max_attempts := 100  # Increased attempts for better reliability

		# Constrain spawn candidates to starting chunk only (not all 49 loaded chunks)
		# This ensures candidates are in the pathfinding graph we just built
		const CHUNK_SIZE := 128
		var starting_chunk_offset := starting_chunk * CHUNK_SIZE

		for attempt in range(max_attempts):
			# Sample candidate from within starting chunk (0,0)
			var local_x := randi() % CHUNK_SIZE
			var local_y := randi() % CHUNK_SIZE
			var candidate := starting_chunk_offset + Vector2i(local_x, local_y)

			# Skip if not walkable (in a wall)
			if not grid.is_walkable(candidate):
				continue

			# Validate spawn can reach at least 2 adjacent chunks (not in isolated area)
			if Pathfinding.can_reach_chunk_edges(candidate, starting_chunk):  # Default min_adjacent = 2
				grid_position = candidate
				spawn_found = true
				Log.system("Found valid spawn at %s after %d attempts (reaches 2+ adjacent chunks)" % [candidate, attempt + 1])
				break

		if not spawn_found:
			Log.warn(Log.Category.SYSTEM, "Could not find spawn that reaches 2+ adjacent chunks, using center of starting chunk")
			# Fallback: use center of starting chunk and hope for the best
			grid_position = starting_chunk_offset + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			# Find nearest walkable if center is a wall (search within starting chunk only)
			if not grid.is_walkable(grid_position):
				# Spiral search outward from center within starting chunk
				var found_walkable := false
				for radius in range(1, CHUNK_SIZE / 2):
					for dx in range(-radius, radius + 1):
						for dy in range(-radius, radius + 1):
							if abs(dx) + abs(dy) != radius:
								continue  # Only check tiles at this exact radius

							var test_pos := grid_position + Vector2i(dx, dy)
							if grid.is_walkable(test_pos):
								grid_position = test_pos
								found_walkable = true
								break
						if found_walkable:
							break
					if found_walkable:
						break

		# SNAP to grid position (turn-based = no smooth movement)
		update_visual_position()

		Log.system("Player3D ready at grid position: %s" % grid_position)

func _unhandled_input(event: InputEvent) -> void:
	# Block gameplay input when paused (UI navigation takes over)
	if PauseManager and PauseManager.is_paused:
		return

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

# ============================================================================
# STATS SYSTEM
# ============================================================================

func _initialize_stats() -> void:
	"""Initialize player stats from template (or defaults)"""
	# TODO: Load from StatTemplate resource when created
	# For now, use default StatBlock (BODY=5, MIND=5, NULL=0)
	stats = StatBlock.new()

	# Initialize item pools (3 slots each for BODY/MIND/NULL, 1 slot for LIGHT)
	body_pool = ItemPool.new(Item.PoolType.BODY, 3)
	mind_pool = ItemPool.new(Item.PoolType.MIND, 3)
	null_pool = ItemPool.new(Item.PoolType.NULL, 3)
	light_pool = ItemPool.new(Item.PoolType.LIGHT, 1)

	# DEBUG: Add DEBUG_ITEM to NULL pool for testing
	var debug_item = DebugItem.new()
	null_pool.add_item(debug_item, 0, self)  # Add to slot 0, enabled by default

	# Connect KnowledgeDB signals for EXP rewards
	KnowledgeDB.discovery_made.connect(_on_discovery_made)

	# Connect ChunkManager signals for exploration EXP
	ChunkManager.new_chunk_entered.connect(_on_new_chunk_entered)

	# Connect StatBlock signals
	stats.level_increased.connect(_on_level_increased)  # Triggers perk selection (TODO)
	stats.clearance_increased.connect(_on_clearance_increased)  # Syncs KnowledgeDB

	# Log for debugging
	Log.system("Player stats initialized: %s" % str(stats))
	Log.system("Item pools initialized: BODY=%s, MIND=%s, NULL=%s, LIGHT=%s" % [
		body_pool,
		mind_pool,
		null_pool,
		light_pool
	])

func _on_discovery_made(_subject_type: String, _subject_id: String, exp_reward: int) -> void:
	"""Called when player discovers something novel - award EXP"""
	if stats:
		stats.gain_exp(exp_reward)

func _on_new_chunk_entered(chunk_position: Vector3i) -> void:
	"""Called when player enters a new chunk - award exploration EXP"""
	if stats:
		var exp_reward = 10 * (stats.level + 1)
		stats.gain_exp(exp_reward)
		Log.player("Entered new chunk %s - awarded %d EXP (Level %d)" % [
			Vector2i(chunk_position.x, chunk_position.y),
			exp_reward,
			stats.level
		])

func _on_level_increased(old_level: int, new_level: int) -> void:
	"""Called when Level increases - trigger perk selection"""
	Log.player("Player Level Up! %d → %d" % [old_level, new_level])
	# TODO: Show perk selection UI

func _on_clearance_increased(old_level: int, new_level: int) -> void:
	"""Called when Clearance increases (via perk choice) - sync with KnowledgeDB"""
	KnowledgeDB.set_clearance_level(new_level)
	Log.player("Player Clearance increased: %d → %d (knowledge unlocked)" % [old_level, new_level])

# ============================================================================
# ITEM SYSTEM
# ============================================================================

func execute_item_pools() -> void:
	"""Execute all item pools in order (called each turn)

	Execution order: BODY → MIND → NULL → LIGHT
	This order matters for synergies between items.
	"""
	if body_pool:
		body_pool.execute_turn(self, turn_count)
	if mind_pool:
		mind_pool.execute_turn(self, turn_count)
	if null_pool:
		null_pool.execute_turn(self, turn_count)
	if light_pool:
		light_pool.execute_turn(self, turn_count)
