# Backrooms Power Crawl - Design Document

## Core Concept

A top-down roguelike combining Caves of Qud's deep simulation and character building with Vampire Survivors' automatic combat and horde survival mechanics, set in the liminal horror of the Backrooms universe.

## Inspirations

### Caves of Qud
- Deep character mutation/build system
- Emergent gameplay through physics simulation (liquids, temperature, materials)
- Vast generative tree of options and combinations
- Turn-based tactical decision making
- Esoteric and weird world-building

### Vampire Survivors
- Automatic combat - player focuses on positioning and movement
- Escalating enemy hordes
- Build-focused gameplay loop
- Quick runs with meaningful progression
- Simple controls, deep strategy

### The Backrooms / SCP Foundation
- Liminal spaces and reality-bending horror
- Procedurally generated levels with distinct themes
- Entity catalog with specific behaviors and containment procedures
- Information as progression reward (redacted → revealed)
- Environmental storytelling

## Core Gameplay Loop

1. **Hub Area**: Prepare for expeditions, interact with NPCs, review knowledge database
2. **Movement & Positioning**: Player navigates tile-based Backrooms levels
3. **Mission Completion**: Survive hordes OR hunt/contain specific entities
4. **Automatic Combat**: Equipped abilities/mutations trigger automatically based on conditions
5. **Build Evolution**: Gain mutations, abilities, and anomalies during runs
6. **Examination & Knowledge**: Use right stick to examine environment, learning entity behaviors and hazards
7. **Physics Interaction**: Combine items, liquids, and environmental elements strategically
8. **Return to Hub**: Process discoveries, gain knowledge, prepare for next run

## Mission Types

### Horde Missions (Survival Focus)
- **Goal**: Survive for X minutes or kill Y entities
- **Gameplay**: Classic Vampire Survivors - positioning, kiting, crowd control
- **Rewards**: Combat-focused mutations, offensive abilities
- **Build priority**: Damage, survivability, area control
- **Playstyle**: Aggressive, high-tempo

### Hunt Missions (Research/Containment Focus)
- **Goal**: Locate and contain specific entities without killing them
- **Gameplay**: Stealth, tracking, specialized containment tools
- **Rewards**: Knowledge, research data, containment equipment
- **Build priority**: Mobility, detection, non-lethal abilities
- **Playstyle**: Methodical, strategic, risk-management

### Design Tension
**Player must choose builds that excel at ONE priority:**
- Pure survival builds sacrifice research capability
- Research builds are vulnerable in combat
- Hybrid builds are viable but less specialized
- Mission type is revealed before departure (informed decision)
- Some abilities hurt one goal while helping another:
  - Loud AoE damage great for hordes, terrible for hunts
  - Stealth field perfect for hunts, useless in survival
  - Entity attraction helpful for hunts, deadly in hordes

## Visual Design

### Art Style
- **Tile-based with simple sprites**: Clean, readable pixel art or minimalist graphics
- **Graphical corruption as theme**:
  - Shader effects: glitch, chromatic aberration, pixel displacement
  - Corruption intensity based on:
    - Proximity to entities
    - Player corruption level
    - Reality stability
    - Current Backrooms level

### UI/UX

**Layout** (Implemented):
- **3D Viewport** (top-left): PSX-style 3D world at 640x480 with vertex wobble, affine textures, dithering
- **Character Sheet** (right panel): Stats (HP, Sanity, Mana), resource pools, turn counter, position
- **Core Inventory** (right panel): Build-defining items in Body/Mind/NULL/Light pools
- **Game Log** (bottom panel): Real-time event stream with color-coded messages
- **Terminal Aesthetic**: IBM Plex Mono font, minimal black panels, lowercase text

**HUD Indicators** (Planned):
- **Turn Preview**: "What Happens Next" action list with target indicators
- **Sound Level**: Visual indicator of local ambient noise + player noise generation
- **Light Level**: Current position's brightness + light source status
- **Danger Meter**: Corruption/escalation level for current area
- **Resource Pools**: HP/Sanity/Mana bars with current/max values

**Log System** (Implemented):
- Live game event feed in bottom panel
- Color-coded by severity:
  - ERROR: red - critical failures
  - WARN: yellow - unexpected events
  - INFO: white - important actions
  - DEBUG: light gray - state changes
  - TRACE: dark gray - verbose details
- Abbreviated category tags: [sys], [state], [move], [action], [turn], etc.
- Connected to centralized Logger autoload

**Log Revelation Mechanics** (Planned):
- **Items control log visibility**:
  - Base state: Only INFO/WARN/ERROR logs visible
  - "Diagnostic Scanner" item: Reveals DEBUG logs
  - "System Analyzer" item: Reveals TRACE logs
  - "Corrupted Terminal" item: Adds glitch/noise to logs
  - "Clearance Badge" tiers: Unlock specific categories
- **Progression through information**:
  - Early game: Minimal logs, vague descriptions
  - Late game: Full diagnostic access, complete information
- **Tie-in to knowledge system**: Log detail correlates with entity/hazard knowledge

**Menu Navigation** (Planned):
- **Pause System**:
  - Press START/ESC to pause game
  - Pausing makes UI panels selectable/scrollable
  - D-pad/left stick: Navigate between panels
  - A button: Select/expand items
  - B button: Back/close
- **Controller-first design**:
  - All UI elements accessible via gamepad
  - Smooth scrolling with analog stick
  - Face buttons for quick actions
- **Seamless transition**: Unpause returns to gameplay controls

**SCP-style tooltips and panels**:
- Monospace font, clinical documentation style
- Redaction bars (████) for unknown information
- Clearance levels unlock full descriptions
- Document types: Entity files, incident reports, exploration logs

### Information Progression & Examination System

**All Objects Have Descriptions:**
- **Everything is examinable**: Items, entities, walls, ceiling, floor, environmental objects
- **Source material**: Descriptions lifted directly from SCP Wiki or Backrooms Wiki
- **Accessible to game code**: Stored as data for the "look" action (Right Stick examination)
- **Lore integration**: Players learn about the Backrooms/SCP universe through examination
- **Examples**:
  - Wall: "Standard office wallpaper. Yellow with faint geometric patterns. Shows signs of moisture damage."
  - Almond Water: "Clear liquid with a distinct almond scent. Properties: [REDACTED]. Effects: Hydration, mild regeneration."
  - Exit door: "Rusted metal door. Lock mechanism appears functional. Destination: Level 1."

**Progression Tiers:**
1. **Early game**: Heavy redaction, minimal info
   ```
   Entity: ████████
   Class: [REDACTED]
   Threat Level: ██
   ```

2. **Mid game**: Partial information unlocked through clearance
   ```
   Entity: Skin-Stealer
   Class: Hostile Humanoid
   Threat Level: 4
   Behavior: [PARTIAL DATA]
   ```

3. **Late game**: Full dossiers with behaviors, weaknesses, containment procedures
   ```
   Entity: Skin-Stealer
   Class: Hostile Humanoid
   Threat Level: 4
   Behavior: Mimics human appearance, attracted to sound...
   Weakness: Bright light exposure reveals true form...
   ```

4. **Meta-Knowledge (Special Mind Item)**: **Code Revelation**
   - **"System Analyzer" Mind Item**: Reveals actual game code for examined objects
   - **Purpose**: Enable game-breaking strategies through code understanding
   - **Display**: Shows GDScript/data structures alongside lore description
   - **Example**:
     ```
     Item: Almond Water
     [Lore Description...]

     --- SYSTEM DATA (REQUIRES CLEARANCE OMEGA) ---
     class_name: AlmondWater
     resource_type: Consumable
     on_use():
       player.hp += 20
       player.sanity += 10
       player.status_effects.append("Regeneration", duration=5)
     ```
   - **Design Intent**: Reward curious players who explore the meta-layer
   - **Balancing**: Make it a rare/late-game Mind item so it doesn't trivialize early runs
   - **Architecture Note**: All items must expose their logic in human-readable format for this feature

## Simulation Systems

### Physics Layer (Qud-inspired)
- **Liquids**:
  - Spreading, pooling, mixing
  - Almond water (healing/beneficial)
  - Hazardous substances
  - Hybrid effects (acid + water = diluted acid cloud)

- **Temperature**:
  - Cold zones slow entities
  - Heat causes combustion
  - Temperature transfer between tiles
  - Material state changes (water ↔ ice)

- **Materials**:
  - Flammable objects
  - Corrosive damage over time
  - Structural integrity (breakable walls)
  - Conductivity (electricity spread)

### Item Combination
- Qud-style emergent interactions
- Examples:
  - Throw oil → light fire → burning zone
  - Mix chemicals → create smoke screen
  - Electrify water pools
  - Freeze liquid surfaces

## Character Building

### Resource Pools & Item System

**Three Core Resource Pools:**

1. **Health / Body**
   - **Resource**: HP (Physical health)
   - **Damage Type**: Physical damage, most environmental hazards
   - **Base Attack**: Unarmed strike (low range, low damage)
   - **Item Pool**: 3 slots for BODY items
   - **Item Function**: All items modify the physical attack
     - Increase damage, range, attack speed
     - Add special effects (stun, bleed, knockback)
     - Transform attack type (punch → kick → weapon swing)
   - **Examples**: Brass knuckles, steel pipe, mutated limbs

2. **Sanity / Mind**
   - **Resource**: Sanity (Mental stability)
   - **Damage Type**: Psychological attacks from entities (Smilers, etc.)
   - **Base Attack**: Whistle (basic sound attack, minimal effect)
   - **Item Pool**: 3 slots for MIND items
   - **Item Function**: Perception, knowledge, reality manipulation
     - Perception bonuses (see hidden passages, entity weaknesses)
     - Multiple turns per turn (time dilation)
     - Detection range increases
     - Sanity-based attacks against specific entities
   - **Examples**: Researcher's notes, mental focus techniques, perception filters

3. **Mana / NULL**
   - **Resource**: Mana (Anomalous energy)
   - **Starting State**: 0/0 - does not exist until acquired
   - **No Base Attack**: Must acquire mana-generating items first
   - **Item Pool**: 3 slots for NULL items
   - **Item Function**: All bets are off - pure anomalous effects
     - Reality manipulation
     - Dimensional effects
     - Anomalous phenomena
     - Unpredictable synergies
   - **Examples**: SCP artifacts, Backrooms anomalies, corrupted objects

**Special Item Pool:**

4. **Light**
   - **Single Slot**: Only one LIGHT item active at a time
   - **Function**: Determines how character generates light radius
   - **Affects**: Visibility, entity attraction, stealth capability
   - **Default**: No light source (rely on ambient/environmental light)
   - **Examples**:
     - Flashlight (directed cone, battery drain)
     - Magical orb (omnidirectional, constant)
     - Polaroid camera (flash pulses, reveals hidden entities)
     - Glowstick (dim radius, no resource cost)
     - Corrupted lantern (attracts entities but reveals secrets)

### Item Synergy & Management

**Execution Order:**
- Items in each pool execute **top to bottom**
- Order matters - effects stack based on sequence
- Example: `[Fire Enchant] → [Double Strike] → [Life Steal]`
  - Attack gains fire, hits twice, heals from fire damage dealt

**Player Control:**
- **Cooldown-based reordering**: Swap item positions to change effect stacking
- **Toggle individual items**: Enable/disable specific items as needed
- **Disable entire pools**: Turn off auto-attacks when needed (stealth, resource conservation)
- **Tactical decisions**: Disable loud effects when sneaking, enable burst damage for hordes

**Item Sources:**
- **Backrooms Wiki**: Almond water, reality anchors, entity-related artifacts
- **SCP Wiki**: Anomalous objects adapted for gameplay
- **Binding of Isaac Inspiration**: Synergistic effects, weird combinations, emergent gameplay

### Mutation System
- **Dual nature**: Beneficial + detrimental effects
- **Corruption as currency**: Embrace anomalies for power at a cost
- **Examples**:
  - Extra limbs → more attack procs, but increased hitbox
  - Phase shifting → walk through walls, but random teleports
  - Reality perception → see hidden paths, but visual corruption
  - Hive mind → control entities, but lose identity

### Progression Systems

**Clearance Level (Primary Progression):**
- **Replaces traditional EXP/Level system**: Clearance is your "level"
- **EXP = EXploration Points**: Gained through active engagement with the world
  - Kill entities → Gain EXP
  - Examine new objects/entities → Gain EXP
  - Discover new areas/secrets → Gain EXP
  - Complete objectives → Gain EXP
- **Level Up = Clearance Increase**: Each level grants a **Clearance Perk**
- **Perks are meta-flavored build choices**:
  - Example perks:
    - "Security Override" - Access restricted areas
    - "Data Analyst" - Examination reveals more info
    - "Combat Authorization" - Increased damage with Body items
    - "Psionic Training" - Bonus Sanity regeneration
    - "Anomalous Exposure" - Unlock first Mana/NULL slot
    - "System Access" - Reduced cooldown on item reordering
    - "Clearance Omega" - Unlock code revelation in examination
  - Players choose ONE perk per clearance level
  - Perks provide mechanical benefits tied to clearance theme
  - Creates build diversity through clearance progression paths

**Within-Run Progression:**
- Clearance levels gained DURING runs (not persistent)
- Start each run at Clearance Level 0
- Level up by exploring and engaging with the Backrooms
- Higher clearance = less redacted info + access to restricted areas
- Clearance unlocks:
  - Information tiers (redacted → partial → full)
  - Restricted level access (deeper Backrooms require higher clearance)
  - Perk-based mechanical benefits
- **The Backrooms punish hubris**: Unprepared players WILL die
  - Like Qud's baboons - new players learn through failure
  - Proper preparation and caution are survival skills, not optional

**Meta-Progression (Knowledge Only):**
- **Researcher Classification**: Tracks total research/knowledge across all runs
  - Higher classification = cosmetic/lore recognition
  - NO mechanical advantage (avoids power creep)
- **Knowledge Database**: Fills with discovered information
  - Entity patterns, weaknesses, map layouts
  - Optimal build synergies learned through experimentation
  - Unlocked information persists between runs (player memory)
  - All mechanical progression (Clearance, items, stats) resets each run

## Hub Area & NPCs

### The Archive (Hub)
- **Safe zone** between expeditions
- **Knowledge database terminal**: Review discovered entity info, maps, lore
- **NPCs for interaction**: Researchers, survivors, mysterious entities
- **Preparation station**: Select mission, configure loadout
- **Visual aesthetic**: SCP Foundation facility mixed with Backrooms corruption

### Non-Hostile NPCs
- **Location**: Hub AND in-level encounters
  - Hub NPCs: Safe interactions, mission prep, long-term relationships
  - Level NPCs: Risky encounters, field trading, emergency aid
- **Types**:
  - **Researchers**: Offer missions, provide context, share theories
  - **Survivors**: Trade items, share stories, give warnings
  - **Anomalous entities**: Not all entities are hostile - some are neutral/helpful
    - The Wanderers (peaceful entity group)
    - Reality anchors (provide safe zones)
    - Information brokers (sell knowledge)
- **Interactions**: Dialogue trees, trading, quest giving
- **Development**: NPCs react to player's corruption level, clearance, discoveries
- **In-level risk**: Finding NPCs in dangerous areas = opportunity vs time cost

### NPC Systems
- **Reputation/Relationship tracking**: Different factions or individuals
- **Dynamic dialogue**: Changes based on player knowledge and choices
- **Quest lines**: Optional objectives that unlock lore or unique rewards
- **Trading economy**: Exchange resources, knowledge, containment tools

## Backrooms Structure

### Level Design
- **Procedurally generated** per run
- **Distinct level themes**:
  - Level 0: Yellow office rooms (classic)
  - Level 1: Industrial spaces
  - Level 2: Utility tunnels
  - Level 3: Electrical station
  - [Many more based on Backrooms wiki]

**Level Persistence:**
- **Per-run memory**: All explored levels stay in memory or on disk for the current run
- **Free traversal**: Player can return to any previously discovered level
- **Navigation**: Must find entrances/exits (stairs, doors, noclip points) to access levels
- **No teleportation**: Unless items grant it, must retrace steps through connected levels
- **Discovery items**: Special items may reveal shortcuts or alternative paths between levels
- **Strategic backtracking**: Return to safer levels to recover, then push deeper
- **Permanent exploration**: Explored chunks remain explored (no regeneration within run)

### Environmental Hazards

**Sound System:**
- **Local noise level indicator**: Shows ambient noise at current position
- **Player noise generation**: Tracks how much noise you're making
- **Noise sources**:
  - Movement (running vs sneaking)
  - Attacks (some louder than others)
  - Item effects (explosive vs silent)
  - Environmental interactions (breaking objects)
- **Entity attraction**: Loud noises draw hostile entities
- **Tactical considerations**: Balance aggression with stealth

**Lighting System:**
- **Dynamic light radius**: LIGHT item determines visibility
- **Light level indicator**: Shows current position's brightness
- **Entity behavior affected by light**:
  - Some entities only spawn/move in darkness
  - Some are attracted to light sources
  - Some are repelled by specific light types
- **Visibility tradeoff**: Light reveals environment but exposes you

**Danger/Corruption Escalation:**
- **Chunk-based scaling**: Danger increases with each new map chunk accessed
- **Procedural spawn balancing**:
  - More chunks explored = More monsters, fewer treasures (but rarer!)
  - Exit stairs spawn probabilistically (like true Backrooms)
  - Players feel "trapped" until they find the way out
- **Inevitable overwhelm**: Stay too long, you WILL be overwhelmed
- **Resource pressure**: Must balance thorough exploration vs survival
- **Risk/reward**: Push deeper for rare items vs escaping alive

**Per-Level Mechanics:**
- Unique rules and dangers per Backrooms level
- **Reality stability**: Low stability = more corruption, glitches
- Temperature extremes, liquid hazards, structural integrity

### Entity Design
- **Variable hostility**: Hostile, neutral, and friendly entities
- **Horde-based spawning** (hostile entities): Increasing numbers and difficulty
- **Unique behaviors per entity**: Pattern-based AI
- **Weakness system**: Counter specific entities with specific builds
- **Entity attraction**: Sound, light, movement, corruption level
- **Containment mechanics** (hunt missions): Non-lethal capture methods

## Combat System

### Auto-Battler Core Loop
**Vampire Survivors-style automatic combat:**
- **No manual attacks**: All combat actions are automated
- **Focus on exploration & build management**: Player spends mental energy on item synergies, not execution
- **Item-based progression**: Find items during exploration to evolve your build
- **Positioning is key**: Where you stand determines survival

### Automatic Attacks
- **Always active when enabled**: No button mashing
- **Triggered by items**: Each item in Body/Mind/NULL pools defines an action
- **Proc conditions**: On move, on hit, time-based, enemy count, proximity
- **Resource consumption**: Some attacks drain HP, Sanity, or Mana

### Turn Preview System
**"What Happens Next" UI Indicator:**
- **Visual preview**: Shows exactly what actions will execute on next turn
- **Action list**: Displays attacks, movements, resource costs
- **Target indication**: Highlights which enemies will be targeted
- **Visual markers**: In-world indicators show target priorities
- **Standing still option**: Easy controls to "wait" for a turn + see preview
- **Planning tool**: Allows tactical decision-making before committing

**Example Preview:**
```
Next Turn:
  → Move North (1 tile)
  → Body Attack: Steel Pipe (Target: Smiler #3)
  → Mind Attack: Whistle (Target: Hound #1)
  → Sanity drain: -2
```

### Tactical Depth
- **Positioning is primary skill**: Kiting, grouping, separation
- **Item toggling**: Enable/disable items to control behavior
- **Pool management**: Turn off entire attack pools when needed
- **Item reordering**: Change synergy chains mid-run
- **Environmental interaction**: Use simulation to your advantage
- **Resource management**: Balance damage output with sustainability
- **Stealth gameplay**: Disable attacks entirely to sneak past threats

## Technical Considerations

### Engine Choice: Godot 4.x ✅
**Rationale:**
- Free and open source (aligns with project ethos)
- Excellent 2D support with built-in tilemap tools
- GDScript is Python-like (perfect for Python-proficient developer)
- Native controller support (controller-first design)
- Powerful shader system (critical for corruption/glitch effects)
- Scene/Node architecture works well for ECS-like patterns
- Growing roguelike ecosystem
- Source code will be published - GPL-friendly

**Shader Capabilities** (for generative art integration):
- Custom visual shader language
- Post-processing effects
- Per-sprite shaders
- Screen-space effects
- Real-time parameter control
- Perfect for dynamic corruption/reality-bending visuals

### Architecture Needs
- **Entity-Component System**: For flexible entity/item/ability composition
- **Separate simulation layer**: Track material properties, temperatures, liquid volumes per tile
- **Efficient pathfinding**: For horde AI
- **Shader pipeline**: For corruption/glitch effects
- **Data-driven design**: Easy to add/modify entities, abilities, levels

### Data Architecture for Examination & Code Revelation

**All Game Objects Must Support:**

1. **Lore Description System:**
   - Every object (item, entity, tile, environmental object) has a `description` field
   - Descriptions sourced from SCP Wiki / Backrooms Wiki
   - Stored as accessible data (Resource files, JSON, or embedded in classes)
   - Multiple tiers: redacted → partial → full (based on clearance level)

2. **Code Revelation System:**
   - All items/objects expose their logic in human-readable format
   - **Option A**: Store simplified pseudocode as strings alongside actual code
   - **Option B**: Generate code descriptions from actual GDScript at runtime (via reflection)
   - **Option C**: Export logic as data structures that can be displayed as code

3. **Recommended Implementation:**
   ```gdscript
   class_name Item extends Resource

   @export var item_name: String
   @export_multiline var lore_description: String  # From wiki
   @export_multiline var code_description: String  # For meta-knowledge reveal

   # Actual implementation
   func on_use(player: Player) -> void:
       player.hp += 20
       player.sanity += 10

   # Human-readable code for System Analyzer item
   func get_code_representation() -> String:
       return code_description if code_description else """
   class_name: %s
   on_use():
     player.hp += %d
     player.sanity += %d
   """ % [item_name, heal_amount, sanity_amount]
   ```

4. **Design Benefits:**
   - Enables "System Analyzer" Mind item (reveals code)
   - Players can discover game-breaking synergies through meta-knowledge
   - Fits thematic goal: researchers analyzing anomalous objects
   - Reward for curious players who explore the meta-layer
   - All object logic remains accessible even after obfuscation/export

5. **Technical Notes:**
   - Don't rely on GDScript reflection (fragile, may break in exports)
   - Store code descriptions as data (string fields, JSON, or resource metadata)
   - Keep code descriptions synchronized with actual implementation
   - Consider using comments in code that can be extracted during build
   - For tiles (walls, floors, ceilings): Descriptions in MeshLibrary metadata or tilemap data

### Performance Targets
- **Tile-based**: Manageable scope for simulation
- **Horde counts**: Need to handle dozens/hundreds of entities
- **Controller support**: First-class, not an afterthought

## Design Decisions

### Core Mechanics ✅
1. **Turn-based** (like Caves of Qud)
   - Fast when you're experienced and confident
   - Slow when you're new or being cautious
   - Allows for tactical depth and examination without time pressure

2. **Run length: Variable based on playstyle**
   - **No arbitrary timers** - pressure comes from:
     - **Resource depletion**: Food, water, sanity drain over time
     - **Escalating difficulty**: More/stronger entities spawn as you linger (Vampire Survivors-style)
     - **The real horror**: Being trapped forever, starving alone in the Backrooms
   - Speedrunning conserves resources, avoids maximum escalation
   - Thorough exploration risks depletion and overwhelming hordes
   - Find exits to escape before resources run out or entities overwhelm you
   - Player choice: risk vs reward, speed vs thoroughness

3. **Solo only** - no co-op/multiplayer

4. **Viewport: 128x128** starting point
   - Tile size TBD (will experiment - probably 32x32 or 64x64)
   - Adjust for balance of visibility vs atmosphere

### Containment System ✅
**"Mark and Spare" approach:**
- Player marks specific entity in "Level Notes" as **CONTAIN** (vs default KILL)
- Marked entities are excluded from auto-targeting by lethal abilities
- Must use specialized non-lethal tools/abilities to capture
- Risk: Getting close without killing them, managing other threats simultaneously
- Reward: Research data, knowledge unlocks, special items

### Development Approach ✅
**Iterative system implementation:**
- Build one system at a time
- Test each system thoroughly before adding next
- No fixed "first playable" milestone - organic development
- Human playtesting when ready (TBD)

## Open Questions

1. **Containment tools specifics?**
   - Tranquilizer abilities? Capture nets? Reality cages?
   - How do containment tools interact with different entity types?

2. **Level transition mechanics?**
   - How do you "noclip" between levels?
   - Intentional vs accidental transitions?

3. **Starting builds/classes?**
   - Do players start with a template (Combat Specialist, Researcher, etc.)?
   - Or pure blank slate?

4. **Death penalties?**
   - Lose everything?
   - Keep knowledge/research?
   - Corruption persists between runs?

## Next Steps

1. ✅ Create design document
2. ⏳ Choose game engine
3. ⏳ Set up project structure
4. ⏳ Initialize git repository
5. ⏳ Build basic prototype:
   - Tile-based movement with controller
   - Examination system (right stick tooltips)
   - One automatic ability
   - Basic entity spawning

---

**Last Updated**: 2025-10-30
