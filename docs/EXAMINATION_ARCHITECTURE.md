# Examination System Architecture Redesign

**Date**: 2025-01-12
**Status**: PROPOSAL - Awaiting Review
**Problem**: Current GridMap-based examination system is unreliable, complex, and fights against the engine

---

## Executive Summary

**Current System**: Broken
- Raycasts hit GridMap collision shapes
- Tries to infer tile type from surface normals and Y-coordinates
- Unreliable, fragile, requires constant tweaking
- 150+ lines of heuristics and workarounds

**Proposed System**: Clean Separation
- GridMap for visuals only
- Separate Area3D overlay with Examinable components
- Raycast returns Examinable directly
- ~20 lines of code, no guessing

**Migration**: 6-7 hours of focused work
**Outcome**: Industry-standard, maintainable, extensible

---

## Part 1: The Fundamental Problem

### What We're Trying To Do
When player enters Look Mode and aims at a tile:
1. Raycast from camera center
2. Hit something
3. **IDENTIFY WHAT WAS HIT** ← This is the hard part
4. Display examination info from KnowledgeDB

### Why GridMap Fails At This

**GridMap is a rendering optimization**, not a gameplay system:

```
GridMap Philosophy:
- Combine thousands of tiles into one StaticBody3D
- Merge collision shapes for physics efficiency
- Render in batches for GPU efficiency
- Perfect for performance, TERRIBLE for identification
```

**The Core Issue**: When you raycast against GridMap:
- You get: "You hit the GridMap"
- You need: "You hit the yellow wallpaper tile at (71, 0, 4)"

GridMap **cannot tell you which tile you hit** because it merges everything. You must reverse-engineer it from:
- Collision point coordinates (unreliable at boundaries)
- Surface normal vectors (works for axis-aligned only)
- Y-position heuristics (breaks with multi-level structures)

**This is fighting the engine, not using it.**

---

## Part 2: Industry-Standard Solution

### How Other Games Do This

Every successful first-person game with tile interaction uses **separate collision objects**:

**Minecraft**: Each block is a separate entity with metadata
**Portal**: Each surface has a material ID
**Prey (2017)**: Every object has an Examinable component
**System Shock**: Interaction system separate from rendering

**The Pattern**:
```
Rendering System (optimized for GPU)
    ↓ separate from ↓
Gameplay System (optimized for logic)
```

### The Godot Way

```gdscript
// WRONG (what we're doing now):
var hit = raycast()
var tile_type = guess_from_normal(hit.normal)  // 😬

// RIGHT (industry standard):
var hit = raycast()
var examinable = hit.collider.get_node("Examinable")
var tile_type = examinable.entity_id  // 😎
```

**Objects declare what they are. You don't infer it.**

---

## Part 3: Proposed Architecture - Hybrid Overlay System

### High-Level Structure

```
Game Scene
├── Grid3D (GridMap) - VISUAL RENDERING ONLY
│   └── GridMap
│       - collision_layer = 2 (player movement)
│       - Renders walls/floors/ceilings
│       - No examination logic
│
└── ExaminationGrid (Node3D) - EXAMINATION OVERLAY
    ├── FloorTile_0_0 (Area3D)
    │   ├── CollisionShape3D (thin box)
    │   └── Examinable (entity_id="level_0_floor")
    │
    ├── WallTile_0_1 (Area3D)
    │   ├── CollisionShape3D (box matching wall)
    │   └── Examinable (entity_id="level_0_wall")
    │
    └── ... (one Area3D per examinable tile)
```

### Layer Separation

| System | Purpose | Collision Layer | Query Mask |
|--------|---------|-----------------|------------|
| GridMap | Rendering + Movement | Layer 2 | - |
| Player Movement | Collision with walls | - | Layer 2 |
| ExaminationGrid | Raycast detection | Layer 8 | - |
| Look Mode Raycast | Find examinables | - | Layer 8 |

**Key Insight**: Movement collision (layer 2) and examination detection (layer 8) are **completely independent**.

---

## Part 4: Component Design

### Examinable Component (Already Exists)

```gdscript
class_name Examinable
extends Area3D
## Component that makes an object examinable in Look Mode

@export var entity_id: String = ""  # KnowledgeDB lookup key
@export var entity_type: EntityType = EntityType.ENVIRONMENT

enum EntityType {
    ENTITY_HOSTILE,
    ENTITY_NEUTRAL,
    ENTITY_FRIENDLY,
    HAZARD,
    ITEM,
    ENVIRONMENT
}
```

**This component is PERFECT.** It already does exactly what we need. We just need to attach it to tiles.

### ExaminationGrid System (NEW)

```gdscript
class_name ExaminationGrid
extends Node3D
## Overlay system for tile-based examination
##
## Creates Area3D nodes with Examinable components for grid tiles.
## Positioned at same world coordinates as GridMap tiles.

# Tile size (must match GridMap cell_size)
const TILE_SIZE = Vector3(2.0, 1.0, 2.0)

# Tile types (must match Grid3D enum)
enum TileType {
    FLOOR = 0,
    WALL = 1,
    CEILING = 2
}

# Tracking
var examination_tiles: Dictionary = {}  # Vector3i -> Area3D

# Generation
func generate_from_grid(grid: Grid3D) -> void:
    """Create examination overlay matching GridMap layout"""

func _create_floor_tile(grid_pos: Vector3i) -> void:
    """Create examinable floor tile at position"""

func _create_wall_tile(grid_pos: Vector3i) -> void:
    """Create examinable wall tile at position"""

func _create_ceiling_tile(grid_pos: Vector3i) -> void:
    """Create examinable ceiling tile at position"""
```

### FirstPersonCamera (SIMPLIFIED)

```gdscript
func get_current_target() -> Examinable:
    """Get what player is looking at (dead simple now)"""
    var hit = get_look_raycast()
    if hit.is_empty():
        return null

    var collider = hit.collider

    # Check if it's directly an Examinable
    if collider is Examinable:
        return collider

    # Check if it has an Examinable child
    return _find_examinable_in_descendants(collider)
```

**That's it. 10 lines. No surface normals. No Y-coordinates. No grid cell lookups.**

---

## Part 5: Detailed Implementation Plan

### Phase 1: Create ExaminationGrid Class (2 hours)

**File**: `/scripts/examination_grid.gd`

**Tasks**:
1. Create class structure with enums and constants
2. Implement `generate_from_grid(grid: Grid3D)` method
3. Implement tile creation methods:
   - `_create_floor_tile(pos)`
   - `_create_wall_tile(pos)`
   - `_create_ceiling_tile(pos)`
4. Add collision shape creation helper
5. Add Examinable component attachment logic

**Acceptance Criteria**:
- Can iterate through Grid3D data
- Creates Area3D for each tile with correct type
- Positions match GridMap visual tiles exactly
- Collision shapes appropriate for each tile type

**Testing**:
```gdscript
# In game_3d.gd _ready():
var exam_grid = ExaminationGrid.new()
add_child(exam_grid)
exam_grid.generate_from_grid(grid_3d)
print("Created %d examination tiles" % exam_grid.examination_tiles.size())
```

---

### Phase 2: Simplify FirstPersonCamera (1 hour)

**File**: `/scripts/player/first_person_camera.gd`

**Tasks**:
1. Remove surface normal classification logic (`_classify_surface_by_normal`)
2. Remove manual grid raycast fallback (`_manual_grid_raycast`)
3. Simplify `get_current_target_or_grid()` to just check for Examinable
4. Update raycast collision mask to layer 8 (Examinable layer)
5. Keep physics raycast query logic (it's fine)

**Before** (current mess):
```gdscript
func get_current_target_or_grid() -> Variant:
    var hit = get_look_raycast()
    if collider is GridMap:
        var surface_type = _classify_surface_by_normal(hit.normal)
        var tile_type = _surface_type_to_tile_type(surface_type)
        # ... 20 more lines of complexity
    var fallback = _manual_grid_raycast()
    # ... 50 more lines of stepping
```

**After** (clean):
```gdscript
func get_current_target() -> Examinable:
    var hit = get_look_raycast()
    if hit.is_empty():
        return null

    var collider = hit.collider
    if collider is Examinable:
        return collider
    return _find_examinable_in_descendants(collider)
```

**Acceptance Criteria**:
- Raycast returns Examinable or null
- No surface normal analysis
- No manual grid traversal
- No Y-coordinate heuristics

---

### Phase 3: Update LookModeState (30 minutes)

**File**: `/scripts/player/states/look_mode_state.gd`

**Tasks**:
1. Change `get_current_target_or_grid()` to `get_current_target()`
2. Remove grid tile handling (now unified with Examinable)
3. Simplify target change detection (just compare Examinable refs)
4. Remove `_get_entity_id_for_tile()` helper (no longer needed)

**Before**:
```gdscript
func process_frame(_delta: float) -> void:
    var new_target = first_person_camera.get_current_target_or_grid()
    if new_target is Examinable:
        # Handle Examinable
    elif new_target is Dictionary:
        # Handle grid tile
        examination_ui.show_panel_for_grid_tile(new_target)
```

**After**:
```gdscript
func process_frame(_delta: float) -> void:
    var new_target = first_person_camera.get_current_target()
    if new_target != current_target:
        current_target = new_target
        if current_target:
            examination_ui.show_panel(current_target)
        else:
            examination_ui.hide_panel()
```

**Acceptance Criteria**:
- Single code path for all examination (tiles and entities)
- No special grid tile handling
- Works with both environment tiles and placed entities

---

### Phase 4: Update ExaminationUI (30 minutes)

**File**: `/scripts/ui/examination_ui.gd`

**Tasks**:
1. Remove `show_panel_for_grid_tile()` method (no longer needed)
2. Unify all examination through `show_panel(target: Examinable)`
3. Remove grid-specific logging
4. Simplify target tracking

**Before**:
```gdscript
func show_panel(target: Examinable) -> void:
    # Handle entities

func show_panel_for_grid_tile(tile_info: Dictionary) -> void:
    # Handle grid tiles differently
```

**After**:
```gdscript
func show_panel(target: Examinable) -> void:
    # Handle ALL examinables the same way
    var info = KnowledgeDB.get_entity_info(target.entity_id)
    entity_name_label.text = info.get("name", "Unknown")
    # ...
```

**Acceptance Criteria**:
- Single show_panel() method handles everything
- No Dictionary handling
- No tile_type matching
- Works identically for tiles and entities

---

### Phase 5: Integrate with Game Scene (1 hour)

**File**: `/scripts/game_3d.gd`

**Tasks**:
1. Instantiate ExaminationGrid in `_ready()`
2. Call `generate_from_grid()` after Grid3D initialization
3. Add debug option to visualize examination layer
4. Ensure proper initialization order

**Code**:
```gdscript
# game_3d.gd
func _ready() -> void:
    # Existing grid generation
    grid_3d = Grid3D.new()
    add_child(grid_3d)
    grid_3d.generate_test_level()

    # NEW: Create examination overlay
    var exam_grid = ExaminationGrid.new()
    exam_grid.name = "ExaminationGrid"
    add_child(exam_grid)
    exam_grid.generate_from_grid(grid_3d)

    Log.system("Examination overlay created: %d tiles" % exam_grid.examination_tiles.size())
```

**Acceptance Criteria**:
- ExaminationGrid generates successfully
- No errors on scene load
- Examination tiles positioned correctly
- Can toggle visibility for debugging

---

### Phase 6: Entity Database Updates (2 hours)

**File**: `/scripts/autoload/entity_registry.gd` (or JSON data)

**Tasks**:
1. Add entity definitions for tile types:
   - `level_0_floor`
   - `level_0_wall`
   - `level_0_ceiling`
2. Write progressive descriptions (discovery levels 0-3)
3. Add clearance-gated information
4. Set appropriate threat levels (all 0 for environment)

**Example Entity**:
```gdscript
{
    "level_0_wall": {
        "name_levels": [
            "Wall",
            "Yellow Wallpaper",
            "Level 0 Wall",
            "Backrooms Office Wallpaper"
        ],
        "description_levels": [
            "A yellow wall.",
            "Greyish-yellow office wallpaper with a faint pattern.",
            "Standard office wallpaper showing moisture damage. Pattern: chevron.",
            "Level 0 environmental feature. Chevron pattern wallpaper, sourced from unknown manufacturer. Moisture retention: high. No anomalous properties detected."
        ],
        "object_class_levels": [
            "[REDACTED]",
            "Safe",
            "Safe",
            "Safe"
        ],
        "threat_level": 0
    }
}
```

**Acceptance Criteria**:
- All three tile types have entity definitions
- Progressive revelation works (discovery level 0 → 3)
- Descriptions match Backrooms wiki lore
- Clearance requirements set appropriately

---

### Phase 7: Testing & Polish (1-2 hours)

**Test Cases**:

1. **Basic Examination**:
   - Enter Look Mode
   - Look at floor → should show "Level 0 Floor" description
   - Look at wall → should show "Level 0 Wall" description
   - Look at ceiling → should show "Level 0 Ceiling" description
   - Verify crosshair changes color correctly

2. **Entity Examination**:
   - Look at TestCube → should show test entity description
   - Verify entities take priority over tiles
   - Verify discovery level increments on first examination

3. **Discovery Progression**:
   - First examination → Discovery level 1 (brief description)
   - Multiple examinations → Discovery level increases
   - Max discovery level 3 → Full detailed description

4. **Performance**:
   - Check framerate in Look Mode
   - Verify no stuttering when moving camera
   - Check memory usage (should be minimal)

5. **Edge Cases**:
   - Look at empty space (no tiles) → should hide panel
   - Rapidly switch between tiles → should update smoothly
   - Enter/exit Look Mode repeatedly → no memory leaks

**Acceptance Criteria**:
- All test cases pass
- No console errors
- Smooth 60 FPS
- Examination data correct for all tile types

---

## Part 6: Benefits of New Architecture

### Code Simplicity

| Metric | Current | New | Change |
|--------|---------|-----|--------|
| Lines of raycast logic | 150+ | ~20 | **-87%** |
| Number of detection methods | 3 | 1 | **-67%** |
| Heuristics/thresholds | 5 | 0 | **-100%** |
| Complexity | High | Low | **Better** |

### Maintainability

**Current System**:
- Change collision shape → breaks detection
- Add slope → breaks Y-coordinate logic
- Multi-level rooms → breaks layer assumptions
- New tile type → must update multiple systems

**New System**:
- Change collision shape → no effect on examination
- Add slope → just create Area3D at angle
- Multi-level rooms → works automatically
- New tile type → add one entity definition

### Extensibility

**Easy Additions**:
- ✅ Per-tile unique descriptions (specific water stains)
- ✅ Damaged/broken variants of tiles
- ✅ Interactable tiles (doors, vents, switches)
- ✅ Dynamic tile states (lights on/off)
- ✅ Tile metadata (last examined time, notes)

**Current System Makes These HARD**:
- ❌ All tiles of same type share entity_id
- ❌ No way to attach per-instance data
- ❌ Can't distinguish two walls in different rooms

### Performance

**Memory Overhead**:
- One Area3D per tile: ~500 bytes
- 128x128 grid = 16,384 tiles maximum
- Worst case: 8 MB (negligible)
- **Optimization**: Only create Area3D for tiles with descriptions

**CPU Performance**:
- Godot's physics engine handles thousands of Area3D efficiently
- Raycast queries are O(log n) via spatial partitioning
- No manual grid traversal overhead
- **Result**: Faster than current manual raycast fallback

**GPU Performance**:
- GridMap rendering unchanged (still batched)
- Area3D has no visual component (zero GPU cost)
- **Result**: Identical rendering performance

---

## Part 7: Migration Strategy

### Step-by-Step Transition

**Week 1 - Implementation** (6-7 hours):
- Day 1: Phases 1-2 (ExaminationGrid + simplified camera)
- Day 2: Phases 3-4 (LookModeState + ExaminationUI)
- Day 3: Phases 5-6 (Integration + entity data)

**Week 2 - Testing** (2-3 hours):
- Day 4: Phase 7 (comprehensive testing)
- Day 5: Polish and optimization

**Week 3 - Cleanup** (1 hour):
- Remove old surface normal logic
- Remove manual grid raycast fallback
- Update documentation

### Rollback Plan

If new system doesn't work:
1. Keep old code in git branch
2. Revert changes to FirstPersonCamera
3. Debug ExaminationGrid separately
4. Can run both systems in parallel for comparison

### Risk Mitigation

**Risk**: Area3D performance issues
**Mitigation**: Start with small test level, profile before full rollout

**Risk**: Collision shape alignment problems
**Mitigation**: Debug visualization mode to see Area3D boxes

**Risk**: Entity data management complexity
**Mitigation**: Use JSON or GDScript resources, not hardcoded

---

## Part 8: Future Enhancements

### After Basic System Works

1. **Per-Tile Unique Descriptions**:
   - Generate entity_id with grid position: `"level_0_wall_71_4"`
   - Procedurally vary descriptions based on position seed
   - "Wall with water stain near bottom" vs "Pristine wall section"

2. **Dynamic Tile States**:
   - Lights can be on/off
   - Doors can be open/closed
   - Vents can be blocked/unblocked
   - Update Examinable entity_id when state changes

3. **Examination History**:
   - Track when each tile was last examined
   - Show "You've examined this before" message
   - Unlock achievements for examining all tiles in a room

4. **Interactive Tiles**:
   - Some tiles respond to examination (doors unlock)
   - Examination can trigger events
   - Integrate with future ability system

5. **Optimization**:
   - Spatial partitioning for examination tiles
   - Only load Area3D within certain radius of player
   - Unload distant tiles from physics system

---

## Part 9: Comparison to Alternatives

### Alternative 1: Keep GridMap, Fix Collision Shapes

**Pros**: Less work upfront
**Cons**:
- Still fighting the engine
- Fragile (any mesh change breaks detection)
- Can't add per-tile metadata
- Still requires surface normal heuristics

**Verdict**: ❌ Kicking the can down the road

### Alternative 2: Pure MultiMeshInstance3D

**Pros**: Maximum control, best performance
**Cons**:
- 14-16 hours migration time
- Complete rewrite of rendering system
- More complex than needed
- Overkill for this project

**Verdict**: ⚠️ Only if rebuilding entire level system

### Alternative 3: Hybrid Overlay (RECOMMENDED)

**Pros**:
- Clean separation of concerns
- Keeps existing rendering
- Industry-standard approach
- Future-proof
- Reasonable time investment

**Cons**:
- Initial 6-7 hour investment
- Slight memory overhead (negligible)

**Verdict**: ✅ **Best balance of quality and effort**

---

## Part 10: Questions to Answer Before Implementation

### Design Decisions

1. **Tile Granularity**:
   - Option A: One Area3D per grid cell (16k nodes)
   - Option B: One Area3D per tile type (3 nodes total)
   - Option C: One Area3D per "interesting" tile (hundreds)
   - **Recommendation**: Start with B, evolve to C as needed

2. **Entity ID Strategy**:
   - Option A: Shared entity_id per tile type ("level_0_wall")
   - Option B: Unique entity_id per position ("level_0_wall_71_4")
   - **Recommendation**: Start with A, add B when needed

3. **Collision Shape Sizes**:
   - Floor: Thin box at Y=0 (size: 2x0.1x2)
   - Wall: Full box at Y=0-4 (size: 2x4x2)
   - Ceiling: Thin box at Y=2.98 (size: 2x0.1x2)
   - **Recommendation**: Match visual tile dimensions exactly

4. **Layer Configuration**:
   - GridMap movement: Layer 2
   - Examinable detection: Layer 8
   - **Recommendation**: Keep separate, no overlap

### Technical Clarifications

1. **Does ExaminationGrid need to be a child of Grid3D?**
   - No, sibling node is cleaner
   - ExaminationGrid queries Grid3D data during generation

2. **Should we generate all tiles or only visible ones?**
   - Start with all tiles for simplicity
   - Add viewport culling later if performance issues

3. **What happens when grid changes dynamically?**
   - Call `examination_grid.regenerate()` after changes
   - Or add/remove individual tiles via API

4. **How do we debug misaligned tiles?**
   - Add debug mode to render Area3D collision shapes
   - Visual comparison with GridMap rendering

---

## Part 11: Success Criteria

### Must Have (MVP)

- ✅ Can examine floor, wall, ceiling in Look Mode
- ✅ Examination panel shows correct entity descriptions
- ✅ No grid cell confusion (floor never says "ceiling")
- ✅ Discovery level tracking works
- ✅ Placed entities (like TestCube) still work
- ✅ No performance regression

### Should Have (Polish)

- ✅ Clean, maintainable code (< 50 lines for raycast)
- ✅ Extensible for future features
- ✅ Debug visualization mode
- ✅ Proper separation of concerns

### Nice to Have (Future)

- ⏳ Per-tile unique descriptions
- ⏳ Dynamic tile states
- ⏳ Examination history tracking
- ⏳ Viewport culling for performance

---

## Conclusion

**Current system**: 150+ lines of fragile heuristics fighting GridMap
**Proposed system**: 20 lines of clean code using proper components

**Time investment**: 6-7 focused hours
**Payoff**: Maintainable, extensible, industry-standard architecture

**Next step**: Review this plan, ask questions, then execute phase by phase.

---

## Appendix: Key Files

**New Files**:
- `/scripts/examination_grid.gd` - Overlay system
- `/data/entities/backrooms_tiles.json` - Entity definitions

**Modified Files**:
- `/scripts/player/first_person_camera.gd` - Simplified raycast
- `/scripts/player/states/look_mode_state.gd` - Unified target handling
- `/scripts/ui/examination_ui.gd` - Remove grid-specific code
- `/scripts/game_3d.gd` - Initialize ExaminationGrid

**Deleted Code** (after migration):
- `_classify_surface_by_normal()` - No longer needed
- `_manual_grid_raycast()` - No longer needed
- `_surface_type_to_tile_type()` - No longer needed
- Surface normal logic - No longer needed

**Total LOC Change**: -130 lines deleted, +150 lines added (net +20)
**Complexity Change**: High → Low
