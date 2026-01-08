# Backrooms Power Crawl - Core Gameplay Implementation TODO

**Created**: 2026-01-08
**Status**: Planning Phase - Post-Vacation Development Push

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

What we need to add:
- ❌ **Enemy entities** (Bacteria Brood Mother, Bacteria Spawn)
- ❌ **Enemy AI system** (pathfinding, behavior trees, target acquisition)
- ❌ **Attack/Combat system** (BODY, MIND, NULL attack types with range/area/frequency)
- ❌ **Entity spawning** (corruption-based, per-chunk on load)
- ❌ **More items** (variety for Level 0)
- ❌ **Staircase exit** (Level 0 → Level 1 transition)

---

## 📋 Implementation Order & Dependencies

### Phase 1: Combat System Foundation + Debug Enemy
**Goal**: AUTO-BATTLER COMBAT - Player moves, attacks happen automatically

**CRITICAL DESIGN**: This is a **turn-based auto-battler** like Vampire Survivors!
- Player does NOT manually attack
- Player just moves and manages build
- Attacks happen automatically based on equipped items
- Fast-paced, dopamine-rich gameplay

1. **Debug Enemy First** ⭐ START HERE
   - `scripts/entities/debug_enemy.gd` - Simple test enemy
   - Spawns once per chunk (guaranteed)
   - **Tons of HP** (1000+) so it doesn't die during testing
   - Does NOT attack back (yet)
   - Does NOT move (yet)
   - Just stands there as a punching bag
   - **Why first**: Need something to attack to test combat!
   - **Testing**: Walk around, see debug enemies in every chunk

2. **Auto-Attack System Base Classes**
   - `scripts/combat/attack.gd` - Base Attack class (like Action pattern)
   - `scripts/combat/attack_executor.gd` - Handles attack resolution
   - Attack properties: damage, range, area, frequency, attack_type (BODY/MIND/NULL)
   - **AUTO-TARGETING**: Finds nearest enemy in range
   - **FREQUENCY**: Attacks every N turns automatically
   - **Why second**: Foundation for auto-battler combat
   - **Testing**: Player auto-attacks debug enemies when in range

3. **Attack Types Implementation**
   - BODY attacks: short range (1-2 tiles), physical damage, high frequency (every 1-2 turns)
   - MIND attacks: medium range (3-5 tiles), sanity damage, medium frequency (every 3-5 turns)
   - NULL attacks: long range (5-10 tiles), anomalous damage, low frequency (every 5-10 turns)
   - Area effects (single tile, 3x3, line, cone, etc.)
   - **Why third**: Defines the combat design space before complex items
   - **Testing**: Each attack type behaves distinctly, respects stat scaling

4. **Player Auto-Attack Integration**
   - Player automatically attacks each turn (in ExecutingTurnState or PostTurnState)
   - No manual input required
   - Item pools execute → attacks happen
   - Visual feedback (projectiles, damage numbers, hit effects)
   - **Why fourth**: Makes combat functional without manual control
   - **Testing**: Walk near debug enemy, see automatic attacks, HP drops

5. **Attack Preview & Targeting Indicators**
   - **Visual highlight**: Shader effect on targetable enemies (glow, outline, etc.)
     - Show in IdleState (between turns when player can see what will happen)
     - Enemies in range for next turn get highlighted
   - **Action preview UI**: Update existing ActionPreviewUI system
     - Show "Attack [Enemy Name]" when enemy in range
     - Preview updates based on movement indicator position
     - Example: "Move forward → Attack Bacteria Spawn"
   - **Why fifth**: Player needs to understand what will happen before committing
   - **Testing**: Can tell which enemies will be attacked before moving

---

### Phase 2: Entity Foundation (Still No AI)
**Goal**: Entities exist in world, have stats, can take damage, but don't act yet

**IMPORTANT - Minimap Integration**:
- Entities should appear on minimap (different color from player)
- Architecture should support this from the start
- May tie to specific items later (e.g., "Enemy Radar" item)
- For now: Always show entities on minimap for testing

4. **Entity Base Class**
   - `scripts/entities/entity.gd` - Base class extending Node3D
   - Has StatBlock (reuse player's stat system)
   - Has visual representation (billboard sprite like items)
   - Position on grid, collision with player
   - **Why fourth**: Reuses StatBlock, can test entity spawning/rendering
   - **Testing**: Entities spawn in world, visible, have HP, take damage from player attacks

5. **Entity Visual System**
   - `scripts/entities/entity_renderer.gd` - Billboard sprites for entities
   - Health bars (optional, shows on hover/damage)
   - Death animations (fade out, particle effects)
   - **Why fifth**: Immediate visual feedback for testing
   - **Testing**: Can see entities, health changes are visible

6. **Entity Templates for Level 0**
   - `scripts/resources/bacteria_spawn_template.gd` - Weak enemy stats
   - `scripts/resources/bacteria_brood_mother_template.gd` - Strong enemy stats
   - Defines base stats, HP, damage resistance, loot drops
   - **Why sixth**: Data-driven entity configuration
   - **Testing**: Different entity types have different stat profiles

---

### Phase 3: Entity Spawning (Entities Exist But Still Don't Act)
**Goal**: Entities spawn when chunks load, respecting corruption

7. **Entity Spawner System**
   - `scripts/world/entity_spawner.gd` - Like ItemSpawner but for entities
   - Spawn probabilities increase with corruption
   - Bacteria Spawn: common, increases with corruption (positive multiplier)
   - Bacteria Brood Mother: rare, moderate increase with corruption
   - **Why seventh**: Reuses ItemSpawner pattern, hooks into chunk loading
   - **Testing**: Walk around, see entity density increase over time

8. **EntityRegistry Integration**
   - Register entity templates in EntityRegistry autoload
   - Provide entity info (descriptions) for examination system
   - Clearance-based revelation for entity details
   - **Why eighth**: Reuses existing knowledge/examination systems
   - **Testing**: Can examine entities, see descriptions based on Clearance

9. **Chunk Loading Integration**
   - Hook entity spawner into ChunkManager (like items)
   - Spawn entities once per chunk on load
   - Store entities per chunk for unloading/reloading
   - **Why ninth**: Ensures entities persist with chunks
   - **Testing**: Entities spawn when entering new chunks, persist when returning

---

### Phase 4: AI & Behavior (Entities Finally Act!)
**Goal**: Entities move toward player and attack

10. **AI Base System**
    - `scripts/ai/ai_controller.gd` - Base AI controller class
    - Turn-based: AI acts on player turn completion
    - Decision tree: sense → think → act
    - **Why tenth**: Foundation for all entity behaviors
    - **Testing**: Entities take turns, log their decisions

11. **Basic Pathfinding AI**
    - Reuse PathfindingManager (A* to player position)
    - Move toward player each turn
    - Stop when in attack range
    - **Why eleventh**: Reuses existing pathfinding, simple behavior
    - **Testing**: Entities chase player, stop at attack range

12. **Attack Behavior**
    - Entities use Attack system (reuse player's attack system)
    - Auto-attack player when in range
    - Bacteria Spawn: BODY attacks (weak, frequent)
    - Bacteria Brood Mother: BODY attacks (strong, summons adds)
    - **Why twelfth**: Reuses attack system, makes combat functional
    - **Testing**: Entities attack player, player loses HP

13. **Special Abilities**
    - Bacteria Brood Mother: Spawn Bacteria Spawn as bonus action
    - Frequency: every N turns
    - Spawns near mother's position
    - **Why thirteenth**: Adds variety, tests entity spawning from entities
    - **Testing**: Brood Mother spawns minions during combat

---

### Phase 5: Combat Polish & Balance
**Goal**: Combat feels good, challenge is appropriate

14. **Attack Visual Effects Architecture**
    - **CRITICAL**: Design for per-item cosmetic customization
    - Base attack types have default visuals:
      - BODY: Melee slash/punch effects
      - MIND: Psychic waves/pulses
      - NULL: Anomalous distortions/glitches
    - Items override with custom effects:
      - Example: "Brass Knuckles" → yellow punch particles
      - Example: "Psychic Crown" → purple mind wave
      - Example: "Void Shard" → black hole distortion
    - Effect components: projectile sprite, trail particles, impact particles, screen shake
    - **Architecture**: AttackEffect resource (like Item) with visual properties
    - Items specify: `attack_effect: AttackEffect` (defaults to base type if null)
    - **Why fourteenth**: Cool visuals = dopamine = fun!
    - **Testing**: Each item feels unique and satisfying to use
    - **Note**: Sound engineering comes MUCH later (focus on visuals now)

15. **Damage Numbers & Feedback**
    - Floating damage numbers (sprite-based or label)
    - Screen shake on hit (optional)
    - Sound effects (hit, death, attack)
    - **Why fifteenth**: Polish makes testing more enjoyable
    - **Testing**: Can tell what's happening in combat

16. **Death & Respawn**
    - Player death: game over screen, restart option
    - Entity death: drop loot (items), award EXP
    - **Why sixteenth**: Closes the gameplay loop
    - **Testing**: Dying matters, killing enemies is rewarding

---

### Phase 6: Items & Variety
**Goal**: More items to find, build variety

17. **Level 0 Item Roster**
    - BODY items: Brass Knuckles, Pipe, Baseball Bat, etc.
    - MIND items: Journals, Maps, Mental Focus items
    - NULL items: Anomalous artifacts, strange objects
    - LIGHT items: Flashlights, glowsticks, torches
    - **Quantity goal**: 10-15 items total (3-4 per pool)
    - **Why seventeenth**: Variety comes after core systems work
    - **Testing**: Multiple build paths, item synergies emerge

18. **Item Effects Implementation**
    - Active abilities (press button to activate)
    - Passive effects (stat bonuses, auras)
    - On-turn effects (regeneration, periodic damage)
    - **Why eighteenth**: Makes items interesting, not just stat sticks
    - **Testing**: Items feel unique, create build diversity

---

### Phase 7: Level Exit & Progression
**Goal**: Can progress to Level 1

19. **Staircase Entity**
    - Rare spawn, appears in explored chunks
    - Interactable: "Press E to descend"
    - Triggers level transition
    - **Why nineteenth**: Simple after entity system exists
    - **Testing**: Can find stairs, transition to new level

20. **Level Transition System**
    - Save current state (player stats, inventory)
    - Unload Level 0 chunks
    - Load Level 1 (new generator, new config)
    - Reset player position, keep stats/items
    - **Why twentieth**: Reuses existing level loading systems
    - **Testing**: Smooth transition, stats persist

---

## 🤔 Design Decisions Needed

These questions should be answered BEFORE implementing the relevant phase:

### Combat System (Phase 1)
- [x] **Auto-attack vs Manual attack**: ✅ **DECIDED - AUTO-ATTACK**
  - This is a **turn-based auto-battler** like Vampire Survivors
  - Player moves and manages build, attacks happen automatically
  - No manual attack button (unless special item abilities later)
  - Focus is on positioning, build planning, and fast-paced movement

- [x] **Attack range indicators**: ✅ **DECIDED - Dual system**
  - **Visual highlight**: Shader effect on targetable enemies (shown between turns in IdleState)
  - **Action preview UI**: Text showing "Attack [Enemy Name]" when enemy in range
  - Updates based on player's next action:
    - When movement indicator shows next position → preview attacks from that position
    - When in look mode (waiting) → preview attacks from current position
  - **Why dual**: Visual feedback for positioning + explicit UI for planning

- [x] **Attack frequency**: ✅ **DECIDED - Turn-based cooldowns**
  - Each attack type has a frequency (attacks every N turns)
  - BODY: every 1-2 turns (high frequency)
  - MIND: every 3-5 turns (medium frequency)
  - NULL: every 5-10 turns (low frequency)
  - Items can modify frequency (faster attacks = more DPS)

### Entity System (Phase 2-3)
- [ ] **Entity HP scaling**: Should entity HP scale with player level? Corruption? Both?
  - **Recommendation**: Scale with corruption (ties to level exploration)

- [ ] **Spawn density**: How many entities per chunk?
  - Low corruption: 0-2 entities per chunk
  - High corruption: 5-10 entities per chunk
  - **Recommendation**: Start conservative, tune based on testing

- [ ] **Entity persistence**: Do entities respawn when chunks unload/reload?
  - Option A: Entities persist with chunks (if you clear a chunk, it stays clear)
  - Option B: Entities respawn each time chunk loads (infinite enemies)
  - **Recommendation**: Option A (reward clearing areas)

### AI System (Phase 4)
- [ ] **AI turn budget**: How many entities can act per turn?
  - Option A: All entities in loaded chunks act each turn
  - Option B: Only entities near player act (performance optimization)
  - Option C: Stagger entity turns (some act every other turn)
  - **Recommendation**: Option B (entities in ACTIVE_RADIUS only)

- [ ] **Pathfinding refresh**: How often do entities recalculate path?
  - Every turn: Expensive but responsive
  - Every N turns: Cheaper, entities lag behind player
  - **Recommendation**: Every turn for entities in combat range, every 3 turns for distant entities

---

## 🎓 Lessons Learned & Patterns to Follow

### Reuse Existing Systems
- **StatBlock** works great for player → reuse for entities
- **ItemSpawner** pattern → EntitySpawner uses same approach
- **Action pattern** (movement, wait) → Attack is just another action
- **ChunkManager hooks** → Items spawn on chunk load → entities do same

### Test Incrementally
- Phase 1: Attack empty space (tests mechanics without AI complexity)
- Phase 2: Entities exist but don't act (tests spawning, rendering)
- Phase 3: Entities spawn (tests integration with chunks)
- Phase 4: Entities act (finally functional combat)

### Data-Driven Design
- Entity templates define stats (not hardcoded in entity scripts)
- Attack templates define damage/range/area
- Spawn configs define probabilities
- **Why**: Easy to balance, easy to add new content

### Performance Considerations
- Only AI-process entities near player (ACTIVE_RADIUS = 3 chunks)
- Entities far from player "freeze" (no pathfinding, no updates)
- Unload entities with chunks (don't keep all entities in memory)

---

## 📝 Notes & Open Questions

### Implementation Philosophy
- **Quality over speed**: Each phase should be fully working before moving on
- **Test early, test often**: Add debug visualizations (attack range, AI state, etc.)
- **Document as you go**: Update CLAUDE.md with new patterns/lessons

### Future Considerations (Post-MVP)
- Advanced AI: Fleeing, grouping, special behaviors
- More attack types: Status effects, AOE, DOT
- Boss entities: Unique mechanics, multi-phase fights
- Ally entities: Summons, pets, friendly NPCs
- Level-specific mechanics: Hazards, traps, environmental dangers

### User Testing Checklist
After each phase, user should test:
- [ ] **Functionality**: Does it work as designed?
- [ ] **Performance**: Does it run smoothly? (60 FPS target)
- [ ] **Feel**: Does it feel good to play?
- [ ] **Balance**: Is difficulty appropriate?
- [ ] **Bugs**: Any edge cases or crashes?

---

## 🚀 Next Steps

**Immediate Action**: Review this TODO with user, discuss design decisions

**Questions for User**:
1. Does this implementation order make sense?
2. Which design decisions do you want to make now vs later?
3. Should we start with Phase 1 (Combat System Foundation)?
4. Any concerns or additional features to add?

**After Approval**: Create detailed implementation plan for Phase 1, begin coding

---

*This is a living document - update as implementation progresses and new insights emerge*
