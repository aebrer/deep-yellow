# Entity System Architecture Plan

**Status**: Research complete, implementation planned for future PR
**Research Date**: 2025-01-12
**Target**: Phase 4+ (after examination system is stable)

---

## Executive Summary

This document outlines the recommended architecture for the entity system that will handle hundreds of entity types and thousands of runtime instances. Based on industry research and analysis of successful Godot roguelikes, we recommend a **Hybrid Data-Oriented approach** combining lightweight data objects with on-demand visual representation.

---

## Core Architecture

### 1. EntityData (Resource-based)

Lightweight data container for all entity types:

```gdscript
class_name EntityData extends Resource
## Lightweight data container for all entity types
## Instances stored in EntityManager arrays, NOT as nodes

@export var entity_id: String = ""
@export var entity_type: EntityType

# Core stats
@export var max_hp: int = 100
@export var max_sanity: int = 100
@export var movement_speed: int = 5

# Visual
@export var sprite_texture: Texture2D
@export var mesh_scene: PackedScene

# Components (composition via data)
@export var has_inventory: bool = false
@export var has_ai: bool = false
@export var ai_behavior: String = ""

# Runtime state
var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
var current_sanity: int = 0
var status_effects: Array[StatusEffect] = []
var inventory_items: Array[ItemData] = []

enum EntityType { PLAYER, HOSTILE, NEUTRAL, NPC, ITEM, DOOR, STAIRS, ANOMALY }
```

**Key Benefits**:
- ~1KB per entity (vs ~10KB for Node3D)
- Cache-friendly arrays
- Scales to thousands of entities

### 2. EntityManager (Autoload Singleton)

Manages all runtime entities as data objects:

```gdscript
extends Node
## EntityManager - Manages all runtime entities as data objects

# All entities stored as lightweight data objects
var entities: Array[EntityData] = []

# Spatial index for fast queries
var spatial_grid: Dictionary = {}  # {position: [entity_refs]}

# Visual representation pool (nodes are reused!)
var entity_node_pool: Array[Node3D] = []
var active_visuals: Dictionary = {}  # {entity: node}

func spawn_entity(definition: EntityData, pos: Vector2i) -> EntityData:
  var entity = definition.duplicate()
  entity.position = pos
  entities.append(entity)
  _add_to_spatial_grid(entity, pos)

  # Only create visual if in viewport
  if _is_in_viewport(pos):
    _create_visual_for_entity(entity)

  return entity
```

**Key Benefits**:
- Viewport culling (only render visible entities)
- Object pooling (reuse Node3D instances)
- Spatial hashing (fast position queries)
- Works with existing Grid culling system

### 3. Component Composition

Node-based components shared between Player and NPCs/Monsters:

```gdscript
# scripts/components/health_component.gd
class_name HealthComponent extends EntityComponent

@export var max_hp: int = 100
var current_hp: int = 100

signal health_changed(current: int, maximum: int)
signal death

func take_damage(amount: int, source: Entity = null) -> int:
  current_hp = max(0, current_hp - amount)
  health_changed.emit(current_hp, max_hp)

  if current_hp <= 0:
    death.emit()

  return amount
```

**Shared Components**:
- HealthComponent (player, monsters, NPCs)
- SanityComponent (player, some NPCs)
- InventoryComponent (player, monsters, NPCs)
- AbilityComponent (player, special monsters)
- StatusEffectComponent (all entities)

**Why This Matters**:
- Player and monsters use identical code
- Give monster same item player can have = easy balancing
- Emergent gameplay from component interactions

---

## File Organization

### Directory Structure

```
data/entities/
├── monsters/
│   ├── smiler.tres
│   ├── smiler_elite.tres
│   ├── skin_stealer.tres
│   └── hound.tres
├── items/
│   ├── body/
│   │   ├── brass_knuckles.tres
│   │   └── steel_pipe.tres
│   ├── mind/
│   │   ├── system_analyzer.tres
│   │   └── perception_filter.tres
│   └── null/
│       ├── reality_anchor.tres
│       └── corrupted_lantern.tres
├── npcs/
│   ├── researcher_jones.tres
│   └── wanderer_neutral.tres
└── environmental/
    ├── door.tres
    └── stairs.tres

scripts/components/
├── entity_component.gd          # Base class
├── health_component.gd
├── sanity_component.gd
├── inventory_component.gd
├── ability_component.gd
└── status_effect_component.gd

scripts/systems/
├── entity_manager.gd             # Autoload
├── ai_system.gd                  # Process hostile AI
├── physics_system.gd             # Liquids, temperature
└── status_effect_system.gd
```

### Why This Structure

- **Category-based**: Clear separation by entity type
- **One file per entity**: Prevents merge conflicts, easy to find
- **Components as nodes**: Works with Godot's strengths
- **Systems for processing**: Turn-based system integration

---

## Data Format: Resources vs JSON

### Primary: Godot Resources (.tres)

**Advantages**:
- ✅ Editor integration (Inspector, drag-drop)
- ✅ Type safety (catch errors early)
- ✅ Inheritance support (variants)
- ✅ Zero serialization code
- ✅ Performance (binary .res format)

**Usage**:
```gdscript
# Load entity definition
var skin_stealer = load("res://data/entities/monsters/skin_stealer.tres")
var entity = EntityManager.spawn_entity(skin_stealer, Vector2i(10, 5))
```

### Secondary: JSON (Future Modding)

**Advantages**:
- ✅ Plain text editing
- ✅ Modding-friendly
- ✅ Version control friendly

**Implementation**:
Add JSON importer/exporter later without refactoring core systems.

---

## Performance Considerations

### Memory Estimates

**Node-based** (current approach):
- Node3D: ~10KB per instance
- 1000 entities = ~10MB + scene tree overhead
- Performance: 30-60 FPS with 500-1000 entities

**Data-based** (recommended):
- EntityData: ~1KB per instance
- 1000 entities = ~1MB
- Only render visible (~100-200 visuals)
- Performance: 60 FPS with 1000s of entities

### Optimization Strategies

1. **Viewport Culling** (like Grid system)
   - Only render entities near player
   - Destroy off-screen visuals, keep data

2. **Object Pooling**
   - Reuse Node3D instances
   - Pre-instantiate common entity types

3. **Chunk-Based Processing**
   - Only process entities in active chunks
   - Dormant chunks stored as data only

4. **Spatial Hashing**
   - O(1) queries: "entities at position X"
   - Fast radius queries for AI

---

## Integration with Existing Systems

### Examination System

```gdscript
# When spawning entity visual:
var examinable = Examinable.new()
examinable.entity_id = entity.entity_id
entity_visual.add_child(examinable)

# KnowledgeDB, EntityRegistry work unchanged!
```

### Turn System

```gdscript
# ExecutingTurnState processes entities
func execute_turn():
  # Process player action (existing)
  player_action.execute(player_data)

  # Process all hostile entities (new)
  var hostiles = EntityManager.get_entities_by_type(EntityType.HOSTILE)
  AISystem.process_turn(hostiles)

  # Process physics simulation (Phase 5)
  PhysicsSystem.simulate_step()
```

### Action System

```gdscript
# Entities use same Action pattern
var move_action = MovementAction.new(entity, target_pos)
if move_action.can_execute(entity):
  move_action.execute(entity)
```

---

## Implementation Phases

### Phase 1: Foundation (Next PR)

1. Create `EntityData` Resource class
2. Create `EntityManager` Autoload
3. Create `EntityComponent` base class
4. Create `HealthComponent`
5. Test with 10 entities

**Deliverable**: Spawn 10 entities, verify performance

### Phase 2: Core Components

6. Create `InventoryComponent`
7. Create `StatusEffectComponent`
8. Port Player to use EntityData
9. Test with 100 entities

**Deliverable**: Player and entities use same components

### Phase 3: Enemy AI

10. Create `AIComponent`
11. Create `AISystem` for turn processing
12. Implement pathfinding
13. Test with 500 entities (horde mode)

**Deliverable**: Functional enemy AI using turn system

### Phase 4: Items & Interactions

14. Create item entity definitions
15. Implement pickup/drop mechanics
16. Create loot tables
17. Test item interactions

**Deliverable**: Items work as entities

### Phase 5: Advanced Features

18. Physics simulation (liquids, temperature)
19. JSON entity loading (modding support)
20. Procedural spawning system
21. Profile with 1000+ entities

**Deliverable**: Full system at scale

---

## Real-World Examples

### Caves of Qud Pattern
- Data-driven entities with component composition
- JSON definitions for 1000s of entity types
- Efficient simulation through data-oriented processing

### Binding of Isaac Pattern
- Item pool management (Body/Mind/NULL slots)
- Effect stacking through ordered execution
- Thousands of synergies through data composition

### Your Project's Advantage
- Turn-based = no per-frame overhead
- Viewport culling already implemented
- Existing Resource-based patterns
- Small initial scope (scales up)

---

## Component Examples

### Entity Base Class

```gdscript
class_name Entity extends Node2D
## Base entity class composed of components

@export var entity_name: String = "Unknown"
@export var entity_id: String = ""
@export var grid_position: Vector2i = Vector2i.ZERO

var health: HealthComponent = null
var sanity: SanityComponent = null
var inventory: InventoryComponent = null
var abilities: AbilityComponent = null

func _ready() -> void:
  _cache_components()

func _cache_components() -> void:
  health = get_node_or_null("HealthComponent")
  sanity = get_node_or_null("SanityComponent")
  inventory = get_node_or_null("InventoryComponent")
  abilities = get_node_or_null("AbilityComponent")

  # Set entity reference on all components
  for child in get_children():
    if child is EntityComponent:
      child.entity = self

func process_turn() -> void:
  # Process all components
  for child in get_children():
    if child is EntityComponent:
      child.process_turn()
```

### InventoryComponent (Shared!)

```gdscript
class_name InventoryComponent extends EntityComponent

@export var max_slots: int = 20
var items: Array[Item] = []

signal item_added(item: Item)
signal item_removed(item: Item)

func add_item(item: Item) -> bool:
  if items.size() >= max_slots:
    return false

  items.append(item)
  item_added.emit(item)
  return true

func remove_item(item: Item) -> bool:
  var idx = items.find(item)
  if idx == -1:
    return false

  items.remove_at(idx)
  item_removed.emit(item)
  return true
```

---

## JSON Entity Definition Format

```json
{
  "entity_id": "skin_stealer",
  "entity_name": "Skin-Stealer",
  "sprite": "res://assets/sprites/entities/skin_stealer.png",
  "components": [
    {
      "type": "HealthComponent",
      "config": {
        "max_hp": 50,
        "armor": 5,
        "regeneration_per_turn": 1
      }
    },
    {
      "type": "InventoryComponent",
      "config": {
        "max_slots": 5
      }
    },
    {
      "type": "AIComponent",
      "config": {
        "ai_behavior": "aggressive_stealth"
      }
    }
  ]
}
```

---

## Benefits Summary

✅ **Scalable**: Handles thousands of entities
✅ **Performant**: Data-oriented with viewport culling
✅ **Modular**: Components compose naturally
✅ **Balanced**: Player/monsters share components
✅ **Maintainable**: Clear file organization
✅ **Moddable**: JSON export for modders (future)
✅ **Turn-based friendly**: No per-frame overhead
✅ **Works with existing code**: Minimal refactoring

---

## References

- **Agent Research Reports**: Full research output stored in conversation history
- **GDQuest Entity-Component Pattern**: https://www.gdquest.com/tutorial/godot/design-patterns/entity-component-pattern/
- **SelinaDev Roguelike Tutorial**: https://github.com/SelinaDev/Godot-Roguelike-Tutorial
- **GECS Documentation**: https://github.com/csprance/gecs
- **Godot Performance Discussion**: https://godotengine.org/article/why-isnt-godot-ecs-based-game-engine/

---

## Next Steps

When ready to implement (future PR):

1. Read this document in full
2. Start with Phase 1 (Foundation)
3. Test performance at each phase
4. Profile with actual gameplay
5. Iterate based on measurements

**Do NOT over-engineer** - start simple, scale as needed.

---

*Last Updated: 2025-01-12*
*Status: Planning - Not Yet Implemented*
