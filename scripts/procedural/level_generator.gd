class_name LevelGenerator extends RefCounted
## Base class for procedural level generators
##
## Each Backrooms level has unique generation rules, entity spawning,
## and visual characteristics. Subclasses implement specific level logic.
##
## Uses EntityConfig and LevelConfig (defined in separate files).

# ============================================================================
# LEVEL PROPERTIES
# ============================================================================

var level_config: ProceduralLevelConfig

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	# Subclasses should override and call setup_level_config()
	pass

func setup_level_config(config: ProceduralLevelConfig) -> void:
	"""Initialize level configuration (called by subclasses)"""
	level_config = config

# ============================================================================
# CHUNK GENERATION (Abstract Interface)
# ============================================================================

func generate_chunk(_chunk: Chunk, _world_seed: int) -> void:
	"""Generate maze layout and tiles for a chunk

	This is the main generation method that subclasses must implement.

	Args:
		_chunk: The chunk to generate (already initialized with position/level)
		_world_seed: World seed for deterministic generation

	Subclasses should:
		1. Create a seeded RNG from world_seed + chunk position
		2. Generate maze walls/floors using their algorithm
		3. Add special tiles (doors, exits, decorations)
		4. NOT spawn entities (EntitySpawner handles that in Phase 4)
	"""
	push_error("LevelGenerator.generate_chunk() must be overridden by subclass")

# ============================================================================
# CONFIGURATION ACCESS
# ============================================================================

func get_level_config() -> ProceduralLevelConfig:
	"""Get level configuration (for entity spawning, corruption, etc.)"""
	return level_config

func get_corruption_per_chunk() -> float:
	"""Get how much corruption increases per new chunk"""
	return level_config.corruption_per_chunk if level_config else 0.01

# ============================================================================
# UTILITY METHODS
# ============================================================================

func create_seeded_rng(chunk: Chunk, world_seed: int) -> RandomNumberGenerator:
	"""Create a deterministic RNG for this chunk

	Combines world seed with chunk position to ensure:
	- Same world seed = same chunk generation
	- Different chunks = different random sequences
	"""
	var rng := RandomNumberGenerator.new()

	# Hash chunk position into seed
	# This ensures each chunk gets unique but deterministic generation
	var chunk_seed := world_seed
	chunk_seed = hash(chunk_seed + chunk.position.x * 73856093)
	chunk_seed = hash(chunk_seed + chunk.position.y * 19349663)
	chunk_seed = hash(chunk_seed + chunk.level_id * 83492791)

	rng.seed = chunk_seed
	return rng

# ============================================================================
# DEBUG
# ============================================================================

func _to_string() -> String:
	if level_config:
		return "LevelGenerator(%s)" % level_config
	return "LevelGenerator(not configured)"
