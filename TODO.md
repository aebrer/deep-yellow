# Backrooms Power Crawl - Core Gameplay Implementation TODO

**Created**: 2026-01-08
**Last Updated**: 2026-01-10
**Status**: Phase 1 COMPLETE - Combat System Fully Functional

This document outlines the implementation plan for the remaining core gameplay systems needed to make Backrooms Power Crawl a complete, playable game.

---

## 🎯 Implementation Goals

The game currently has:
- ✅ Turn-based movement system
- ✅ Stats system (BODY, MIND, NULL)
- ✅ Item system with pools (BODY, MIND, NULL, LIGHT)
- ✅ Corruption tracking and escalation
- ✅ Chunk streaming and generation
- ✅ Level progression (EXP, Level, Clearance)
- ✅ UI systems (HUD, inventory, examination)
- ✅ **Auto-attack combat system** (NEW!)
- ✅ **Debug enemy spawning** (NEW!)
- ✅ **Combat visual feedback** (NEW!)

What we need to add:
- ❌ **Real enemy entities** (Bacteria Brood Mother, Bacteria Spawn with actual AI)
- ❌ **Enemy AI system** (pathfinding, behavior trees, target acquisition)
- ❌ **Enemy attacks** (enemies attack player back)
- ❌ **More items** (variety for Level 0)
- ❌ **Staircase exit** (Level 0 → Level 1 transition)

---

## ✅ COMPLETED: Phase 1 - Combat System Foundation

**Status**: FULLY IMPLEMENTED AND TESTED

### 1. Debug Enemy System ✅
- Debug enemies spawn in chunks for combat testing
- 20 enemies per chunk (configurable via `DEBUG_ENEMIES_PER_CHUNK`)
- 50 HP each (was 1100, reduced for faster iteration)
- Stationary punching bags - don't move or attack
- Uses WorldEntity data pattern (like items)
- Rendered via EntityRenderer with billboard sprites

### 2. Auto-Attack System ✅
- `scripts/combat/attack_executor.gd` - Handles all attack execution
- `scripts/combat/attack_types.gd` - Constants and enums for attack types
- `scripts/combat/pool_attack.gd` - Attack instance with modifiers applied
- Three attack types: BODY (punch), MIND (whistle), NULL (anomaly burst)
- Auto-targeting: Finds nearest enemy in range automatically
- Cooldown system: Each attack type has independent cooldown
- **CRITICAL**: This is an AUTO-BATTLER - camera direction is NEVER used for targeting

### 3. Attack Types Implementation ✅
- **BODY**: Range 1.5, damage 5, cooldown 1 turn, SINGLE target, scales with STRENGTH (+10%/pt)
- **MIND**: Range 3.0, damage 3, cooldown 5 turns, AOE_AROUND, scales with PERCEPTION (+20%/pt)
- **NULL**: Range 3.0, damage 5, cooldown 4 turns, CONE, scales with ANOMALY (+50%/pt), costs 5 mana

### 4. Line-of-Sight System ✅
- `Grid3D.has_line_of_sight()` - Bresenham's algorithm for LOS checks
- Walls block attacks (can't shoot through walls)
- Entities do NOT block attacks (AOE can hit multiple enemies in a row)
- LOS filtering happens before area-type filtering

### 5. Cone Attack Auto-Targeting ✅
- Cone attacks automatically aim toward nearest enemy
- All enemies within 45° of that direction are hit
- Camera direction is irrelevant (auto-battler design)

### 6. Attack Preview & Targeting ✅
- Visual highlight on targetable enemies (red tint)
- Action preview UI shows attack name, damage, target count
- Preview updates based on movement indicator position
- Shows "X targets for Y dmg" format
- Mana cost displayed for NULL attacks

### 7. Combat Visual Feedback ✅
- Floating emoji VFX when attacks hit (👊, 📢, ✨)
- Floating damage numbers alongside emoji
- Death skull emoji (💀) on kill (2x size)
- Health bars appear when entity damaged (shader-based)
- Health bars hidden at full HP, visible when damaged

### 8. EXP & Leveling System ✅
- EXP awarded on enemy death (base 10 EXP per kill)
- Clearance level multiplies EXP gains (+10% per clearance)
- Level up triggers perk selection UI
- EXP formula: BASE × ((level + 1) ^ 1.5)
- Weighted perk selection (Clearance is rare)

### 9. Damage Scaling ✅
- Banker's rounding (round half to even, like Python)
- Stat scaling: damage *= (1.0 + stat_value * scaling_rate)
- Item modifiers: ADD first, then MULTIPLY
- Minimum cooldown of 1 turn enforced

### 10. Entity Renderer System ✅
- `scripts/world/entity_renderer.gd` - Manages entity billboards
- Integrates with chunk loading/unloading
- Examination support (Examinable component)
- Minimap integration (entities shown as dots)

---

## 📋 Remaining Implementation Phases

### Phase 2: Real Enemy AI (Priority: HIGH)
**Goal**: Enemies move toward player and attack back

1. **AI Controller Base**
   - `scripts/ai/ai_controller.gd` - Base AI decision tree
   - Turn-based: AI acts after player turn completes
   - Sense → Think → Act pattern
   - **Dependencies**: None (uses existing entity system)

2. **Pathfinding Integration**
   - Reuse existing PathfindingManager (A* algorithm)
   - Move toward player each turn
   - Stop when in attack range
   - **Dependencies**: AI Controller

3. **Enemy Attack System**
   - Enemies use same attack system as player
   - Bacteria Spawn: weak BODY attacks, high frequency
   - Bacteria Brood Mother: strong BODY attacks, spawns minions
   - **Dependencies**: AI Controller, Pathfinding

4. **Entity Templates**
   - Data-driven entity definitions
   - `assets/entities/bacteria_spawn.tres`
   - `assets/entities/bacteria_brood_mother.tres`
   - Stats, attack patterns, spawn weights

### Phase 3: Entity Spawning System (Priority: MEDIUM)
**Goal**: Replace debug enemies with proper spawning

1. **EntitySpawner System**
   - Like ItemSpawner but for entities
   - Spawn probabilities based on corruption
   - Per-level configuration

2. **Corruption-Based Scaling**
   - Low corruption: 0-2 entities per chunk
   - High corruption: 5-10 entities per chunk
   - Entity HP/damage scales with corruption

3. **Entity Persistence**
   - Killed entities stay dead (per-chunk tracking)
   - Entities persist with chunk save/load

### Phase 4: Items & Variety (Priority: MEDIUM)
**Goal**: More items to find, build diversity

1. **Level 0 Item Roster** (10-15 items)
   - BODY: Brass Knuckles, Pipe, Baseball Bat
   - MIND: Journal, Map, Focus Crystal
   - NULL: Void Shard, Strange Coin, Anomalous Object

2. **Item Effect System**
   - Attack modifiers (damage_add, range_add, cooldown_add)
   - Attack emoji customization
   - Special effects (lifesteal, multi-hit, etc.)

### Phase 5: Level Exit & Progression (Priority: LOW)
**Goal**: Can progress to Level 1

1. **Staircase Entity**
   - Rare spawn in explored chunks
   - Interactable for level transition

2. **Level Transition System**
   - Save player state
   - Load new level configuration
   - Reset chunks, keep stats/items

---

## 🤔 Design Decisions - Status

### Resolved ✅
- [x] **Auto-attack vs Manual attack**: AUTO-ATTACK (turn-based auto-battler)
- [x] **Attack range indicators**: Dual system (visual highlight + action preview UI)
- [x] **Attack frequency**: Turn-based cooldowns per attack type
- [x] **Cone targeting**: Auto-aim at nearest enemy (not camera direction)
- [x] **LOS blocking**: Walls block attacks, entities don't

### Still Open ❓
- [ ] **Entity HP scaling**: Scale with corruption? Player level? Both?
- [ ] **Spawn density tuning**: How many entities feels right?
- [ ] **Entity persistence**: Clear chunks stay clear, or respawn?
- [ ] **AI turn budget**: All entities act, or only nearby ones?
- [ ] **Pathfinding refresh rate**: Every turn, or staggered?

---

## 🎓 Lessons Learned (This Branch)

### Auto-Battler Design
- Camera direction should NEVER affect attack targeting
- Attacks auto-target nearest enemy (or nearest for cone direction)
- Player agency is in positioning and build, not aiming

### Visual Feedback is Critical
- Floating damage numbers + emoji = satisfying hits
- Health bars should only appear when damaged
- Death effects (skull emoji) communicate kills clearly

### Line-of-Sight Matters
- Bresenham's algorithm works well for grid-based LOS
- Check intermediate tiles only (not start/end positions)
- Walls block attacks, but entities should NOT block (allows AOE)

### Documentation Prevents Bugs
- Clear docstrings prevent future agents from misusing systems
- "CRITICAL" warnings in class headers catch attention
- Example: Camera direction warning saved debugging time

---

## 🚀 Next Steps

**Immediate Priority**: Phase 2 - Enemy AI
- Enemies currently just stand there
- Need movement toward player
- Need enemy attacks (player takes damage)

**Testing Focus**:
- Combat feels good with current visual feedback
- Balance tuning needed once enemies fight back
- Performance testing with many active AI entities

---

*This is a living document - update as implementation progresses*
