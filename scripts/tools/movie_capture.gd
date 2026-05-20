extends Control
## Automated atmospheric capture using the actual in-game scene.
##
## This intentionally instances scenes/game.tscn (the real HUD/game scene), then
## displays only its existing SubViewport full-screen for the movie writer. The
## renderer, SubViewport, Game3D scene, chunk streaming, shaders, post-process,
## and level transition path are the same systems used in normal gameplay.
##
## Godot's --write-movie records from frame 1, so this script writes a marker
## file when the warm-up is complete. The batch script uses that marker to encode
## only the real capture window and discard loading/build-up frames.

@export_range(10.0, 300.0) var capture_duration: float = 60.0
@export_range(0.0, 120.0) var warmup_duration: float = 30.0
@export var output_resolution: Vector2i = Vector2i(640, 480)

enum CameraMode {
	FPV_ORBIT,
	TACTICAL_ORBIT,
}

@export var camera_mode: CameraMode = CameraMode.FPV_ORBIT

const VIEWPORT_CONTAINER_PATH := "MarginContainer/HBoxContainer/LeftSide/ViewportPanel/MarginContainer/SubViewportContainer"
const SUBVIEWPORT_PATH := VIEWPORT_CONTAINER_PATH + "/SubViewport"
const GAME_3D_PATH := SUBVIEWPORT_PATH + "/Game3D"

var _game_root: Control
var _viewport_container: SubViewportContainer
var _subviewport: SubViewport
var _game_3d: Node3D
var _player: Node3D
var _grid: Grid3D
var _elapsed: float = 0.0


func _enter_tree() -> void:
	get_window().size = output_resolution
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	seed(Time.get_ticks_usec())
	_apply_environment_overrides()

	var game_scene := preload("res://scenes/game.tscn")
	_game_root = game_scene.instantiate()
	# Avoid ChunkManager's normal /root/Game auto-start while still using the
	# actual game scene. We explicitly start the run below after references exist,
	# so no tutorial chunks are queued before jumping to Level 0.
	_game_root.name = "MovieCaptureGame"
	add_child(_game_root)
	_game_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Let the real game scene run its normal _ready() path.
	await get_tree().process_frame
	await get_tree().process_frame

	if not _wire_references():
		get_tree().quit(1)
		return

	_isolate_existing_game_viewport()
	_hide_capture_ui()

	# Start a fresh run explicitly, then ensure ChunkManager has discovered the
	# actual game's Grid3D/Player3D.
	if ChunkManager:
		ChunkManager.start_new_run()
		ChunkManager._find_grid_3d()
		ChunkManager._connect_to_player_signal()

	# Use the normal level-change path so the real game scene configures visuals.
	await _load_level_0()

	# Move away from spawn spraypaint without leaving the safe loaded interior.
	_disable_player_input()
	_move_to_atmospheric_position()
	_setup_camera()
	_hide_capture_ui()

	# Let post-process, flicker/lightmap, chunk streaming, and GPU resources settle.
	await get_tree().create_timer(warmup_duration).timeout

	_write_capture_start_marker()
	Log.system("[MovieCapture] Locked-off capture window started at frame %d" % Engine.get_frames_drawn())

	get_tree().create_timer(capture_duration).timeout.connect(_on_capture_timeout)


func _apply_environment_overrides() -> void:
	var env_capture_duration := OS.get_environment("DY_CAPTURE_DURATION")
	if env_capture_duration != "":
		capture_duration = env_capture_duration.to_float()

	var env_warmup_duration := OS.get_environment("DY_CAPTURE_WARMUP")
	if env_warmup_duration != "":
		warmup_duration = env_warmup_duration.to_float()


func _wire_references() -> bool:
	_viewport_container = _game_root.get_node_or_null(VIEWPORT_CONTAINER_PATH)
	_subviewport = _game_root.get_node_or_null(SUBVIEWPORT_PATH)
	_game_3d = _game_root.get_node_or_null(GAME_3D_PATH)

	if not _viewport_container or not _subviewport or not _game_3d:
		push_error("[MovieCapture] Failed to find actual game viewport nodes")
		return false

	_player = _game_3d.get_node_or_null("Player3D")
	_grid = _game_3d.get_node_or_null("Grid3D")
	if not _player or not _grid:
		push_error("[MovieCapture] Failed to find Player3D or Grid3D")
		return false

	return true


func _isolate_existing_game_viewport() -> void:
	"""Show the real game's SubViewport full-screen, without recreating rendering."""
	var old_parent := _viewport_container.get_parent()
	if old_parent:
		old_parent.remove_child(_viewport_container)

	add_child(_viewport_container)
	move_child(_viewport_container, get_child_count() - 1)
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.offset_left = 0.0
	_viewport_container.offset_top = 0.0
	_viewport_container.offset_right = 0.0
	_viewport_container.offset_bottom = 0.0
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	_viewport_container.visible = true

	# Keep the game logic alive but hide the HUD layout that used to contain the viewport.
	_game_root.visible = false


func _hide_capture_ui() -> void:
	"""Hide UI overlays while preserving post-process and world rendering."""
	# In-viewport game UI.
	for node_path in ["ViewportUILayer", "TextUIOverlay", "LoadingScreen", "MoveIndicator"]:
		var node := _game_3d.get_node_or_null(node_path)
		if node:
			node.visible = false

	# The external HUD is not in the SubViewport after reparenting, but hide it for
	# the live window too. This does not affect saved gameplay state.
	for node_path in [
		"FPSCounter",
		"MarginContainer/HBoxContainer/LeftSide/LogPanel",
		"MarginContainer/HBoxContainer/RightSide",
	]:
		var node := _game_root.get_node_or_null(node_path)
		if node:
			node.visible = false

	var model := _player.get_node_or_null("Model")
	if model:
		model.visible = false


func _load_level_0() -> void:
	if not ChunkManager:
		push_error("[MovieCapture] ChunkManager missing")
		return

	ChunkManager.change_level(0)
	_hide_capture_ui()

	if not ChunkManager.initial_load_complete:
		await ChunkManager.initial_load_completed

	# Let game_3d._respawn_player_for_new_level(), lightmap upload, and renderer
	# cleanup finish before we begin the explicit warm-up timer.
	for i in range(20):
		await get_tree().process_frame

	_hide_capture_ui()


func _disable_player_input() -> void:
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	if _player.state_machine:
		_player.state_machine.set_process(false)
		_player.state_machine.set_process_unhandled_input(false)

	if _player.first_person_camera:
		_player.first_person_camera.set_process(false)
		_player.first_person_camera.set_process_unhandled_input(false)
	if _player.camera_rig:
		_player.camera_rig.set_process(false)
		_player.camera_rig.set_process_unhandled_input(false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _move_to_atmospheric_position() -> void:
	"""Relocate within the already-loaded interior, away from spawn text.

	This keeps the capture truthful to the real generated game world while avoiding
	the player-facing spawn spraypaint. Candidates are restricted to the spawn
	chunk or its immediate neighbors, with a chunk-edge margin so the camera cannot
	look out past loaded geometry into the void.
	"""
	const CHUNK_SIZE := 128
	const CHUNK_EDGE_MARGIN := 24
	const MIN_DISTANCE_FROM_SPAWN := 30.0
	const MIN_DISTANCE_FROM_SPRAYPAINT := 18.0

	if not ChunkManager:
		return

	var spawn_pos: Vector2i = _player.grid_position
	var spawn_chunk: Vector2i = ChunkManager.tile_to_chunk(spawn_pos)
	var spraypaint_positions := _get_spraypaint_positions()

	var candidates := _find_atmospheric_candidates(
		spawn_pos,
		spawn_chunk,
		spraypaint_positions,
		0,
		CHUNK_SIZE,
		CHUNK_EDGE_MARGIN,
		MIN_DISTANCE_FROM_SPAWN,
		MIN_DISTANCE_FROM_SPRAYPAINT
	)

	# If the spawn chunk is cramped, allow immediate neighbor chunks. The initial
	# load covers a 5×5 area, so neighbor chunks still have loaded geometry beyond
	# them in every direction.
	if candidates.is_empty():
		candidates = _find_atmospheric_candidates(
			spawn_pos,
			spawn_chunk,
			spraypaint_positions,
			1,
			CHUNK_SIZE,
			CHUNK_EDGE_MARGIN,
			MIN_DISTANCE_FROM_SPAWN,
			MIN_DISTANCE_FROM_SPRAYPAINT
		)

	if candidates.is_empty():
		Log.system("[MovieCapture] No safe away-from-spawn capture position found; keeping spawn")
		return

	# Prefer a farther candidate, but keep some run-to-run variety.
	candidates.shuffle()
	var best_pos: Vector2i = candidates[0]
	var best_score: float = -INF
	for candidate_variant in candidates.slice(0, mini(candidates.size(), 64)):
		var candidate: Vector2i = candidate_variant
		var score: float = candidate.distance_to(spawn_pos)
		for spray_pos in spraypaint_positions:
			score += minf(candidate.distance_to(spray_pos), 40.0) * 0.25
		if score > best_score:
			best_score = score
			best_pos = candidate

	_player.grid_position = best_pos
	_player.snap_visual_position()
	Log.system("[MovieCapture] Repositioned from spawn %s to atmospheric position %s" % [spawn_pos, best_pos])


func _find_atmospheric_candidates(
		spawn_pos: Vector2i,
		spawn_chunk: Vector2i,
		spraypaint_positions: Array[Vector2i],
		max_chunk_distance: int,
		chunk_size: int,
		chunk_edge_margin: int,
		min_distance_from_spawn: float,
		min_distance_from_spraypaint: float) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []

	for pos in _grid.walkable_cells.keys():
		var grid_pos: Vector2i = pos
		var chunk_pos: Vector2i = ChunkManager.tile_to_chunk(grid_pos)
		var chunk_distance = maxi(abs(chunk_pos.x - spawn_chunk.x), abs(chunk_pos.y - spawn_chunk.y))
		if chunk_distance > max_chunk_distance:
			continue

		var local_pos := grid_pos - chunk_pos * chunk_size
		if local_pos.x < chunk_edge_margin or local_pos.x > chunk_size - chunk_edge_margin:
			continue
		if local_pos.y < chunk_edge_margin or local_pos.y > chunk_size - chunk_edge_margin:
			continue
		if grid_pos.distance_to(spawn_pos) < min_distance_from_spawn:
			continue
		if _is_near_spraypaint(grid_pos, spraypaint_positions, min_distance_from_spraypaint):
			continue

		candidates.append(grid_pos)

	return candidates


func _get_spraypaint_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	if not _grid.spraypaint_renderer:
		return positions

	for labels in _grid.spraypaint_renderer.chunk_labels.values():
		for label in labels:
			if is_instance_valid(label):
				positions.append(_grid.world_to_grid(label.global_position))

	return positions


func _is_near_spraypaint(pos: Vector2i, spraypaint_positions: Array[Vector2i], min_distance: float) -> bool:
	for spray_pos in spraypaint_positions:
		if pos.distance_to(spray_pos) < min_distance:
			return true
	return false


func _setup_camera() -> void:
	_player._set_camera_yaw(randf() * 360.0)

	match camera_mode:
		CameraMode.FPV_ORBIT:
			_activate_fpv()
		CameraMode.TACTICAL_ORBIT:
			_activate_tactical()


func _activate_fpv() -> void:
	var fpc: FirstPersonCamera = _player.first_person_camera
	var tac: TacticalCamera = _player.camera_rig
	if not fpc:
		return

	var fpc_cam: Camera3D = fpc.get_node_or_null("HorizontalPivot/VerticalPivot/Camera3D")
	var tac_cam: Camera3D = null
	if tac:
		tac_cam = tac.get_node_or_null("HorizontalPivot/VerticalPivot/Camera3D")
	if fpc_cam:
		fpc_cam.current = true
	if tac_cam:
		tac_cam.current = false

	var v_pivot := fpc.get_node_or_null("HorizontalPivot/VerticalPivot")
	if v_pivot:
		v_pivot.rotation_degrees.x = -12.0


func _activate_tactical() -> void:
	var fpc: FirstPersonCamera = _player.first_person_camera
	var tac: TacticalCamera = _player.camera_rig
	if not tac:
		return

	var fpc_cam: Camera3D = null
	if fpc:
		fpc_cam = fpc.get_node_or_null("HorizontalPivot/VerticalPivot/Camera3D")
	var tac_cam: Camera3D = tac.get_node_or_null("HorizontalPivot/VerticalPivot/Camera3D")
	if tac_cam:
		tac_cam.current = true
	if fpc_cam:
		fpc_cam.current = false

	tac.current_zoom = 14.0
	tac.camera.position.z = 14.0
	tac.v_pivot.rotation_degrees.x = -55.0


func _write_capture_start_marker() -> void:
	var marker_dir := OS.get_environment("DY_CAPTURE_MARKER_DIR")
	if marker_dir == "":
		return

	DirAccess.make_dir_recursive_absolute(marker_dir)
	var marker_path := marker_dir.path_join("capture_start_frame.txt")
	var file := FileAccess.open(marker_path, FileAccess.WRITE)
	if not file:
		push_warning("[MovieCapture] Could not write capture marker: %s" % marker_path)
		return

	file.store_line(str(Engine.get_frames_drawn()))
	file.close()


func _process(_delta: float) -> void:
	# Deliberately locked-off. The subject is entropy-locked lighting and
	# atmosphere, not camera motion.
	pass


func _animate_fpv(delta: float) -> void:
	const YAW_SPEED := 6.0
	const PITCH_FREQ := 0.25
	const PITCH_AMP := 8.0

	var fpc: FirstPersonCamera = _player.first_person_camera
	if not fpc:
		return

	var h_pivot := fpc.get_node_or_null("HorizontalPivot")
	if h_pivot:
		h_pivot.rotation_degrees.y += delta * YAW_SPEED

	var v_pivot := fpc.get_node_or_null("HorizontalPivot/VerticalPivot")
	if v_pivot:
		v_pivot.rotation_degrees.x = -12.0 + sin(_elapsed * PITCH_FREQ * TAU) * PITCH_AMP


func _animate_tactical(delta: float) -> void:
	const YAW_SPEED := 10.0
	const ZOOM_FREQ := 0.12
	const ZOOM_AMP := 4.0
	const BASE_ZOOM := 14.0

	var tac: TacticalCamera = _player.camera_rig
	if not tac:
		return

	tac.h_pivot.rotation_degrees.y += delta * YAW_SPEED
	tac.current_zoom = BASE_ZOOM + sin(_elapsed * ZOOM_FREQ * TAU) * ZOOM_AMP
	tac.camera.position.z = tac.current_zoom


func _on_capture_timeout() -> void:
	Log.system("[MovieCapture] Capture complete — %d seconds" % capture_duration)
	get_tree().quit()
