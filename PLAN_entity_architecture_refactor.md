# Entity Architecture Refactor Plan

## Problem Summary

The current entity system has a fundamental data flow issue:
- `WorldEntity` class exists with proper state management methods (`take_damage()`, `is_alive()`, etc.)
- But SubChunk stores **dictionaries**, not WorldEntity objects
- `EntityRenderer` does dict surgery directly: `entity_data["current_hp"] = new_hp`
- State changes are **never persisted back to SubChunk** = persistence bugs

### Current Data Flow (Broken)
```
SubChunk.world_entities (Array[Dictionary])
    ↓ render_chunk_entities()
EntityRenderer.entity_data_cache (Dict reference to same dicts)
    ↓ damage_entity_at()
AttackExecutor modifies dict directly
    ✗ Changes never sync to SubChunk = persistence bug
```

### Target Data Flow (Fixed)
```
SubChunk.world_entities (Array[WorldEntity])
    ↓ render_chunk_entities()
EntityRenderer reads WorldEntity state (read-only)
    ↓ get_entity_at() returns WorldEntity
AttackExecutor calls WorldEntity.take_damage()
    ↓ WorldEntity emits signals
EntityRenderer updates visuals
    ✓ SubChunk already has the updated WorldEntity
```

---

## Implementation Phases

### Phase 1: Make WorldEntity Authoritative

**Goal**: SubChunk stores WorldEntity objects, not dicts. State changes happen on WorldEntity.

**Files to modify:**
1. `scripts/world/world_entity.gd` - Add signals
2. `scripts/procedural/sub_chunk.gd` - Change `world_entities: Array[Dictionary]` to `Array[WorldEntity]`
3. `scripts/procedural/chunk_manager.gd` - Create WorldEntity objects when spawning
4. `scripts/world/entity_renderer.gd` - Store WorldEntity refs, not dicts; connect to signals

**Changes:**

#### 1.1 WorldEntity - Add signals
```gdscript
signal hp_changed(current_hp: float, max_hp: float)
signal died(entity: WorldEntity)

func take_damage(amount: float) -> void:
    current_hp = max(0.0, current_hp - amount)
    hp_changed.emit(current_hp, max_hp)
    if current_hp <= 0:
        is_dead = true
        died.emit(self)
```

#### 1.2 SubChunk - Store WorldEntity objects
```gdscript
# Before:
var world_entities: Array[Dictionary] = []

# After:
var world_entities: Array[WorldEntity] = []

func add_world_entity(entity: WorldEntity) -> void:
    world_entities.append(entity)

func remove_world_entity(world_position: Vector2i) -> bool:
    for i in range(world_entities.size()):
        if world_entities[i].world_position == world_position:
            world_entities.remove_at(i)
            return true
    return false

func get_entity_at(world_position: Vector2i) -> WorldEntity:
    for entity in world_entities:
        if entity.world_position == world_position:
            return entity
    return null
```

**Serialization**: Keep `to_dict()`/`from_dict()` for future save/load, but runtime uses objects.

#### 1.3 ChunkManager - Create WorldEntity objects
```gdscript
# Before:
var entity_data = {
    "entity_type": "debug_enemy",
    ...
}
subchunk.add_world_entity(entity_data)

# After:
var entity = WorldEntity.new(
    "debug_enemy",
    spawn_pos,
    50.0,  # max_hp
    0      # spawn_turn
)
subchunk.add_world_entity(entity)
```

#### 1.4 EntityRenderer - Connect to WorldEntity signals
```gdscript
# Before:
var entity_data_cache: Dictionary = {}  # Vector2i -> Dictionary

# After:
var entity_cache: Dictionary = {}  # Vector2i -> WorldEntity

func render_chunk_entities(chunk: Chunk) -> void:
    for subchunk in chunk.sub_chunks:
        for entity in subchunk.world_entities:
            if entity.is_dead:
                continue

            var billboard = _create_billboard(entity)
            entity_billboards[entity.world_position] = billboard
            entity_cache[entity.world_position] = entity

            # Connect signals
            entity.hp_changed.connect(_on_entity_hp_changed.bind(entity.world_position))
            entity.died.connect(_on_entity_died_internal)

func _on_entity_hp_changed(current_hp: float, max_hp: float, world_pos: Vector2i) -> void:
    var hp_percent = current_hp / max_hp if max_hp > 0 else 0.0
    _update_health_bar(world_pos, hp_percent)

func _on_entity_died_internal(entity: WorldEntity) -> void:
    # Emit signal for EXP rewards
    entity_died.emit(_entity_to_dict(entity))  # Convert for backwards compat
    # Spawn death VFX
    _spawn_death_emoji(entity.world_position)
    # Delayed removal
    _remove_entity_delayed(entity.world_position, HIT_EMOJI_DURATION)
```

---

### Phase 2: EntityRenderer Only Renders

**Goal**: Remove state management from EntityRenderer. It only creates/destroys visuals.

**Changes:**

#### 2.1 Remove damage_entity_at() from EntityRenderer

The current `damage_entity_at()` does:
1. Modifies HP (state) ❌ → Move to caller
2. Spawns VFX ✓ → Keep
3. Emits death signal ❌ → Move to WorldEntity
4. Removes billboard ✓ → Keep (triggered by signal)

New approach:
```gdscript
# EntityRenderer only has:
func spawn_hit_vfx(world_pos: Vector2i, emoji: String, damage: float) -> void:
    """Spawn floating damage VFX (no state changes)"""
    _spawn_hit_emoji(world_pos, emoji, damage)
```

#### 2.2 AttackExecutor targets WorldEntity directly
```gdscript
# Before:
var success = player.grid.entity_renderer.damage_entity_at(target_pos, attack.damage, attack.attack_emoji)

# After:
var entity = player.grid.get_entity_at(target_pos)
if entity and entity.is_alive():
    entity.take_damage(attack.damage)
    player.grid.entity_renderer.spawn_hit_vfx(target_pos, attack.attack_emoji, attack.damage)
```

#### 2.3 Grid3D gets entity query methods
```gdscript
# Grid3D becomes the entity query interface (delegates to SubChunks)
func get_entity_at(world_pos: Vector2i) -> WorldEntity:
    var chunk = get_chunk_at_world_position(world_pos)
    if chunk:
        var subchunk = chunk.get_sub_chunk_at_tile(world_pos)
        if subchunk:
            return subchunk.get_entity_at(world_pos)
    return null

func get_entities_in_range(center: Vector2i, radius: float) -> Array[WorldEntity]:
    # Query all relevant chunks/subchunks
    ...

func has_entity_at(world_pos: Vector2i) -> bool:
    var entity = get_entity_at(world_pos)
    return entity != null and entity.is_alive()
```

---

### Phase 3: Fix Code Review Items

#### 3.1 Cone targeting duplication (attack_executor.gd)
```gdscript
# Refactor to have one implementation
func _filter_cone_targets(player, candidates: Array[Vector2i]) -> Array[Vector2i]:
    return _filter_cone_targets_from_position(player, candidates, player.grid_position)

func _filter_cone_targets_from_position(player, candidates: Array[Vector2i], from_pos: Vector2i) -> Array[Vector2i]:
    # ... existing implementation (lines 399-437)
```

---

### Phase 4: Decide Entity.gd Role

**Current state:**
- `Entity` (Node3D) exists with AI hooks, movement, damage
- `DebugEnemy extends Entity` exists
- Neither are actually instantiated - system uses WorldEntity data + EntityRenderer billboards

**Options:**

**Option A: Delete Entity.gd** (Recommended for now)
- WorldEntity handles data + state
- EntityRenderer handles visuals
- AI behavior goes in separate AIController that references WorldEntity
- DebugEnemy.gd also deleted (not used)

**Option B: Entity wraps WorldEntity** (Future, for complex AI)
- Entity is runtime behavior wrapper
- WorldEntity is persistence + state
- Entity contains WorldEntity reference
- For Phase 2 enemies with complex AI

**Recommendation**: Option A for now. Delete Entity.gd and DebugEnemy.gd (they're unused). When we need complex enemy AI, we can design a proper system.

---

## File Change Summary

| File | Changes |
|------|---------|
| `world_entity.gd` | Add `hp_changed`, `died` signals |
| `sub_chunk.gd` | `world_entities: Array[WorldEntity]`, new query methods |
| `chunk_manager.gd` | Create WorldEntity objects, not dicts |
| `entity_renderer.gd` | Store WorldEntity refs, connect signals, remove `damage_entity_at()` |
| `attack_executor.gd` | Target WorldEntity directly, fix cone duplication |
| `grid_3d.gd` | Add entity query methods (delegate to SubChunk) |
| `entity.gd` | DELETE (unused) |
| `debug_enemy.gd` | DELETE (unused) |
| `scenes/debug_enemy.tscn` | DELETE (unused) |

---

## Testing Checklist

- [ ] Spawn entity → verify billboard appears
- [ ] Damage entity → verify HP bar updates
- [ ] Kill entity → verify death VFX, EXP awarded
- [ ] Kill entity → leave area → return → verify entity stays dead
- [ ] Damage entity → leave area → return → verify HP persists
- [ ] Multiple enemies in cone attack → all damaged
- [ ] Minimap shows entities correctly
- [ ] Attack preview highlights correct targets

---

## Risks

1. **Signal disconnection on chunk unload**: Need to disconnect WorldEntity signals before unloading
2. **Circular references**: WorldEntity should not hold EntityRenderer ref (use signals)
3. **Serialization for save/load**: Keep `to_dict()`/`from_dict()` working for future save system

---

## Implementation Order

1. **WorldEntity signals** - Add signals, verify existing methods work
2. **SubChunk storage** - Change to Array[WorldEntity]
3. **ChunkManager spawning** - Create objects not dicts
4. **EntityRenderer adaptation** - Store refs, connect signals
5. **Grid3D query methods** - Add entity query interface
6. **AttackExecutor refactor** - Target WorldEntity, fix duplication
7. **Delete unused files** - Entity.gd, DebugEnemy.gd, debug_enemy.tscn
8. **Test everything**
