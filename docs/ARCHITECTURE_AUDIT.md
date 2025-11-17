# Backrooms Power Crawl - Complete Architecture Audit
**Generated**: 2025-11-17
**Total GDScript LOC**: 6,943 lines
**Total Files Analyzed**: 67 files (.gd, .tscn, .tres, .md, .py)

---

## Executive Summary

### Project Status
**Current State**: Transitioning from 2D prototype to 3D production with procedural generation
**Active Branch**: `feature/procedural-generation`
**Most Recent Major Change**: Threaded chunk generation for smooth gameplay (e586ec0)

### Architecture Overview
The project has TWO parallel implementations:
1. **Legacy 2D System** (`grid.gd`, `player.gd`, `game.gd`) - **DEAD CODE, not in use**
2. **Active 3D System** (`grid_3d.gd`, `player_3d.gd`, `game_3d.gd`) - **CURRENTLY IN USE**

The 3D system is embedded in the main HUD scene (`game.tscn`) as a SubViewport, using:
- **Main wrapper**: `game.gd` (2D Control node, manages HUD)
  - **3D viewport**: `game_3d.gd` (embedded in SubViewport with PSX shaders)
    - **Grid system**: `grid_3d.gd` (GridMap-based world)
    - **Player**: `player_3d.gd` (CharacterBody3D)

### Key Systems Inventory
- ✅ **Input System**: Fully implemented, controller-first
- ✅ **State Machine**: Turn-based state management complete
- ✅ **Action System**: Command pattern for moves/waits
- ✅ **Logging System**: Comprehensive category-based logging
- ✅ **Examination System**: On-demand tile creation with raycasting
- ✅ **Procedural Generation**: WFC-based Level 0 maze generation
- ✅ **Chunk System**: Infinite world with threaded chunk generation + streaming
- ✅ **Performance Optimizations**: Threaded generation (0ms main thread), optimized grid application (3.6x faster)
- ✅ **Level Management**: Multi-level config system with LRU cache
- ⚠️ **2D Legacy Code**: Completely unused, safe to delete
- ⚠️ **Documentation**: Some outdated references to old systems

---

## File Inventory

### 🎯 Active Core Systems (3D)

#### **Main Game Entry**
**Purpose**: Root scene that contains HUD + embedded 3D viewport
**Status**: ACTIVE (modified Nov 14)

##### `scenes/game.tscn`
- **Scene Structure**: Control → HBoxContainer → (LeftSide + RightSide)
  - LeftSide: ViewportPanel → SubViewportContainer → SubViewport → `game_3d.tscn`
  - RightSide: Log panel UI
- **Script**: `scripts/game.gd`
- **Dependencies**:
  - Embeds `game_3d.tscn` (3D world in viewport)
  - Uses `ExaminationPanel` (TextUIOverlay/ExaminationPanel)
  - Uses `ActionPreviewUI` (ViewportUILayer/ActionPreviewUI)
- **Git History**:
  - `fac7117`: Split examination UI for VHS post-processing prep
  - `938a791`: Connect logging system to UI log panel
  - `ee4b533`: Refactor UI - separate PSX viewport from native HUD

##### `scripts/game.gd`
- **Git History**:
  - Last modified: fac7117 (Split examination UI)
- **Class**: extends Control
- **Purpose**: Root HUD manager, does NOT handle 3D gameplay
- **Methods**:
  - `_ready()`: Initialize logging presets
  - (Minimal - mostly UI orchestration)
- **Dependencies**:
  - Uses LoggerPresets
  - Contains ExaminationPanel + ActionPreviewUI references
- **Used By**: Main scene (`scenes/game.tscn`)
- **Status**: Active - HUD wrapper only

---

#### **3D World System**
**Purpose**: Actual 3D game viewport with grid, player, camera
**Status**: ACTIVE (modified Nov 15)

##### `scenes/game_3d.tscn`
- **Scene Structure**: Node3D → (Grid3D, Player3D, TacticalCamera, FirstPersonCamera, WorldEnvironment, OverheadLight, MoveIndicator)
- **Script**: `scripts/game_3d.gd`
- **Viewport Settings**:
  - Size: 640x480 (PSX resolution)
  - Embedded in SubViewport with VHS post-processing shader
- **Dependencies**:
  - Grid3D (procedural chunk loading)
  - Player3D (CharacterBody3D with state machine)
  - TacticalCamera + FirstPersonCamera
- **Git History**:
  - Last modified: Nov 15 (grid integration updates)

##### `scripts/game_3d.gd`
- **Git History**: None listed (new file, likely in procedural-generation branch)
- **Class**: extends Node3D
- **Purpose**: 3D gameplay coordinator
- **Constants**: None
- **Lifecycle Methods**:
  - `_ready()`:
    - Load Level 0 config via LevelManager
    - Configure grid with level settings (lighting, background, materials)
    - Link player to grid and move indicator
    - Link grid back to player (for proximity fade)
- **Node References**:
  - `@onready var grid: Grid3D`
  - `@onready var player: Player3D`
  - `@onready var move_indicator: Node3D`
- **Dependencies**:
  - LevelManager (load_level, transition_to_level)
  - Grid3D (configure_from_level, set_player)
- **Used By**: `scenes/game.tscn` (embedded in SubViewport)
- **Status**: Active - 3D world coordinator

---

#### **Grid System (3D)**
**Purpose**: Tile-based world using GridMap, supports procedural chunks
**Status**: ACTIVE (modified Nov 14)

##### `scripts/grid_3d.gd`
- **Git History**: Modified on feature/procedural-generation branch
- **Class**: `class_name Grid3D extends Node3D`
- **Purpose**: 3D grid system using GridMap for tile-based world
- **Constants**:
  - `GRID_SIZE := Vector2i(128, 128)` (per-chunk size)
  - `CELL_SIZE := Vector3(2.0, 1.0, 2.0)` (doubled for visibility)
  - `cell_octant_size = 16` (increased from default 8 for procedural generation)
- **Enums**:
  - `TileType`: FLOOR=0, WALL=1, CEILING=2
- **Exported Vars**: None
- **Instance Vars**:
  - `@onready var grid_map: GridMap`
  - `var grid_size: Vector2i`
  - `var walkable_cells: Dictionary` (Vector2i → bool)
  - `var current_level: LevelConfig`
  - `var player_node: Node3D` (for proximity fade)
  - `var use_procedural_generation: bool`
  - `var wall_materials: Array[ShaderMaterial]`
  - `var ceiling_materials: Array[ShaderMaterial]`
- **Methods**:
  - `_ready()`: Initialize grid map
  - `initialize(size: Vector2i)`: Legacy method
  - `configure_from_level(level_config: LevelConfig)`: **MAIN ENTRY POINT**
    - Applies level visuals (lighting, background, materials)
    - Detects ChunkManager for procedural mode
    - Caches materials for proximity fade
  - `_apply_level_visuals(config)`: Apply runtime settings to scene nodes
  - `_generate_grid()`: Legacy static generation (not used in procedural mode)
  - `load_chunk(chunk: Chunk)`: Load chunk from ChunkManager into GridMap
  - `unload_chunk(chunk: Chunk)`: Clear chunk tiles from GridMap
  - `grid_to_world(grid_pos: Vector2) → Vector3`: Coordinate conversion
  - `world_to_grid(world_pos: Vector3) → Vector2`: Reverse conversion
  - `is_walkable(pos: Vector2i) → bool`: Check if tile is walkable
  - `_cache_wall_materials()`, `_cache_ceiling_materials()`: Shader material caching
  - `set_player(player)`: Link player for proximity fade updates
  - `_process(delta)`: Update shader uniforms for proximity fade
- **Dependencies**:
  - LevelConfig (current_level)
  - Chunk, ChunkManager (procedural generation)
  - GridMap (rendering)
- **Performance**:
  - GridMap loading: ~27ms per chunk
- **Used By**:
  - game_3d.gd (configure_from_level)
  - player_3d.gd (grid_to_world, is_walkable)
  - ChunkManager (load_chunk, unload_chunk)
  - FirstPersonCamera (world_to_grid for examination)
- **Status**: Active - core 3D grid system

---

#### **Player System (3D)**
**Purpose**: Turn-based player controller with state machine
**Status**: ACTIVE (modified Nov 13)

##### `scripts/player/player_3d.gd`
- **Git History**: Created during 3D migration
- **Class**: `class_name Player3D extends CharacterBody3D`
- **Purpose**: 3D player controller for turn-based movement
- **Signals**:
  - `action_preview_changed(actions: Array[Action])` - For UI updates
  - `turn_completed()` - For ChunkManager and other turn-based systems
- **Instance Vars**:
  - `var grid_position: Vector2i = Vector2i(64, 64)`
  - `var pending_action = null`
  - `var turn_count: int = 0`
  - `var grid: Grid3D = null`
  - `var move_indicator: Node3D = null`
  - `@onready var model: Node3D`
  - `@onready var state_machine: InputStateMachine`
  - `@onready var camera_rig: TacticalCamera`
- **Methods**:
  - `_ready()`: Add to "player" group, set initial grid position (69, 1)
  - `_unhandled_input(event)`: Delegate to state machine
  - `_process(delta)`: Delegate to state machine
  - `update_visual_position()`: SNAP to grid (turn-based, no lerping)
  - `get_camera_forward_grid_direction() → Vector2i`: Calculate direction from camera yaw
  - `update_move_indicator()`: Show green arrow 1 cell ahead
  - `hide_move_indicator()`: Hide movement preview
- **Dependencies**:
  - Grid3D (grid reference, grid_to_world, is_walkable)
  - InputStateMachine (state management)
  - TacticalCamera (camera_rig for forward direction)
  - Action (MovementAction, WaitAction)
- **Used By**:
  - game_3d.gd (initialization)
  - States (IdleState, LookModeState, ExecutingTurnState)
  - ChunkManager (turn_completed signal)
- **Status**: Active - core player controller

##### `scripts/player/first_person_camera.gd`
- **Git History**: Created for examination system
- **Class**: `class_name FirstPersonCamera extends Node3D`
- **Purpose**: First-person look camera for examination mode (LT/RMB)
- **Exports**:
  - `@export var rotation_speed: float = 360.0` (same as TacticalCamera)
  - `@export var mouse_sensitivity: float = 0.15`
  - `@export var rotation_deadzone: float = 0.3` (right stick)
  - `@export var pitch_min: float = -89.0`
  - `@export var pitch_max: float = 89.0`
  - `@export var default_fov: float = 75.0`
  - `@export var fov_min: float = 60.0`
  - `@export var fov_max: float = 90.0`
  - `@export var fov_zoom_speed: float = 5.0`
- **Constants**:
  - `MAX_CACHED_TILES := 20` (examination tile cache limit)
- **Instance Vars**:
  - `@onready var h_pivot: Node3D`, `v_pivot: Node3D`, `camera: Camera3D`
  - `var active: bool` (controlled by LookModeState)
  - `var examination_tile_cache: Dictionary` (Vector2i → ExaminableEnvironmentTile)
  - `var examination_world: Node3D` (parent for cached tiles)
- **Methods**:
  - `_ready()`: Position at eye height (1.6m), initialize camera
  - `_process(delta)`: Right stick camera rotation (same as tactical)
  - `_unhandled_input(event)`: Mouse camera rotation + FOV zoom
  - `activate()`: Switch to first-person, create examination world
  - `deactivate()`: Switch back to tactical, clear cache
  - `get_look_raycast() → Dictionary`: Raycast from camera center (5m range, layer 4)
  - `get_current_target() → Examinable`: **ON-DEMAND TILE CREATION**
    - First checks layer 4 for existing Examinable
    - If not found, raycasts GridMap (layer 2) and creates tile on-demand
    - Caches tiles for reuse (max 20)
  - `_raycast_gridmap() → Dictionary`: Raycast GridMap (layer 2)
  - `_get_tile_type_at_position(...) → String`: Determine floor/wall/ceiling from GridMap + normal
  - `_create_examination_tile(...) → Examinable`: Create ExaminableEnvironmentTile on-demand
  - `_clear_examination_cache()`: Free all cached tiles
- **Dependencies**:
  - Examinable (examination component)
  - ExaminableEnvironmentTile (on-demand tile scene)
  - Grid3D (world_to_grid, get_cell_item)
  - KnowledgeDB (examine_entity)
- **Used By**: LookModeState (activate, deactivate, get_current_target)
- **Issues**: None - clean on-demand caching system
- **Status**: Active - examination camera with on-demand tile generation

##### `scripts/player/tactical_camera.gd`
- **Git History**:
  - `620a327`: Fix Start button mapping
  - `eefbe28`: Fix GDScript warnings and double ceiling fade
  - `d9af93c`: Replace ShapeCast3D ceiling system
  - `cdb23fe`: Implement Fortnite-style third-person camera
- **Class**: `class_name TacticalCamera extends Node3D`
- **Purpose**: Third-person tactical camera with right-stick/mouse rotation
- **Exports**:
  - `@export var rotation_speed: float = 360.0` (gamepad rotation speed)
  - `@export var mouse_sensitivity: float = 0.15`
  - `@export var rotation_deadzone: float = 0.3`
  - `@export var pitch_min: float = -60.0`, `pitch_max: float = 70.0`
  - `@export var zoom_speed: float = 5.0`
  - `@export var zoom_min: float = 3.0`, `zoom_max: float = 15.0`
  - `@export var default_zoom: float = 8.0`
- **Instance Vars**:
  - `@onready var h_pivot: Node3D`, `v_pivot: Node3D`, `spring_arm: SpringArm3D`, `camera: Camera3D`
- **Methods**:
  - `_ready()`: Initialize rotation and zoom
  - `_process(delta)`: **DIRECT rotation** (no lerping!) for 1:1 stick response
    - Right stick X → horizontal rotation
    - Right stick Y → vertical rotation (pitch)
    - LB/RB → zoom in/out
  - `_unhandled_input(event)`: Mouse rotation when captured
  - `reset_rotation()`: Reset to default view
  - `set_zoom(distance)`: Adjust SpringArm length
- **Dependencies**:
  - InputManager (get_joy_axis for stick input)
  - Input (mouse_mode for capture state)
- **Used By**:
  - player_3d.gd (camera_rig for forward direction)
  - LookModeState (sync rotations with FirstPersonCamera)
- **Issues**: None - standard third-person camera
- **Status**: Active - tactical camera with input parity

##### `scripts/player/input_state_machine.gd`
- **Git History**: Created during input system implementation
- **Class**: `class_name InputStateMachine extends Node`
- **Purpose**: State machine for managing player input states
- **Instance Vars**:
  - `var current_state: PlayerInputState = null`
  - `var states: Dictionary = {}` (name → state node)
- **Methods**:
  - `_ready()`: Auto-register child states, connect signals
  - `_register_state(state)`: Register state and connect transitions
  - `change_state(new_state_name)`: Exit current, enter new state
  - `get_current_state_name() → String`: For debugging
  - `handle_input(event)`: Delegate to current state
  - `process_frame(delta)`: Delegate to current state
  - `_on_state_transition_requested(new_state_name)`: Handle state transitions
- **Dependencies**:
  - PlayerInputState (base class for all states)
  - Player3D (parent node reference)
- **Used By**:
  - player_3d.gd (_unhandled_input, _process)
  - States (IdleState, LookModeState, ExecutingTurnState, PostTurnState)
- **Status**: Active - core state management

---

#### **Player States**
**Purpose**: Turn-based input state handlers
**Status**: ACTIVE

##### `scripts/player/states/player_input_state.gd`
- **Class**: `class_name PlayerInputState extends Node`
- **Purpose**: Base class for all player input states
- **Signals**:
  - `state_transition_requested(new_state_name: String)`
- **Instance Vars**:
  - `var player = null` (set by state machine)
  - `var state_machine = null` (set by state machine)
  - `var state_name: String = "BaseState"`
- **Methods**:
  - `enter()`: Called when entering state
  - `exit()`: Called when exiting state
  - `handle_input(event)`: Override in subclasses
  - `process_frame(delta)`: Override in subclasses
  - `transition_to(new_state_name)`: Request state transition
- **Dependencies**: None (base class)
- **Used By**: All state implementations
- **Status**: Active - base state class

##### `scripts/player/states/idle_state.gd`
- **Class**: `extends PlayerInputState`
- **Purpose**: Waiting for player input, handles forward movement
- **Instance Vars**:
  - `var rt_held: bool` (RT/Click hold tracking)
  - `var rt_hold_time: float`
  - `var rt_repeat_timer: float`
- **Constants**:
  - `INITIAL_DELAY: float = 0.3` (before repeat starts)
  - `REPEAT_INTERVAL_START: float = 0.25` (first repeat delay)
  - `REPEAT_INTERVAL_MIN: float = 0.08` (max repeat speed)
  - `RAMP_TIME: float = 2.0` (time to reach max speed)
- **Methods**:
  - `_init()`: Set state_name = "IdleState"
  - `enter()`: Show forward indicator, update action preview
  - `handle_input(event)`: Check for look mode (LT/RMB)
  - `_move_forward()`: Create MovementAction in camera direction
  - `process_frame(delta)`:
    - Update forward indicator
    - Handle RT/Click press and hold-to-repeat
    - Ramp repeat speed over time
  - `_update_action_preview()`: Emit action_preview_changed with MovementAction
- **Dependencies**:
  - InputManager (is_action_just_pressed, is_action_pressed)
  - MovementAction (create movement action)
- **Used By**: InputStateMachine
- **Status**: Active - main idle/movement state

##### `scripts/player/states/look_mode_state.gd`
- **Class**: `extends PlayerInputState`
- **Purpose**: First-person examination mode (LT/RMB held)
- **Instance Vars**:
  - `var first_person_camera: FirstPersonCamera`
  - `var tactical_camera: TacticalCamera`
  - `var examination_crosshair: ExaminationCrosshair`
  - `var examination_panel: ExaminationPanel`
  - `var current_target: Examinable`
  - `var current_grid_tile: Dictionary` (unused)
- **Methods**:
  - `_init()`: Set state_name = "LookModeState"
  - `enter()`:
    - Get camera and UI references
    - Sync FP camera rotation to tactical camera
    - Switch to first-person camera
    - Hide tactical UI, show examination crosshair
    - Update action preview (wait action)
  - `exit()`:
    - Sync tactical camera rotation back to FP camera
    - Switch to tactical camera
    - Hide examination UI
  - `handle_input(event)`: Exit on LT/RMB release
  - `process_frame(delta)`:
    - Handle RT/LMB for wait action
    - Update raycast and examination target
    - Show/hide examination panel based on target
  - `_execute_wait_action()`: Execute WaitAction while staying in look mode
  - `_update_action_preview()`: Emit action_preview_changed with WaitAction
- **Dependencies**:
  - FirstPersonCamera (activate, deactivate, get_current_target)
  - TacticalCamera (sync rotations)
  - ExaminationCrosshair, ExaminationPanel (UI)
  - KnowledgeDB (examine_entity)
  - WaitAction (pass turn)
- **Used By**: InputStateMachine
- **Status**: Active - examination mode

##### `scripts/player/states/executing_turn_state.gd`
- **Class**: `extends PlayerInputState`
- **Purpose**: Processing player action and turn consequences
- **Methods**:
  - `_init()`: Set state_name = "ExecutingTurnState"
  - `enter()`: Hide movement indicator, execute turn immediately
  - `handle_input(event)`: Block all input (pass)
  - `_execute_turn()`:
    - Execute player.pending_action
    - Clear pending_action
    - Emit turn_completed signal
    - Transition to PostTurnState
- **Dependencies**:
  - Action (execute)
  - Player3D (pending_action, turn_count, turn_completed signal)
- **Used By**: InputStateMachine (triggered by IdleState after move confirmation)
- **Issues**: None
- **Status**: Active - turn execution

##### `scripts/player/states/post_turn_state.gd`
- **Class**: `extends PlayerInputState`
- **Purpose**: Processing world updates after action execution (waits for chunk generation)
- **Methods**:
  - `_init()`: Set state_name = "PostTurnState"
  - `enter()`: Connect to ChunkManager.chunk_updates_completed (CONNECT_ONE_SHOT)
  - `handle_input(event)`: Block ALL input (prevents input queuing during chunk gen)
  - `_on_chunk_updates_complete()`: Transition back to IdleState
- **Dependencies**:
  - ChunkManager (chunk_updates_completed signal)
- **Used By**: InputStateMachine (triggered by ExecutingTurnState)
- **Issues**: None - proper signal cleanup with CONNECT_ONE_SHOT
- **Status**: Active - chunk generation blocking

---

### 🎮 Input System (Autoload)

#### `scripts/autoload/input_manager.gd`
- **Git History**: Created during input system implementation
- **Class**: `extends Node` (Autoload singleton)
- **Purpose**: Centralized input handling for turn-based roguelike
- **Enums**:
  - `InputDevice`: GAMEPAD, MOUSE_KEYBOARD
- **Signals**:
  - `input_device_changed(device: InputDevice)`
- **Exports**:
  - `@export var aim_deadzone: float = 0.15`
  - `@export var debug_input: bool = true`
- **Constants**:
  - `TRIGGER_THRESHOLD: float = 0.5`
  - `TRIGGER_AXIS_LEFT: int = 4` (LT)
  - `TRIGGER_AXIS_RIGHT: int = 5` (RT)
- **Instance Vars**:
  - `var current_input_device: InputDevice`
  - `var aim_direction: Vector2` (normalized, or ZERO)
  - `var aim_direction_grid: Vector2i` (8-way snapped)
  - `var _actions_this_frame: Dictionary` (action tracking)
  - `var left_trigger_value: float`, `right_trigger_value: float`
  - `var left_trigger_pressed: bool`, `right_trigger_pressed: bool`
  - `var _left_trigger_just_pressed: bool`, `_right_trigger_just_pressed: bool`
  - `var left_mouse_pressed: bool`, `_left_mouse_just_pressed: bool`
- **Methods**:
  - `_ready()`: Log initialization, list connected controllers
  - `_process(delta)`: Clear frame tracking, update triggers/mouse, update aim direction
  - `_input(event)`: Detect input device from event type
  - `_unhandled_input(event)`: Log input events, track action presses
  - `_detect_input_device(event)`: Auto-switch between gamepad and mouse+keyboard
  - `_update_aim_direction()`: Read left stick/WASD with radial deadzone
  - `_analog_to_grid_8_direction(analog) → Vector2i`: Angle-based octant snapping
  - `get_aim_direction() → Vector2`: Current aim direction
  - `get_aim_direction_grid() → Vector2i`: 8-way snapped direction
  - `_update_triggers()`: Read trigger axes, synthesize move_confirm action
  - `_update_mouse_buttons()`: Track mouse button state, synthesize move_confirm
  - `is_action_just_pressed(action) → bool`: Check if action pressed this frame
  - `is_action_pressed(action) → bool`: Check if action currently held (handles triggers + mouse)
  - `set_aim_deadzone(deadzone)`: Configure deadzone
  - `set_debug_mode(enabled)`: Toggle debug logging
  - `_log_input_event(event)`: Generic input logger (TRACE level)
  - `_get_axis_name(axis) → String`: Human-readable axis names
  - `_get_button_name(button_index) → String`: Human-readable button names (Xbox layout)
  - `_get_mouse_button_name(button_index) → String`: Mouse button names
  - `get_debug_info() → Dictionary`: Current input state for debugging
- **Dependencies**:
  - Log (logger autoload)
  - Input (Godot's input system)
- **Used By**:
  - All states (is_action_just_pressed, is_action_pressed)
  - player_3d.gd (aim_direction_grid)
- **Issues**: None - comprehensive input abstraction
- **Status**: Active - core input system

---

### 📊 Logging System (Autoload)

#### `scripts/autoload/logger.gd`
- **Class**: `extends Node` (Autoload singleton as "Log")
- **Purpose**: Centralized logging with category and level filtering
- **Enums**:
  - `Level`: TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, NONE=5
  - `Category`: INPUT, STATE, MOVEMENT, ACTION, TURN, GRID, CAMERA, ENTITY, ABILITY, PHYSICS, SYSTEM
- **Signals**:
  - `message_logged(category: Category, level: Level, message: String)`
- **Exports**:
  - `@export var global_level: Level = Level.DEBUG`
  - `@export var log_input: bool = false` (disabled by default - verbose)
  - `@export var log_state: bool = true`
  - `@export var log_movement: bool = true`
  - `@export var log_action: bool = true`
  - `@export var log_turn: bool = true`
  - `@export var log_grid: bool = true` (enabled for procedural debugging)
  - `@export var log_camera: bool = false` (disabled - verbose)
  - `@export var log_entity: bool = true`
  - `@export var log_ability: bool = true`
  - `@export var log_physics: bool = false` (disabled - verbose)
  - `@export var log_system: bool = true`
  - `@export var show_timestamps: bool = false`
  - `@export var show_frame_count: bool = false`
  - `@export var show_category_prefix: bool = true`
  - `@export var show_level_prefix: bool = false`
  - `@export var enable_file_logging: bool = false` (future feature)
  - `@export var log_file_path: String = "user://logs/game.log"`
  - `@export var max_log_file_size_mb: int = 10`
- **Constants**:
  - `CATEGORY_NAMES: Dictionary` (enum → string lookup)
  - `LEVEL_NAMES: Dictionary` (enum → string lookup)
- **Instance Vars**:
  - `var _frame_count: int = 0`
  - `var _log_file: FileAccess = null`
- **Methods**:
  - `_ready()`: Print initialization info
  - `_process(delta)`: Increment frame counter
  - `_exit_tree()`: Close log file
  - `msg(category, level, message)`: **CORE LOGGING METHOD** (all others route through this)
  - `_should_log(category, level) → bool`: Fast path check (level + category filter)
  - Convenience methods:
    - `input(message)`, `input_trace(message)`
    - `state(message)`, `state_info(message)`
    - `movement(message)`, `movement_info(message)`
    - `action(message)`
    - `turn(message)`
    - `grid(message)`
    - `camera(message)`
    - `warn(category, message)`, `error(category, message)`, `trace(category, message)`
    - `system(message)` (always logged unless global_level=ERROR+)
  - `_format_message(...) → String`: Build formatted log string
  - `_get_active_categories() → String`: List active categories
  - `_open_log_file()`: Open file for logging (future feature)
  - `set_global_level(level)`: Runtime level change
  - `enable_category(category, enabled)`: Runtime category toggle
  - `enable_all_categories()`, `disable_all_categories()`: Bulk toggles
- **Dependencies**: None
- **Used By**: ALL systems (Log.system, Log.state, Log.movement, etc.)
- **Issues**: None - comprehensive logging system
- **Status**: Active - core debugging infrastructure

#### `scripts/autoload/logger_presets.gd`
- **Class**: `class_name LoggerPresets` (static utility class)
- **Purpose**: Pre-configured logging profiles for common scenarios
- **Static Methods**:
  - `apply_development()`: Normal verbosity (STATE, MOVEMENT, ACTION, TURN, ENTITY, ABILITY, SYSTEM)
  - `apply_deep_debug()`: TRACE level, all categories, timestamps + frame count
  - `apply_release()`: WARN+ only, SYSTEM only
  - `apply_silent()`: NONE (performance testing)
  - `apply_input_debug()`: TRACE level, INPUT + SYSTEM only
  - `apply_state_debug()`: TRACE level, STATE + ACTION + TURN + SYSTEM
- **Dependencies**: Log (logger autoload)
- **Used By**: game.gd (_ready)
- **Status**: Active - logging presets

---

### 🗺️ Procedural Generation System (Chunk-Based)

#### `scripts/procedural/chunk_manager.gd`
- **Class**: `extends Node` (Autoload singleton as "ChunkManager")
- **Purpose**: Manages chunk loading, unloading, corruption escalation
- **Signals**:
  - `chunk_updates_completed()` (for PostTurnState to unblock input)
- **Constants**:
  - `CHUNK_SIZE := 128` (tiles per chunk)
  - `ACTIVE_RADIUS := 3` (chunks to keep loaded)
  - `GENERATION_RADIUS := 3` (chunks to pre-generate, 7×7 grid)
  - `UNLOAD_RADIUS := 5` (hysteresis buffer)
  - `MAX_LOADED_CHUNKS := 64` (memory limit)
  - `CHUNK_BUDGET_MS := 4.0` (max ms per frame)
  - `MAX_CHUNKS_PER_FRAME := 3` (hard limit)
- **Instance Vars**:
  - `var loaded_chunks: Dictionary` (Vector3i → Chunk)
  - `var generating_chunks: Array[Vector3i]` (queued for generation)
  - `var world_seed: int`
  - `var visited_chunks: Dictionary` (Vector3i → bool)
  - `var last_player_chunk: Vector3i`
  - `var hit_chunk_limit: bool`
  - `var was_generating: bool`
  - `var initial_load_complete: bool`
  - `var corruption_tracker: CorruptionTracker`
  - `var level_generators: Dictionary` (level_id → LevelGenerator)
  - `var grid_3d: Grid3D` (cached reference)
  - `var generation_thread: ChunkGenerationThread` (worker thread for async generation)
- **Methods**:
  - `_ready()`: Initialize corruption tracker, level generators, find Grid3D, connect to player, start generation thread
  - `_process(delta)`: Process completed chunks from thread, queue next batch
  - `_connect_to_player_signal()`: Connect to player.turn_completed (deferred)
  - `on_turn_completed()`: **MAIN UPDATE LOOP**
    - Check player chunk change
    - Update chunks around player
    - Unload distant chunks
    - Emit chunk_updates_completed if nothing queued
  - `_update_chunks_around_player()`: Queue chunks for loading (distance-sorted)
  - `_check_player_chunk_change()`: Increase corruption when entering new chunk
  - `_process_generation_queue()`: Process completed chunks from thread, queue next batch
  - `_generate_chunk(chunk_key)`: Queue chunk for generation on worker thread
  - `_unload_distant_chunks()`: Unload chunks beyond UNLOAD_RADIUS (LRU)
  - `_get_player_position() → Vector2i`: Get player grid position
  - `_get_player_level() → int`: Get current level (always 0 for now)
  - `_find_grid_3d()`: Search scene tree for Grid3D reference
  - `tile_to_chunk(tile_pos) → Vector2i`: Convert tile to chunk coordinates
  - `get_chunk(chunk_key) → Chunk`: Get loaded chunk or null
  - `is_chunk_loaded(chunk_key) → bool`: Check if chunk exists
  - `get_loaded_chunk_count() → int`: Count loaded chunks
  - Various debug/stats methods
- **Dependencies**:
  - Chunk, SubChunk (chunk data structures)
  - LevelGenerator, Level0Generator (maze generation)
  - ChunkGenerationThread (async chunk generation)
  - CorruptionTracker (corruption per level)
  - Grid3D (load_chunk, unload_chunk)
  - Player3D (turn_completed signal)
- **Features**:
  - Uses ChunkGenerationThread for async chunk generation
  - Receives completed chunks via signal + call_deferred
- **Performance**:
  - Generation: 0ms main thread (runs on worker)
- **Used By**:
  - PostTurnState (chunk_updates_completed signal)
  - Grid3D (provides chunks)
- **Issues**: None - proper distance-sorted priority queue, frame budget limiting, threaded generation
- **Status**: Active - core chunk streaming system with threading

#### `scripts/procedural/chunk_generation_thread.gd`
- **Created**: 2025-11-17 (commit e586ec0)
- **Class**: `class_name ChunkGenerationThread extends RefCounted`
- **Purpose**: Worker thread for asynchronous chunk generation
- **Key Features**:
  - Runs Level0Generator.generate_chunk() on background thread
  - Thread-safe request/completion queues with Mutex + Semaphore
  - Signal emission when chunks complete
  - Clean shutdown in _exit_tree()
- **Instance Vars**:
  - `var level_generator: LevelGenerator` (generator reference)
  - `var thread: Thread` (worker thread instance)
  - `var request_queue: Array` (queued generation requests)
  - `var completion_queue: Array` (completed chunks)
  - `var request_mutex: Mutex` (thread-safe queue access)
  - `var completion_semaphore: Semaphore` (signal when chunk ready)
  - `var should_stop: bool` (shutdown flag)
- **Signals**:
  - `chunk_completed(chunk, pos, level_id)`: Emitted when chunk generation finishes
- **Methods**:
  - `_init(level_generator)`: Initialize with generator reference
  - `start()`: Start worker thread
  - `stop()`: Stop and cleanup thread
  - `queue_chunk_generation(pos, level_id, seed)`: Queue chunk for generation
  - `process_completed_chunks()`: Emit signals for completed chunks (main thread)
  - `_thread_function()`: Worker thread main loop
  - `_wait_for_shutdown()`: Cleanup during _exit_tree()
- **Dependencies**:
  - Chunk (data structure)
  - LevelGenerator (interface)
  - Log (for system messages, thread-safe)
- **Performance**:
  - Eliminates 28ms frame hitches by moving generation off main thread
  - Main thread only does queue polling and signal emission
- **Used By**: ChunkManager (async chunk generation)
- **Issues**: None - proper mutex locking, clean thread lifecycle
- **Status**: Active - asynchronous chunk generation worker

#### `scripts/procedural/chunk.gd`
- **Class**: `class_name Chunk extends RefCounted`
- **Purpose**: Data structure for 128×128 tile chunk
- **Constants**:
  - `SIZE := 128` (tiles per side)
  - `SUB_CHUNKS_PER_SIDE := 8` (8×8 sub-chunks)
- **Instance Vars**:
  - `var position: Vector2i` (chunk coordinates)
  - `var sub_chunks: Array[SubChunk]` (64 sub-chunks, 16×16 each)
  - `var island_id: int` (which maze island)
  - `var level_id: int` (which Backrooms level)
  - `var corruption_level: float` (reality stability)
- **Methods**:
  - `_init(pos, level)`: Initialize chunk with empty sub-chunks
  - `get_sub_chunk(local_pos) → SubChunk`: Get sub-chunk at position
  - `set_sub_chunk(local_pos, sub_chunk)`: Set sub-chunk
  - `get_tile(tile_pos) → int`: Get tile type at absolute tile position
  - `set_tile(tile_pos, tile_type)`: Set tile type
  - `is_fully_generated() → bool`: Check if all sub-chunks generated
- **Dependencies**: SubChunk
- **Used By**:
  - ChunkManager (create, store, query chunks)
  - LevelGenerator (populate chunks)
  - Grid3D (load_chunk)
- **Status**: Active - chunk data structure

#### `scripts/procedural/sub_chunk.gd`
- **Class**: `class_name SubChunk extends RefCounted`
- **Purpose**: 16×16 tile sub-chunk (building block of chunks)
- **Constants**:
  - `SIZE := 16` (tiles per side)
- **Enums**:
  - `TileType`: FLOOR=0, WALL=1, CEILING=2, EXIT_STAIRS=3
- **Instance Vars**:
  - `var tiles: Array[Array]` (16×16 2D array, layer 0 = floor/walls)
  - `var ceiling_tiles: Array[Array]` (16×16 2D array, layer 1 = ceilings)
  - `var is_generated: bool`
- **Methods**:
  - `_init()`: Initialize empty arrays
  - `get_tile(pos) → int`: Get tile at position
  - `set_tile(pos, tile_type)`: Set tile at position
  - `get_tile_at_layer(pos, layer) → int`: Get tile at specific layer
  - `set_tile_at_layer(pos, layer, tile_type)`: Set tile at layer
  - `fill(tile_type)`: Fill all tiles with type
  - `get_neighbor(pos, direction) → int`: Get neighboring tile
- **Dependencies**: None
- **Used By**:
  - Chunk (storage)
  - LevelGenerator (populate sub-chunks)
  - Grid3D (load_chunk reads sub-chunk tiles)
- **Status**: Active - sub-chunk data structure

#### `scripts/procedural/level_generator.gd`
- **Class**: `class_name LevelGenerator extends RefCounted`
- **Purpose**: Base class for level-specific generators
- **Instance Vars**:
  - `var level_id: int`
  - `var level_name: String`
- **Methods**:
  - `generate_chunk(chunk, world_seed)`: Override in subclasses
  - `get_corruption_per_chunk() → float`: Default 0.01
  - `should_spawn_entity(corruption) → bool`: Override in subclasses
- **Dependencies**: Chunk
- **Used By**: Level0Generator (subclass)
- **Status**: Active - base generator class

#### `scripts/procedural/level_0_generator.gd`
- **Class**: `class_name Level0Generator extends LevelGenerator`
- **Purpose**: Wave Function Collapse (WFC) maze generator for Level 0
- **Constants**:
  - `TILE_FLOOR := 0`, `TILE_WALL := 1`, `TILE_CEILING := 2`
  - `MAX_ITERATIONS := 10000` (WFC iteration limit)
- **Enums**:
  - `Direction`: NORTH, SOUTH, EAST, WEST
- **Instance Vars**:
  - `var rng: RandomNumberGenerator`
  - `var adjacency_rules: Dictionary` (WFC adjacency constraints)
- **Methods**:
  - `_init()`: Set level_id=0, level_name="Level 0"
  - `generate_chunk(chunk, world_seed)`: **MAIN GENERATION**
    - Seed RNG
    - Generate all sub-chunks with WFC
    - Place ceilings on layer 1
    - Use direct sub-chunk access for optimal performance
  - `_generate_sub_chunk_wfc(sub_chunk)`: Wave Function Collapse algorithm
    - Initialize superposition (all tiles have both floor+wall possibilities)
    - While uncollapsed tiles exist:
      - Pick tile with minimum entropy (fewest possibilities)
      - Collapse to random valid state
      - Propagate constraints to neighbors
    - Returns true if successful, false if contradiction
  - `_initialize_superposition(sub_chunk) → Array`: Create 16×16 array of possible states
  - `_find_min_entropy_tile(superposition) → Vector2i`: Find tile with fewest options
  - `_collapse_tile(superposition, pos, sub_chunk)`: Choose random tile type
  - `_propagate_constraints(superposition, start_pos, sub_chunk)`: Update neighbors
  - `_get_valid_neighbors(tile_type, direction) → Array`: Get allowed adjacent tiles
  - `_constrain_tile(superposition, pos, allowed_types)`: Remove invalid possibilities
  - `_is_fully_collapsed(superposition) → bool`: Check if all tiles decided
  - `_apply_grid_to_chunk(chunk)`: Optimized direct sub-chunk access (3.6x speedup)
  - `get_corruption_per_chunk() → float`: Returns 0.005 (slower corruption for Level 0)
  - `should_spawn_entity(corruption) → bool`: Returns false (no entities yet)
- **Dependencies**:
  - Chunk, SubChunk (data structures)
  - RandomNumberGenerator (seeded RNG)
- **Performance**:
  - Generation: 19-30ms (was 48-56ms before optimization)
  - Optimized _apply_grid_to_chunk() with direct sub-chunk access (3.6x speedup)
- **Used By**: ChunkManager (level_generators[0]), ChunkGenerationThread (threaded generation)
- **Issues**: None - clean WFC implementation with optimizations
- **Status**: Active - Level 0 maze generation

#### `scripts/procedural/corruption_tracker.gd`
- **Class**: `class_name CorruptionTracker extends RefCounted`
- **Purpose**: Track reality corruption per level (affects entity spawns, visuals)
- **Instance Vars**:
  - `var corruption_per_level: Dictionary` (level_id → float)
- **Methods**:
  - `_init()`: Initialize empty dictionary
  - `get_corruption(level_id) → float`: Get corruption (default 0.0)
  - `increase_corruption(level_id, amount, cap)`: Increase corruption (with optional cap)
  - `set_corruption(level_id, value)`: Set corruption directly
  - `reset_corruption(level_id)`: Reset to 0.0
  - `get_all_corruption() → Dictionary`: Get all levels
- **Dependencies**: None
- **Used By**: ChunkManager (track corruption as player explores)
- **Status**: Active - corruption tracking

#### `scripts/procedural/entity_config.gd`
- **Class**: `class_name EntityConfig extends RefCounted`
- **Purpose**: Configuration for entity spawning in chunks
- **Instance Vars**:
  - `var entity_id: String`
  - `var spawn_weight: float`
  - `var min_corruption: float`
  - `var max_corruption: float`
  - `var min_distance_from_player: int`
  - `var max_per_chunk: int`
- **Methods**: None (data class)
- **Dependencies**: None
- **Used By**: LevelConfig (entity_configs)
- **Issues**: ⚠️ **NOT YET USED** - entity spawning not implemented
- **Status**: Planned - entity spawn configuration

---

### 🎯 Level System (Config-Based)

#### `scripts/resources/level_config.gd`
- **Class**: `class_name LevelConfig extends Resource`
- **Purpose**: Per-level configuration (appearance, generation, entities)
- **Exports**:
  - `@export var level_id: int = 0`
  - `@export var display_name: String = "Level 0"`
  - `@export var grid_size: Vector2i = Vector2i(128, 128)`
  - `@export var background_color: Color = Color(0.65, 0.60, 0.55)` (greyish-beige)
  - `@export var directional_light_color: Color = Color(0.95, 0.95, 1.0)` (slight blue tint)
  - `@export var directional_light_energy: float = 0.9`
  - `@export var directional_light_rotation: Vector3 = Vector3(0, 0, 80)` (overhead)
  - `@export var mesh_library_path: String = "res://assets/grid_mesh_library.tres"`
  - `@export var floor_material: Material = null` (future)
  - `@export var wall_material: Material = null` (future)
  - `@export var ceiling_material: Material = null` (future)
  - `@export var entity_configs: Array[EntityConfig] = []` (future)
  - `@export var exit_destinations: Array[int] = []` (connected levels)
- **Methods**:
  - `validate() → bool`: Check required fields
  - `on_load()`: Lifecycle hook (called when loaded)
  - `on_enter()`: Lifecycle hook (called when entered)
  - `on_exit()`: Lifecycle hook (called when exited)
  - `on_unload()`: Lifecycle hook (called when unloaded from cache)
  - `on_generation_complete()`: Lifecycle hook (called after grid generated)
- **Dependencies**: EntityConfig (spawn configuration)
- **Used By**:
  - Level0Config (subclass)
  - LevelManager (load_level, caching)
  - Grid3D (configure_from_level, _apply_level_visuals)
- **Status**: Active - level configuration base class

#### `scripts/resources/level_00_config.gd`
- **Class**: `class_name Level0Config extends LevelConfig`
- **Purpose**: Level 0 specific configuration (overrides defaults)
- **Methods**:
  - `_init()`: Override default values (display_name, lighting, etc.)
- **Dependencies**: LevelConfig (parent)
- **Used By**: LevelManager (registered as level 0)
- **Status**: Active - Level 0 config

#### `assets/levels/level_00/level_00_config.tres`
- **Resource Type**: Level0Config
- **Purpose**: Level 0 runtime configuration resource
- **Used By**: LevelManager.load_level(0)
- **Status**: Active - Level 0 config resource

#### `scripts/autoload/level_manager.gd`
- **Class**: `extends Node` (Autoload singleton as "LevelManager")
- **Purpose**: Manages level loading, LRU cache, transitions
- **Signals**:
  - `level_load_started(level_id: int)`
  - `level_loaded(level_config: LevelConfig)`
  - `level_transition_started(from_level, to_level)`
  - `level_transition_completed(to_level)`
  - `level_unloaded(level_id: int)`
- **Constants**:
  - `MAX_CACHED_LEVELS := 3` (LRU cache size)
  - `LEVEL_CONFIG_DIR := "res://assets/levels/"`
  - `LEVEL_CONFIG_PATTERN := "level_%02d/level_%02d_config.tres"`
- **Instance Vars**:
  - `var _current_level: LevelConfig`
  - `var _level_cache: Dictionary` (level_id → LevelConfig)
  - `var _lru_order: Array[int]` (most recent last)
  - `var _preloaded_levels: Dictionary`
  - `var _level_registry: Dictionary` (level_id → resource_path)
- **Methods**:
  - `_ready()`: Build level registry by scanning filesystem
  - `_build_level_registry()`: Scan assets/levels/ for level_XX folders
  - `load_level(level_id) → LevelConfig`: Load from cache/preload/disk
  - `_load_level_from_disk(level_id) → LevelConfig`: Load resource, validate
  - `transition_to_level(target_level_id)`: Exit current, enter new, preload exits
  - `get_current_level() → LevelConfig`: Get active level
  - `is_level_cached(level_id) → bool`, `is_level_preloaded(level_id) → bool`
  - `preload_level(level_id)`: Async preload for fast transitions
  - `_preload_exit_destinations(config)`: Preload connected levels
  - `_add_to_cache(level_id, config)`: Add to LRU cache (evict if full)
  - `_touch_lru(level_id)`: Mark as recently used
  - `_evict_lru()`: Remove least recently used level
  - `clear_cache()`: Clear all cached levels
  - `hot_reload_current()`: Development hot-reload
  - `get_cache_stats() → Dictionary`, `print_cache_stats()`: Debugging
- **Dependencies**: LevelConfig (level resources)
- **Used By**:
  - game_3d.gd (load_level, transition_to_level)
  - Grid3D (current_level)
- **Status**: Active - level management system

---

### 🔍 Examination System

#### `scripts/components/examinable.gd`
- **Class**: `class_name Examinable extends Area3D`
- **Purpose**: Component for examinable objects (entities + environment tiles)
- **Exports**:
  - `@export var entity_id: String = ""` (references EntityRegistry)
- **Instance Vars**: None (data component)
- **Methods**: None (pure data)
- **Dependencies**: None
- **Used By**:
  - ExaminableEnvironmentTile (attached component)
  - FirstPersonCamera (get_current_target returns Examinable)
  - LookModeState (examine entities)
- **Issues**: None - simple component
- **Status**: Active - examination component

#### `scripts/environment/examinable_environment_tile.gd`
- **Class**: `class_name ExaminableEnvironmentTile extends StaticBody3D`
- **Purpose**: On-demand examination tile for floor/wall/ceiling
- **Instance Vars**:
  - `var tile_type: String` (floor/wall/ceiling)
  - `var grid_position: Vector2`
  - `@onready var examinable: Examinable`
- **Methods**:
  - `_ready()`: Get examinable component reference
  - `setup(type, entity_id, grid_pos, world_pos)`: Configure tile
    - Set tile_type, grid_position, global_position
    - Set examinable.entity_id
    - Set collision layer 4 (examination overlay)
- **Dependencies**: Examinable (child component)
- **Used By**: FirstPersonCamera (_create_examination_tile)
- **Issues**: None - clean on-demand tile
- **Status**: Active - examination tile

#### `scenes/environment/examinable_environment_tile.tscn`
- **Scene Structure**: StaticBody3D → (Examinable, CollisionShape3D)
- **Script**: `scripts/environment/examinable_environment_tile.gd`
- **Collision Layer**: 4 (examination overlay)
- **Used By**: FirstPersonCamera (preload + instantiate)
- **Status**: Active - examination tile scene

#### `scripts/environment/examination_world_generator.gd`
- **Class**: `class_name ExaminationWorldGenerator extends Node`
- **Purpose**: **DEAD CODE** - was for pre-generating examination overlay
- **Git History**:
  - Created: 7917dbc (PR #1 - examination overlay system)
  - **REMOVED**: e7dbcac (Remove chunk examination overlay system)
- **Status**: 💀 **DEAD CODE** - file still exists but unused

#### `scripts/ui/examination_ui.gd`
- **Class**: `class_name ExaminationUI extends Control`
- **Purpose**: **LEGACY** - old monolithic examination UI (before split)
- **Git History**:
  - Created: Phase 1 examination system
  - **REPLACED**: 275338a (Split into ExaminationCrosshair + ExaminationPanel)
- **Status**: ⚠️ **POTENTIALLY DEAD** - check if still referenced

#### `scripts/ui/examination_crosshair.gd`
- **Class**: `class_name ExaminationCrosshair extends Control`
- **Purpose**: Center crosshair for examination mode (in viewport, can have VHS effects)
- **Instance Vars**:
  - `@onready var crosshair: Control`
- **Methods**:
  - `_ready()`: Hide by default
  - `show_crosshair()`: Make visible
  - `hide_crosshair()`: Make invisible
- **Dependencies**: None
- **Used By**: LookModeState (show/hide crosshair)
- **Status**: Active - examination crosshair

#### `scripts/ui/examination_panel.gd`
- **Class**: `class_name ExaminationPanel extends Control`
- **Purpose**: Text panel for examination descriptions (in main viewport, clean text)
- **Instance Vars**:
  - `@onready var entity_name_label: Label`
  - `@onready var entity_description_label: RichTextLabel`
  - `@onready var object_class_label: Label`
  - `@onready var threat_level_label: Label`
- **Methods**:
  - `_ready()`: Hide by default
  - `show_panel(target: Examinable)`: Display entity info from KnowledgeDB
  - `hide_panel()`: Make invisible
- **Dependencies**:
  - Examinable (entity_id)
  - KnowledgeDB (get_entity_info)
- **Used By**: LookModeState (show/hide panel)
- **Status**: Active - examination panel

---

### 💾 Knowledge System (Autoload)

#### `scripts/autoload/knowledge_db.gd`
- **Class**: `extends Node` (Autoload singleton as "KnowledgeDB")
- **Purpose**: Track player knowledge and discoveries
- **Instance Vars**:
  - `var discovered_entities: Dictionary` (entity_id → discovery_level 0-3)
  - `var clearance_level: int = 0` (0-5 scale)
  - `var researcher_classification: int = 0` (total research score)
- **Methods**:
  - `_ready()`: Log initialization
  - `examine_entity(entity_id)`: Increase discovery level (max 3), increment research score
  - `get_discovery_level(entity_id) → int`: Get current discovery (0-3)
  - `get_entity_info(entity_id) → Dictionary`: Query EntityRegistry with discovery + clearance
  - `set_clearance_level(level)`: Set clearance (0-5)
  - `increase_clearance()`: Increment clearance (max 5)
  - `reset_knowledge()`: Clear all knowledge
  - `get_stats() → Dictionary`, `print_stats()`: Debugging
- **Dependencies**: EntityRegistry (get_info)
- **Used By**:
  - LookModeState (examine_entity)
  - ExaminationPanel (get_entity_info)
  - FirstPersonCamera (examine_entity)
- **Status**: Active - knowledge tracking

#### `scripts/autoload/entity_registry.gd`
- **Class**: `extends Node` (Autoload singleton as "EntityRegistry")
- **Purpose**: Registry of entity definitions with progressive revelation
- **Instance Vars**:
  - `var _entities: Dictionary` (entity_id → EntityInfo)
- **Methods**:
  - `_ready()`: Load entities
  - `_load_entities()`: **HARDCODED PLACEHOLDERS**
    - "unknown_entity" (generic placeholder)
    - "level_0_wall" (yellow wallpaper)
    - "level_0_floor" (brown carpet)
    - "level_0_ceiling" (acoustic tiles)
  - `get_info(entity_id, discovery_level, clearance) → Dictionary`: Progressive revelation
  - `has_entity(entity_id) → bool`
  - `get_all_entity_ids() → Array[String]`
  - `register_entity(entity: EntityInfo)`: Runtime additions
  - `_get_unknown_entity_info() → Dictionary`: Fallback
  - `print_registry()`: Debugging
- **Dependencies**: EntityInfo (entity data resource)
- **Used By**: KnowledgeDB (get_info)
- **Issues**: ⚠️ **HARDCODED DATA** - should load from JSON/resources
- **Status**: Active but needs data system

#### `scripts/resources/entity_info.gd`
- **Class**: `class_name EntityInfo extends Resource`
- **Purpose**: Entity data with progressive revelation (SCP-style)
- **Exports**:
  - `@export var entity_id: String = ""`
  - `@export var name_levels: Array[String] = []` (4 levels: redacted → full name)
  - `@export var description_levels: Array[String] = []` (4 levels)
  - `@export var clearance_required: Array[int] = []` (per level)
  - `@export var object_class_levels: Array[String] = []` (4 levels)
  - `@export var threat_level: int = 0` (0-10 scale)
- **Methods**:
  - `get_info(discovery_level, clearance) → Dictionary`: Return name, description, class based on discovery + clearance
- **Dependencies**: None
- **Used By**: EntityRegistry (store entity data)
- **Status**: Active - entity data resource

---

### 🎬 Action System (Command Pattern)

#### `scripts/actions/action.gd`
- **Class**: `class_name Action extends RefCounted`
- **Purpose**: Base class for all player actions
- **Methods**:
  - `can_execute(player) → bool`: Override in subclasses
  - `execute(player)`: Override in subclasses
  - `get_description() → String`: Override for action preview
- **Dependencies**: None
- **Used By**: MovementAction, WaitAction
- **Status**: Active - base action class

#### `scripts/actions/movement_action.gd`
- **Class**: `class_name MovementAction extends Action`
- **Purpose**: Grid movement with validation
- **Instance Vars**:
  - `var direction: Vector2i`
- **Methods**:
  - `_init(dir)`: Store direction
  - `can_execute(player) → bool`: Check if target is walkable
  - `execute(player)`:
    - Move player.grid_position
    - Increment turn_count
    - Update visual position (SNAP, no lerp)
  - `get_description() → String`: "Move [direction]"
- **Dependencies**: Player3D (grid_position, turn_count, grid.is_walkable)
- **Used By**:
  - IdleState (_move_forward, _update_action_preview)
  - ExecutingTurnState (_execute_turn)
- **Status**: Active - movement action

#### `scripts/actions/wait_action.gd`
- **Class**: `class_name WaitAction extends Action`
- **Purpose**: Pass turn without moving
- **Methods**:
  - `can_execute(player) → bool`: Always true
  - `execute(player)`: Increment turn_count only
  - `get_description() → String`: "Wait (pass turn)"
- **Dependencies**: Player3D (turn_count)
- **Used By**:
  - LookModeState (_execute_wait_action, _update_action_preview)
- **Status**: Active - wait action

---

### 🎨 UI System

#### `scripts/ui/action_preview_ui.gd`
- **Class**: `class_name ActionPreviewUI extends Control`
- **Purpose**: Show next turn actions and turn counter
- **Instance Vars**:
  - `@onready var turn_counter_label: Label`
  - `@onready var action_description_label: Label`
- **Methods**:
  - `_ready()`: Connect to player's action_preview_changed signal
  - `_on_action_preview_changed(actions: Array[Action])`: Update UI
    - Format action descriptions
    - Show turn counter
- **Dependencies**:
  - Player3D (action_preview_changed signal, turn_count)
  - Action (get_description)
- **Used By**: game.gd (connected to player)
- **Status**: Active - action preview UI

---

### 🐍 Python Tooling

#### `_claude_scripts/strip_mesh_library_previews.py`
- **Purpose**: Strip preview images from grid_mesh_library.tres (reduce from 99KB to 3KB)
- **Why**: Claude's Read tool can't handle ~30,000+ tokens, preview images bloat the file
- **Usage**: Run before asking Claude to edit grid_mesh_library.tres
- **Status**: Active - maintenance tool

#### `_claude_scripts/textures/*/generate.py`
- **Purpose**: Procedural texture generation (PIL/NumPy)
- **Textures**:
  - `backrooms_wallpaper/generate.py` (yellow chevron wallpaper, 7 iterations to get tiling right)
  - `backrooms_carpet/generate.py` (brown loop pile carpet)
  - `backrooms_ceiling/generate.py` (acoustic tile ceiling)
  - `hazmat_suit/generate.py` (player character sprite)
- **Status**: Active - generative art tooling

#### `venv/` (Python virtual environment)
- **Purpose**: Isolated Python environment for maintenance scripts
- **Packages**: PIL, NumPy, etc.
- **Status**: Active (gitignored)

---

## System Flows & Architecture Diagrams

### 🔍 On-Demand Examination System

**Purpose**: Create examination tiles lazily only when player looks at them, instead of pre-generating entire overlay

**Flow**:
```
Player presses LT/RMB (look mode)
    ↓
LookModeState.enter()
    ↓
FirstPersonCamera.activate()
    ↓
Creates "OnDemandExaminationWorld" container (if needed)
    ↓
Every frame in LookModeState:
    ↓
FirstPersonCamera.get_current_target()
    ├─→ Raycast Layer 4 (existing examination tiles)
    │   └─→ Hit? Return existing Examinable
    │
    └─→ No hit? Calculate ray-plane intersection
        ├─→ Determine tile type from camera pitch:
        │   ├─→ pitch < -10° → floor (looking down)
        │   ├─→ pitch > 10° → ceiling (looking up)
        │   └─→ -10° ≤ pitch ≤ 10° → wall (horizontal)
        │
        ├─→ Intersect with appropriate plane:
        │   ├─→ Floor: Y=0 plane intersection
        │   ├─→ Ceiling: Y=2.98 plane intersection
        │   └─→ Wall: Grid traversal along ray
        │
        ├─→ Get grid position from intersection
        ├─→ Verify tile exists in GridMap
        ├─→ Check cache: examination_tile_cache[grid_x, grid_y, type]
        │   └─→ Found? Return cached tile
        │
        └─→ Not cached? Create new tile
            ├─→ LRU eviction if cache >= 20 tiles
            ├─→ Load ExaminableEnvironmentTile scene
            ├─→ Setup(tile_type, entity_id, grid_pos, world_pos)
            ├─→ Add to examination_world container
            ├─→ Set collision layer 4
            ├─→ Cache in examination_tile_cache[grid_x, grid_y, type]
            └─→ Return Examinable component
```

**Key Classes**:
- `FirstPersonCamera` ([scripts/player/first_person_camera.gd:161-226](scripts/player/first_person_camera.gd:161-226))
  - `get_current_target() → Examinable`: Main entry point for on-demand creation
  - `_create_examination_tile(...)`: Factory method for new tiles
  - `examination_tile_cache: Dictionary`: LRU cache (max 20 tiles)
  - `examination_world: Node3D`: Container for all cached tiles

- `ExaminableEnvironmentTile` ([scripts/environment/examinable_environment_tile.gd:1](scripts/environment/examinable_environment_tile.gd:1))
  - `setup(type, entity_id, grid_pos, world_pos)`: Configure tile
  - Collision layer 4 (examination overlay only)

**Benefits**:
- **Memory Efficient**: Only creates tiles player actually looks at (~20 max vs thousands)
- **Performance**: No pre-generation overhead, instant examination mode activation
- **Clean Separation**: Examination overlay (layer 4) separate from GridMap (layer 2)

**Cache Eviction**:
- LRU policy: Oldest tile removed when cache hits 20
- Full cache clear on examination mode exit (deactivate)

---

### 🌍 Chunk Generation Flow

**Purpose**: Stream infinite procedural world with frame budget limiting

**High-Level Flow**:
```
Player completes turn
    ↓
Player3D emits turn_completed signal
    ↓
ChunkManager.on_turn_completed()
    ├─→ Check if player entered new chunk
    │   └─→ Yes? Increase corruption (0.01 per chunk)
    │
    ├─→ Calculate chunks within GENERATION_RADIUS (3 = 7×7 grid)
    ├─→ Filter: only queue unloaded chunks
    ├─→ Sort by distance (nearest first)
    └─→ Add to generating_chunks queue (Array[Vector3i])
        ↓
    Emit chunk_updates_completed if queue empty
    (PostTurnState waits for this signal)
```

**Generation Loop** (runs in `_process`, spread over frames):
```
ChunkManager._process_generation_queue()
    ↓
Frame budget: 4ms, max 3 chunks/frame
    ↓
For each chunk in queue (while budget remaining):
    ├─→ Pop chunk_key from generating_chunks
    ├─→ ChunkManager._generate_chunk(chunk_pos, level_id)
    │   ├─→ Create Chunk instance
    │   ├─→ chunk.state = GENERATING
    │   ├─→ Get LevelGenerator for level_id
    │   │   (Level 0 → Level0Generator)
    │   ├─→ generator.generate_chunk(chunk, world_seed)
    │   │   ↓
    │   │   Level0Generator.generate_chunk()
    │   │   ├─→ Seed RNG (world_seed + chunk position hash)
    │   │   ├─→ For each of 64 sub-chunks (8×8):
    │   │   │   └─→ _generate_sub_chunk_wfc(sub_chunk)
    │   │   │       ↓
    │   │   │       **Wave Function Collapse Algorithm**:
    │   │   │       1. Initialize superposition (all tiles = {FLOOR, WALL})
    │   │   │       2. While uncollapsed tiles exist:
    │   │   │          ├─→ Find tile with minimum entropy (fewest options)
    │   │   │          ├─→ Collapse to FLOOR (70%) or WALL (30%)
    │   │   │          └─→ Propagate constraints to neighbors
    │   │   │       3. Place ceilings on layer 1
    │   │   │
    │   │   └─→ Returns generated chunk
    │   │
    │   ├─→ chunk.state = LOADED
    │   └─→ Add to loaded_chunks[chunk_key]
    │
    ├─→ Grid3D.load_chunk(chunk)
    │   └─→ Iterate sub-chunks, call GridMap.set_cell_item()
    │
    └─→ Check frame budget, continue if time remaining
        ↓
When generating_chunks empty:
    └─→ Emit chunk_updates_completed
        └─→ PostTurnState receives signal
            └─→ Transition to IdleState (unblock input)
```

**World-Space Seeding** (guarantees chunk connectivity):
```gdscript
# From Level0Generator:
var chunk_seed := world_seed
chunk_seed = hash(chunk_seed + chunk.position.x * 73856093)
chunk_seed = hash(chunk_seed + chunk.position.y * 19349663)
rng.seed = chunk_seed
```
- Same chunk position + world seed → Same maze layout
- Ensures adjacent chunks have compatible edges

**Key Constants**:
- `CHUNK_SIZE = 128` tiles (128×128 per chunk)
- `GENERATION_RADIUS = 3` chunks (7×7 grid around player)
- `CHUNK_BUDGET_MS = 4.0` ms per frame
- `MAX_CHUNKS_PER_FRAME = 3` hard limit
- `MAX_LOADED_CHUNKS = 64` memory cap

**WFC Parameters**:
- `FLOOR_WEIGHT = 0.70` → ~70% floor tiles
- `WALL_WEIGHT = 0.30` → ~30% wall tiles
- `MAX_ITERATIONS = 10000` safety limit

---

### 🎮 State Machine Lifecycle

**Purpose**: Turn-based input blocking during world updates

**Full Turn Cycle**:
```
═══════════════════════════════════════════════════════════
STATE 1: IdleState (waiting for player input)
═══════════════════════════════════════════════════════════
    ├─→ Show move indicator (green arrow 1 cell ahead)
    ├─→ Handle RT/Space/Click: create MovementAction
    ├─→ Handle LT/RMB: transition to LookModeState
    └─→ On move confirm:
        ├─→ player.pending_action = MovementAction
        └─→ Transition to ExecutingTurnState

───────────────────────────────────────────────────────────

═══════════════════════════════════════════════════════════
STATE 2: ExecutingTurnState (process player action)
═══════════════════════════════════════════════════════════
    ├─→ BLOCKS ALL INPUT (handle_input does nothing)
    ├─→ Execute player.pending_action
    │   ├─→ MovementAction.execute(player)
    │   │   ├─→ Update player.grid_position
    │   │   ├─→ Increment player.turn_count
    │   │   └─→ Update visual position (SNAP, no lerp)
    │   └─→ Clear player.pending_action = null
    ├─→ Emit player.turn_completed signal
    │   └─→ ChunkManager receives signal
    │       ├─→ Check for new chunk entry (corruption++)
    │       ├─→ Queue chunks for generation
    │       └─→ (Generation happens in background)
    └─→ Transition to PostTurnState

───────────────────────────────────────────────────────────

═══════════════════════════════════════════════════════════
STATE 3: PostTurnState (BLOCKING - wait for chunks)
═══════════════════════════════════════════════════════════
    ├─→ BLOCKS ALL INPUT (prevents input queuing)
    ├─→ Connect to ChunkManager.chunk_updates_completed
    │   (CONNECT_ONE_SHOT to avoid leaks)
    ├─→ Wait for signal... (~80ms for nearby chunks)
    │   └─→ ChunkManager processes generation queue
    │       ├─→ Frame budget: 4ms per frame
    │       ├─→ Generates 1-3 chunks per frame
    │       └─→ When queue empty: emit chunk_updates_completed
    └─→ On chunk_updates_completed:
        └─→ Transition to IdleState (INPUT UNBLOCKED)

───────────────────────────────────────────────────────────

═══════════════════════════════════════════════════════════
ALTERNATE PATH: LookModeState (examination)
═══════════════════════════════════════════════════════════
    ├─→ Entered from IdleState (LT/RMB pressed)
    ├─→ Switch to FirstPersonCamera
    ├─→ Every frame:
    │   ├─→ Update examination raycast
    │   └─→ Show/hide examination panel
    ├─→ Handle RT/Click: execute WaitAction
    │   ├─→ Increment turn_count (no movement)
    │   ├─→ Emit turn_completed
    │   └─→ STAY IN LookModeState (don't exit examination)
    └─→ On LT/RMB release:
        ├─→ Switch back to TacticalCamera
        └─→ Transition to IdleState
```

**Why PostTurnState Blocks Input**:
1. **Prevents Input Queuing**: Without blocking, rapid RT presses would queue multiple moves while chunks generate
2. **Frame Budget Spread**: Chunk generation takes ~80ms total, spread over multiple frames (4ms/frame)
3. **Clean Turn Boundaries**: Each turn completes fully before accepting next input
4. **Signal Cleanup**: CONNECT_ONE_SHOT ensures no leaked connections

**Timing Breakdown** (typical turn):
- ExecutingTurnState: <1ms (just update grid position)
- PostTurnState: 20-80ms (wait for chunk generation)
  - 1-3 chunks/frame × 4ms budget = ~20-80ms total
  - Most turns: 0 chunks (already loaded) = instant
  - New chunk entry: ~5-10 chunks queued = ~80ms

**Key Signal Flow**:
```
Player3D.turn_completed
    ├─→ ChunkManager.on_turn_completed() [queues chunks]
    └─→ (ChunkManager emits after generation)
        └─→ ChunkManager.chunk_updates_completed
            └─→ PostTurnState._on_chunk_updates_complete()
                └─→ Transition to IdleState
```

---

### 📐 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GAME ENTRY POINT                             │
│  scenes/game.tscn (Control node - HUD wrapper)                      │
│    ├─ LeftSide: SubViewport (PSX 640×480)                          │
│    │   └─→ game_3d.tscn (3D world)                                 │
│    └─ RightSide: Log Panel UI                                      │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────────┐
│                    3D WORLD (game_3d.tscn)                          │
│  ├─ Grid3D (GridMap + chunk streaming)                             │
│  ├─ Player3D (CharacterBody3D + state machine)                     │
│  ├─ TacticalCamera (third-person, right stick rotation)            │
│  ├─ FirstPersonCamera (examination mode, on-demand tiles)          │
│  ├─ MoveIndicator (green arrow, 1 cell ahead)                      │
│  └─ Lighting (DirectionalLight3D, WorldEnvironment)                │
└───────┬──────────────┬──────────────┬───────────────┬──────────────┘
        │              │              │               │
        ▼              ▼              ▼               ▼
  ┌─────────┐    ┌─────────┐   ┌──────────┐   ┌──────────────┐
  │ INPUT   │    │ STATE   │   │  ACTION  │   │  PROCEDURAL  │
  │ SYSTEM  │    │MACHINE  │   │  SYSTEM  │   │  GENERATION  │
  └─────────┘    └─────────┘   └──────────┘   └──────────────┘
```

**System Dependencies**:
```
Player3D
  ├─ depends on → InputStateMachine
  │   ├─ IdleState
  │   ├─ LookModeState
  │   ├─ ExecutingTurnState
  │   └─ PostTurnState
  │
  ├─ depends on → Grid3D
  │   ├─ grid_to_world()
  │   ├─ is_walkable()
  │   └─ configure_from_level()
  │
  ├─ emits → turn_completed signal
  │   └─→ ChunkManager.on_turn_completed()
  │       ├─ Queues chunk generation
  │       └─ Emits chunk_updates_completed
  │           └─→ PostTurnState (unblock input)
  │
  └─ depends on → Action system
      ├─ MovementAction
      └─ WaitAction

Grid3D
  ├─ depends on → LevelConfig (visuals, lighting)
  ├─ depends on → ChunkManager (load/unload chunks)
  └─ depends on → GridMap (Godot rendering)

ChunkManager
  ├─ depends on → LevelGenerator
  │   └─ Level0Generator (WFC algorithm)
  ├─ depends on → CorruptionTracker
  └─ emits → chunk_updates_completed

FirstPersonCamera
  ├─ depends on → KnowledgeDB (examine_entity)
  ├─ creates → ExaminableEnvironmentTile (on-demand)
  └─ depends on → Grid3D (world_to_grid, get_cell_item)
```

---

### 🔄 Data Flow: Single Turn Example

```
Frame N: Player in IdleState, RT pressed
  ↓
IdleState detects RT press
  ├─→ Creates MovementAction(forward_direction)
  ├─→ Sets player.pending_action = action
  └─→ Transitions to ExecutingTurnState
      ↓
Frame N+1: ExecutingTurnState.enter()
  ├─→ Executes player.pending_action
  │   ├─→ Updates player.grid_position (64, 64) → (64, 65)
  │   ├─→ Increments player.turn_count (17 → 18)
  │   └─→ Snaps visual position to new grid cell
  ├─→ Emits player.turn_completed signal
  │   └─→ ChunkManager.on_turn_completed()
  │       ├─→ Detects player still in same chunk (no corruption)
  │       ├─→ Checks GENERATION_RADIUS (3 chunks)
  │       │   └─→ All chunks already loaded (no queue)
  │       └─→ Immediately emits chunk_updates_completed
  └─→ Transitions to PostTurnState
      ↓
Frame N+2: PostTurnState.enter()
  ├─→ Connects to chunk_updates_completed (CONNECT_ONE_SHOT)
  └─→ Receives signal immediately (no chunks queued)
      └─→ Transitions to IdleState
          ↓
Frame N+3: IdleState.enter()
  ├─→ Shows move indicator
  └─→ INPUT UNBLOCKED - ready for next turn

Total latency: 3 frames (~50ms @ 60fps) when no chunks need generation
```

**With Chunk Generation** (player enters new chunk):
```
Frame N: Player moves to (128, 64) - NEW CHUNK!
  ↓
ChunkManager.on_turn_completed()
  ├─→ Detects new chunk entry
  ├─→ Increases corruption (0.00 → 0.01)
  ├─→ Queues 7 new chunks (7×7 grid, center already loaded)
  └─→ generating_chunks = [chunk1, chunk2, ..., chunk7]
      ↓
Frame N+1-N+20: _process_generation_queue()
  ├─→ Frame N+1: Generate chunks 1-3 (4ms budget)
  ├─→ Frame N+2: Generate chunks 4-6 (4ms budget)
  ├─→ Frame N+3: Generate chunk 7 (4ms budget)
  └─→ Queue empty → emit chunk_updates_completed
      ↓
Frame N+21: PostTurnState receives signal
  └─→ Transitions to IdleState (INPUT UNBLOCKED)

Total latency: ~20 frames (~333ms @ 60fps) when generating 7 chunks
```

---

**End of Architecture Audit**
**Last Updated**: 2025-11-17 (Added threaded chunk generation system)
**Auditor**: Claude (Haiku 4.5)
