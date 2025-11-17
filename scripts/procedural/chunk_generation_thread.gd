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

# Generator reference
var generator: LevelGenerator = null

# Signals (emitted from main thread via call_deferred)
signal chunk_completed(chunk: Chunk, chunk_pos: Vector2i, level_id: int)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _init(level_generator: LevelGenerator) -> void:
	"""Initialize thread with generator reference"""
	generator = level_generator

func start() -> void:
	"""Start the worker thread"""
	if thread:
		push_warning("[ChunkGenerationThread] Thread already running")
		return

	should_exit = false
	thread = Thread.new()
	thread.start(_thread_function)
	Log.system("ChunkGenerationThread started")

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
	Log.system("ChunkGenerationThread stopped")

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

		# Use generator to populate chunk data
		if generator:
			generator.generate_chunk(chunk, request.seed)

		# Add to completion queue
		mutex.lock()
		completion_queue.append({
			"chunk": chunk,
			"pos": request.pos,
			"level_id": request.level_id
		})
		mutex.unlock()

		# Note: Signal emission happens in process_completed_chunks() on main thread
