# v0.7.0 Implementation Plan

## Overview
Seven features for improved onboarding, UI polish, and new content. Branch: `v0.7.0`

---

## Feature 1: Level-Up Perk Hover Explanations

**Problem**: Players don't understand what stats like "NULL" or "Anomaly" mean when choosing level-up perks.

**Approach**: Show examination-panel-style descriptions when hovering/focusing a perk option in the level-up panel. Reuse ExaminationPanel's display pattern.

**Implementation**:
1. Add `PERK_EXPLANATIONS` dict to `level_up_panel.gd` with longer help text per perk
   - e.g. `NULL_PLUS_1`: "Anomaly: controls mana total, mana-based damage, and mana regeneration. Gaining NULL unblocks the mana stat and unlocks new mana-powered attack types."
2. Connect `mouse_entered` / `focus_entered` signals on each perk button to show explanation
3. Add a description label below the perk buttons (or reuse ExaminationPanel via signal)
4. On hover/focus: populate description with `PERK_EXPLANATIONS[perk_type]`
5. On hover exit / focus exit: clear description

**Files Modified**:
- `scripts/ui/level_up_panel.gd` — add explanation dict, hover signals, description label

---

## Feature 2: Minimap Zoom

**Problem**: Minimap is fixed at 1 tile = 1 pixel (256×256 tiles visible). No zoom control.

**Approach**: Add a `zoom_level` variable that controls tiles-per-pixel ratio. Arrow keys (MKB) and D-pad left/right (controller) adjust zoom. The 256×256 image stays the same size but shows fewer tiles when zoomed in.

**Implementation**:
1. Add `zoom_level: int` (1-4, default 1) to `minimap.gd`
   - Zoom 1: 1 tile = 1 pixel (current, 256×256 tile view)
   - Zoom 2: 1 tile = 2 pixels (128×128 tile view)
   - Zoom 3: 1 tile = 3 pixels (85×85 tile view)
   - Zoom 4: 1 tile = 4 pixels (64×64 tile view)
2. Add input actions `minimap_zoom_in` / `minimap_zoom_out` in project.godot
   - MKB: Right arrow / Left arrow
   - Controller: D-pad right / D-pad left
3. Modify `_render_full_map()` to use `view_radius = MAP_SIZE / (2 * zoom_level)` instead of `MAP_SIZE / 2`
4. Modify `_world_to_screen()` to multiply by zoom_level: `relative * zoom_level + center`
5. Scale all marker sizes by zoom_level (player marker, entity markers, item markers)
6. Entity/item sprite rendering (Feature 5) will use zoom_level for sprite size

**Files Modified**:
- `scripts/ui/minimap.gd` — zoom state, scaled rendering
- `project.godot` — new input actions

---

## Feature 3: In-Game Spraypaint Lore Text

**Problem**: Need a way to paint text/emojis on floors and walls for the tutorial level (and future lore).

**Approach**: Create a "spraypaint" system using Label3D nodes placed at world positions with a grungy/hand-painted font. Text is stored in chunk data and rendered like entities/items.

**Implementation**:
1. Find/generate a spraypaint-style font (or use existing monospace with shader effects)
2. Create `SpraypaintText` data class (RefCounted):
   - `text: String`, `position: Vector2i`, `color: Color`, `size: float`
   - `surface: String` ("floor" or "wall"), `rotation: float`
3. Create `SpraypaintRenderer` (Node3D, child of Grid3D):
   - Manages Label3D nodes for spraypaint text in loaded chunks
   - Floor text: Label3D rotated -90° on X axis, placed at Y=0.01 (just above floor)
   - Wall text: Label3D placed at wall face, oriented to face outward
4. Store spraypaint data in SubChunk (new `spraypaint_data: Array[Dictionary]`)
5. Level generators can place spraypaint during generation
6. Tutorial level (Feature 6) will use this extensively

**Files Modified**:
- New: `scripts/world/spraypaint_renderer.gd`
- `scripts/procedural/sub_chunk.gd` — add spraypaint data storage
- `scripts/grid_3d.gd` — instantiate SpraypaintRenderer as child

---

## Feature 4: Codex Panel

**Problem**: Players have no way to review what they've learned about entities/items. KnowledgeDB tracks examination history but has no UI.

**Approach**: Add a "Codex" button to the settings panel. When pressed, opens a scrollable codex panel showing all examined subjects with progressive revelation and redacted info.

**Implementation**:
1. Create `CodexPanel` (Control, similar to LevelUpPanel pattern):
   - Full-screen overlay with scrollable list
   - Categories: "Entities", "Items", "Environment"
   - Each entry shows: name, description (at current clearance), redacted sections
   - Redacted info: show `[REDACTED — CLEARANCE LEVEL X REQUIRED]` placeholder
   - Entries only appear after first examination (from `KnowledgeDB.examined_at_clearance`)
2. Data flow:
   - Query `KnowledgeDB.examined_at_clearance` for all examined subjects
   - For each subject, get info at current clearance via `KnowledgeDB.get_entity_info()`
   - Compare current clearance vs max clearance (5) — if info exists at higher clearance, show redacted
3. Add "Codex" button to `settings_panel.gd` (between FOV slider and Restart button)
4. Button opens codex panel, settings panel hides
5. Codex panel has "Back" button to return to settings

**Files Modified**:
- New: `scripts/ui/codex_panel.gd`
- `scripts/ui/settings_panel.gd` — add Codex button
- `scripts/autoload/knowledge_db.gd` — add `get_all_examined_subjects()` helper

---

## Feature 5: Minimap Entity/Item Sprites

**Problem**: Entities and items show as single-color pixels on the minimap, making them hard to distinguish.

**Approach**: Replace colored pixels with scaled-down versions of actual entity/item sprite textures. Sprites scale dynamically with minimap zoom level.

**Implementation**:
1. Pre-cache minimap sprite images at startup:
   - Load each entity texture from `ENTITY_TEXTURES` dict in entity_renderer.gd
   - Load each item texture (need to map item_id → texture path, similar to entity pattern)
   - Resize each to small icon (e.g., 8×8 base) using `Image.resize()` with LANCZOS
   - Store as `Dictionary[String, Image]` for fast blitting
2. In `_draw_entities()`: instead of drawing 2×2 magenta pixels, blit the cached sprite image
   - Sprite draw size = `base_icon_size * zoom_level` pixels (e.g., 2px at zoom 1, 8px at zoom 4)
   - Use `Image.blit_rect()` to copy sprite pixels onto minimap image
   - Center sprite on entity position
3. In `_draw_discovered_items()`: same approach with item sprites
   - Items without sprites fall back to colored pixel (current behavior)
4. At zoom level 1, sprites may be 2-3px — barely distinguishable but distinct from floor
5. At zoom level 4, sprites are 8-12px — clearly recognizable

**Bug Fix**: Also fix variant wall rendering — replace `cell_item == 1` with `Grid3D.is_wall_tile(cell_item)` at line 260

**Files Modified**:
- `scripts/ui/minimap.gd` — sprite caching, scaled sprite drawing, wall variant fix

---

## Feature 6: Level -1 (Tutorial Level)

**Problem**: New players don't understand basic mechanics (movement, items, combat, minimap).

**Approach**: Create a small hand-crafted tutorial level that teaches core mechanics through forced encounters with spraypaint instructions on the ground.

**Layout**:
```
[Room 1: Spawn] → [Hallway 1] → [Room 2: Item] → [Hallway 2] → [Room 3: Combat] → [Exit]
```

**Implementation**:

### 6a. Level Config
1. Create `level_neg1_config.gd` (extends LevelConfig):
   - `level_id = -1`, `display_name = "Level -1: Training Grounds"`
   - Forest/snowy theme: green-white ambient, fog
   - `permitted_items`: pull from a tutorial item pool (debug_item for now)
   - `exit_destinations = [0]` — exits to Level 0
   - `starting_items = []` — item given in Room 2

### 6b. Level Generator
2. Create `level_neg1_generator.gd` (extends LevelGenerator):
   - **Hand-crafted layout** — no WFC, just direct tile placement
   - Room 1 (8×8): Player spawn, spraypaint "MOVE FORWARD →"
   - Hallway 1 (3×12): Connecting corridor
   - Room 2 (8×8): Single forced item spawn, spraypaint "PICK IT UP"
   - Hallway 2 (3×12): Connecting corridor
   - Room 3 (10×10): Single stationary enemy, spraypaint about auto-attacks
   - Exit area: EXIT_STAIRS tile leading to Level 0
   - Place spraypaint text via SpraypaintRenderer data

### 6c. Tutorial Enemy
3. Create `tutorial_dummy` entity:
   - Register in EntityRegistry with appropriate lore
   - Behavior: stationary (never moves), 0 damage, moderate HP
   - Register in BehaviorRegistry with `TutorialDummyBehavior`
   - `process_turn()` is a no-op

### 6d. Tutorial Item Pool
4. Create tutorial item pool in level config:
   - For now, use `debug_item` as placeholder
   - Every run starts with one item from this pool (given in Room 2)

### 6e. Snowy Forest Theme
5. Visual assets for Level -1:
   - Generate snowy ground texture (white/gray with sparse grass)
   - Generate dark tree bark wall texture
   - Generate dark sky ceiling texture
   - Create new MeshLibrary for Level -1
   - Snow particle shader (GPUParticles3D with billboard particles falling)

### 6f. Game Flow Integration
6. Wire tutorial as starting level:
   - `game_3d.gd`: Start at level -1 instead of level 0
   - `level_manager.gd`: Register level -1 in registry
   - Player spawns in Room 1, plays through tutorial, exits to Level 0
   - Level 0 continues as normal infinite procedural generation

**Files Modified/Created**:
- New: `scripts/resources/level_neg1_config.gd`
- New: `scripts/procedural/level_neg1_generator.gd`
- New: `scripts/ai/behaviors/tutorial_dummy_behavior.gd`
- New: `assets/levels/level_neg1/` (textures, materials, mesh library)
- `scripts/autoload/entity_registry.gd` — register tutorial_dummy
- `scripts/autoload/level_manager.gd` — register level -1
- `scripts/game_3d.gd` — start at level -1
- `scripts/ai/behaviors/behavior_registry.gd` — register tutorial_dummy behavior

---

## Feature 7: Vending Machines

**Problem**: No way to trade resources for items mid-run.

**Approach**: Create a vending machine world object that, when interacted with, presents a selection of items. Player picks one, pays in a % of max HP, SANITY, or MANA (varies per item and per item rarity).

**Implementation**:
1. Create `VendingMachine` data class:
   - `stock: Array[Dictionary]` — each entry: `{item: Item, hp_cost: float, sanity_cost: float}`
   - `position: Vector2i`
   - `used: bool` — one purchase per machine
2. Create `VendingMachineRenderer` or add to existing EntityRenderer:
   - Renders as billboard sprite (generate vending machine texture)
   - Shows interaction prompt when player is adjacent
3. Create `VendingMachinePanel` (Control):
   - Shows available items with costs (HP/Sanity)
   - Player selects one, costs deducted, item added to inventory
   - Panel closes, machine marked as used
4. Create `UseVendingMachineAction` (Action):
   - Validates: player adjacent, machine not used, player can afford cost
   - Executes: deduct costs, give item, mark used
5. Add vending machine spawning to chunk generation:
   - Rare spawn (similar to exit stairs frequency)
   - Stock determined by level's permitted_items + corruption scaling
6. Examinable: register in EntityRegistry with lore text

**Files Modified/Created**:
- New: `scripts/world/vending_machine.gd` (data class)
- New: `scripts/ui/vending_machine_panel.gd`
- New: `scripts/actions/use_vending_machine_action.gd`
- `scripts/world/entity_renderer.gd` or new renderer
- `scripts/procedural/level_0_generator.gd` — vending machine spawn logic
- `scripts/autoload/entity_registry.gd` — vending machine lore

---

## Implementation Order

Features are ordered by dependency — later features build on earlier ones.

1. **Feature 2: Minimap Zoom** — standalone, no dependencies
2. **Feature 5: Minimap Sprites + Wall Bug Fix** — depends on Feature 2 (zoom scaling)
3. **Feature 1: Level-Up Explanations** — standalone, small scope
4. **Feature 3: Spraypaint System** — standalone infrastructure, needed by Feature 6
5. **Feature 4: Codex Panel** — standalone, moderate scope
6. **Feature 6: Tutorial Level** — depends on Feature 3 (spraypaint), largest scope
7. **Feature 7: Vending Machines** — standalone, can be done in parallel with Feature 6

Each feature should be testable independently. Commit after each feature passes user testing.
