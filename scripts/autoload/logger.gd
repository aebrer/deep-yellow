extends Node
## Centralized logging system with category-based filtering and level control
##
## This autoload singleton provides:
## - Category-based logging (input, state, movement, action, etc.)
## - Level-based filtering (ERROR, WARN, INFO, DEBUG, TRACE)
## - Zero overhead when categories disabled
## - Structured output with timestamps and context
## - Runtime configuration via exported properties
##
## Usage:
##   Log.input("Direction changed: %s" % direction)
##   Log.state("Entering IdleState")
##   Log.msg(Logger.Category.MOVEMENT, Logger.Level.ERROR, "Invalid grid position")

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when a message is logged (for UI display)
signal message_logged(category: Category, level: Level, message: String)

# ============================================================================
# LOG LEVELS (Priority ordering)
# ============================================================================

enum Level {
	TRACE = 0,   # Most verbose - every frame events
	DEBUG = 1,   # Debug info - state changes, calculations
	INFO = 2,    # Normal info - important events
	PLAYER = 3,  # Player-facing messages - levelups, exp, kills, level transitions
	WARN = 4,    # Warnings - unexpected but recoverable
	ERROR = 5,   # Errors - serious issues
	NONE = 6     # Disable all logging
}

# ============================================================================
# LOG CATEGORIES (Expandable as features grow)
# ============================================================================

enum Category {
	INPUT,       # InputManager events (stick, triggers, actions)
	STATE,       # State machine transitions and state events
	MOVEMENT,    # Movement actions and validation
	ACTION,      # Action system (execute, validate)
	TURN,        # Turn execution and counting
	GRID,        # Grid/tile operations
	CAMERA,      # Camera movement and rotation
	ENTITY,      # Entity spawning/AI (future)
	ABILITY,     # Ability system (future)
	PHYSICS,     # Physics simulation (future)
	SYSTEM,      # System-level events (initialization, errors)
}

# ============================================================================
# CONFIGURATION (Exported for inspector editing)
# ============================================================================

## Global log level - messages below this level are suppressed
@export var global_level: Level = Level.DEBUG

## Enable/disable individual categories (independent of level)
@export_group("Category Filters")
@export var log_input: bool = false     # Disabled by default (very verbose, only for input bugs)
@export var log_state: bool = true
@export var log_movement: bool = true
@export var log_action: bool = true
@export var log_turn: bool = true
@export var log_grid: bool = true       # ENABLED for procedural generation debugging
@export var log_camera: bool = true     # ENABLED for web build input debugging
@export var log_entity: bool = true
@export var log_ability: bool = true
@export var log_physics: bool = false   # Disabled by default (very verbose)
@export var log_system: bool = true

## Output configuration
@export_group("Output Settings")
@export var show_timestamps: bool = false
@export var show_frame_count: bool = false
@export var show_category_prefix: bool = true
@export var show_level_prefix: bool = false

## File logging (future feature)
@export_group("File Logging")
@export var enable_file_logging: bool = false
@export var log_file_path: String = "user://logs/game.log"
@export var max_log_file_size_mb: int = 10

# ============================================================================
# INTERNAL STATE
# ============================================================================

# Category name lookup for formatting
const CATEGORY_NAMES = {
	Category.INPUT: "Input",
	Category.STATE: "State",
	Category.MOVEMENT: "Movement",
	Category.ACTION: "Action",
	Category.TURN: "Turn",
	Category.GRID: "Grid",
	Category.CAMERA: "Camera",
	Category.ENTITY: "Entity",
	Category.ABILITY: "Ability",
	Category.PHYSICS: "Physics",
	Category.SYSTEM: "System",
}

# Level name lookup for formatting
const LEVEL_NAMES = {
	Level.TRACE: "TRACE",
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.PLAYER: "PLAYER",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}

# Frame counter for timestamping
var _frame_count: int = 0

# File handle for logging (if enabled)
var _log_file: FileAccess = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	print("[Logger] Logging system initialized")
	print("[Logger] Global level: %s" % LEVEL_NAMES.get(global_level, "UNKNOWN"))
	print("[Logger] Active categories: %s" % _get_active_categories())

	if enable_file_logging:
		_open_log_file()

func _process(_delta: float) -> void:
	_frame_count += 1

func _exit_tree() -> void:
	if _log_file:
		_log_file.close()

# ============================================================================
# CORE LOGGING API (Level + Category)
# ============================================================================

## Generic logging method (all others route through this)
func msg(category: Category, level: Level, message: String) -> void:
	# ⚠️ THREAD SAFETY - DO NOT REMOVE ⚠️
	# Worker threads (e.g., ChunkGenerationThread) cannot access scene tree nodes.
	# Attempting to emit signals from worker threads causes Godot errors:
	# "Caller thread can't call this function in this node. Use call_deferred()..."
	# Silently skip logging from worker threads - main thread logs are sufficient.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return

	# Fast path: check if this category/level should be logged
	if not _should_log(category, level):
		return

	# Format and output the message
	var formatted = _format_message(category, level, message)
	print(formatted)

	if enable_file_logging and _log_file:
		_log_file.store_line(formatted)

	# Emit signal for UI display
	message_logged.emit(category, level, message)

## Check if a category + level should be logged (performance optimization)
func _should_log(category: Category, level: Level) -> bool:
	# Level check first (most common filter)
	if level < global_level:
		return false

	# Category check (using match for performance)
	match category:
		Category.INPUT: return log_input
		Category.STATE: return log_state
		Category.MOVEMENT: return log_movement
		Category.ACTION: return log_action
		Category.TURN: return log_turn
		Category.GRID: return log_grid
		Category.CAMERA: return log_camera
		Category.ENTITY: return log_entity
		Category.ABILITY: return log_ability
		Category.PHYSICS: return log_physics
		Category.SYSTEM: return log_system

	return false

# ============================================================================
# CONVENIENCE METHODS (Category-specific)
# ============================================================================

# INPUT category
func input(message: String) -> void:
	msg(Category.INPUT, Level.DEBUG, message)

func input_trace(message: String) -> void:
	msg(Category.INPUT, Level.TRACE, message)

# STATE category
func state(message: String) -> void:
	msg(Category.STATE, Level.DEBUG, message)

func state_info(message: String) -> void:
	msg(Category.STATE, Level.INFO, message)

# MOVEMENT category
func movement(message: String) -> void:
	msg(Category.MOVEMENT, Level.DEBUG, message)

func movement_info(message: String) -> void:
	msg(Category.MOVEMENT, Level.INFO, message)

# ACTION category
func action(message: String) -> void:
	msg(Category.ACTION, Level.DEBUG, message)

# TURN category
func turn(message: String) -> void:
	msg(Category.TURN, Level.INFO, message)

# GRID category
func grid(message: String) -> void:
	msg(Category.GRID, Level.DEBUG, message)

# CAMERA category
func camera(message: String) -> void:
	msg(Category.CAMERA, Level.DEBUG, message)

# Cross-category level methods
func warn(category: Category, message: String) -> void:
	msg(category, Level.WARN, message)

func error(category: Category, message: String) -> void:
	msg(category, Level.ERROR, message)

func trace(category: Category, message: String) -> void:
	msg(category, Level.TRACE, message)

# SYSTEM category (always logged unless global level is ERROR+)
func system(message: String) -> void:
	msg(Category.SYSTEM, Level.INFO, message)

# PLAYER-facing messages (levelups, exp, kills, level transitions)
func player(message: String) -> void:
	msg(Category.SYSTEM, Level.PLAYER, message)

# ============================================================================
# FORMATTING
# ============================================================================

func _format_message(category: Category, level: Level, message: String) -> String:
	var parts: Array[String] = []

	# Timestamp (if enabled)
	if show_timestamps:
		var time = Time.get_ticks_msec() / 1000.0
		parts.append("[%.3fs]" % time)

	# Frame count (if enabled)
	if show_frame_count:
		parts.append("[F%d]" % _frame_count)

	# Category prefix (if enabled)
	if show_category_prefix:
		var cat_name = CATEGORY_NAMES.get(category, "Unknown")
		parts.append("[%s]" % cat_name)

	# Level prefix (if enabled and not DEBUG)
	if show_level_prefix and level != Level.DEBUG:
		var level_name = LEVEL_NAMES.get(level, "UNKNOWN")
		parts.append("[%s]" % level_name)

	# Message
	parts.append(message)

	return " ".join(parts)

func _get_active_categories() -> String:
	var active: Array[String] = []
	if log_input: active.append("Input")
	if log_state: active.append("State")
	if log_movement: active.append("Movement")
	if log_action: active.append("Action")
	if log_turn: active.append("Turn")
	if log_grid: active.append("Grid")
	if log_camera: active.append("Camera")
	if log_entity: active.append("Entity")
	if log_ability: active.append("Ability")
	if log_physics: active.append("Physics")
	if log_system: active.append("System")

	return ", ".join(active) if active.size() > 0 else "none"

# ============================================================================
# FILE LOGGING (Future feature)
# ============================================================================

func _open_log_file() -> void:
	# Ensure directory exists
	var dir_path = log_file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# Open file in append mode
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file:
		system("File logging enabled: %s" % log_file_path)
	else:
		push_error("[Logger] Failed to open log file: %s" % log_file_path)

# ============================================================================
# RUNTIME CONFIGURATION API
# ============================================================================

func set_global_level(level: Level) -> void:
	"""Set the global log level at runtime"""
	global_level = level
	system("Global log level changed to: %s" % LEVEL_NAMES.get(level, "UNKNOWN"))

func enable_category(category: Category, enabled: bool) -> void:
	"""Enable/disable a category at runtime"""
	match category:
		Category.INPUT: log_input = enabled
		Category.STATE: log_state = enabled
		Category.MOVEMENT: log_movement = enabled
		Category.ACTION: log_action = enabled
		Category.TURN: log_turn = enabled
		Category.GRID: log_grid = enabled
		Category.CAMERA: log_camera = enabled
		Category.ENTITY: log_entity = enabled
		Category.ABILITY: log_ability = enabled
		Category.PHYSICS: log_physics = enabled
		Category.SYSTEM: log_system = enabled

	var cat_name = CATEGORY_NAMES.get(category, "Unknown")
	system("Category '%s' %s" % [cat_name, "enabled" if enabled else "disabled"])

func enable_all_categories() -> void:
	"""Enable all categories (for deep debugging)"""
	for category in Category.values():
		enable_category(category, true)

func disable_all_categories() -> void:
	"""Disable all categories"""
	for category in Category.values():
		enable_category(category, false)
