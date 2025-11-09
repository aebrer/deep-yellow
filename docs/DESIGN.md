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

## Controls (Controller-First Design)

### Primary Controls
- **Left Stick**: Aim movement direction
- **Right Trigger**: Confirm movement (committed movement, not free movement)
- **Right Stick**: Look/Examine mode (shows tooltips and descriptions)

### Ability Management
- **RB, LB, X, Y**: Toggle abilities 1-4 on/off
  - Abilities auto-proc when enabled
  - Player can disable to manage resources, noise, or unwanted effects

### System Controls
- **Start/ESC**: Pause game → Enter menu mode (UI panels become selectable)
- **Select/Back**: Quick inventory/Character sheet toggle (planned)

### Menu Mode Controls (Planned - Active when paused)
- **D-Pad / Left Stick**: Navigate between UI panels
- **A Button**: Select/expand item or entry
- **B Button**: Back/close panel
- **Right Stick**: Scroll content within selected panel
- **Start/ESC**: Unpause → Return to gameplay

### Design Philosophy
- Minimal button usage for accessibility
- Same control scheme for gameplay and menus
- Deliberate movement creates tension
- Focus on positioning, not mechanical execution

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
- **Character Sheet** (right panel): Stats (hp, sanity, stamina), turn counter, position
- **Core Inventory** (right panel): Build-defining items and abilities
- **Game Log** (bottom panel): Real-time event stream with color-coded messages
- **Terminal Aesthetic**: IBM Plex Mono font, minimal black panels, lowercase text

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

### Information Progression
- **Early game**: Heavy redaction, minimal info
  ```
  Entity: ████████
  Class: [REDACTED]
  Threat Level: ██
  ```
- **Late game**: Full dossiers with behaviors, weaknesses, containment procedures
  ```
  Entity: Skin-Stealer
  Class: Hostile Humanoid
  Threat Level: 4
  Behavior: Mimics human appearance, attracted to sound...
  ```

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

### Mutation System
- **Dual nature**: Beneficial + detrimental effects
- **Corruption as currency**: Embrace anomalies for power at a cost
- **Examples**:
  - Extra limbs → more attack procs, but increased hitbox
  - Phase shifting → walk through walls, but random teleports
  - Reality perception → see hidden paths, but visual corruption
  - Hive mind → control entities, but lose identity

### Ability System
- **Toggleable auto-abilities** on RB/LB/X/Y
- **Resource management**: Some abilities consume stamina, sanity, reality stability
- **Synergies & anti-synergies**: Build around combinations
- **Examples**:
  - Distortion Field: AoE damage but attracts entities (noisy)
  - Dimensional Rift: Auto-dash toward enemies (disable when kiting)
  - Almond Water Aura: Healing over time (resource drain)
  - Echo Location: Reveals map (costs sanity)

### Progression Systems
- **Meta-progression is KNOWLEDGE ONLY**: No arbitrary unlocks or power creep
  - Player learns entity patterns, weaknesses, map layouts
  - Discovers optimal build synergies through experimentation
  - Unlocks information (redacted text becomes readable)
  - Knowledge database fills with research data
  - All mechanical progression resets each run
- **Researcher Classification**: Tracks your total research/knowledge gained
  - Higher classification = less redacted information in tooltips
  - Cosmetic/lore reward, not mechanical advantage
- **Clearance Levels**: Increases DURING runs as you explore and document
  - Unlock access to deeper/more dangerous Backrooms levels within the run
  - Higher clearance = less redacted info + access to restricted areas
  - Risk/reward: Push deeper for better rewards but greater danger
  - **The Backrooms punish hubris**: Unprepared players WILL die
    - Like Qud's baboons - new players learn through failure
    - Proper preparation and caution are survival skills, not optional

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

### Environmental Hazards
- **Per-level mechanics**: Unique rules and dangers
- **Reality stability**: Low stability = more corruption, glitches
- **Noise system**: Loud abilities attract entities
- **Light/darkness**: Some entities only appear in shadow

### Entity Design
- **Variable hostility**: Hostile, neutral, and friendly entities
- **Horde-based spawning** (hostile entities): Increasing numbers and difficulty
- **Unique behaviors per entity**: Pattern-based AI
- **Weakness system**: Counter specific entities with specific builds
- **Entity attraction**: Sound, light, movement, corruption level
- **Containment mechanics** (hunt missions): Non-lethal capture methods

## Combat System

### Automatic Attacks
- **Always active when enabled**: No button mashing
- **Proximity-based**: Auras, fields, projectile spawning
- **Proc conditions**: On move, on hit, time-based, enemy count

### Tactical Depth
- **Positioning is primary skill**: Kiting, grouping, separation
- **Ability toggling**: Enable/disable based on situation
- **Environmental interaction**: Use simulation to your advantage
- **Resource management**: Balance damage output with sustainability

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
