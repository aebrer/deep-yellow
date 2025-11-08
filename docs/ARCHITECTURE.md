# Architecture & Technical Design

## Overview

This document outlines the technical architecture for Backrooms Power Crawl, focusing on systems design, data structures, and implementation patterns.

## ✅ Implemented Architecture (Current)

### Three-Layer Input & Turn System

```
┌─────────────────────────────────────────────────────────────┐
│                   RAW INPUT LAYER                           │
│  Controller / Keyboard → Godot Input Actions                │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              INPUTMANAGER (Autoload)                        │
│  - Device abstraction (controller + keyboard identical)     │
│  - Deadzone handling (radial, 0.2 default)                  │
│  - Analog → 8-direction grid conversion (angle-based)       │
│  - Action tracking for frame-based queries                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              STATE MACHINE LAYER                            │
│  Player → InputStateMachine → Current State                 │
│    States: IdleState, AimingMoveState, ExecutingTurnState   │
│  - State-specific input handling                            │
│  - Turn boundaries explicit                                 │
│  - Queries InputManager for normalized input                │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              ACTION LAYER (Command Pattern)                 │
│  States create Actions → Actions validate & execute         │
│    Actions: MovementAction, WaitAction, (future: others)    │
│  - Decouples input from execution                           │
│  - Enables replays, AI, undo (future)                       │
└─────────────────────────────────────────────────────────────┘
```

### File Structure

```
scripts/
├── autoload/
│   └── input_manager.gd           # InputManager singleton (autoload)
├── actions/
│   ├── action.gd                  # Base Action class
│   ├── movement_action.gd         # Move in direction
│   └── wait_action.gd             # Pass turn
├── player/
│   ├── player.gd                  # Player controller
│   ├── input_state_machine.gd    # State machine manager
│   └── states/
│       ├── player_input_state.gd  # Base state class
│       ├── idle_state.gd          # Waiting for input
│       ├── aiming_move_state.gd   # Aiming movement
│       └── executing_turn_state.gd # Processing turn
├── grid.gd                        # Grid/map management
└── game.gd                        # Main game scene
```

### InputManager (Autoload)

**Purpose**: Normalize input from different devices, provide unified API

**Features**:
- `get_aim_direction() -> Vector2` - Normalized analog input
- `get_aim_direction_grid() -> Vector2i` - 8-way grid-snapped direction
- `is_action_just_pressed(action: String) -> bool` - Frame-based action query
- Radial deadzone (0.2 default, configurable)
- Angle-based 8-direction conversion for clean diagonals
- Debug mode with console logging

**Usage**:
```gdscript
# From any script
var aim = InputManager.get_aim_direction_grid()
if InputManager.is_action_just_pressed("move_confirm"):
    execute_action()
```

### State Machine Pattern

**Purpose**: Manage player input modes and turn boundaries

**States**:
1. **IdleState**: Waiting for player input
   - Transitions to AimingMoveState when stick/WASD pressed
2. **AimingMoveState**: Player aiming movement direction
   - Shows preview indicator (green if valid, red if blocked)
   - Confirms with move_confirm action
   - Returns to IdleState if stick released
   - Transitions to ExecutingTurnState on confirm
3. **ExecutingTurnState**: Processing turn
   - Input blocked during turn execution
   - Executes pending action
   - Processes enemy turns (future)
   - Returns to IdleState when complete

**State Lifecycle**:
```
IdleState
  ├─ stick_moved → AimingMoveState
  └─ (waiting)

AimingMoveState
  ├─ stick_released → IdleState
  ├─ move_confirm + valid → ExecutingTurnState
  └─ move_confirm + invalid → (stay, show error)

ExecutingTurnState
  ├─ execute_action()
  ├─ process_enemies() [future]
  └─ turn_complete → IdleState
```

### Action Pattern (Command)

**Purpose**: Decouple input from execution, enable replays/AI

**Base Class**:
```gdscript
class_name Action
  func can_execute(player) -> bool
  func execute(player) -> void
```

**Implemented Actions**:
- **MovementAction**: Move player in direction, validate bounds/walls
- **WaitAction**: Pass turn without moving

**Future Actions**:
- AbilityAction, ExamineAction, InteractAction, etc.

### Grid System

**Purpose**: Manage map data, tile rendering, viewport culling

**Features**:
- 2D array grid data (0 = floor, 1 = wall)
- Viewport culling: Only render ~400 tiles near player (not 16k!)
- `is_walkable(pos)` - Query tile walkability
- `render_around_position(pos)` - Update visible tiles
- ASCII/emoji placeholder graphics

### Input Configuration (project.godot)

All actions support both controller and keyboard:
- **move_confirm**: R2 / SPACE
- **pause**: START / ESC
- **inventory**: SELECT / I
- **toggle_ability_1-4**: RB/LB/X/Y / 1/2/3/4
- **examine_mode**: L1 / TAB

Movement uses Godot's built-in ui_left/ui_right/ui_up/ui_down (stick + WASD)

---

## 🔮 Planned Architecture (Future)

## Engine: Godot 4.3+

### Why Godot
- Open source, GPL-friendly
- Excellent 2D support
- GDScript (Python-like)
- Native controller support
- Powerful shader system
- Scene/Node architecture

## Core Systems Architecture

### 1. Entity Component System (ECS-lite)

While Godot uses a Scene/Node system, we'll implement ECS-like patterns for flexibility.

#### Component Types
```
Component (Base)
├── PositionComponent (x, y, level)
├── RenderComponent (sprite, shader_params)
├── StatsComponent (hp, sanity, corruption)
├── AbilityComponent (abilities[], cooldowns{})
├── AIComponent (behavior_tree, state)
├── PhysicsComponent (material, temperature, liquid_volume)
├── KnowledgeComponent (discovered_entities[], clearance_level)
└── ContainmentComponent (target_entity, containment_tools[])
```

#### Entity Types
- **Player**: Position, Render, Stats, Abilities, Knowledge, Containment
- **Hostile Entity**: Position, Render, Stats, AI, Physics
- **NPC**: Position, Render, Stats, AI (friendly), Dialogue
- **Item**: Position, Render, Physics
- **Tile**: Position, Render, Physics (liquids, temperature)

### 2. Turn-Based System

#### Turn Manager
```gdscript
class_name TurnManager

var turn_queue: Array[Entity] = []
var current_entity: Entity = null
var turn_number: int = 0

func process_turn():
    # 1. Get next entity from queue
    # 2. Allow entity to take action
    # 3. Process automatic abilities (if entity has them)
    # 4. Update physics simulation
    # 5. Check win/loss conditions
    # 6. Advance to next turn
```

#### Action System
```gdscript
class_name Action extends RefCounted

enum ActionType {
    MOVE,
    WAIT,
    EXAMINE,
    INTERACT,
    TOGGLE_ABILITY,
    USE_ITEM
}

var type: ActionType
var cost: int  # Turn cost (usually 1)
var target: Vector2i  # For moves/interactions

func execute(entity: Entity) -> bool:
    # Override in subclasses
    pass
```

### 3. Tile & Map System

#### Tile Data
```gdscript
class_name Tile extends RefCounted

var position: Vector2i
var terrain_type: TerrainType
var walkable: bool = true
var transparent: bool = true

# Physics data
var liquid_volume: float = 0.0
var liquid_type: LiquidType = LiquidType.NONE
var temperature: float = 20.0  # Celsius
var corruption_level: float = 0.0

# Entities on this tile
var entities: Array[Entity] = []
var items: Array[Item] = []
```

#### Map Generator
```gdscript
class_name MapGenerator

func generate_level(level_type: LevelType, size: Vector2i) -> Map:
    # Procedural generation based on level type
    # Level 0: Maze of office rooms
    # Level 1: Industrial corridors
    # etc.
    pass
```

### 4. Physics Simulation Layer

#### Simulation Manager
```gdscript
class_name SimulationManager

func simulate_step(map: Map):
    _simulate_liquids(map)
    _simulate_temperature(map)
    _simulate_gases(map)
    _simulate_fire(map)
    _simulate_corruption(map)

func _simulate_liquids(map: Map):
    # Spread liquids to adjacent tiles
    # Mix liquids (acid + water = diluted acid)
    # Apply effects to entities in liquid
    pass

func _simulate_temperature(map: Map):
    # Heat transfer between tiles
    # Freeze water -> ice
    # Ignite flammable materials
    pass
```

#### Material System
```gdscript
enum MaterialType {
    FLESH, METAL, WOOD, PLASTIC, CLOTH, CERAMIC, GLASS
}

class_name Material extends RefCounted

var type: MaterialType
var flammable: bool
var conductive: bool
var melting_point: float
var corrosion_resistance: float
```

### 5. Ability System

#### Ability Base Class
```gdscript
class_name Ability extends Resource

@export var name: String
@export var description: String
@export var enabled: bool = true
@export var cooldown: int = 0
@export var resource_cost: float = 0.0

# Auto-proc conditions
@export var proc_on_move: bool = false
@export var proc_on_nearby_enemy: bool = false
@export var proc_interval: int = 0  # Turns between auto-procs

func can_activate(entity: Entity) -> bool:
    return enabled and cooldown == 0

func activate(entity: Entity, target = null):
    # Override in subclasses
    pass

func tick():
    if cooldown > 0:
        cooldown -= 1
```

#### Example Abilities
```gdscript
class_name DistortionFieldAbility extends Ability

func _init():
    name = "Reality Distortion Field"
    description = "Damages nearby entities but creates noise"
    proc_on_nearby_enemy = true

func activate(entity: Entity, target = null):
    var nearby = get_nearby_entities(entity.position, 2)
    for e in nearby:
        e.take_damage(5)
    # Increase noise level (attracts entities)
    entity.noise_level += 10
```

### 6. Knowledge & Examination System

#### Knowledge Database
```gdscript
class_name KnowledgeDB extends Resource

var discovered_entities: Dictionary = {}  # entity_id -> discovery_level
var clearance_level: int = 0
var researcher_classification: int = 0

func get_entity_info(entity_id: String) -> EntityInfo:
    var discovery = discovered_entities.get(entity_id, 0)
    return EntityRegistry.get_info(entity_id, discovery, clearance_level)
```

#### Entity Documentation
```gdscript
class_name EntityInfo extends Resource

@export var entity_id: String
@export var name_levels: Array[String] = ["████████", "???", "Skin-Stealer"]
@export var description_levels: Array[String] = [
    "[REDACTED]",
    "Hostile humanoid entity. [DATA EXPUNGED]",
    "Hostile humanoid entity. Mimics human appearance. Attracted to sound and movement. Weakness: bright light."
]
@export var clearance_required: Array[int] = [0, 1, 3]

func get_display_info(discovery_level: int, clearance: int) -> Dictionary:
    var idx = min(discovery_level, clearance)
    return {
        "name": name_levels[idx],
        "description": description_levels[idx]
    }
```

### 7. UI & Examination Mode

#### Tooltip System
```gdscript
class_name TooltipManager extends CanvasLayer

var current_tile: Vector2i
var knowledge_db: KnowledgeDB

func show_tooltip(tile: Tile):
    var info = _gather_tile_info(tile)
    _render_scp_style_panel(info)

func _render_scp_style_panel(info: Dictionary):
    # Monospace font
    # Redacted bars (████)
    # Clinical formatting
    pass
```

#### Examination Mode
```gdscript
class_name ExaminationController

var active: bool = false
var cursor_position: Vector2i

func _process(delta):
    if not active:
        return

    # Read right stick input
    var look_input = Input.get_vector("look_left", "look_right", "look_up", "look_down")
    _move_cursor(look_input)
    _show_tooltip_at_cursor()
```

### 8. Visual Corruption System

#### Corruption Shader
```glsl
shader_type canvas_item;

uniform float corruption_level : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;
uniform sampler2D noise_texture;

void fragment() {
    vec2 uv = UV;

    // Pixel displacement based on corruption
    float displacement = corruption_level * 0.1;
    vec2 noise_uv = uv + vec2(TIME * 0.1 + time_offset);
    vec2 noise = texture(noise_texture, noise_uv).rg - 0.5;
    uv += noise * displacement;

    // Chromatic aberration
    float aberration = corruption_level * 0.02;
    float r = texture(TEXTURE, uv + vec2(aberration, 0.0)).r;
    float g = texture(TEXTURE, uv).g;
    float b = texture(TEXTURE, uv - vec2(aberration, 0.0)).b;

    // Glitch effect
    float glitch = step(0.98, sin(TIME * 10.0 + uv.y * 100.0)) * corruption_level;
    uv.x += glitch * 0.1;

    COLOR = vec4(r, g, b, texture(TEXTURE, UV).a);
}
```

#### Corruption Manager
```gdscript
class_name CorruptionManager

func update_corruption(entity: Entity, delta: float):
    var corruption = calculate_corruption(entity)
    entity.get_node("Sprite2D").material.set_shader_parameter("corruption_level", corruption)

func calculate_corruption(entity: Entity) -> float:
    var base = entity.corruption_stat / 100.0
    var proximity = _get_entity_proximity_factor(entity)
    var reality_stability = _get_reality_stability(entity.position)

    return clamp(base + proximity + (1.0 - reality_stability), 0.0, 1.0)
```

## Data-Driven Design

### JSON Entity Definitions
```json
{
  "entity_id": "skin_stealer",
  "name": "Skin-Stealer",
  "sprite": "res://assets/sprites/entities/skin_stealer.png",
  "stats": {
    "hp": 50,
    "speed": 5,
    "damage": 10
  },
  "ai_behavior": "aggressive_pursue",
  "attracted_to": ["sound", "movement"],
  "weaknesses": ["bright_light"],
  "loot_table": "standard_hostile"
}
```

### Data Loading
```gdscript
class_name EntityRegistry extends Node

static var entities: Dictionary = {}

static func load_entities():
    var dir = DirAccess.open("res://data/entities/")
    for file in dir.get_files():
        if file.ends_with(".json"):
            var data = _load_json(file)
            entities[data.entity_id] = data
```

## Performance Considerations

### Efficient Tile Updates
- Only simulate tiles within player view + buffer
- Chunk-based processing for large maps
- Spatial hashing for entity queries

### Entity Pooling
- Reuse entity instances instead of creating/destroying
- Especially important for horde modes with hundreds of entities

### Shader Optimization
- LOD system for corruption effects (less complex at distance)
- Batch shader parameter updates

## Development Roadmap

### Phase 1: Core Systems
1. Turn manager + basic movement
2. Tile system + simple map generation
3. Controller input + examination mode
4. Tooltip system with SCP formatting

### Phase 2: Combat & Abilities
5. Entity spawning + basic AI
6. Ability system + toggling
7. Auto-proc implementation
8. Damage/death systems

### Phase 3: Simulation
9. Liquid simulation
10. Temperature system
11. Material interactions
12. Emergent gameplay testing

### Phase 4: Progression & Content
13. Knowledge database
14. Hub area + NPCs
15. Mission types (horde vs hunt)
16. Containment mechanics

### Phase 5: Visual Polish
17. Corruption shaders
18. Visual effects
19. UI refinement
20. Audio integration

## Testing Strategy

- Unit tests for simulation systems (liquids, temperature)
- Controller input testing on multiple devices
- Performance profiling with large hordes
- Playtest each system before moving to next

---

**Last Updated**: 2025-10-30
