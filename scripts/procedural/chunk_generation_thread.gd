class_name ChunkGenerationThread extends RefCounted
## Worker thread for asynchronous chunk generation
##
## Processes chunk generation requests on a background thread to avoid
## frame hitches. Main thread queues requests and receives completed chunks
## via signals.

# Thread control
var thread: Thread = null
var should_exit := false
var mutex: Mutex = Mutex.new()
var semaphore: Semaphore = Semaphore.new()

# Work queues (protected by mutex)
var request_queue: Array = []  # Array of {pos: Vector2i, level_id: int, seed: int}
var completion_queue: Array = []  # Array of {chunk: Chunk, pos: Vector2i, level_id: int}

# Level generators: level_id → LevelGenerator
var generators: Dictionary = {}

# Signals (emitted from main thread via call_deferred)
signal chunk_completed(chunk: Chunk, chunk_pos: Vector2i, level_id: int)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _init(level_generators: Dictionary) -> void:
	"""Initialize thread with all level generators

	Args:
		level_generators: Dictionary mapping level_id (int) → LevelGenerator
	"""
	generators = level_generators

func start() -> void:
	"""Start the worker thread"""
	if thread:
		push_warning("[ChunkGenerationThread] Thread already running")
		return

	should_exit = false
	thread = Thread.new()
	thread.start(_thread_function)

func stop() -> void:
	"""Stop the worker thread (blocks until thread exits)"""
	if not thread:
		return

	# Signal thread to exit
	mutex.lock()
	should_exit = true
	mutex.unlock()
	semaphore.post()  # Wake up thread if waiting

	# Wait for thread to finish
	thread.wait_to_finish()
	thread = null

# ============================================================================
# PUBLIC API (Main Thread)
# ============================================================================

func queue_chunk_generation(chunk_pos: Vector2i, level_id: int, world_seed: int) -> void:
	"""Queue a chunk for generation (called from main thread)"""
	mutex.lock()
	request_queue.append({
		"pos": chunk_pos,
		"level_id": level_id,
		"seed": world_seed
	})
	mutex.unlock()
	semaphore.post()  # Wake up worker thread

func process_completed_chunks() -> void:
	"""Process completed chunks and emit signals (called from main thread)"""
	mutex.lock()
	var completed = completion_queue.duplicate()
	completion_queue.clear()
	mutex.unlock()

	# Emit signals for completed chunks
	for item in completed:
		chunk_completed.emit(item.chunk, item.pos, item.level_id)

func get_pending_count() -> int:
	"""Get number of chunks waiting to be generated"""
	mutex.lock()
	var count = request_queue.size()
	mutex.unlock()
	return count

# ============================================================================
# WORKER THREAD
# ============================================================================

func _thread_function() -> void:
	"""Worker thread main loop (runs on background thread)"""
	while true:
		# Wait for work or exit signal
		semaphore.wait()

		# Check for exit
		mutex.lock()
		var exit = should_exit
		mutex.unlock()

		if exit:
			break

		# Get next request
		mutex.lock()
		var request = null
		if not request_queue.is_empty():
			request = request_queue.pop_front()
		mutex.unlock()

		if not request:
			continue

		# Generate chunk (this is the slow part, runs off main thread!)
		var chunk := Chunk.new()
		chunk.initialize(request.pos, request.level_id)

		# Select generator for this level
		# NOTE: GDScript has no exception handling - if generation crashes, thread dies
		# We validate output to catch logic errors, but runtime crashes are not catchable
		var generation_succeeded := false
		var generator: LevelGenerator = generators.get(request.level_id, null)
		if not generator:
			push_error("[ChunkGenerationThread] No generator for level %d (chunk %s)" % [request.level_id, request.pos])
		else:
			generator.generate_chunk(chunk, request.seed)

			# Validate generation produced walkable tiles (basic sanity check)
			if chunk.get_walkable_count() == 0:
				push_error("[ChunkGenerationThread] Generation failed for chunk at %s - no walkable tiles" % request.pos)
			else:
				generation_succeeded = true

		# Only add successfully generated chunks to completion queue
		if generation_succeeded:
			mutex.lock()
			completion_queue.append({
				"chunk": chunk,
				"pos": request.pos,
				"level_id": request.level_id
			})
			mutex.unlock()
		# Note: Failed chunks are dropped - ChunkManager will timeout and retry if needed

		# Note: Signal emission happens in process_completed_chunks() on main thread
