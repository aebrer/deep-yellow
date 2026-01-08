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
var level_configs: Dictionary = {}  # level_id → LevelConfig (loaded from resources)
var grid_3d: Grid3D = null  # Cached reference to Grid3D (found via search)
var generation_thread: ChunkGenerationThread = null  # Worker thread for async generation
var item_spawner: ItemSpawner = null  # Item spawning system (initialized after corruption_tracker)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Initialize corruption tracker
	corruption_tracker = CorruptionTracker.new()

	# Initialize level generators
	level_generators[0] = Level0Generator.new()

	# Instantiate level configs (use .new() instead of load() so _init() is called)
	level_configs[0] = Level0Config.new()

	# Initialize item spawner with Level 0 config
	item_spawner = ItemSpawner.new(corruption_tracker, level_configs[0])

	# Initialize generation thread with Level 0 generator
	generation_thread = ChunkGenerationThread.new(level_generators[0])
	generation_thread.chunk_completed.connect(_on_chunk_completed)
	generation_thread.start()

	# Generate world seed
	world_seed = randi()

	# Find Grid3D in scene tree (it may be nested in UI structure)
	_find_grid_3d()

	Log.system("ChunkManager initialized (seed: %d, generators: %d, threaded: true, items: true)" % [
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
	var player = _find_player()
	if player:
		if not player.turn_completed.is_connected(on_turn_completed):
			player.turn_completed.connect(on_turn_completed)
			Log.system("[ChunkManager] Connected to player turn_completed signal")
	else:
		Log.warn(Log.Category.SYSTEM, "Player not found for turn signal connection")

func on_turn_completed() -> void:
	"""Called when a turn completes (triggered by player's turn_completed signal)"""
	# Check if player entered a new chunk (for corruption tracking)
	_check_player_chunk_change()

	# Update item discovery state (mark items near player as discovered)
	_update_item_discovery()

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

	# Sort by distance (nearest first - CRITICAL for performance!)
	chunks_to_queue.sort_custom(func(a, b): return a.distance < b.distance)

	# Add to queue in sorted order
	# After initial load, limit to 1 chunk per turn to avoid lag spikes
	var chunks_to_add := chunks_to_queue.size()
	if initial_load_complete and chunks_to_add > 1:
		chunks_to_add = 1

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

	# NOTE: Item spawning happens in _on_chunk_completed() on main thread
	# (not here, since this is only called for fallback synchronous generation)

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

	# Spawn items (separate pass after terrain generation, on main thread)
	var level_config: LevelConfig = level_configs.get(level_id, null)

	# Debug logging to diagnose spawning issues
	Log.system("Item spawning check: level_config=%s, item_spawner=%s, permitted_items=%d" % [
		"exists" if level_config else "null",
		"exists" if item_spawner else "null",
		level_config.permitted_items.size() if level_config else 0
	])

	if level_config and item_spawner and not level_config.permitted_items.is_empty():
		Log.system("Attempting to spawn items in chunk at %s" % chunk.position)
		var spawned_items = item_spawner.spawn_items_for_chunk(
			chunk,
			0,  # Turn number (will be updated later with actual turn tracking)
			level_config.permitted_items
		)

		Log.system("Spawned %d items in chunk" % spawned_items.size())

		# Store spawned items in subchunks for persistence
		for world_item in spawned_items:
			var item_data = world_item.to_dict()
			# Find the subchunk containing this item
			var chunk_world_pos = chunk.position * Chunk.SIZE  # Convert chunk coords to world tile coords
			var local_pos = world_item.world_position - chunk_world_pos
			var subchunk_x = local_pos.x / SubChunk.SIZE
			var subchunk_y = local_pos.y / SubChunk.SIZE
			var subchunk = chunk.get_sub_chunk(Vector2i(subchunk_x, subchunk_y))
			if subchunk:
				subchunk.add_world_item(item_data)
	else:
		Log.warn(Log.Category.SYSTEM, "Item spawning skipped: conditions not met")

	# NOTE: Debug enemy spawning moved to _load_chunk_to_grid()
	# because it uses grid.is_walkable() which queries GridMap

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
		# First load terrain into GridMap (needed for is_walkable)
		grid_3d.load_chunk(chunk)

		# Spawn entities AFTER GridMap is populated (is_walkable needs GridMap)
		# but BEFORE entity rendering (entities need to be in chunk data)
		_spawn_debug_enemy_in_chunk(chunk, chunk_key)

		# Now render entities (after they've been added to chunk data)
		if grid_3d.entity_renderer:
			grid_3d.entity_renderer.render_chunk_entities(chunk)
	else:
		# Only warn once per session
		if loaded_chunks.size() == 1:
			push_warning("[ChunkManager] Grid3D not found in scene tree - procedural generation disabled")

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
# DEBUG ENEMY SPAWNING
# ============================================================================

func _spawn_debug_enemy_in_chunk(chunk: Chunk, _chunk_key: Vector3i) -> void:
	"""Spawn a debug enemy in the center of the chunk for combat testing

	Debug enemy:
	- Spawns once per chunk (guaranteed)
	- Has tons of HP (1000+) for testing
	- Does NOT move or attack
	- Just a stationary punching bag

	Now uses WorldEntity data pattern (like items) instead of Node3D instances.
	EntityRenderer creates billboards when chunk loads.
	"""
	# Wait for grid to exist (needed for is_walkable check)
	if not grid_3d:
		Log.warn(Log.Category.ENTITY, "Cannot spawn debug enemy - no grid_3d reference")
		return

	# Find a walkable spawn position near chunk center
	var chunk_world_pos = chunk.position * CHUNK_SIZE  # Chunk origin in world tiles
	var chunk_center = chunk_world_pos + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)

	# Use same spiral search pattern as player spawning (reusing Grid.is_walkable)
	var spawn_pos: Vector2i = chunk_center
	var found_walkable = false

	# First check if center is walkable
	if grid_3d.is_walkable(chunk_center):
		spawn_pos = chunk_center
		found_walkable = true
	else:
		# Spiral search outward from center (same pattern as player spawn)
		for radius in range(1, 30):  # Search up to 30 tiles out
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					# Only check tiles at this exact radius (Manhattan distance)
					if abs(dx) + abs(dy) != radius:
						continue

					var test_pos = chunk_center + Vector2i(dx, dy)

					# Use Grid.is_walkable (same as player) - this checks GridMap properly
					if grid_3d.is_walkable(test_pos):
						spawn_pos = test_pos
						found_walkable = true
						break
				if found_walkable:
					break
			if found_walkable:
				break

	if not found_walkable:
		Log.warn(Log.Category.ENTITY, "Could not find walkable spawn for debug enemy in chunk %s (tried 30 tile radius)" % chunk.position)
		return

	# Create WorldEntity data (like WorldItem pattern)
	var entity_data = {
		"entity_type": "debug_enemy",
		"world_position": {"x": spawn_pos.x, "y": spawn_pos.y},
		"current_hp": 1100.0,  # High HP for testing (100 BODY = 100 HP + 1000 bonus)
		"max_hp": 1100.0,
		"is_dead": false,
		"spawn_turn": 0
	}

	# Find the subchunk containing this position and add entity data
	var local_pos = spawn_pos - chunk_world_pos
	var subchunk_x = local_pos.x / SubChunk.SIZE
	var subchunk_y = local_pos.y / SubChunk.SIZE
	var subchunk = chunk.get_sub_chunk(Vector2i(subchunk_x, subchunk_y))
	if subchunk:
		subchunk.add_world_entity(entity_data)
		Log.msg(Log.Category.ENTITY, Log.Level.INFO, "Spawned DebugEnemy data at %s in chunk %s" % [spawn_pos, chunk.position])

# ============================================================================
# ITEM DISCOVERY
# ============================================================================

func _update_item_discovery() -> void:
	"""Check all items in loaded chunks and mark as discovered if within range"""
	const DISCOVERY_RANGE = 50.0  # Tiles

	var player_pos := _get_player_position()

	# Iterate through all loaded chunks
	for chunk_key in loaded_chunks:
		var chunk: Chunk = loaded_chunks[chunk_key]

		# Check all subchunks in this chunk
		for subchunk in chunk.sub_chunks:
			# Skip if no items in this subchunk
			if subchunk.world_items.is_empty():
				continue

			# Check each item in the subchunk
			for item_data in subchunk.world_items:
				# Skip if already discovered
				if item_data.get("discovered", false):
					continue

				# Get item position
				var pos_data = item_data.get("world_position", {"x": 0, "y": 0})
				var item_pos = Vector2i(pos_data.get("x", 0), pos_data.get("y", 0))

				# Calculate distance
				var dx = item_pos.x - player_pos.x
				var dy = item_pos.y - player_pos.y
				var distance = sqrt(dx * dx + dy * dy)

				# Mark as discovered if within range
				if distance <= DISCOVERY_RANGE:
					item_data["discovered"] = true
					Log.system("Item discovered at %s (distance: %.1f tiles)" % [item_pos, distance])

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

func _find_player() -> Node:
	"""Find Player3D node dynamically (works in both portrait and landscape layouts)

	Searches the entire scene tree for a node named "Player3D".
	"""
	var root = get_tree().root
	return _search_for_player(root)

func _search_for_player(node: Node) -> Node:
	"""Recursively search for Player3D node"""
	# Check if this node is named Player3D
	if node.name == "Player3D":
		return node

	# Search children
	for child in node.get_children():
		var result = _search_for_player(child)
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
	var player = _find_player()
	if player:
		return player.grid_position
	else:
		Log.warn(Log.Category.GRID, "Player node not found (using default spawn position)")

	# Fallback to default spawn position
	return Vector2i(64, 64)

func _get_player_level() -> int:
	"""Get player's current level

	Returns 0 (Level 0) by default.
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
# UTILITY
# ============================================================================

func get_loaded_chunk_count() -> int:
	"""Get number of currently loaded chunks"""
	return loaded_chunks.size()

func get_corruption(level_id: int) -> float:
	"""Get current corruption for a level"""
	return corruption_tracker.get_corruption(level_id)
