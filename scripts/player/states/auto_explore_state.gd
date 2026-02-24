extends PlayerInputState
## Auto-Explore State - Automatically navigates toward unexplored tiles
##
## Activated by pressing Y key / Y button. Automatically moves the player
## toward the nearest unexplored tile at a configurable speed. Stops on
## various conditions (enemies, low HP, items, stairs, manual input).
##
## Performance optimization: Caches the full path to a distant target and
## follows it step-by-step, only recalculating when interrupted by discoveries
## (items, vending machines, enemies) or when the path is exhausted.

# ============================================================================
# STATE
# ============================================================================

## Time accumulator for step timing
var step_timer: float = 0.0

## Whether we're waiting for a turn to complete (between PreTurnState and return)
var waiting_for_turn: bool = false

## HP at start of last step (for damage detection)
var hp_before_step: float = 0.0

## Reference to the HUD indicator label (set by game_3d or found on enter)
var hud_label: Label = null

## Cached path to current target (array of Vector2i positions)
var _cached_path: Array = []

## Current index in cached path (next position to move to)
var _cached_path_index: int = 0

## The target position we're pathing toward
var _cached_target: Vector2i = ExplorationTracker.NO_TARGET

## If true, we're pathing to be adjacent to an interrupt target (stop when path ends)
var _pathing_to_interrupt: bool = false

## Reason for the interrupt (for logging when we stop)
var _interrupt_reason: String = ""

## If true, navigating to a specific "Go To" target — skip item/vending interrupt checks
var _goto_mode: bool = false

## Persistent goto target position — survives path recalculations so we can retry
## when the target chunk loads
var _goto_target: Vector2i = Vector2i(-999999, -999999)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _init() -> void:
	state_name = "AutoExploreState"

func enter() -> void:
	super.enter()
	var is_resuming := waiting_for_turn
	step_timer = 0.0
	waiting_for_turn = false

	if player and player.stats:
		hp_before_step = player.stats.current_hp

	# Show HUD indicator, hide control hints (MOVE/WAIT not relevant during auto-explore)
	_show_hud_indicator(true)
	_set_control_hints_visible(false)

	# Mark current position as explored
	_mark_current_explored()

	# On fresh start (not resuming from turn), clear cached path and goto state
	if not is_resuming:
		_clear_cached_path()
		_goto_mode = false
		_goto_target = Vector2i(-999999, -999999)

	# Check for "Go To" target from map overlay (takes priority over exploration)
	if not is_resuming and player.goto_target != Vector2i(-999999, -999999):
		_goto_target = player.goto_target
		player.goto_target = Vector2i(-999999, -999999)  # Consume the target
		_goto_mode = true  # Skip item/vending interrupt checks during goto
		_recalculate_path(_goto_target)
		if not _cached_path.is_empty():
			_pathing_to_interrupt = true
			_interrupt_reason = "arrived at marker"
			Log.state("Auto-explore: Go To target at %s" % str(_goto_target))
			Log.player("Navigating to marker...")
			return
		# Path failed (target likely in unloaded chunk) — find intermediate waypoint
		Log.state("Auto-explore: Go To target unreachable, finding waypoint")
		var waypoint := _find_goto_waypoint()
		if waypoint != Vector2i(-999999, -999999):
			_recalculate_path(waypoint)
			if not _cached_path.is_empty():
				Log.player("Navigating toward marker...")
				return
		# No waypoint found either — fall through to normal exploration
		Log.player("Navigating toward marker...")

	# Check if there's anywhere to go (quick check, full path calculated in process_frame)
	var target = ExplorationTracker.find_nearest_unexplored(player.grid_position)
	if target == ExplorationTracker.NO_TARGET:
		Log.state("Auto-explore: No unexplored tiles found, returning to idle")
		Log.player("Auto-explore: No unexplored tiles reachable")
		transition_to("IdleState")
		return

	if not is_resuming:
		Log.state("Auto-explore: Started, nearest unexplored at %s" % str(target))
		Log.player("Auto-explore started")

func exit() -> void:
	super.exit()
	_show_hud_indicator(false)
	_set_control_hints_visible(true)
	# Only clear cached state on actual cancellation (not turn transitions).
	# During a turn, waiting_for_turn is true — we want to preserve the path.
	if not waiting_for_turn:
		_clear_cached_path()
		ExplorationTracker.invalidate_target()

# ============================================================================
# INPUT - Any input cancels auto-explore
# ============================================================================

## Frame on which auto-explore was cancelled (prevents re-trigger on same frame)
static var cancelled_on_frame: int = -1

func handle_input(_event: InputEvent) -> void:
	# Any meaningful input cancels auto-explore
	var should_cancel := false
	if _event is InputEventKey and _event.pressed:
		should_cancel = true
	elif _event is InputEventMouseButton and _event.pressed:
		should_cancel = true
	elif _event is InputEventJoypadButton and _event.pressed:
		should_cancel = true
	elif _event is InputEventJoypadMotion and abs(_event.axis_value) > 0.5:
		should_cancel = true

	if should_cancel:
		Log.state("Auto-explore: Cancelled by player input")
		Log.player("Auto-explore cancelled: player input")
		cancelled_on_frame = Engine.get_process_frames()
		transition_to("IdleState")
		return

# ============================================================================
# FRAME PROCESSING
# ============================================================================

func process_frame(delta: float) -> void:
	if not player:
		return

	# Don't process while waiting for turn to complete
	if waiting_for_turn:
		return

	# Accumulate time
	step_timer += delta

	# Check if it's time for the next step
	var step_interval := 1.0 / Utilities.auto_explore_speed
	if step_timer < step_interval:
		return

	step_timer = 0.0

	# Check immediate stop conditions (damage, HP, sanity, enemies)
	var stop_reason := _check_stop_conditions()
	if not stop_reason.is_empty():
		Log.state("Auto-explore: Stopped - %s" % stop_reason)
		Log.player("Auto-explore stopped: %s" % stop_reason)
		transition_to("IdleState")
		return

	_mark_current_explored()

	# Check for interrupt targets (items, vending machines, stairs) that should
	# override the current path. These are things we discovered while exploring.
	# Skip only when actively pathing to a goto target (not during fallback exploration).
	var _on_goto_path := _goto_mode and _pathing_to_interrupt
	var interrupt := _check_for_interrupt_target() if not _on_goto_path else {}
	if not interrupt.is_empty():
		var obj_pos: Vector2i = interrupt["position"]
		var chebyshev_dist := maxi(absi(obj_pos.x - player.grid_position.x), absi(obj_pos.y - player.grid_position.y))

		if chebyshev_dist <= 1:
			# Already adjacent to interrupt target — stop
			if interrupt["reason"] == "vending machine detected":
				ExplorationTracker.mark_vending_machine_visited(obj_pos)
			Log.state("Auto-explore: Stopped - %s (adjacent)" % interrupt["reason"])
			Log.player("Auto-explore stopped: %s" % interrupt["reason"])
			transition_to("IdleState")
			return
		else:
			# Interrupt target found — recalculate path to adjacent cell
			Log.state("Auto-explore: Interrupted by %s, recalculating path" % interrupt["reason"])
			_recalculate_path_adjacent(obj_pos, interrupt["reason"])

	# If no cached path or path exhausted, check what to do next
	if _cached_path.is_empty() or _cached_path_index >= _cached_path.size():
		# If we were pathing to an interrupt target, stop now (we've arrived adjacent)
		if _pathing_to_interrupt:
			# Mark vending machine as visited if that's what we stopped for
			if _interrupt_reason == "vending machine detected":
				ExplorationTracker.mark_vending_machine_visited(_cached_target)
			Log.state("Auto-explore: Stopped - %s (arrived adjacent)" % _interrupt_reason)
			Log.player("Auto-explore stopped: %s" % _interrupt_reason)
			transition_to("IdleState")
			return

		# If in goto mode, retry pathing to target (chunk may now be loaded)
		if _goto_mode:
			# Check if we've arrived at the exact goto position
			if player.grid_position == _goto_target:
				Log.state("Auto-explore: Arrived at goto target")
				Log.player("Arrived at marker")
				transition_to("IdleState")
				return
			# Try direct path first
			_recalculate_path(_goto_target)
			if not _cached_path.is_empty():
				_pathing_to_interrupt = true
				_interrupt_reason = "arrived at marker"
				Log.state("Auto-explore: Direct path to goto target found")
				return
			# Direct path failed — find intermediate waypoint
			var waypoint := _find_goto_waypoint()
			if waypoint != Vector2i(-999999, -999999):
				_recalculate_path(waypoint)
				if not _cached_path.is_empty():
					Log.state("Auto-explore: Waypoint toward goto target at %s" % str(waypoint))
					return

		# Otherwise, find a new exploration target
		var target := ExplorationTracker.find_nearest_unexplored(player.grid_position)
		if target == ExplorationTracker.NO_TARGET:
			Log.state("Auto-explore: Fully explored, returning to idle")
			Log.player("Auto-explore: Fully explored!")
			transition_to("IdleState")
			return
		_recalculate_path(target)

	# Validate cached path still exists
	if _cached_path.is_empty() or _cached_path_index >= _cached_path.size():
		Log.state("Auto-explore: No path to target, returning to idle")
		Log.player("Auto-explore stopped: no path to target")
		transition_to("IdleState")
		return

	# Get next position from cached path
	var next_pos: Vector2i = _cached_path[_cached_path_index]

	# Safety check: if next position isn't adjacent, path is stale — recalculate
	var dist_to_next := maxi(absi(next_pos.x - player.grid_position.x), absi(next_pos.y - player.grid_position.y))
	if dist_to_next != 1:
		Log.state("Auto-explore: Path stale (next pos not adjacent), recalculating")
		_clear_cached_path()
		return  # Will recalculate on next frame

	var direction: Vector2i = next_pos - player.grid_position

	# Advance path index for next turn
	_cached_path_index += 1

	# Rotate camera to face movement direction
	_rotate_camera_to_direction(direction)

	# Create movement action
	var action: Action = MovementAction.new(direction)

	# Validate and submit
	if action.can_execute(player):
		hp_before_step = player.stats.current_hp if player.stats else 0.0
		player.pending_action = action
		player.return_state = "AutoExploreState"
		waiting_for_turn = true
		transition_to("PreTurnState")
	else:
		# Movement blocked — cancel auto-explore entirely
		Log.state("Auto-explore: Movement blocked, cancelling")
		Log.player("Auto-explore stopped: path blocked")
		transition_to("IdleState")
		return

# ============================================================================
# STOP CONDITIONS
# ============================================================================

func _check_stop_conditions() -> String:
	"""Check for conditions that immediately stop auto-explore."""
	if not player or not player.stats:
		return "no player"

	# Check damage taken
	if Utilities.auto_explore_stop_on_damage:
		if player.stats.current_hp < hp_before_step:
			return "took damage"

	# Check HP threshold
	var hp_pct: float = player.stats.current_hp / player.stats.max_hp
	if hp_pct < Utilities.auto_explore_hp_threshold:
		return "HP below threshold (%.0f%%)" % (hp_pct * 100)

	# Check sanity threshold
	var sanity_pct: float = player.stats.current_sanity / player.stats.max_sanity
	if sanity_pct < Utilities.auto_explore_sanity_threshold:
		return "Sanity below threshold (%.0f%%)" % (sanity_pct * 100)

	# Check for enemies in perception range (based on threat threshold)
	var threat_enemy = _threatening_enemy_in_range()
	if not threat_enemy.is_empty():
		return "enemy detected (%s)" % threat_enemy

	return ""

func _check_for_interrupt_target() -> Dictionary:
	"""Check for objects that should interrupt current path (items, stairs, vending machines).

	Returns {"position": Vector2i, "reason": String} or empty dict if none.
	These are objects we want to path NEXT TO before stopping.
	Only returns targets that aren't already our current destination (to avoid re-interrupting).
	"""
	if not player or not player.stats:
		return {}

	var perception_range: float = 15.0 + (player.stats.perception * 5.0)

	# Check for items in perception range
	if Utilities.auto_explore_stop_for_items:
		var nearest_item = _nearest_item_in_range(perception_range)
		if nearest_item != ExplorationTracker.NO_TARGET and nearest_item != _cached_target:
			return {"position": nearest_item, "reason": "item detected"}

		# Vending machines follow the same rules as items
		var nearest_vending = _nearest_vending_machine_in_range(perception_range)
		if nearest_vending != ExplorationTracker.NO_TARGET and nearest_vending != _cached_target:
			return {"position": nearest_vending, "reason": "vending machine detected"}

	# Check for stairs nearby (within perception range, not just standing on them)
	if Utilities.auto_explore_stop_at_stairs:
		var stairs_pos = _find_stairs_in_range(perception_range)
		if stairs_pos != ExplorationTracker.NO_TARGET and stairs_pos != _cached_target:
			return {"position": stairs_pos, "reason": "stairs detected"}

	return {}

func _threatening_enemy_in_range() -> String:
	"""Check for entities with threat level >= threshold within perception range.

	Returns the entity name if a threatening entity is found, empty string otherwise.
	Threshold 0 stops for all hostile entities.
	"""
	if not player or not player.grid or not player.grid.entity_renderer:
		return ""

	var perception_range: float = 15.0 + (player.stats.perception * 5.0)
	var threshold: int = Utilities.auto_explore_enemy_threat_threshold
	var entity_positions = player.grid.entity_renderer.get_all_entity_positions()

	for entity_pos in entity_positions:
		var dist := Vector2(player.grid_position).distance_to(Vector2(entity_pos))
		if dist > perception_range:
			continue

		# Get entity - only check hostile entities
		var entity = player.grid.entity_renderer.get_entity_at(entity_pos)
		if not entity or not entity.hostile:
			continue

		# Look up threat level from EntityRegistry
		var threat_level: int = 1  # default
		var entity_name: String = entity.entity_type
		if EntityRegistry and EntityRegistry.has_entity(entity.entity_type):
			var info = EntityRegistry.get_info(entity.entity_type, 0)
			threat_level = info.get("threat_level", 1)
			entity_name = info.get("name", entity.entity_type)

		if threat_level >= threshold:
			return entity_name

	return ""

func _nearest_item_in_range(perception_range: float) -> Vector2i:
	"""Find the nearest discovered item within perception range. Returns NO_TARGET if none."""
	if not player or not player.grid or not player.grid.item_renderer:
		return ExplorationTracker.NO_TARGET

	var item_positions = player.grid.item_renderer.get_discovered_item_positions()
	var nearest_pos := ExplorationTracker.NO_TARGET
	var nearest_dist := INF

	for item_pos in item_positions:
		# Skip items the player chose to leave on ground
		if ExplorationTracker.is_item_dismissed(item_pos):
			continue
		var dist := Vector2(player.grid_position).distance_to(Vector2(item_pos))
		if dist <= perception_range and dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = item_pos

	return nearest_pos

func _nearest_vending_machine_in_range(perception_range: float) -> Vector2i:
	"""Find the nearest vending machine within perception range. Returns NO_TARGET if none."""
	if not player or not player.grid or not player.grid.entity_renderer:
		return ExplorationTracker.NO_TARGET

	var nearest_pos := ExplorationTracker.NO_TARGET
	var nearest_dist := INF

	var entity_positions = player.grid.entity_renderer.get_all_entity_positions()
	for entity_pos in entity_positions:
		var entity = player.grid.entity_renderer.get_entity_at(entity_pos)
		if not entity or entity.entity_type != "vending_machine":
			continue
		# Skip vending machines we already stopped at
		if ExplorationTracker.is_vending_machine_visited(entity_pos):
			continue
		var dist := Vector2(player.grid_position).distance_to(Vector2(entity_pos))
		if dist <= perception_range and dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = entity_pos

	return nearest_pos

func _find_stairs_in_range(perception_range: float) -> Vector2i:
	"""Find exit stairs within perception range. Returns NO_TARGET if none."""
	if not player or not ChunkManager:
		return ExplorationTracker.NO_TARGET

	var current_level := LevelManager.get_current_level()
	if not current_level:
		return ExplorationTracker.NO_TARGET

	# Search walkable tiles within perception range for stairs
	var range_int := int(perception_range)
	for dy in range(-range_int, range_int + 1):
		for dx in range(-range_int, range_int + 1):
			var pos: Vector2i = player.grid_position + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > perception_range:
				continue
			var tile_type := ChunkManager.get_tile_type(pos, current_level.level_id)
			if tile_type == SubChunk.TileType.EXIT_STAIRS:
				return pos

	return ExplorationTracker.NO_TARGET

# ============================================================================
# PATH CACHING
# ============================================================================

func _find_goto_waypoint() -> Vector2i:
	"""Find an intermediate waypoint toward the goto target within loaded chunks.

	When the goto target is in an unloaded chunk, we can't pathfind to it directly.
	This walks a line from the player toward the target at decreasing distances,
	returning the furthest reachable tile. The player moves there, chunks load,
	and we retry the full path.
	"""
	var dir := Vector2(_goto_target - player.grid_position).normalized()
	# Try progressively closer distances along the line toward the target
	for dist in [30, 25, 20, 15, 10, 7, 5]:
		var candidate: Vector2i = player.grid_position + Vector2i(roundi(dir.x * dist), roundi(dir.y * dist))
		if candidate == player.grid_position:
			continue
		if not Pathfinding.has_point(candidate):
			continue
		var path := Pathfinding.find_path(player.grid_position, candidate)
		if path.size() >= 2:
			return candidate
	return Vector2i(-999999, -999999)

func _clear_cached_path() -> void:
	"""Clear the cached path, forcing recalculation on next step.
	Note: _goto_mode and _goto_target are NOT cleared here — they persist across
	path segments so we can retry reaching the target as chunks load."""
	_cached_path.clear()
	_cached_path_index = 0
	_cached_target = ExplorationTracker.NO_TARGET
	_pathing_to_interrupt = false
	_interrupt_reason = ""

func _recalculate_path(target: Vector2i) -> void:
	"""Calculate and cache a new path to the given target (exploration target)."""
	_cached_target = target
	_pathing_to_interrupt = false
	_interrupt_reason = ""
	var path := Pathfinding.find_path(player.grid_position, target)

	if path.size() < 2:
		_clear_cached_path()
		return

	# Convert path to Vector2i array, skipping first element (current position)
	_cached_path.clear()
	for i in range(1, path.size()):
		_cached_path.append(Vector2i(int(path[i].x), int(path[i].y)))
	_cached_path_index = 0

	Log.state("Auto-explore: Cached path with %d steps to %s" % [_cached_path.size(), str(target)])

func _recalculate_path_adjacent(target: Vector2i, reason: String) -> void:
	"""Calculate path to a walkable cell adjacent to target (for items, vending machines, stairs)."""
	_cached_target = target
	_pathing_to_interrupt = true
	_interrupt_reason = reason

	# Find the best adjacent walkable cell (closest to player)
	var adjacent_cells: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var adj_pos := target + Vector2i(dx, dy)
			if Pathfinding.has_point(adj_pos):
				adjacent_cells.append(adj_pos)

	if adjacent_cells.is_empty():
		Log.state("Auto-explore: No walkable cells adjacent to %s" % reason)
		_clear_cached_path()
		return

	# Find path to nearest adjacent cell
	var best_path: Array = []
	var best_length: int = 999999

	for adj_pos in adjacent_cells:
		var path := Pathfinding.find_path(player.grid_position, adj_pos)
		if path.size() >= 2 and path.size() < best_length:
			best_path = path
			best_length = path.size()
			if best_length == 2:
				break  # Can't do better than 1 step away

	if best_path.size() < 2:
		_clear_cached_path()
		return

	# Convert path to Vector2i array, skipping first element (current position)
	_cached_path.clear()
	for i in range(1, best_path.size()):
		_cached_path.append(Vector2i(int(best_path[i].x), int(best_path[i].y)))
	_cached_path_index = 0

	Log.state("Auto-explore: Cached path with %d steps to adjacent cell of %s" % [_cached_path.size(), reason])

# ============================================================================
# HELPERS
# ============================================================================

func _mark_current_explored() -> void:
	if not player or not player.stats:
		return
	var perception_range: float = 15.0 + (player.stats.perception * 5.0)
	ExplorationTracker.mark_explored(player.grid_position, perception_range)

func _rotate_camera_to_direction(direction: Vector2i) -> void:
	"""Rotate the FPV camera to face the movement direction with smooth tweening"""
	if not player or not player.first_person_camera:
		return

	# Direction → forward angle (degrees) mapping
	# Based on octant array in get_camera_forward_grid_direction:
	# (1,0)→0°, (1,1)→45°, (0,1)→90°, (-1,1)→135°, (-1,0)→180°, (-1,-1)→225°, (0,-1)→270°, (1,-1)→315°
	var forward_angle := rad_to_deg(atan2(direction.y, direction.x))
	if forward_angle < 0:
		forward_angle += 360.0

	# Inverse of: forward_yaw_deg = -camera_yaw_deg + 270
	# So: camera_yaw_deg = 270 - forward_angle
	var target_yaw := 270.0 - forward_angle

	# Normalize to -180..180 range
	target_yaw = fmod(target_yaw + 180.0, 360.0) - 180.0

	# Smooth rotation via tween (Anathema Interloper pattern)
	var current_yaw: float = player.first_person_camera.h_pivot.rotation_degrees.y

	# Find shortest rotation path
	var delta_yaw: float = target_yaw - current_yaw
	while delta_yaw > 180.0:
		delta_yaw -= 360.0
	while delta_yaw < -180.0:
		delta_yaw += 360.0
	var final_yaw: float = current_yaw + delta_yaw

	var tween = player.get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(player.first_person_camera.h_pivot, "rotation_degrees:y", final_yaw, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Also sync tactical camera
	if player.camera_rig:
		tween.tween_property(player.camera_rig.h_pivot, "rotation_degrees:y", final_yaw, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_control_hints_visible(is_visible: bool) -> void:
	"""Show or hide the persistent MOVE/WAIT control hints"""
	if not player:
		return
	var game_3d = player.get_parent()
	if game_3d and game_3d.control_hints:
		game_3d.control_hints.visible = is_visible

func _show_hud_indicator(visible: bool) -> void:
	"""Show or hide the AUTO-EXPLORE HUD indicator"""
	if not hud_label and player:
		# Create the label dynamically in the ViewportUILayer
		var game_3d = player.get_parent()
		var ui_layer = game_3d.get_node_or_null("ViewportUILayer") if game_3d else null
		if ui_layer:
			hud_label = Label.new()
			hud_label.name = "AutoExploreLabel"
			hud_label.text = "AUTO-EXPLORE"
			hud_label.add_theme_font_size_override("font_size", 18)
			hud_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
			hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
			hud_label.add_theme_constant_override("shadow_offset_x", 1)
			hud_label.add_theme_constant_override("shadow_offset_y", 1)
			# Position at top-center of screen
			hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hud_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
			hud_label.offset_top = 40
			hud_label.offset_left = -150
			hud_label.offset_right = 150
			ui_layer.add_child(hud_label)

	if hud_label:
		hud_label.visible = visible
