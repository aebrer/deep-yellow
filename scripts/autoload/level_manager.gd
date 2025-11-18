extends Node
## LevelManager - Singleton for managing Backrooms level loading and transitions
##
## This autoload handles:
## - Loading LevelConfig resources
## - LRU cache (max 3 levels in memory)
## - Preloading exit destination levels
## - Level transitions with lifecycle hooks
## - Hot-reloading for development
##
## Usage:
##   LevelManager.load_level(0)  # Load Level 0
##   LevelManager.transition_to_level(1)  # Transition to Level 1
##   var current = LevelManager.get_current_level()

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when a level starts loading
signal level_load_started(level_id: int)

## Emitted when a level finishes loading
signal level_loaded(level_config: LevelConfig)

## Emitted when level transition begins
signal level_transition_started(from_level: int, to_level: int)

## Emitted when level transition completes
signal level_transition_completed(to_level: int)

## Emitted when a level is unloaded from cache
signal level_unloaded(level_id: int)

# ============================================================================
# CONFIGURATION
# ============================================================================

## Maximum levels to keep in cache (LRU eviction)
const MAX_CACHED_LEVELS := 3

## Directory where level configs are stored
const LEVEL_CONFIG_DIR := "res://assets/levels/"

## Level config file naming pattern: level_XX_config.tres
const LEVEL_CONFIG_PATTERN := "level_%02d/level_%02d_config.tres"

## Preloaded level configs (ensures they're included in web exports)
## Web builds require preload() to include resources - runtime load() doesn't work reliably
const PRELOADED_CONFIGS := {
	0: preload("res://assets/levels/level_00/level_00_config.tres")
}

# ============================================================================
# INTERNAL STATE
# ============================================================================

## Current active level
var _current_level: LevelConfig = null

## LRU cache: {level_id: LevelConfig}
var _level_cache: Dictionary = {}

## LRU access order (most recent last)
var _lru_order: Array[int] = []

## Preloaded levels for fast transitions
var _preloaded_levels: Dictionary = {}

## Level registry: {level_id: resource_path}
var _level_registry: Dictionary = {}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	Log.system("LevelManager initialized")
	_build_level_registry()
	Log.system("Found %d registered levels" % _level_registry.size())

## Build registry of available levels
##
## Web builds cannot scan directories at runtime, so we hardcode known levels.
## Native builds could scan, but we use the same approach for consistency.
func _build_level_registry() -> void:
	_level_registry.clear()

	# Hardcoded list of known levels
	# Add new levels here as they're created
	var known_levels := [0]  # Level 0 exists

	for level_id in known_levels:
		var config_path := LEVEL_CONFIG_DIR + LEVEL_CONFIG_PATTERN % [level_id, level_id]

		# Register the path (don't check file existence - it doesn't work in web builds)
		# The actual load() will fail gracefully if the file isn't included
		_level_registry[level_id] = config_path
		Log.system("Registered level %d: %s" % [level_id, config_path])

# ============================================================================
# PUBLIC API - LOADING
# ============================================================================

## Load a level by ID (uses cache if available)
func load_level(level_id: int) -> LevelConfig:
	# Check cache first
	if _level_cache.has(level_id):
		_touch_lru(level_id)
		Log.system("Level %d loaded from cache" % level_id)
		return _level_cache[level_id]

	# Check preloaded
	if _preloaded_levels.has(level_id):
		var preloaded_config: LevelConfig = _preloaded_levels[level_id]
		_add_to_cache(level_id, preloaded_config)
		_preloaded_levels.erase(level_id)
		Log.system("Level %d loaded from preload" % level_id)
		return preloaded_config

	# Load from disk
	level_load_started.emit(level_id)

	var config := _load_level_from_disk(level_id)
	if config:
		_add_to_cache(level_id, config)
		level_loaded.emit(config)
		return config
	else:
		push_error("[LevelManager] Failed to load level %d" % level_id)
		return null

## Load level config from disk
func _load_level_from_disk(level_id: int) -> LevelConfig:
	# Check preloaded configs first (required for web builds)
	if PRELOADED_CONFIGS.has(level_id):
		var config: LevelConfig = PRELOADED_CONFIGS[level_id]
		Log.system("Level %d loaded from PRELOADED_CONFIGS" % level_id)
		if config.validate():
			config.on_load()
			return config
		else:
			push_error("[LevelManager] Preloaded config validation failed for level %d" % level_id)
			return null

	# Fallback: try runtime load (works in native builds)
	if not _level_registry.has(level_id):
		push_error("[LevelManager] Level %d not registered" % level_id)
		return null

	var config_path: String = _level_registry[level_id]

	# Try loading as resource
	var config := load(config_path) as LevelConfig
	if not config:
		push_error("[LevelManager] Failed to load config: %s" % config_path)
		return null

	# Validate configuration
	if not config.validate():
		push_error("[LevelManager] Validation failed for level %d" % level_id)
		return null

	Log.system("Level %d loaded from disk: %s" % [level_id, config.display_name])
	config.on_load()

	return config

# ============================================================================
# PUBLIC API - TRANSITIONS
# ============================================================================

## Transition from current level to new level
func transition_to_level(target_level_id: int) -> void:
	var from_level_id := -1
	if _current_level:
		from_level_id = _current_level.level_id
		_current_level.on_exit()

	level_transition_started.emit(from_level_id, target_level_id)
	Log.system("Transitioning: level %d -> level %d" % [from_level_id, target_level_id])

	# Load target level
	var target_config := load_level(target_level_id)
	if not target_config:
		push_error("[LevelManager] Failed to transition to level %d" % target_level_id)
		return

	# Set as current
	_current_level = target_config
	_current_level.on_enter()

	# Preload exit destinations
	_preload_exit_destinations(_current_level)

	level_transition_completed.emit(target_level_id)
	Log.system("Transition complete: now in level %d" % target_level_id)

## Get current active level
func get_current_level() -> LevelConfig:
	return _current_level

## Check if a level is loaded in cache
func is_level_cached(level_id: int) -> bool:
	return _level_cache.has(level_id)

## Check if a level is preloaded
func is_level_preloaded(level_id: int) -> bool:
	return _preloaded_levels.has(level_id)

# ============================================================================
# PRELOADING
# ============================================================================

## Preload a level asynchronously (for fast transitions)
func preload_level(level_id: int) -> void:
	if _level_cache.has(level_id):
		Log.system("Level %d already cached, skipping preload" % level_id)
		return

	if _preloaded_levels.has(level_id):
		Log.system("Level %d already preloaded" % level_id)
		return

	if not _level_registry.has(level_id):
		push_warning("[LevelManager] Cannot preload unregistered level %d" % level_id)
		return

	# Load config (will be moved to cache when accessed)
	var config := _load_level_from_disk(level_id)
	if config:
		_preloaded_levels[level_id] = config
		Log.system("Level %d preloaded" % level_id)

## Preload all exit destinations for a level
func _preload_exit_destinations(config: LevelConfig) -> void:
	for dest_id in config.exit_destinations:
		if not is_level_cached(dest_id) and not is_level_preloaded(dest_id):
			preload_level(dest_id)

# ============================================================================
# LRU CACHE MANAGEMENT
# ============================================================================

## Add level to cache (evicts LRU if full)
func _add_to_cache(level_id: int, config: LevelConfig) -> void:
	# Evict if cache is full
	if _level_cache.size() >= MAX_CACHED_LEVELS and not _level_cache.has(level_id):
		_evict_lru()

	# Add to cache
	_level_cache[level_id] = config
	_touch_lru(level_id)

	Log.system("Level %d added to cache (%d/%d)" % [level_id, _level_cache.size(), MAX_CACHED_LEVELS])

## Mark level as recently used (move to end of LRU)
func _touch_lru(level_id: int) -> void:
	_lru_order.erase(level_id)
	_lru_order.append(level_id)

## Evict least recently used level from cache
func _evict_lru() -> void:
	if _lru_order.is_empty():
		return

	var evict_id: int = _lru_order[0]
	_lru_order.remove_at(0)

	# Call lifecycle hook
	if _level_cache.has(evict_id):
		var config: LevelConfig = _level_cache[evict_id]
		config.on_unload()

	_level_cache.erase(evict_id)
	level_unloaded.emit(evict_id)

	Log.system("Evicted level %d from cache (LRU)" % evict_id)

## Clear all cached levels (for testing/debugging)
func clear_cache() -> void:
	for level_id in _level_cache.keys():
		var config: LevelConfig = _level_cache[level_id]
		config.on_unload()

	_level_cache.clear()
	_lru_order.clear()
	_preloaded_levels.clear()

	Log.system("Level cache cleared")

# ============================================================================
# DEVELOPMENT / DEBUGGING
# ============================================================================

## Hot-reload current level (for development)
func hot_reload_current() -> void:
	if not _current_level:
		push_warning("[LevelManager] No current level to reload")
		return

	var level_id := _current_level.level_id

	# Remove from cache
	_level_cache.erase(level_id)
	_lru_order.erase(level_id)

	# Reload from disk
	var reloaded := _load_level_from_disk(level_id)
	if reloaded:
		_current_level = reloaded
		_add_to_cache(level_id, reloaded)
		Log.system("Hot-reloaded level %d" % level_id)
	else:
		push_error("[LevelManager] Hot-reload failed for level %d" % level_id)

## Get cache statistics (for debugging)
func get_cache_stats() -> Dictionary:
	return {
		"cached_levels": _level_cache.keys(),
		"cache_size": _level_cache.size(),
		"max_cache_size": MAX_CACHED_LEVELS,
		"lru_order": _lru_order.duplicate(),
		"preloaded_levels": _preloaded_levels.keys(),
		"current_level_id": _current_level.level_id if _current_level else -1
	}

## Print cache stats to console
func print_cache_stats() -> void:
	var stats := get_cache_stats()
	print("\n=== LevelManager Cache Stats ===")
	print("Current level: %d" % stats.current_level_id)
	print("Cached levels: %s" % str(stats.cached_levels))
	print("Cache usage: %d/%d" % [stats.cache_size, stats.max_cache_size])
	print("LRU order: %s" % str(stats.lru_order))
	print("Preloaded: %s" % str(stats.preloaded_levels))
	print("=================================\n")
