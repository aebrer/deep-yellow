extends PlayerInputState
## Auto-Explore State - Automatically navigates toward unexplored tiles
##
## Activated by pressing Y key / Y button. Automatically moves the player
## toward the nearest unexplored tile at a configurable speed. Stops on
## various conditions (enemies, low HP, items, stairs, manual input).

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

	# Show HUD indicator
	_show_hud_indicator(true)

	# Mark current position as explored
	_mark_current_explored()

	# Check if there's anywhere to go
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

	# Check for objects to navigate toward (items, stairs)
	var nav_target := _find_navigate_target()
	var target := ExplorationTracker.NO_TARGET

	if not nav_target.is_empty():
		var obj_pos: Vector2i = nav_target["position"]
		var chebyshev_dist := maxi(absi(obj_pos.x - player.grid_position.x), absi(obj_pos.y - player.grid_position.y))

		if chebyshev_dist <= 1:
			# Already adjacent — stop
			# Mark vending machines as visited so we don't stop for them again
			if nav_target["reason"] == "vending machine detected":
				ExplorationTracker.mark_vending_machine_visited(obj_pos)
			Log.state("Auto-explore: Stopped - %s (adjacent)" % nav_target["reason"])
			Log.player("Auto-explore stopped: %s" % nav_target["reason"])
			transition_to("IdleState")
			return
		else:
			# Path toward the object
			target = obj_pos
	else:
		# No navigate target — find nearest unexplored tile
		target = ExplorationTracker.find_nearest_unexplored(player.grid_position)

	if target == ExplorationTracker.NO_TARGET:
		Log.state("Auto-explore: Fully explored, returning to idle")
		Log.player("Auto-explore: Fully explored!")
		transition_to("IdleState")
		return

	# Get path to target
	var path := Pathfinding.find_path(player.grid_position, target)
	if path.size() < 2:
		Log.state("Auto-explore: No path to target, returning to idle")
		Log.player("Auto-explore stopped: no path to target")
		transition_to("IdleState")
		return

	# Extract next step direction from path
	var next_pos = Vector2i(int(path[1].x), int(path[1].y))
	var direction = next_pos - player.grid_position

	# Rotate camera to face movement direction
	_rotate_camera_to_direction(direction)

	# Check for item at target (auto-pickup)
	var item_at_target = _get_item_at_position(next_pos)

	# Create action
	var action: Action
	if item_at_target and not item_at_target.is_empty():
		action = PickupItemAction.new(next_pos, item_at_target)
	else:
		action = MovementAction.new(direction)

	# Validate and submit
	if action.can_execute(player):
		hp_before_step = player.stats.current_hp if player.stats else 0.0
		player.pending_action = action
		player.return_state = "AutoExploreState"
		waiting_for_turn = true
		transition_to("PreTurnState")
	else:
		Log.state("Auto-explore: Movement blocked, returning to idle")
		Log.player("Auto-explore stopped: movement blocked")
		transition_to("IdleState")

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

	# Check for enemies in perception range
	if Utilities.auto_explore_stop_for_enemies:
		if _enemies_in_range():
			return "enemy detected"

	return ""

func _find_navigate_target() -> Dictionary:
	"""Find an object to navigate toward before stopping.

	Returns {"position": Vector2i, "reason": String} or empty dict if none.
	These are objects we want to path NEXT TO before stopping (items, stairs, vending machines).
	"""
	if not player or not player.stats:
		return {}

	var perception_range: float = 15.0 + (player.stats.perception * 5.0)

	# Check for items in perception range
	if Utilities.auto_explore_stop_for_items:
		var nearest_item = _nearest_item_in_range(perception_range)
		if nearest_item != ExplorationTracker.NO_TARGET:
			return {"position": nearest_item, "reason": "item detected"}

		# Vending machines follow the same rules as items
		var nearest_vending = _nearest_vending_machine_in_range(perception_range)
		if nearest_vending != ExplorationTracker.NO_TARGET:
			return {"position": nearest_vending, "reason": "vending machine detected"}

	# Check for stairs nearby (within perception range, not just standing on them)
	if Utilities.auto_explore_stop_at_stairs:
		var stairs_pos = _find_stairs_in_range(perception_range)
		if stairs_pos != ExplorationTracker.NO_TARGET:
			return {"position": stairs_pos, "reason": "stairs detected"}

	return {}

func _enemies_in_range() -> bool:
	if not player or not player.grid or not player.grid.entity_renderer:
		return false

	var perception_range: float = 15.0 + (player.stats.perception * 5.0)
	var entity_positions = player.grid.entity_renderer.get_all_entity_positions()

	for entity_pos in entity_positions:
		var dist := Vector2(player.grid_position).distance_to(Vector2(entity_pos))
		if dist <= perception_range:
			return true

	return false

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

func _get_item_at_position(grid_pos: Vector2i) -> Dictionary:
	if not player or not player.grid or not player.grid.item_renderer:
		return {}
	return player.grid.item_renderer.get_item_at(grid_pos)

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
