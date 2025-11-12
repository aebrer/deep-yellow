# EXAMINATION SYSTEM REDESIGN PLAN
**Date:** 2025-01-12
**Status:** Approved, Ready for Implementation
**Branch:** `feature/examination-overlay-system`

---

## Executive Summary

The current GridMap-based examination system is fundamentally flawed due to architectural mismatch: we're building a 3D game with a 2D grid, causing collision detection issues, complex workarounds, and unmaintainable code.

This document outlines a complete redesign using industry-standard component-based architecture, reducing code by 60% while improving reliability and maintainability.

---

## Root Cause Analysis

### The Fundamental Problem

**Current architecture:**
- Grid is 2D: `(x, z)` coordinates only
- Tiles placed at fixed Y layers: Y=0 for floor/walls, Y=1 for ceilings
- GridMap collision shapes overlap and misalign with visual meshes
- Examination system tries to reverse-engineer what was hit using:
  - Surface normal analysis (dot product with Vector3.UP)
  - Y-coordinate heuristics (`if Y < 0.5: floor`)
  - Manual grid cell traversal as fallback
  - Complex state machines with multiple code paths

**Why this fails:**
1. Walls at grid Y=0 have collision extending from world Y=0 to Y=4
2. Ceilings at grid Y=1 have collision at world Y=~3.98
3. GridMap `local_to_map()` returns grid cell, not the specific tile face hit
4. Raycast hits at Y=2.0 could be wall OR ceiling depending on angle
5. Floor detection fails because wall collision boxes extend down to Y=0
6. 400+ lines of heuristics that still fail randomly

### The Insight

**We're treating 3D space as 2D + layering hack, when we should use proper 3D positioning.**

GridMap is a **rendering optimization**, not a gameplay system. We shouldn't be raycasting against it for examination - that's fighting the tool's intended purpose.

---

## Proposed Architecture: Component-Based Examination Overlay

### Philosophy Shift

**OLD (wrong):**
"Grid stores tile IDs, raycast reverse-engineers what was hit from collision math"

**NEW (correct):**
"Every examinable object declares what it is, raycast asks the object directly"

### Architecture Diagram

```
Game World
│
├── Grid3D (GridMap)
│   └── PURPOSE: Visual rendering only (PSX shaders, tile meshes)
│   └── COLLISION: Player movement blocking (walls)
│   └── NOT USED: Examination/interaction
│
├── ExaminationWorld (Node3D)
│   └── PURPOSE: Examination detection layer
│   └── COLLISION LAYER: 4 (bit 8, separate from movement)
│   ├── FloorTile_0_0 (Area3D + Examinable)
│   ├── WallSegment_A (Area3D + Examinable)
│   ├── CeilingTile_5_3 (Area3D + Examinable)
│   └── ... (one Area3D per examinable tile)
│
└── Entities (Node3D)
    └── ExaminableCube (RigidBody3D + Examinable) ✓ Already works!
```

**Key Principle:** Separation of Concerns
- **Rendering:** GridMap handles visuals
- **Movement:** GridMap collision layer 2 blocks player
- **Examination:** Separate Area3D overlay on layer 4
- **Interaction:** Examinable components on entities

---

## Detailed Component Design

### Component 1: Examinable (Existing, Minor Enhancement)

**Location:** `/scripts/components/examinable.gd`

**Current status:** ✅ Already works perfectly for entities (cube)

**Minor additions needed:**
```gdscript
# Add optional metadata for environment tiles
@export var tile_grid_position: Vector2i = Vector2i.ZERO
@export var tile_type: String = ""  # "wall", "floor", "ceiling"
```

**No breaking changes** - purely additive.

---

### Component 2: ExaminableEnvironmentTile (New Scene)

**Location:** `/scenes/environment/examinable_environment_tile.tscn`

**Scene Structure:**
```
ExaminableEnvironmentTile
└── Area3D
    ├── CollisionShape3D (BoxShape3D)
    └── Examinable (component)
```

**Script:** `/scripts/environment/examinable_environment_tile.gd`

```gdscript
class_name ExaminableEnvironmentTile
extends Area3D
## Invisible examination area for environment tiles
##
## Positioned at same world location as GridMap visual tile.
## Contains Examinable component for Look Mode detection.

@onready var examinable: Examinable = $Examinable

func setup(tile_type: String, entity_id: String, grid_pos: Vector2i, world_pos: Vector3) -> void:
    """Initialize this examination tile

    Args:
        tile_type: "wall", "floor", or "ceiling"
        entity_id: KnowledgeDB lookup ID (e.g., "level_0_wall")
        grid_pos: Grid coordinates (for debugging)
        world_pos: 3D world position
    """
    name = "Exam_%s_%d_%d" % [tile_type, grid_pos.x, grid_pos.y]
    global_position = world_pos

    examinable.entity_id = entity_id
    examinable.entity_type = Examinable.EntityType.ENVIRONMENT
    examinable.tile_grid_position = grid_pos
    examinable.tile_type = tile_type

    collision_layer = 8  # Layer 4 (bit 8)
    collision_mask = 0

    Log.system("Created examinable tile: %s at %s" % [entity_id, world_pos])
```

**Purpose:** Template instantiated for each examinable tile during world generation.

---

### Component 3: ExaminationWorldGenerator (New System)

**Location:** `/scripts/environment/examination_world_generator.gd`

**Purpose:** Generate examination overlay during Grid3D initialization

```gdscript
class_name ExaminationWorldGenerator
extends Node
## Generates examination overlay for GridMap tiles
##
## Creates ExaminableEnvironmentTile nodes for walls, floors, ceilings.

const EXAM_TILE_SCENE = preload("res://scenes/environment/examinable_environment_tile.tscn")

# Tile dimensions (match GridMap cell_size)
const TILE_SIZE = Vector2(2.0, 2.0)  # X, Z
const FLOOR_HEIGHT = 0.0
const WALL_HEIGHT = 2.0
const CEILING_HEIGHT = 3.0

var examination_world: Node3D

func generate_examination_layer(grid: Grid3D, parent: Node3D) -> void:
    """Generate examination tiles for entire grid"""
    Log.system("Generating examination layer...")

    examination_world = Node3D.new()
    examination_world.name = "ExaminationWorld"
    parent.add_child(examination_world)

    var tiles_created = 0

    for y in range(grid.grid_size.y):
        for x in range(grid.grid_size.x):
            var grid_pos = Vector2i(x, y)
            var cell_3d = Vector3i(x, 0, y)
            var cell_item = grid.grid_map.get_cell_item(cell_3d)

            match cell_item:
                Grid3D.TileType.FLOOR:
                    _create_floor_tile(grid, grid_pos)
                    tiles_created += 1
                Grid3D.TileType.WALL:
                    _create_wall_tile(grid, grid_pos)
                    tiles_created += 1
                Grid3D.TileType.CEILING:
                    _create_ceiling_tile(grid, grid_pos)
                    tiles_created += 1

    Log.system("Created %d examination tiles" % tiles_created)

func _create_floor_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
    var world_pos = grid.grid_to_world(grid_pos)
    world_pos.y = FLOOR_HEIGHT

    var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
    examination_world.add_child(tile)
    tile.setup("floor", "level_0_floor", grid_pos, world_pos)

    var collision = tile.get_node("CollisionShape3D")
    var shape = BoxShape3D.new()
    shape.size = Vector3(TILE_SIZE.x, 0.1, TILE_SIZE.y)
    collision.shape = shape

func _create_wall_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
    var world_pos = grid.grid_to_world(grid_pos)
    world_pos.y = WALL_HEIGHT

    var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
    examination_world.add_child(tile)
    tile.setup("wall", "level_0_wall", grid_pos, world_pos)

    var collision = tile.get_node("CollisionShape3D")
    var shape = BoxShape3D.new()
    shape.size = Vector3(TILE_SIZE.x, 4.0, TILE_SIZE.y)
    collision.shape = shape

func _create_ceiling_tile(grid: Grid3D, grid_pos: Vector2i) -> void:
    var world_pos = grid.grid_to_world(grid_pos)
    world_pos.y = CEILING_HEIGHT

    var tile = EXAM_TILE_SCENE.instantiate() as ExaminableEnvironmentTile
    examination_world.add_child(tile)
    tile.setup("ceiling", "level_0_ceiling", grid_pos, world_pos)

    var collision = tile.get_node("CollisionShape3D")
    var shape = BoxShape3D.new()
    shape.size = Vector3(TILE_SIZE.x, 0.1, TILE_SIZE.y)
    collision.shape = shape
```

**Integration point:** Called from `Grid3D.generate_grid()` after GridMap generation.

---

### Component 4: Simplified FirstPersonCamera

**Location:** `/scripts/player/first_person_camera.gd`

**BEFORE:** 300+ lines with surface normal analysis, manual grid traversal, Y-coordinate heuristics

**AFTER:** ~50 lines, simple and obvious

```gdscript
func get_current_target() -> Examinable:
    """Get what the player is looking at

    Returns:
        Examinable component, or null if looking at nothing
    """
    var hit = get_look_raycast()

    if hit.is_empty():
        return null

    var collider = hit.get("collider")

    # Check if collider has Examinable component
    if collider.has_node("Examinable"):
        return collider.get_node("Examinable")

    # Check children for Examinable
    for child in collider.get_children():
        if child is Examinable:
            return child

    return null

func get_look_raycast() -> Dictionary:
    """Perform raycast from camera center"""
    var viewport = get_viewport()
    var screen_center = viewport.get_visible_rect().size / 2.0

    var ray_origin = camera.project_ray_origin(screen_center)
    var ray_direction = camera.project_ray_normal(screen_center)
    var ray_length = 10.0

    var space_state = get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(
        ray_origin,
        ray_origin + ray_direction * ray_length
    )
    query.collision_mask = 8  # Layer 4 (examination)

    return space_state.intersect_ray(query)
```

**Removed:**
- `SurfaceType` enum
- `_classify_surface_by_normal()`
- `_surface_type_to_tile_type()`
- `_surface_type_name()`
- `_manual_grid_raycast()`
- All surface normal/grid traversal logic

**Code reduction:** ~250 lines deleted

---

### Component 5: Simplified LookModeState

**Location:** `/scripts/player/states/look_mode_state.gd`

**BEFORE:** Complex grid tile type matching, entity ID mapping

**AFTER:**

```gdscript
func process_frame(delta: float) -> void:
    """Process Look Mode each frame"""
    if not is_active or not fp_camera or not examination_ui:
        return

    var target = fp_camera.get_current_target()

    if target:
        var entity_info = target.get_display_info()
        examination_ui.show_panel_for_entity(entity_info)
    else:
        examination_ui.hide_panel()
```

**Removed:**
- `_get_entity_id_for_tile()` method
- Grid tile type matching logic
- Surface type to entity_id conversion

---

### Component 6: Simplified ExaminationUI

**Location:** `/scripts/ui/examination_ui.gd`

**BEFORE:** Separate methods for entities vs grid tiles

**AFTER:** Single unified method

```gdscript
func show_panel_for_entity(entity_info: Dictionary) -> void:
    """Display examination info for ANY entity (environment or object)"""
    if entity_info.is_empty():
        hide_panel()
        return

    entity_name_label.text = entity_info.get("name", "Unknown")
    description_label.text = entity_info.get("description", "[DATA EXPUNGED]")
    clearance_label.text = "CLEARANCE: %d" % entity_info.get("clearance_required", 0)

    panel.visible = true

func hide_panel() -> void:
    panel.visible = false
```

**Removed:**
- `show_panel_for_grid_tile()` method
- Tile type matching logic

---

## Migration Plan

### Phase 1: Create New Components (No Breaking Changes)

**Time:** 2 hours

**Tasks:**
1. Create `scenes/environment/examinable_environment_tile.tscn`
2. Create `scripts/environment/examinable_environment_tile.gd`
3. Create `scripts/environment/examination_world_generator.gd`

**Testing:**
- Game loads without errors
- New code not called yet, no behavior changes

---

### Phase 2: Integrate with Grid3D

**Time:** 30 minutes

**Changes:**
```gdscript
# In scripts/grid_3d.gd:

func generate_grid() -> void:
    # ... existing GridMap generation ...

    # NEW: Generate examination overlay
    var exam_generator = ExaminationWorldGenerator.new()
    exam_generator.generate_examination_layer(self, get_parent())
```

**Testing:**
- Scene tree shows "ExaminationWorld" node
- ExaminableEnvironmentTile nodes created for each tile
- Enable "Visible Collision Shapes" debug view
- Verify green boxes (layer 4) appear at tile positions

---

### Phase 3: Simplify FirstPersonCamera

**Time:** 1 hour

**Tasks:**
1. Remove surface normal classification code
2. Remove manual grid raycast
3. Replace with simple `get_current_target()` method
4. Change collision_mask from `2 | 8` to just `8` (examination layer only)

**Testing:**
- Enter Look Mode
- Look at cube → shows entity info ✓
- Look at wall → shows wall description ✓
- Look at floor → shows floor description ✓
- Look at ceiling → shows ceiling description ✓

---

### Phase 4: Simplify LookModeState

**Time:** 30 minutes

**Tasks:**
1. Remove `_get_entity_id_for_tile()` method
2. Simplify `process_frame()` to single code path

**Testing:**
- Same as Phase 3

---

### Phase 5: Simplify ExaminationUI

**Time:** 30 minutes

**Tasks:**
1. Remove `show_panel_for_grid_tile()` method
2. Keep only `show_panel_for_entity()`

**Testing:**
- All examination works through unified method
- UI displays correctly for all entity types

---

### Phase 6: Cleanup GridMap Collision (Optional)

**Time:** 15 minutes

**Tasks:**
1. Remove collision shapes from Floor/Ceiling items in MeshLibrary
2. Keep Wall collision for player movement blocking

**Rationale:**
- Examination now uses separate overlay (layer 4)
- GridMap collision only needed for player movement
- Walls need collision to block player
- Floors/ceilings don't need collision anymore

**Testing:**
- Player can't walk through walls ✓
- Examination still works ✓

---

## Benefits Summary

### Code Reduction
- **Before:** ~400 lines for examination system
- **After:** ~150 lines
- **Reduction:** 60%+ less code

### Complexity Reduction
- **Before:** Surface normals, Y-coordinate heuristics, fallback systems, grid math
- **After:** Objects declare what they are, raycast asks directly

### Maintainability
- **Before:** "Why is floor detected as wall?" requires understanding collision transforms, GridMap layering, surface normal math
- **After:** Enable collision shape debug view, see exactly what's examinable

### Debugging
- **Before:** Add logging to 5 different functions, trace through complex state
- **After:** Single raycast → single component → single method

### Extensibility
- **Want unique wall descriptions per position?** Change entity_id in setup
- **Want doors/vents/special tiles?** Add Examinable, done
- **Want multi-level structures?** Works automatically (no grid layer confusion)

---

## Success Criteria

After migration complete:

### Functional Requirements
✅ Look at floor → shows floor description
✅ Look at wall → shows wall description
✅ Look at ceiling → shows ceiling description
✅ Look at entity → shows entity info
✅ No false positives (floor as wall, etc.)
✅ Works from all camera angles

### Code Quality Requirements
✅ Examination system < 200 lines total
✅ No surface normal analysis
✅ No Y-coordinate heuristics
✅ No manual grid traversal
✅ Single code path for all examination

### Maintainability Requirements
✅ New developer understands system in 10 minutes
✅ Debug visualization shows all examinable regions
✅ Adding new examinable = add Examinable component

---

## Risk Assessment

### Low Risk
- Creating new components (additive, no changes to existing)
- Adding examination generator (opt-in)

### Medium Risk
- Removing lots of code from FirstPersonCamera
- **Mitigation:** Git branch, can revert if needed

### High Risk
- None (architecture is additive, can be rolled back at any phase)

---

## Future Enhancements

With new architecture, these become trivial:

### Per-Tile Unique Descriptions
```gdscript
var entity_id = "level_0_wall_%d_%d" % [grid_pos.x, grid_pos.y]
# Each wall can have unique damage, stains, text
```

### Interactive Environment
```gdscript
signal examined(times_examined: int)

func _on_examined():
    # Trigger events, spawn entities, change state
```

### Dynamic Environment Changes
```gdscript
func update_wall_appearance(grid_pos: Vector2i, new_entity_id: String):
    var tile = get_examination_tile(grid_pos)
    tile.examinable.entity_id = new_entity_id
```

---

## File Structure Changes

### New Files
```
scenes/environment/
└── examinable_environment_tile.tscn

scripts/environment/
├── examinable_environment_tile.gd
└── examination_world_generator.gd
```

### Modified Files
```
scripts/grid_3d.gd                      (add generator call)
scripts/player/first_person_camera.gd   (massive simplification)
scripts/player/states/look_mode_state.gd (simplification)
scripts/ui/examination_ui.gd            (simplification)
assets/grid_mesh_library.tres           (optional cleanup)
```

### Unchanged Files
```
scripts/components/examinable.gd        (already perfect)
scripts/autoload/knowledge_db.gd        (already perfect)
data/entities/*.json                    (already perfect)
```

---

## Industry Standards Alignment

This architecture follows:

### Component-Based Design (Unity, Unreal, Godot)
- Objects have components that declare capabilities
- Systems query components, not reverse-engineer behavior

### Separation of Concerns
- Rendering: GridMap
- Movement: GridMap collision layer 2
- Examination: Overlay collision layer 4
- Data: KnowledgeDB

### Explicit Over Implicit
- Objects say "I am a wall" (Examinable component)
- Not "I have normal (0, 0, 1) so I must be a wall" (inference)

---

## Conclusion

**This is the industry-standard way to build examination systems.**

The current GridMap-based approach fights against the tool's intended purpose, requiring complex workarounds that still fail. The overlay approach embraces proper separation of concerns and component-based architecture.

**Total estimated time:** 5-6 hours focused work

**Ready for implementation.**
