extends Node
## Manages chunk loading, unloading, and corruption escalation
##
## ChunkManager is an autoload singleton that handles:
## - Loading chunks near the player
## - Unloading distant chunks to save memory
## - Tracking corruption per level
## - Coordinating with generators and spawners
## - Providing chunk query API

## Emitted when chunk updates complete (for PostTurnState to unblock input)
@warning_ignore("unused_signal")
signal chunk_updates_completed()

## Emitted when initial chunk load completes (all chunks in 7×7 grid loaded)
@warning_ignore("unused_signal")
signal initial_load_completed()

## Emitted during initial load to report progress (loaded_count, total_count)
@warning_ignore("unused_signal")
signal initial_load_progress(loaded_count: int, total_count: int)

## Emitted when player enters a new chunk (for EXP rewards)
signal new_chunk_entered(chunk_position: Vector3i)

# Constants
const CHUNK_SIZE := 128
const ACTIVE_RADIUS := 3  # Chunks to keep loaded around player
const GENERATION_RADIUS := 3  # Chunks to pre-generate (7×7 = 49 chunks)
const UNLOAD_RADIUS := 5  # Chunks beyond this distance are candidates for unloading (hysteresis buffer)
const MAX_LOADED_CHUNKS := 64  # Memory limit - allows full 7×7 grid + buffer zone for unloading
const CHUNK_BUDGET_MS := 4.0  # Max milliseconds per frame for chunk operations
const MAX_CHUNKS_PER_FRAME := 3  # Hard limit to prevent burst overload

# State
var loaded_chunks: Dictionary = {}  # Vector3i(x, y, level) -> Chunk
var generating_chunks: Array[Vector3i] = []  # Chunks queued for generation
var world_seed: int = 0
var visited_chunks: Dictionary = {}  # Vector3i -> bool (chunks player has entered)
var last_player_chunk: Vector3i = Vector3i(-999, -999, -999)  # Track chunk changes
var hit_chunk_limit: bool = false  # Track if we've logged hitting the limit
var was_generating: bool = false  # Track if chunks were queued (for completion signal)
var initial_load_complete: bool = false  # Track if initial area load is done

# Systems (will be initialized when available)
var corruption_tracker: CorruptionTracker
var level_generators: Dictionary = {}  # level_id → LevelGenerator
var grid_3d: Grid3D = null  # Cached reference to Grid3D (found via search)
var generation_thread: ChunkGenerationThread = null  # Worker thread for async generation
# var island_manager: IslandManager  # TODO: Phase 5
# var entity_spawner: EntitySpawner  # TODO: Phase 4

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Initialize corruption tracker
	corruption_tracker = CorruptionTracker.new()

	# Initialize level generators
	level_generators[0] = Level0Generator.new()

	# Initialize generation thread with Level 0 generator
	generation_thread = ChunkGenerationThread.new(level_generators[0])
	generation_thread.chunk_completed.connect(_on_chunk_completed)
	generation_thread.start()

	# Generate world seed
	world_seed = randi()

	# Find Grid3D in scene tree (it may be nested in UI structure)
	_find_grid_3d()

	Log.system("ChunkManager initialized (seed: %d, generators: %d, threaded: true)" % [
		world_seed,
		level_generators.size()
	])

	# Connect to node_added signal to detect when game scene loads
	# DON'T start chunk generation yet - wait for Grid3D to exist first
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	"""Detect when game scene loads and initialize chunk generation"""
	# The root Control node from game.tscn is named "Game"
	# (Not "Game3D" - that's just the instance name for the nested game_3d.tscn)
	if node.name == "Game" and node is Control and not grid_3d:
		Log.system("Game scene detected, searching for Grid3D and starting chunk generation...")
		# Search for Grid3D (deferred to ensure SubViewport content is ready)
		call_deferred("_find_grid_3d")
		call_deferred("_connect_to_player_signal")
		# NOW trigger initial chunk load (only after game scene is loaded)
		call_deferred("on_turn_completed")

func _exit_tree() -> void:
	"""Clean up worker thread on exit"""
	if generation_thread:
		generation_thread.stop()

func _process(_delta: float) -> void:
	# Don't process chunks until Grid3D exists (e.g., on start menu)
	if not grid_3d:
		return

	# Process completed chunks from worker thread
	if generation_thread:
		generation_thread.process_completed_chunks()

	# TURN-BASED: Send chunks to worker thread for generation
	# Actual chunk loading/unloading happens in on_turn_completed() triggered by player signal
	_process_generation_queue()

func _connect_to_player_signal() -> void:
	"""Connect to player's turn_completed signal"""
	var player_path := "/root/Game/MarginContainer/HBoxContainer/LeftSide/ViewportPanel/MarginContainer/SubViewportContainer/SubViewport/Game3D/Player3D"
	if has_node(player_path):
		var player = get_node(player_path)
		if not player.turn_completed.is_connected(on_turn_completed):
			player.turn_completed.connect(on_turn_completed)
			Log.system("[ChunkManager] Connected to player turn_completed signal")
	else:
		Log.warn(Log.Category.SYSTEM, "Player not found at %s for turn signal connection" % player_path)

func on_turn_completed() -> void:
	"""Called when a turn completes (triggered by player's turn_completed signal)"""
	# Check if player entered a new chunk (for corruption tracking)
	_check_player_chunk_change()

	# Update chunks around player (queue new chunks if needed)
	_update_chunks_around_player()

	# Unload distant chunks
	_unload_distant_chunks()

	# Track if we NOW have chunks generating (after queuing)
	was_generating = not generating_chunks.is_empty()

	# If nothing is queued, emit completion signal (deferred to allow PostTurnState to connect)
	# (PostTurnState can transition to IdleState without waiting)
	if not was_generating:
		chunk_updates_completed.emit.call_deferred()

	# Note: Initial load completion is now checked in _process_generation_queue() every frame
	# This avoids chicken-and-egg problem where player can't take turns until spawned,
	# but spawn waits for initial load completion

# ============================================================================
# CHUNK LOADING
# ============================================================================

func _update_chunks_around_player() -> void:
	"""Queue chunks for loading near player (distance-sorted priority queue)"""
	# Get actual player position from game scene
	var player_tile := _get_player_position()
	var player_level := _get_player_level()

	var player_chunk := tile_to_chunk(player_tile)

	# Collect chunks with distances
	var chunks_to_queue: Array[Dictionary] = []

	for y in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
		for x in range(-GENERATION_RADIUS, GENERATION_RADIUS + 1):
			var chunk_pos := player_chunk + Vector2i(x, y)
			var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, player_level)

			# Skip if already loaded or queued
			if chunk_key in loaded_chunks or chunk_key in generating_chunks:
				continue

			var distance := player_chunk.distance_to(chunk_pos)
			chunks_to_queue.append({"key": chunk_key, "distance": distance})

	# Log if we found chunks to queue
	# if not chunks_to_queue.is_empty():
	# 	Log.grid("Found %d new chunks to queue around player chunk %s" % [
	# 		chunks_to_queue.size(),
	# 		player_chunk
	# 	])  # Too verbose

	# Sort by distance (nearest first - CRITICAL for performance!)
	chunks_to_queue.sort_custom(func(a, b): return a.distance < b.distance)

	# Add to queue in sorted order
	# After initial load, limit to 1 chunk per turn to avoid lag spikes
	var chunks_to_add := chunks_to_queue.size()
	if initial_load_complete and chunks_to_add > 1:
		chunks_to_add = 1
		# Log.grid("Limiting to 1 chunk per turn (post-initial load)")  # Too verbose

	for i in range(chunks_to_add):
		generating_chunks.append(chunks_to_queue[i].key)

func _check_player_chunk_change() -> void:
	"""Check if player entered a new chunk and increase corruption"""
	var player_tile := _get_player_position()
	var player_level := _get_player_level()
	var player_chunk := tile_to_chunk(player_tile)
	var chunk_key := Vector3i(player_chunk.x, player_chunk.y, player_level)

	# Check if player moved to a different chunk
	if chunk_key != last_player_chunk:
		last_player_chunk = chunk_key

		# Check if this is a NEW chunk (never visited before)
		if chunk_key not in visited_chunks:
			visited_chunks[chunk_key] = true

			# Emit signal for EXP reward
			emit_signal("new_chunk_entered", chunk_key)

			# Increase corruption when entering new chunk
			# Get corruption amount from level generator
			var corruption_amount := 0.01  # Default fallback
			var generator: LevelGenerator = level_generators.get(player_level, null)
			if generator:
				corruption_amount = generator.get_corruption_per_chunk()

			corruption_tracker.increase_corruption(player_level, corruption_amount, 0.0)

			# Log.grid("Entered new chunk %s (visited: %d, corruption: %.2f)" % [
			# 	player_chunk,
			# 	visited_chunks.size(),
			# 	corruption_tracker.get_corruption(player_level)
			# ])  # Too verbose (fires every new chunk)

func _process_generation_queue() -> void:
	"""Send chunks to worker thread for generation"""
	if generating_chunks.is_empty():
		# Check if thread has no work and we're waiting for completion
		if was_generating and generation_thread and generation_thread.get_pending_count() == 0:
			chunk_updates_completed.emit()
			was_generating = false

		# Check for initial load completion (when queue is empty and chunks are loaded)
		if not initial_load_complete and loaded_chunks.size() > 0:
			var expected_chunks := (GENERATION_RADIUS * 2 + 1) * (GENERATION_RADIUS * 2 + 1)  # 7×7 = 49
			var has_all_chunks := loaded_chunks.size() >= expected_chunks

			if has_all_chunks or (generation_thread and generation_thread.get_pending_count() == 0):
				initial_load_complete = true
				Log.system("Initial chunk load complete (%d/%d chunks), switching to 1-chunk-per-turn mode" % [
					loaded_chunks.size(),
					expected_chunks
				])
				initial_load_completed.emit()

		return

	# Check memory limit
	if loaded_chunks.size() >= MAX_LOADED_CHUNKS:
		if not hit_chunk_limit:
			Log.grid("Hit MAX_LOADED_CHUNKS (%d), stopping generation (queue: %d)" % [MAX_LOADED_CHUNKS, generating_chunks.size()])
			hit_chunk_limit = true
		# Emit completion signal since we can't generate more chunks
		if was_generating:
			chunk_updates_completed.emit()
			was_generating = false
		return

	# Send all queued chunks to worker thread (no frame budget needed - thread handles it!)
	while not generating_chunks.is_empty():
		var chunk_key: Vector3i = generating_chunks.pop_front()
		var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
		var level_id: int = chunk_key.z

		# Queue for async generation on worker thread
		if generation_thread:
			generation_thread.queue_chunk_generation(chunk_pos, level_id, world_seed)
		else:
			# Fallback: synchronous generation if thread not available
			var chunk := _generate_chunk(chunk_pos, level_id)
			_load_chunk_immediate(chunk, chunk_key)

func _generate_chunk(chunk_pos: Vector2i, level_id: int) -> Chunk:
	"""Generate a new chunk using LevelGenerator"""
	var chunk := Chunk.new()
	chunk.initialize(chunk_pos, level_id)
	chunk.state = Chunk.State.GENERATING

	# Get generator for this level
	var generator: LevelGenerator = level_generators.get(level_id, null)
	if generator:
		# Use LevelGenerator to create maze layout
		generator.generate_chunk(chunk, world_seed)
	else:
		# Fallback: Use placeholder if no generator available
		push_warning("No generator for level %d, using placeholder" % level_id)
		_generate_placeholder_chunk(chunk)

	# TODO: Phase 4 - Spawn entities
	# var level_config := generator.get_level_config()
	# entity_spawner.spawn_entities_in_chunk(chunk, level_config)

	# Corruption is no longer increased during generation
	# It now increases when player ENTERS a chunk for the first time

	chunk.state = Chunk.State.LOADED
	return chunk

func _generate_placeholder_chunk(chunk: Chunk) -> void:
	"""Generate simple placeholder chunk (Phase 1 only)

	Creates walls on edges, floor in middle.
	"""
	for sy in range(Chunk.SUB_CHUNKS_PER_SIDE):
		for sx in range(Chunk.SUB_CHUNKS_PER_SIDE):
			var sub := chunk.get_sub_chunk(Vector2i(sx, sy))

			for y in range(SubChunk.SIZE):
				for x in range(SubChunk.SIZE):
					# Calculate absolute position within chunk
					var chunk_x := sx * SubChunk.SIZE + x
					var chunk_y := sy * SubChunk.SIZE + y

					# Walls on edges, floor in middle
					var is_edge := chunk_x == 0 or chunk_x == Chunk.SIZE - 1 or \
								   chunk_y == 0 or chunk_y == Chunk.SIZE - 1

					if is_edge:
						sub.set_tile(Vector2i(x, y), SubChunk.TileType.WALL)
					else:
						sub.set_tile(Vector2i(x, y), SubChunk.TileType.FLOOR)

func _on_chunk_completed(chunk: Chunk, chunk_pos: Vector2i, level_id: int) -> void:
	"""Handle chunk completion from worker thread (called via signal)"""
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)

	# Store chunk in loaded_chunks
	loaded_chunks[chunk_key] = chunk

	# Emit progress during initial load
	if not initial_load_complete:
		var expected_chunks := (GENERATION_RADIUS * 2 + 1) * (GENERATION_RADIUS * 2 + 1)  # 7×7 = 49
		initial_load_progress.emit(loaded_chunks.size(), expected_chunks)

	# Load into GridMap (deferred to ensure main thread)
	call_deferred("_load_chunk_to_grid", chunk, chunk_key)

func _load_chunk_to_grid(chunk: Chunk, chunk_key: Vector3i) -> void:
	"""Load chunk into Grid3D (runs on main thread via call_deferred)"""
	var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
	var level_id := chunk_key.z

	# Notify Grid3D to render it
	if not grid_3d:
		_find_grid_3d()

	if grid_3d:
		grid_3d.load_chunk(chunk)
	else:
		# Only warn once per session
		if loaded_chunks.size() == 1:
			push_warning("[ChunkManager] Grid3D not found in scene tree - procedural generation disabled")

	# Log chunk generation
	# Log.grid("Generated chunk %s on Level %d" % [chunk_pos, level_id])  # Too verbose (per-chunk)

	# Log first few chunks and progress milestones to System for visibility
	if loaded_chunks.size() <= 5 or loaded_chunks.size() % 25 == 0:
		Log.system("ChunkManager: %d chunks generated (latest: %s)" % [
			loaded_chunks.size(),
			chunk_pos
		])

func _load_chunk_immediate(chunk: Chunk, chunk_key: Vector3i) -> void:
	"""Load chunk immediately (fallback for synchronous generation)"""
	loaded_chunks[chunk_key] = chunk
	_load_chunk_to_grid(chunk, chunk_key)

# ============================================================================
# CHUNK UNLOADING
# ============================================================================

func _unload_distant_chunks() -> void:
	"""Unload chunks far from player"""
	var player_tile := _get_player_position()
	var player_level := _get_player_level()

	var player_chunk := tile_to_chunk(player_tile)

	var chunks_to_unload: Array[Vector3i] = []

	for chunk_key in loaded_chunks.keys():
		var chunk_pos := Vector2i(chunk_key.x, chunk_key.y)
		var chunk_level: int = chunk_key.z

		# Only unload chunks on current level
		if chunk_level != player_level:
			continue

		var distance := player_chunk.distance_to(chunk_pos)
		if distance > UNLOAD_RADIUS:
			chunks_to_unload.append(chunk_key)

	# Unload distant chunks
	if not chunks_to_unload.is_empty():
		Log.grid("Unloading %d chunks beyond radius %d" % [chunks_to_unload.size(), UNLOAD_RADIUS])
		hit_chunk_limit = false  # Reset limit flag since we're freeing up space

	var unload_count := 0
	for chunk_key in chunks_to_unload:
		_unload_chunk(chunk_key)
		unload_count += 1

		# After initial load, limit to 1 chunk per turn to avoid lag spikes
		if initial_load_complete and unload_count >= 1:
			break

		# Stop if we're back under comfortable limit
		if loaded_chunks.size() <= MAX_LOADED_CHUNKS * 0.8:
			break

func _unload_chunk(chunk_key: Vector3i) -> void:
	"""Unload a chunk from memory"""
	var chunk: Chunk = loaded_chunks[chunk_key]

	# TODO: Phase 7 - Save chunk state if modified (entities killed, items taken)

	# Remove from Grid3D render (use cached reference)
	if grid_3d:
		grid_3d.unload_chunk(chunk)

	# Remove from memory
	loaded_chunks.erase(chunk_key)

	Log.grid("Unloaded chunk %s" % Vector2i(chunk_key.x, chunk_key.y))

# ============================================================================
# COORDINATE CONVERSION
# ============================================================================

func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	"""Convert tile position to chunk position

	Example:
		tile (100, 50) → chunk (0, 0)  # 100/128=0, 50/128=0
		tile (150, 200) → chunk (1, 1)  # 150/128=1, 200/128=1
		tile (-10, -10) → chunk (-1, -1)  # Negative tiles work too
	"""
	return Vector2i(
		floori(float(tile_pos.x) / CHUNK_SIZE),
		floori(float(tile_pos.y) / CHUNK_SIZE)
	)

func chunk_to_world(chunk_pos: Vector2i) -> Vector2i:
	"""Convert chunk position to world tile position (chunk origin)

	Example:
		chunk (0, 0) → tile (0, 0)
		chunk (1, 1) → tile (128, 128)
		chunk (-1, -1) → tile (-128, -128)
	"""
	return chunk_pos * CHUNK_SIZE

func tile_to_local(tile_pos: Vector2i) -> Vector2i:
	"""Convert tile position to local chunk position (0-127)

	Example:
		tile (100, 50) → local (100, 50)
		tile (150, 200) → local (22, 72)  # 150%128=22, 200%128=72
	"""
	return Vector2i(
		posmod(tile_pos.x, CHUNK_SIZE),
		posmod(tile_pos.y, CHUNK_SIZE)
	)

# ============================================================================
# SCENE TREE QUERIES
# ============================================================================

func _find_grid_3d() -> void:
	"""Find Grid3D in scene tree by searching recursively

	Grid3D may be nested deep in UI structure (SubViewport, etc.),
	so we search the entire tree instead of hardcoding paths.
	"""
	if grid_3d:
		return  # Already found

	# Start search from root
	var root = get_tree().root
	grid_3d = _search_for_grid_3d(root)

	if grid_3d:
		Log.system("Found Grid3D at: %s" % grid_3d.get_path())
	else:
		Log.system("Grid3D not found in scene tree")

func _search_for_grid_3d(node: Node) -> Grid3D:
	"""Recursively search for Grid3D node"""
	# Check if this node is Grid3D
	if node is Grid3D:
		return node

	# Search children
	for child in node.get_children():
		var result = _search_for_grid_3d(child)
		if result:
			return result

	return null

# ============================================================================
# PLAYER QUERIES
# ============================================================================

func _get_player_position() -> Vector2i:
	"""Get player's current grid position

	Returns default (64, 64) if player not found.
	"""
	# Try to get player from game scene
	# Player is at: /root/Game/.../SubViewport/Game3D/Player3D
	var player_path := "/root/Game/MarginContainer/HBoxContainer/LeftSide/ViewportPanel/MarginContainer/SubViewportContainer/SubViewport/Game3D/Player3D"

	if has_node(player_path):
		var player = get_node(player_path)
		# Player3D script has grid_position property
		return player.grid_position
	else:
		Log.warn(Log.Category.GRID, "Player node not found at %s" % player_path)

	# Fallback to default spawn position
	return Vector2i(64, 64)

func _get_player_level() -> int:
	"""Get player's current level

	Returns 0 (Level 0) by default.
	TODO: Add level tracking to Player when multi-level support is implemented.
	"""
	# Try to get player from game scene
	if has_node("/root/Game/Player"):
		var player: Node = get_node("/root/Game/Player")
		if player.has("current_level"):
			return player.current_level

	# Default to Level 0
	return 0

# ============================================================================
# PUBLIC API
# ============================================================================

func get_chunk_at_tile(tile_pos: Vector2i, level_id: int) -> Chunk:
	"""Get chunk containing a tile

	Returns null if chunk is not loaded.
	"""
	var chunk_pos := tile_to_chunk(tile_pos)
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
	return loaded_chunks.get(chunk_key, null)

func get_chunk_at_position(chunk_pos: Vector2i, level_id: int) -> Chunk:
	"""Get chunk at chunk coordinates

	Returns null if chunk is not loaded.
	"""
	var chunk_key := Vector3i(chunk_pos.x, chunk_pos.y, level_id)
	return loaded_chunks.get(chunk_key, null)

func is_tile_walkable(tile_pos: Vector2i, level_id: int) -> bool:
	"""Check if tile is walkable

	Returns false if chunk is not loaded.
	"""
	var chunk := get_chunk_at_tile(tile_pos, level_id)
	if not chunk:
		return false

	return chunk.is_walkable(tile_pos)

func get_tile_type(tile_pos: Vector2i, level_id: int) -> int:
	"""Get tile type at position

	Returns -1 if chunk is not loaded.
	"""
	var chunk := get_chunk_at_tile(tile_pos, level_id)
	if not chunk:
		return -1

	return chunk.get_tile(tile_pos)

# ============================================================================
# RUN MANAGEMENT
# ============================================================================

func start_new_run(new_seed: int = -1) -> void:
	"""Start a new run, clear all state

	Args:
		new_seed: World seed (-1 for random)
	"""
	if new_seed == -1:
		world_seed = randi()
	else:
		world_seed = new_seed

	loaded_chunks.clear()
	generating_chunks.clear()
	visited_chunks.clear()
	last_player_chunk = Vector3i(-999, -999, -999)
	initial_load_complete = false  # Reset for new run
	corruption_tracker.reset_all()

	# Re-initialize level generators (fresh instances for new run)
	level_generators.clear()
	level_generators[0] = Level0Generator.new()

	Log.system("New run started (seed: %d, generators: %d)" % [
		world_seed,
		level_generators.size()
	])

# ============================================================================
# CHUNK VALIDATION
# ============================================================================

# ============================================================================
# DEBUG
# ============================================================================

func get_loaded_chunk_count() -> int:
	"""Get number of currently loaded chunks"""
	return loaded_chunks.size()

func get_corruption(level_id: int) -> float:
	"""Get current corruption for a level"""
	return corruption_tracker.get_corruption(level_id)
