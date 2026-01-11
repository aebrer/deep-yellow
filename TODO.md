# Backrooms Power Crawl - Core Gameplay Implementation TODO

**Created**: 2026-01-08
**Last Updated**: 2026-01-11
**Status**: Phase 1-3 COMPLETE - Combat, AI, and Spawning Systems Fully Functional

This document outlines the implementation plan for the remaining core gameplay systems needed to make Backrooms Power Crawl a complete, playable game.

---

## 🎯 Implementation Goals

The game currently has:
- ✅ Turn-based movement system
- ✅ Stats system (BODY, MIND, NULL)
- ✅ Item system with pools (BODY, MIND, NULL)
- ✅ Corruption tracking and escalation
- ✅ Chunk streaming and generation
- ✅ Level progression (EXP, Level, Clearance)
- ✅ UI systems (HUD, inventory, examination)
- ✅ Auto-attack combat system
- ✅ **Real enemy entities** (Bacteria Motherload, Bacteria Spawn with AI)
- ✅ **Enemy AI system** (pathfinding, sense/think/act, target acquisition)
- ✅ **Enemy attacks** (enemies attack player back)
- ✅ **Entity spawning system** (corruption-based, weighted spawn tables)

What we need to add:
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

### 11. HUD & UI Improvements ✅
- **EXP Bar**: Vertical progress bar along left edge of game viewport
  - Fills bottom-to-top as EXP accumulates toward next level
  - Shows current level number in center
  - Glows when close to level up (≥80% progress)
  - Smooth fill animation on EXP gain
- **SCORE Metric**: Composite score on game over screen
  - Formula: `(corruption × 500 × kills × 10) + (EXP / (turns × 0.025))`
  - Uses banker's rounding (round half to even, unbiased)
  - Rewards risk-taking and efficient progression
- **Corruption Display**: Stats panel shows current level corruption
  - Color-coded by severity (gray → purple → magenta)
  - Updates each turn as player explores
- **Utilities Autoload**: Shared functions (banker's rounding) in `scripts/autoload/utilities.gd`
- **Examination Panel**: Embedded in RightSide VBoxContainer below inventory
  - Full width, proper anchoring
  - Shows stat tooltips and entity examination info

### 12. Balance Adjustments ✅
- **Motherload Damage Halved**: Direct damage reduced from 8 → 4
- **Starting HP Regen**: Base 0.1% HP regen per turn (tiny passive recovery)
  - Perks add +0.3% each for meaningful stacking
- **Logging Cleanup**: ~90% of debug logs removed for cleaner output
  - Turn start/end markers preserved for debugging

---

## ✅ COMPLETED: Phase 2 - Real Enemy AI

**Status**: FULLY IMPLEMENTED AND TESTED

### 1. AI Controller Base ✅
- `scripts/ai/entity_ai.gd` - Static utility class with sense/think/act pattern
- Turn-based: AI acts after player turn completes (via ChunkManager)
- Entity types: debug_enemy, bacteria_spawn, bacteria_motherload
- Per-entity state tracking (cooldowns, last seen position, moves remaining)

### 2. Pathfinding Integration ✅
- Uses existing PathfindingManager autoload (A* algorithm)
- Smart sidestep when path blocked by other entities
- Fallback to greedy navigation when pathfinding unavailable
- Wander behavior for entities not tracking player

### 3. Enemy Attack System ✅
- Enemies attack player when in range with LOS
- **Bacteria Spawn**: 1 damage, 1.5 range, must wait after attacking
- **Bacteria Motherload**: 4 damage (halved for balance), 1.5 range, 2 turn cooldown
- Attack VFX spawned on player (🦠 and 🧫 emojis)
- Damage dealt via player.stats.take_damage()

### 4. Entity Behavior Patterns ✅
- **Bacteria Spawn**:
  - 1 move per turn
  - Senses player from 80 tiles away
  - Must wait 1 turn after attacking
  - Probabilistic hold/shuffle in attack range (organic swarm feel)
- **Bacteria Motherload**:
  - 2 moves per turn when player nearby, 1 otherwise
  - Senses player from 32 tiles
  - Spawns bacteria_spawn minions (10 turn cooldown)
  - Must wait after spawning, not after attacking
  - Wanders when player not sensed

---

## ✅ COMPLETED: Phase 3 - Entity Spawning System

**Status**: FULLY IMPLEMENTED AND TESTED

### 1. EntitySpawner System ✅
- Integrated into ChunkManager._spawn_entities_in_chunk()
- Uses LevelConfig.entity_spawn_table for entity types and weights
- Weighted spawn selection based on corruption and threat level

### 2. Corruption-Based Scaling ✅
- Entity count scales with corruption: BASE + (corruption × ENTITIES_PER_CORRUPTION)
- Entity HP scales with corruption via hp_scale multiplier
- Higher threat entities become MORE common at high corruption
- Lower threat entities become LESS common at high corruption
- Corruption threshold per entity type (minimum corruption to spawn)

### 3. Entity Persistence ✅
- WorldEntity.is_dead flag tracks killed entities
- Dead entities excluded from AI processing and rendering
- SubChunk.get_living_entities() filters out dead entities
- WorldEntity.to_dict()/from_dict() for chunk save/load (future)

### 4. Level 0 Entity Configuration ✅
- `scripts/resources/level_00_config.gd` with entity_spawn_table
- bacteria_spawn: weight 10, 100 HP, threat 1, +50% HP/corruption
- bacteria_motherload: weight 3, 500 HP, threat 3, +100% HP/corruption, requires 0.3 corruption

---

## 📋 Remaining Implementation Phases

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
- [x] **Entity HP scaling**: Scales with corruption via hp_scale multiplier
- [x] **Spawn density tuning**: BASE_ENTITIES + corruption × ENTITIES_PER_CORRUPTION
- [x] **Entity persistence**: Dead entities tracked via is_dead flag
- [x] **AI turn budget**: All entities in loaded chunks act each turn
- [x] **Pathfinding refresh**: Every turn, with intelligent sidestep fallback

### Still Open ❓
- [ ] **Item variety**: What effects should items have?
- [ ] **Level exit placement**: Fixed location or procedural?

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

### AI Architecture
- Static utility class (EntityAI) works well for simple behaviors
- WorldEntity holds ALL state - AI just reads/modifies it
- Sense/Think/Act pattern keeps logic organized
- Pathfinding should be terrain-only, entity collision checked at move time

### Documentation Prevents Bugs
- Clear docstrings prevent future agents from misusing systems
- "CRITICAL" warnings in class headers catch attention
- Example: Camera direction warning saved debugging time

---

## 🚀 Next Steps

**Immediate Priority**: UI Polish
- ✅ Move/shrink examination panel (right side under inventory) - DONE
- Portrait mode examination panel overlay
- Any other HUD adjustments as needed

**Then**: Phase 4 - Item Variety
- More item types beyond Debug Item
- Attack modifiers and special effects

**Testing Focus**:
- Combat feels good with current visual feedback ✅
- Balance tuning with real enemies ✅
- Performance testing with many active AI entities

---

*This is a living document - update as implementation progresses*
