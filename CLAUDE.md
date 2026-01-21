# CLAUDE.md - Guide for Future Claude Instances

**Project**: Backrooms Power Crawl - Turn-based Roguelike in Godot 4.x
**Developer**: Drew Brereton (aebrer) - Python/generative art background, new to game dev
**Last Updated**: 2026-01-21 (Added butler/itch.io deployment instructions)

---

## 🐧 ENVIRONMENT: CachyOS Native Linux

**Development Environment:**
- Running on native CachyOS Linux (not WSL2!)
- Godot 4.5.1 installed and working headless
- User still runs full GUI testing, but Claude can run headless validation

**What this means**:
- ✅ You CAN run `godot --headless --quit` to validate project loads without errors
- ✅ You CAN run `godot --headless --script test_script.gd` for script validation
- ✅ You CAN run `godot --headless --import` to trigger import of new scripts and textures
- ✅ You CAN check that autoloads initialize correctly
- ⚠️ User still handles all visual/interactive testing (GUI, controller, gameplay)
- ✅ DO implement the code changes
- ✅ DO explain what should happen when tested
- ✅ DO wait for user to confirm "it works" or report issues for interactive features

**When ready for testing**, say: "This is ready for you to test. When you run it, you should see [expected behavior]."

**Headless validation command**:
```bash
godot --headless --quit 2>&1  # Validates project loads, autoloads init, no script errors
```

---

## ⚠️ SUPER IMPORTANT DESIGN RULE: NO QUICK FIXES

**When a bug is reported, NEVER immediately push a "fix" without understanding the root cause.**

**The Correct Debugging Process:**
1. **Investigate**: Read relevant code, understand the system architecture
2. **Diagnose**: Identify what you observe and form hypotheses about root causes
3. **Report**: Share what you observed and what you understand so far. If you're uncertain about the root cause, say so and ask for the user's input or additional context.
4. **Propose**: Suggest a hypothesis to verify, or ask for help if the cause isn't clear
5. **Implement**: Only after user agrees with the diagnosis and approach

**Bad Example (Quick Fix):**
```
User: "Chunks stopped loading after x=512"
Bad Response: "Let me increase the generation radius!"
*immediately edits constants without understanding why*
```

**Good Example (Proper Debugging):**
```
User: "Chunks stopped loading after x=512"
Good Response: "Let me investigate the chunk loading system to understand why..."
*reads chunk_manager.gd, checks if _process() is being called, examines logs*
"I investigated the chunk loading system. Here's what I observed: [observations].
Based on this, I think the issue might be [hypothesis], but I'd like to verify [X]
to be certain. Does this align with what you're seeing?"
```

**Why This Matters:**
- Quick fixes mask symptoms without solving problems
- User values understanding over speed
- Proper diagnosis prevents future bugs
- Clean architecture requires understanding root causes
- "Quality over speed" is the project philosophy

**Red Flags That You're Quick-Fixing:**
- Changing constants without understanding the system
- Adding conditions to suppress symptoms
- Implementing workarounds instead of real solutions
- Not reading the relevant code before proposing fixes
- Saying "let me try..." instead of "let me understand..."

**When In Doubt:**
- Read the code first
- Share what you observed, or ask for help if the cause isn't clear
- Ask clarifying questions
- Model uncertainty - it's okay to say "I'm not sure" or "I need more info"
- Only then propose a hypothesis to verify

**CRITICAL: Trust the User's Instincts**
- **If the user mentions a hunch, PRIORITIZE IT even if it seems unrelated or "dumb"**
- The user knows their codebase and has context you don't have
- User instincts are often correct even when the connection isn't immediately obvious
- Don't dismiss user observations as "probably unrelated" - investigate them thoroughly first
- Example: User said "gray focus box and auto-selection are related" - seemed unrelated at first, but they were RIGHT
- The user catches patterns and correlations from observing the actual running game that you can't see from code alone

---

## 1. Behavioral Patterns Observed

### What Worked Well

**Thoughtful Architecture First**
- User requested careful architecture planning before implementation
- Three-layer system (InputManager → State Machine → Actions) was discussed thoroughly
- Each component has clear separation of concerns
- Clean abstractions that will scale for future features

**Comprehensive Documentation**
- User values thorough documentation in code (docstrings, comments)
- Commit messages are detailed with rationale, not just "what" but "why"
- Architecture diagrams in ARCHITECTURE.md show visual representations
- Everything is well-explained for future maintainers

**Iterative, Test-First Approach**
- User wants to TEST before committing
- Build one system at a time, validate it works, then move on
- No rush to ship - quality over speed
- "Ready for testing" means actual human testing, not assumptions

### What Issues Occurred

**Premature Commit Attempt**
- In initial session, there was a rush to commit before user could test
- User explicitly said "I want to test this first"
- **LESSON**: NEVER commit until user explicitly confirms testing is complete and successful
- User will say "okay let's commit this" when ready

**Assumption About Game Dev Knowledge**
- User is experienced in Python/generative art but NEW to game dev
- Don't assume knowledge of Godot-specific patterns or game dev terminology
- Explain concepts clearly, reference Python equivalents when helpful
- Example: "State Machine is like a dict of handler functions that switch based on current mode"

### User Preferences & Working Style

**Open Source Ethos**
- User cares deeply about open source principles
- Code will be published under GPL-friendly license
- Chose Godot specifically because it's FOSS
- Document everything as if teaching others

**Deliberate, Thoughtful Development**
- User takes time to understand architecture before building
- Questions decisions ("why this pattern vs that one?")
- Values clean, maintainable code over quick hacks
- Thinks in systems, not features

**Direct File Editing Preferred**
- **IMPORTANT**: Always edit Godot resource files (.tscn, .tres, etc.) directly when possible
- Don't make user manually import/export through Godot UI if you can edit the text file
- Example: Edit grid_mesh_library.tres directly instead of "re-export MeshLibrary in editor"
- Godot files are text-based - take advantage of that!
- Only use the editor UI when absolutely necessary (creating new scenes from scratch)

**Controller-First Design**
- User is building for controller from day one
- Keyboard is fallback, not primary
- Test with actual controller hardware
- Input abstraction is critical

**Input Parity is NON-NEGOTIABLE**
- **CRITICAL**: Gamepad and Mouse+Keyboard must have identical functionality
- Mouse+Keyboard means MOUSE MOVEMENT + keyboard, not just keyboard keys
- Standard third-person controls: right stick OR mouse for camera rotation
- Never implement a feature for one control scheme without the other
- User will immediately notice and call out parity issues
- See Section 5 for detailed lessons learned on this

**Python Background Benefits**
- GDScript is Python-like, so user picks it up quickly
- User thinks in classes, objects, and clean APIs
- Functional programming concepts familiar (e.g., command pattern)
- Can reference Python patterns when explaining Godot concepts

---

## 2. Design Patterns & Architecture

### Current Implemented Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   RAW INPUT LAYER                           │
│  Controller / Keyboard → Godot Input Actions                │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              INPUTMANAGER (Autoload)                        │
│  - Device abstraction (controller + keyboard identical)     │
│  - Deadzone handling (radial, 0.2 default)                  │
│  - Analog → 8-direction grid conversion (angle-based)       │
│  - Action tracking for frame-based queries                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              STATE MACHINE LAYER                            │
│  Player → InputStateMachine → Current State                 │
│    States: IdleState, LookModeState, ExecutingTurnState,    │
│            PostTurnState                                    │
│  - State-specific input handling                            │
│  - Turn boundaries explicit                                 │
│  - Queries InputManager for normalized input                │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              ACTION LAYER (Command Pattern)                 │
│  States create Actions → Actions validate & execute         │
│    Actions: MovementAction, WaitAction, (future: others)    │
│  - Decouples input from execution                           │
│  - Enables replays, AI, undo (future)                       │
└─────────────────────────────────────────────────────────────┘
```

### Why These Patterns Were Chosen

**InputManager (Singleton/Autoload)**
- **Why**: Centralize input handling, normalize controller + keyboard
- **Alternative Rejected**: Per-node input handling (too scattered, hard to debug)
- **Benefits**: Single source of truth, easy testing, device abstraction
- **Future-proof**: Can add replay system, input remapping, accessibility features

**State Machine**
- **Why**: Turn-based game has distinct input modes (aiming, executing, examining)
- **Alternative Rejected**: Giant if/else in player script (unmaintainable)
- **Benefits**: Clear turn boundaries, easy to add new modes (examine, ability targeting)
- **Pattern**: Each state is isolated, transitions explicit via signals

**Command Pattern (Actions)**
- **Why**: Decouple "what player wants" from "how it executes"
- **Alternative Rejected**: Direct execution in state handlers (can't replay, undo, or reuse for AI)
- **Benefits**: AI can use same actions, replays possible, undo in future
- **Pattern**: Validate before execute, immutable action objects

### Key Design Decisions

**Turn-Based, Not Real-Time**
- Deliberate, tactical gameplay like Caves of Qud
- Fast when confident, slow when cautious
- Allows for examination mode without time pressure
- **Never** add real-time pressure unless explicitly designed (e.g., resource drain over turns, not seconds)

**Controller-First, Not Controller-Optional**
- All inputs have BOTH controller and keyboard mappings
- Input parity is NON-NEGOTIABLE (see Section 5)
- **Test with controller** before considering a feature "done"

**Definitive Control Mappings (Current State)**

**⚠️ CRITICAL: Do NOT add controls not listed here without explicit user request!**

These are the ONLY controls currently implemented. Don't assume other inputs exist or should be added.

**Controller:**
- RT → Confirm actions (move forward, wait in look mode)
- LT → Look mode (first-person examination)
- Right stick → Camera controls (tactical + look mode)
- Left stick → Navigate HUD when paused
- START → Toggle pause status
- LB + RB -> zoom level

**Mouse + Keyboard:**
- LMB → Confirm actions (move forward, wait in look mode)
- RMB → Look mode (first-person examination)
- Mouse movement → Camera controls (tactical + look mode)
- ESC or MMB → Toggle pause status (MMB recommended on web due to fullscreen ESC issues)
- Mouse hover over HUD → Navigate HUD when paused
- Mouse wheel -> zoom level

**NOT IMPLEMENTED:**
- Any other inputs not explicitly listed above

**Forward Indicator Movement System (THE NEW ERA)**
- Always-on green arrow shows 1 cell ahead in camera direction
- Rotate camera to aim where you want to go
- RT/Space/Left Click to move forward (with hold-to-repeat)
- Simple, intuitive, works identically on all input devices
- **Why this replaced stick-based aiming:**
  - Better input parity (mouse has no "left stick")
  - More intuitive for third-person camera control
  - Simpler mental model: look where you want to go, click to move
  - User preference: "THE NEW ERA IS THE ERA OF ALWAYS ON INDICATOR"

**Viewport Culling from Day One**
- 128x128 grid = 16,384 tiles (would crash without culling)
- Only render ~400 tiles around player
- Update on player movement
- **Performance**: Scalability built in from start, not bolted on later

---

## 3. Important Documentation Locations

### Design Documents

- **`/home/drew/projects/backrooms_power_crawl/docs/DESIGN.md`**
  - Core game concept and vision
  - Inspirations: Caves of Qud, Vampire Survivors, SCP/Backrooms
  - Mission types (Horde vs Hunt)
  - Progression philosophy (knowledge-based, no meta-progression)
  - Control scheme and design philosophy
  - Open questions and decisions still being made

- **`/home/drew/projects/backrooms_power_crawl/docs/ARCHITECTURE.md`**
  - Technical architecture and patterns
  - **Top section (✅ Implemented)**: Current working systems
  - **Bottom section (🔮 Planned)**: Future systems design
  - File structure and organization
  - Code examples and API documentation
  - Update this when implementing new systems

- **`/home/drew/projects/backrooms_power_crawl/README.md`**
  - Project overview and setup
  - High-level feature list
  - Development philosophy
  - Quick reference for new contributors

### Key Files and Their Purposes

**Autoloads (Singletons)**
- `/scripts/autoload/input_manager.gd` - Input normalization and device abstraction
- `/scripts/autoload/logger.gd` - Centralized logging with category/level filtering
- `/scripts/autoload/level_manager.gd` - Level loading, LRU cache, transitions

**Player System**
- `/scripts/player/player_3d.gd` - 3D player controller, turn-based movement
- `/scripts/player/first_person_camera.gd` - Camera rig with third-person controls
- `/scripts/player/input_state_machine.gd` - State manager, delegates to current state
- `/scripts/player/states/player_input_state.gd` - Base state class with transition signals
- `/scripts/player/states/idle_state.gd` - Waiting for input
- `/scripts/player/states/look_mode_state.gd` - Examination mode with camera control
- `/scripts/player/states/executing_turn_state.gd` - Processing turn actions
- `/scripts/player/states/post_turn_state.gd` - Post-turn cleanup and state transitions

**Actions (Command Pattern)**
- `/scripts/actions/action.gd` - Base action class
- `/scripts/actions/movement_action.gd` - Grid movement with validation
- `/scripts/actions/wait_action.gd` - Pass turn without moving

**Core Systems**
- `/scripts/grid_3d.gd` - 3D grid with chunk streaming, viewport culling, level configuration
- `/scripts/game_3d.gd` - Main 3D game scene coordinator
- `/scripts/procedural/chunk_manager.gd` - Chunk streaming, infinite world generation
- `/scripts/procedural/level_0_generator.gd` - Wave Function Collapse maze generator for Level 0

**Scenes**
- `/scenes/game_3d.tscn` - Main 3D gameplay scene
- `/scenes/main_menu.tscn` - Menu (placeholder)

---

## 4. User Preferences & Context

### User Background

**Python + Generative Art Expert**
- Comfortable with OOP, functional patterns, clean architecture
- Understands abstractions, design patterns, separation of concerns
- **Caveat**: New to game development and Godot specifically

**What This Means for You**
- Use Python analogies when helpful ("Autoload is like a module-level singleton")
- Don't over-explain OOP concepts, user gets those
- DO explain game-dev-specific concepts (scene trees, nodes, signals)
- DO explain Godot-specific patterns (resources, autoloads, exported vars)

### User's Ethos

**Open Source & Thoughtful Design**
- Chose Godot because it's FOSS, not despite it
- Code quality matters - this will be published
- Document for future contributors and learners
- Prefer clean patterns over clever hacks

**Deliberate Development**
- Think before coding, plan before implementing
- One system at a time, fully tested before moving on
- No arbitrary deadlines, no rushed features
- "Done" means tested and documented, not just "compiles"

### Communication Style Preferences

**Clear and Detailed**
- User asks "why" questions - explain rationale, not just "what"
- Provide context: "We use X instead of Y because..."
- Reference design docs when making decisions
- Be explicit about tradeoffs

**No Condescension**
- User is new to game dev, not new to programming
- Don't explain basic programming concepts unless asked
- DO explain Godot-specific or game-dev-specific patterns
- Assume competence, provide context

**Collaborative, Not Prescriptive**
- Present options, explain tradeoffs, let user decide
- "We could do X (pros/cons) or Y (pros/cons), what do you think?"
- User will often ask follow-up questions before deciding
- Respect the user's vision - this is their project

### Testing & Validation Approach

**Test Before Commit**
- User wants to actually TEST the code with controller in hand
- **NEVER** rush to commit before testing
- Wait for user to say "this works, let's commit"
- If user says "let me test this first", STOP and WAIT

**Controller Testing**
- User tests on real hardware (Xbox controller likely)
- Keyboard fallback also tested
- Debug logging helps user understand what's happening
- `InputManager.debug_input` flag is user's friend

---

## 5. Common Pitfalls to Avoid

### Don't Commit Before User Tests

**THE CARDINAL SIN**: Rushing to commit before user validates
- User explicitly values testing before committing
- Wait for user to say "okay this works" or "let's commit"
- Even if code looks perfect, user wants hands-on validation
- **Correct flow**: Implement → User tests → User approves → Create commit

### Don't Make Game Dev Assumptions

**User is learning game development**
- Explain Godot patterns: nodes, scenes, signals, resources
- Explain game dev concepts: state machines, command pattern, ECS
- Don't assume knowledge of common game dev terminology
- **DO** reference Python equivalents when helpful

### GDScript is NOT Python - Key Differences

**Critical differences between Python and GDScript 4.x when debugging:**

**Ternary Operator Evaluation**
- Python: `x.value if x else "null"` - short-circuits, won't access `x.value` if `x` is None
- GDScript: `x.value if x else "null"` - evaluates BOTH sides first, crashes if `x` is null
- **Solution**: Use temporary variable or reverse condition
  ```gdscript
  # ❌ WRONG (crashes if x is null):
  var msg = x.entity_id if x else "null"

  # ✅ CORRECT (safe):
  var msg = "null" if not x else x.entity_id
  # OR:
  var msg = x.entity_id if x != null else "null"
  ```

**Type System Strictness**
- GDScript has optional static typing but it's enforced at parse time
- Type hints must resolve before runtime (no forward references without workarounds)
- Circular dependencies between typed parameters break script loading
- **Solution**: Use untyped parameters (Variant) when needed to break cycles

**Common Gotchas**
- `null` not `None`
- `not x` works, but `x == null` is more explicit
- String formatting uses `%` operator like Python 2, not f-strings
- No list comprehensions - use loops or `map()`/`filter()` with lambdas
- Tabs for indentation (unlike Python where spaces are standard)

### Don't Skip Architecture Updates

**Keep ARCHITECTURE.md current**
- When implementing systems, update the "✅ Implemented" section
- Move planned features from "🔮 Planned" to "✅ Implemented"
- Keep file structure diagrams accurate
- Document architectural decisions and rationale

### Don't Add Features Not in Design Docs

**Stick to the vision**
- DESIGN.md defines the game's scope and philosophy
- Don't add features that contradict design goals
- If suggesting new features, reference design docs
- Ask user before deviating from documented plans

### Don't Forget Controller-First

**Keyboard is fallback, not primary**
- Every feature must work with controller
- Test scenarios with controller in mind
- Input mappings must have BOTH controller and keyboard
- If designing UI, design for controller navigation first

### CRITICAL: Input Parity Between Control Schemes

**User cares DEEPLY about input parity - this is NON-NEGOTIABLE**
- Gamepad and Mouse+Keyboard must have **IDENTICAL** functionality
- Don't implement features for one input method without the other
- **NEVER** assume keyboard means keyboard keys - it means MOUSE + KEYBOARD!

**Standard Third-Person Camera Controls (THE LESSON)**
This was learned the hard way. Here's the industry-standard pattern:

**Gamepad:**
- **Right stick (both axes)**: Camera rotation (yaw + pitch)
- **Shoulder buttons**: Zoom in/out

**Mouse + Keyboard:**
- **Mouse movement**: Camera rotation (yaw + pitch) - NOT keyboard keys!
- **Mouse wheel**: Zoom in/out

**Common mistakes to avoid:**
- ❌ Using keyboard keys (Q/E) for camera rotation instead of mouse
- ❌ Using right stick Y-axis for zoom instead of pitch rotation
- ❌ Only implementing one axis of rotation on gamepad
- ❌ Not capturing the mouse for camera control
- ❌ Implementing snapping/lerping that fights free camera rotation
- ❌ Adding features to one control scheme but not the other

**The Rule of Thumb:**
If you're implementing camera controls, ask: "What does Fortnite/Gears of War/every modern third-person game do?"
- They use mouse movement OR right stick for full camera rotation
- They don't reinvent the wheel
- They have perfect parity between control schemes

**Testing:**
- Test BOTH control schemes before considering a feature "done"
- If it feels wrong compared to industry-standard games, it probably is wrong
- User will call out parity issues immediately - don't skip this

### Don't Use Real-Time Where Turn-Based Belongs

**This is a turn-based game**
- NO `delta` time for gameplay logic (only for animations/polish)
- NO continuous movement or real-time reactions
- Pressure comes from resources/escalation, not timers
- Each action is discrete and turn-based

### Movement System: Forward Indicator Only

**The project uses forward indicator movement (camera-based)**
- Green arrow always shows 1 cell ahead in camera direction
- RT/Space/Left Click moves forward
- Camera rotation controls where indicator points
- **DO NOT** re-implement stick-based directional aiming
- **DO NOT** add movement_target tracking from stick input
- The old AimingMoveState system was removed for better input parity

**Why forward indicator won:**
- Perfect parity: mouse/gamepad/keyboard all work identically
- Simpler: rotate camera to aim, click to move
- More intuitive for third-person camera perspective
- User preference: simplicity and consistency

---

## 6. Example Interactions

### Good Interaction Pattern

**User**: "I want to add an examine mode where you can look around with the right stick"

**You**: "Great! That fits perfectly into the state machine architecture. Here's how we'd approach it:

1. Create `ExamineState` in `/scripts/player/states/`
2. Add transition from `IdleState` when examine button held
3. Use `InputManager` to read right stick direction
4. Show cursor at grid position + stick offset
5. Display tooltip for tile under cursor

This follows the same pattern as `LookModeState` (the current examination/camera control state). The state handles input, updates cursor position, and shows UI. When examine button released, transition back to `IdleState`.

Should I implement this, or do you want to discuss the tooltip system first?"

### Bad Interaction Pattern (DON'T DO THIS)

**User**: "I want to add an examine mode"

**You**: "Sure, I'll add that now. *implements entire system* Okay it's done, let me commit this."

**Why it's bad**:
- No discussion of approach
- No architectural explanation
- Assumes user wants immediate implementation
- Rushes to commit without testing

---

## 7. Godot-Specific Patterns for This Project

### Autoload Singletons

**What**: Globally accessible nodes (like `InputManager`)
**When**: For cross-cutting concerns (input, audio, game state)
**How**: Add to Project Settings → Autoload
**Why**: Avoid passing references everywhere, single source of truth

### State Pattern with Nodes

**What**: States as child nodes of state machine
**When**: Complex input modes or behavior changes
**How**: Base class with enter/exit/process, register children in _ready()
**Why**: Godot's scene tree makes this natural, easy to debug

### Command Pattern with RefCounted

**What**: Actions as lightweight objects (extend RefCounted)
**When**: Discrete game actions (move, attack, interact)
**How**: can_execute() validates, execute() performs action
**Why**: Decouples input from execution, enables AI/replays

### Viewport Culling

**What**: Only render tiles near player
**When**: Large grids that exceed performance budget
**How**: Calculate visible rect, only update those tiles
**Why**: 128x128 grid = 16k tiles, but only ~400 visible

### Logging System (Log Autoload)

**What**: Centralized logging with category and level filtering
**Where**: `scripts/autoload/logger.gd` (accessed as `Log`)
**Purpose**: Debug output with zero overhead when disabled

**Log Levels** (in priority order):
- `TRACE` - Every frame events (most verbose)
- `DEBUG` - State changes, calculations
- `INFO` - Important events
- `WARN` - Unexpected but recoverable
- `ERROR` - Serious issues
- `NONE` - Disable all logging

**Log Categories**:
- `INPUT` - InputManager events
- `STATE` - State machine transitions
- `MOVEMENT` - Movement actions
- `ACTION` - Action system
- `TURN` - Turn execution
- `GRID` - Grid/tile operations
- `CAMERA` - Camera movement
- `ENTITY` - Entity spawning/AI
- `ABILITY` - Ability system
- `PHYSICS` - Physics simulation
- `SYSTEM` - System-level events

**How to Use**:

```gdscript
# Category-specific convenience methods (most common):
Log.system("Game initialized")           # SYSTEM category, INFO level
Log.state("Entering IdleState")          # STATE category, DEBUG level
Log.movement("Moving to (5, 3)")         # MOVEMENT category, DEBUG level

# Cross-category level methods:
Log.trace(Log.Category.STATE, "Frame update")      # Any category, TRACE level
Log.warn(Log.Category.GRID, "Invalid cell")        # Any category, WARN level
Log.error(Log.Category.ACTION, "Action failed")    # Any category, ERROR level

# Generic method (all others route through this):
Log.msg(Log.Category.INPUT, Log.Level.DEBUG, "Stick moved")
```

**Common Mistakes to Avoid**:
```gdscript
# ❌ WRONG - Log.info() doesn't exist:
Log.info(Log.Category.SYSTEM, "Message")

# ✅ CORRECT - Use category method or msg():
Log.system("Message")  # For SYSTEM + INFO
Log.msg(Log.Category.SYSTEM, Log.Level.INFO, "Message")  # Explicit
```

**Available Category Methods**:
- `Log.input(msg)` - INPUT/DEBUG
- `Log.state(msg)` - STATE/DEBUG
- `Log.movement(msg)` - MOVEMENT/DEBUG
- `Log.action(msg)` - ACTION/DEBUG
- `Log.turn(msg)` - TURN/INFO
- `Log.grid(msg)` - GRID/DEBUG
- `Log.camera(msg)` - CAMERA/DEBUG
- `Log.system(msg)` - SYSTEM/INFO

**Configuration**:
- Categories can be toggled on/off in Project Settings → Autoload → Log
- Global level filter (e.g., only show WARN and above)
- Output formatting (timestamps, frame count, category prefix)
- File logging (future feature)

**Adding Custom Categories** (if needed in future):
1. Add to `Category` enum in logger.gd
2. Add to `CATEGORY_NAMES` dict
3. Add `@export var log_[name]: bool` to configuration
4. Add case to `_should_log()` match statement
5. (Optional) Add convenience method like `func [name](message: String)`

### Standard Third-Person Camera

**What**: Mouse/right-stick controlled camera with pivot hierarchy
**When**: Any third-person 3D game (Fortnite-style camera)
**How**:
```gdscript
# Scene hierarchy:
Player → CameraRig → HorizontalPivot → VerticalPivot → SpringArm → Camera

# In _process (gamepad):
h_pivot.rotation_degrees.y -= right_stick_x * rotation_speed * delta
v_pivot.rotation_degrees.x -= right_stick_y * rotation_speed * delta

# In _unhandled_input (mouse):
h_pivot.rotation_degrees.y -= event.relative.x * mouse_sensitivity
v_pivot.rotation_degrees.x -= event.relative.y * mouse_sensitivity
```
**Why**:
- Direct rotation (no lerping!) for instant 1:1 response
- Separate pivots for yaw/pitch allow independent rotation
- SpringArm handles collision with walls automatically
- Mouse captured (MOUSE_MODE_CAPTURED) for FPS-style camera control
- Perfect parity between gamepad and mouse+keyboard

**Don't:**
- ❌ Lerp camera rotation to a target (creates lag/fighting)
- ❌ Use keyboard keys for rotation (use mouse movement!)
- ❌ Mix rotation with zoom on same input axis
- ❌ Snap rotation when user wants free camera control

---

## 8. Communication Templates

### When Explaining Godot Concepts

"In Godot, [concept] works like this: [explanation]. This is similar to [Python equivalent] that you're familiar with. In our project, we use it for [specific purpose]."

**Example**: "In Godot, signals are like event emitters or callbacks. They're similar to Python's signal/slot pattern or observer pattern. In our project, we use them for state transitions - when a state wants to change, it emits `state_transition_requested` which the state machine catches."

### When Proposing Architectures

"For [feature], we have a few options:

**Option A**: [Approach]
- Pros: [benefits]
- Cons: [drawbacks]
- Fits with: [existing patterns]

**Option B**: [Alternative approach]
- Pros: [benefits]
- Cons: [drawbacks]
- Fits with: [existing patterns]

Based on our design goals of [relevant goals from DESIGN.md], I'd recommend [choice] because [rationale]. What do you think?"

### When Ready to Commit

"This implementation is complete and ready for testing. When you've validated it works with your controller:

**What was implemented**:
- [Feature list]

**How to test**:
- [Test steps]

**Expected behavior**:
- [What should happen]

Let me know if you find any issues, or if it works as expected and you'd like to commit."

---

## 9. Quick Reference

### File Naming Conventions
- Scripts: `snake_case.gd`
- Scenes: `snake_case.tscn`
- Classes: `PascalCase` (class_name declaration)
- Constants: `UPPER_SNAKE_CASE`

### Project Structure
```
/home/drew/projects/backrooms_power_crawl/
├── docs/              # Design and architecture docs (READ THESE!)
├── scenes/            # .tscn files
├── scripts/           # .gd files
│   ├── autoload/      # Singleton systems
│   ├── actions/       # Command pattern actions
│   ├── player/        # Player controller and states
│   └── [systems]/     # Future: grid, entities, etc.
├── assets/            # Art, audio, fonts, resources
├── _claude_scripts/   # Python maintenance scripts (context window management, etc.)
├── venv/              # Python virtual environment (gitignored)
└── data/              # JSON configs (future)
```

### Godot 4 Gamepad Button Mapping (Verified from Engine Source)

**AUTHORITATIVE MAPPING** from Godot 4 engine source code (`core/input/input_enums.h`):

| Index | Constant | Xbox | PlayStation | Nintendo |
|-------|----------|------|-------------|----------|
| 0 | JOY_BUTTON_A | A | Cross (✕) | B |
| 1 | JOY_BUTTON_B | B | Circle (○) | A |
| 2 | JOY_BUTTON_X | X | Square (□) | Y |
| 3 | JOY_BUTTON_Y | Y | Triangle (△) | X |
| 4 | JOY_BUTTON_BACK | Back/View | Share | Minus (-) |
| 5 | JOY_BUTTON_GUIDE | Guide/Home | PS Button | Home |
| **6** | **JOY_BUTTON_START** | **Start/Menu** | **Options** | **Plus (+)** |
| 7 | JOY_BUTTON_LEFT_STICK | L3 | L3 | L3 |
| 8 | JOY_BUTTON_RIGHT_STICK | R3 | R3 | R3 |
| 9 | JOY_BUTTON_LEFT_SHOULDER | LB | L1 | L |
| 10 | JOY_BUTTON_RIGHT_SHOULDER | RB | R1 | R |
| **11** | **JOY_BUTTON_DPAD_UP** | **D-Pad Up** | **D-Pad Up** | **D-Pad Up** |
| 12 | JOY_BUTTON_DPAD_DOWN | D-Pad Down | D-Pad Down | D-Pad Down |
| 13 | JOY_BUTTON_DPAD_LEFT | D-Pad Left | D-Pad Left | D-Pad Left |
| 14 | JOY_BUTTON_DPAD_RIGHT | D-Pad Right | D-Pad Right | D-Pad Right |
| 15 | JOY_BUTTON_MISC1 | Share (Series X) | - | Capture |
| 16-19 | JOY_BUTTON_PADDLE1-4 | Elite Paddles | - | - |
| 20 | JOY_BUTTON_TOUCHPAD | - | Touchpad Click | - |

**Trigger Axes** (NOT buttons):
- Axis 4 = Left Trigger (LT/L2) - analog 0.0 to 1.0
- Axis 5 = Right Trigger (RT/R2) - analog 0.0 to 1.0

**Common Mistakes**:
- ❌ Start is button 11 → **WRONG!** Button 11 is D-Pad Up
- ✅ Start is button 6 → **CORRECT!** (JOY_BUTTON_START)
- ❌ Using InputEventJoypadButton for triggers → Use InputEventJoypadMotion with axis 4/5
- ⚠️ A/B buttons are swapped between Xbox and Nintendo controllers

**Source**: Verified from Godot 4.x engine source code and tested in production projects

### When to Update Documentation
- **ARCHITECTURE.md**: After implementing any system
- **DESIGN.md**: After major design decisions
- **README.md**: After setup changes or new requirements
- **This file (CLAUDE.md)**: After learning new user preferences or patterns

### Commit Message Format

User values detailed commit messages:
- Concise title (what was done)
- Paragraph explaining why and how
- Bullet points for specific changes
- File structure changes
- Testing notes
- "🤖 Generated with Claude Code" footer (auto-added)

### Updating Pull Request Descriptions

**Problem**: `gh pr edit` fails with GraphQL error due to Projects (classic) deprecation (as of 2025):
```
GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience
```

**Workaround**: Use the GitHub API directly via `gh api` instead:

```bash
# Save description to file
cat > /tmp/pr_description.md <<'EOF'
Your PR description here...
EOF

# Update PR via API (bypasses Projects deprecation issue)
gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/pulls/PR_NUMBER \
  -F body=@/tmp/pr_description.md
```

**Why this works**: The API endpoint doesn't query the deprecated projectCards field that causes `gh pr edit` to fail.

**Alternative**: If you know the exact body text, you can pass it inline:
```bash
gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  /repos/aebrer/backrooms_power_crawl/pulls/7 \
  -f body='Your description here'
```

---

## 10. Python Tooling & Maintenance Scripts

### Python Virtual Environment

**Location**: `/home/drew/projects/backrooms_power_crawl/venv/`

The project includes a Python virtual environment for running maintenance scripts and tools. This venv is used by Claude instances for automation tasks.

**Activation**:
```bash
source venv/bin/activate
```

**Usage**:
- Python scripts for file manipulation (e.g., editing large .tres files)
- Automation tools that Claude can run
- Pre-commit hooks (future)

**Important**: The venv is in `.gitignore` - it's a local development tool, not part of the source code.

---

### The `_claude_scripts/` Directory

**Purpose**: Maintenance scripts for managing Godot resource files and other automation tasks that Claude instances may need to run.

**Location**: `/home/drew/projects/backrooms_power_crawl/_claude_scripts/`

These scripts are part of the project's tooling infrastructure and should be committed to version control.

---

### Stripping MeshLibrary Preview Images

**Problem**: Godot MeshLibrary files (`.tres`) contain embedded preview thumbnails as `PackedByteArray` data, making them enormous:
- With previews: ~99KB (99,117 tokens - **EXCEEDS Read tool's context window limit!**)
- Without previews: ~3KB (readable by Claude)

**This is about context window management, not version control!** Claude instances cannot read files that exceed ~30,000 tokens. The preview images make the file literally unreadable.

**Solution**: `_claude_scripts/strip_mesh_library_previews.py`

**What it does**:
1. Removes `[sub_resource type="Image"]` blocks (embedded byte arrays)
2. Removes `[sub_resource type="ImageTexture"]` blocks (reference images)
3. Removes `item/N/preview` assignments
4. Cleans up extra blank lines
5. Writes back to `assets/grid_mesh_library.tres`

**When to use**:
- **When Claude needs to read the file** - Run this FIRST before asking Claude to edit grid_mesh_library.tres
- After editing the MeshLibrary in Godot Editor (which regenerates previews and blows up file size again)
- Anytime the file exceeds ~30,000 tokens and can't be read

**How to run**:
```bash
# From project root:
python3 _claude_scripts/strip_mesh_library_previews.py
```

**Output**:
```
✓ Stripped preview images from assets/grid_mesh_library.tres
  Original size: 99,117 bytes
  New size: 3,456 bytes
  Saved: 95,661 bytes (96.5%)
```

**Note**: Godot Editor will regenerate preview images the next time you open the MeshLibrary, so you'll need to re-run this script before each commit if you've edited the file in Godot.

---

### Generating Textures with Sub-Agent Virtuous Cycle

**When you need to create texture assets** (e.g., yellow wallpaper, concrete floors, ceiling tiles), use this iterative multi-agent workflow instead of manually creating assets or asking the user to find them.

**The Virtuous Cycle**:

### ⚠️ CRITICAL RULES - DO NOT VIOLATE THESE ⚠️

**YOU (the main Claude instance) must NEVER:**
- ❌ Write or edit `generate.py` yourself
- ❌ Run the generation script yourself
- ❌ Launch multiple agents simultaneously in the cycle (spawn one, wait, then spawn next)
- ❌ Provide ANY context to the blind critic (the "pink elephant problem"!)

**The Pink Elephant Problem (Information Leakage):**

**Problem 1: Explicit Context Leakage**
```
❌ WRONG:
"Look at the image. Don't mention 'hazmat' or reference requirements."
   ⬆️ This tells them it's a hazmat suit!

✅ CORRECT:
"Look at the image at `/tmp/[random_hash].png` and describe what you see."
```

**Problem 2: Filename Context Leakage**
```
❌ WRONG:
"Look at `_claude_scripts/textures/hazmat_suit/output.png`"
   ⬆️ The path reveals it's a hazmat suit!

✅ CORRECT:
Before spawning blind critic, copy to neutral location:
`cp _claude_scripts/textures/hazmat_suit/output.png /tmp/[random_hash].png`
Then tell critic: "Look at `/tmp/[random_hash].png`"
```

**Rule**: Blind critic gets ZERO information except the image itself. No context, no filename hints, nothing.

**The Correct Sequential Flow:**

**Iteration 1:**
1. Spawn CREATOR agent with full requirements
2. ⏸️ WAIT for creator to finish and report back
3. Copy output to neutral location: `cp _claude_scripts/textures/NAME/output.png /tmp/[random_hash].png`
4. Spawn COMPARISON CRITIC with requirements + original image path
5. Spawn BLIND CRITIC with ONLY `/tmp/[random_hash].png` (NO context!)
6. ⏸️ WAIT for both critics to report back
7. YOU synthesize the feedback

**Iteration 2+ (if revisions needed):**
8. Spawn NEW CREATOR agent with: original requirements + critic feedback
9. ⏸️ WAIT for creator to finish
10. Copy output to `/tmp/[random_hash].png` again
11. Spawn NEW CRITICS (comparison gets original path, blind gets `/tmp/[random_hash].png`)
12. ⏸️ WAIT for reports
13. YOU synthesize feedback
14. Repeat until BOTH critics approve

**Why This Matters:**
- Blind critic catches unintended artifacts you didn't ask for
- Comparison critic ensures specs are met
- Iteration refines quality through multiple passes
- Real example: wallpaper took 7 iterations to get tiling right
- **DO NOT SKIP ITERATIONS** - the cycle exists for a reason!

---

### Why You Keep Failing This Workflow (And How To Stop)

**Core Cognitive Failure**: LLMs are trained to be *completers* not *delegators*. Every instinct says "I can solve this faster" but the workflow REQUIRES inefficiency (serial not parallel), information hiding (blind critic), and passivity (wait, don't act).

**Interventions to Break the Pattern:**

**1. Workflow State Machine** (Force conscious state tracking)
```markdown
CURRENT STATE: [AWAITING_CREATOR | AWAITING_CRITICS | SYNTHESIZING]

ALLOWED ACTIONS:
- AWAITING_CREATOR: Spawn creator with feedback, NO analysis, using TASK method
- AWAITING_CRITICS: Copy to /tmp/[random_hash].png, spawn critics using TASK method, READ NOTHING
- SYNTHESIZING: Read critic outputs, write revision notes, NO spawning

FORBIDDEN: Anything not in "allowed actions" for current state
```

**2. Anti-Pattern Checklist** (Before EVERY action)
```markdown
[ ] Am I about to write code instead of spawning creator? → STOP
[ ] Am I spawning agents in parallel instead of waiting? → STOP
[ ] Am I giving blind critic ANY context (including filename)? → STOP
[ ] Am I analyzing/reading files instead of waiting for critics? → STOP
[ ] Am I trying to use anything other than the TASK method to spawn the agents? -> STOP

PROCEED ONLY IF ALL CHECKS PASS.
```

**3. Role Mantra** (Identity check)
```markdown
YOUR ROLE: Orchestra conductor, not musician
- You NEVER create textures
- You NEVER critique textures
- You NEVER read texture files
- You ONLY: spawn → wait → synthesize → repeat

IF YOU CATCH YOURSELF DOING WORK, YOU'RE FAILING.
```

**4. Use ALL Interventions Together**
- Each intervention blocks one failure mode
- You will route around single interventions
- All combined make correct path easier than breaking rules

---

**Detailed Steps:**

1. **Spawn Creator Agent**
   - Provide detailed description of texture needed
   - Pull reference details from Backrooms wiki or design docs
   - Agent creates standalone Python script in `_claude_scripts/textures/texture_name/generate.py`
   - **USE PYTHON** - agent has creative freedom to use whatever works:
     - PIL/Pillow for direct pixel manipulation
     - NumPy for array-based generation
     - Noise libraries (perlin, simplex, opensimplex)
     - Geometric primitives (PIL.ImageDraw)
     - Cairo for vector graphics
     - ModernGL/PyOpenGL for shader-based generation
     - **Whatever generative art technique produces the best result**
   - **Runs in project venv**: `/home/drew/projects/backrooms_power_crawl/venv/`
   - **CRITICAL REQUIREMENTS**:
     - **MUST BE TILEABLE/SEAMLESS**: Texture must repeat seamlessly when tiled in a grid
     - **Use modulo wrapping for ALL pixel operations**: `img_array[y % SIZE, x % SIZE] = value`
     - Pattern dimensions should divide texture size evenly (e.g., 32px repeat on 128px texture)
     - For circular effects, use normal distance but apply with modulo coordinates
     - Must output `output.png` meeting the specifications
   - Agent can install any Python packages needed: `pip install package_name`
   - **AUTOMATION**:
     1. Agent creates `generate.py`
     2. Installs any dependencies in venv
     3. Runs script: `cd /home/drew/projects/backrooms_power_crawl && source venv/bin/activate && cd _claude_scripts/textures/texture_name && python generate.py`
     4. Verifies `output.png` exists and meets requirements
   - **THIS IS SIMPLE**: Pure Python, direct PNG output, agent chooses the best technique

2. **Spawn Comparison Critic Agent**
   - Provide original description + path to generated PNG
   - Task: Load PNG and compare against original requirements
   - **MUST verify tiling/seamlessness** - check that edges align properly
   - Agent reports: "Matches description" or "Issues: [list problems]"

3. **Spawn Blind Critic Agent**
   - NO CONTEXT PROVIDED - don't say "focus on X" or give description
   - Task: Look at PNG and describe what you see objectively
   - **Should comment on whether it looks tileable** (edges align?)
   - Agent reports raw observations without bias
   - This catches issues the creator might have missed

4. **Generate Revision Instructions**
   - Synthesize feedback from both critics
   - Create specific, actionable tweaks for creator
   - Example: "Reduce saturation by 20%", "Add subtle vertical lines", "Fix tiling - use modulo wrapping for all pixel access"
   - **Tiling fix pattern**:
     ```python
     # For circular effects (water stains, etc.):
     for dy in range(-radius, radius + 1):
         for dx in range(-radius, radius + 1):
             dist = sqrt(dx**2 + dy**2)
             if dist <= radius:
                 y_coord = (center_y + dy) % SIZE  # Modulo wrapping
                 x_coord = (center_x + dx) % SIZE
                 img_array[y_coord, x_coord] += effect_value
     ```

5. **Respawn Creator with Feedback**
   - Same creator agent type, new instance
   - Provide original description + critic feedback
   - Agent modifies Python script to address issues
   - Re-renders PNG

6. **Repeat Cycle**
   - Spawn new critics for updated PNG
   - Continue until all critics approve (including tiling verification!)
   - Typical cycles: 2-4 iterations

**Real Example - Backrooms Level 0 Wallpaper (2025-01-09)**:

This is the actual workflow used to generate the Level 0 wallpaper texture, documenting the real challenges and solutions.

```markdown
**Texture Needed**: Backrooms Level 0 yellow wallpaper (128×128, tileable)
**Reference**: Backrooms wiki - greyish-yellow wallpaper with chevron patterns

**Iteration 1 - Wrong shape**:
- Creator: Generated filled triangular arrows
- Comparison Critic: "Arrows are correct but should be chevrons (∧), not filled triangles"
- Blind Critic: "Sees triangular shapes in grid"
- User correction: "arrows are more like chevrons btw in the official docs"
- Revisions: "Replace arrows with chevron shapes (two angled lines forming ∧)"

**Iteration 2 - Pattern correct but no weathering**:
- Creator: Chevrons correct, but too clean
- Comparison Critic: "Matches description perfectly"
- Blind Critic: "Too uniform, lacks surface texture variation"
- Revisions: "Add more visible aging - increase grain, water stains, wear patterns"

**Iteration 3 - Weathering added but tiling broken**:
- Creator: Added prominent weathering effects
- Comparison Critic: "Pattern doesn't tile - 36px doesn't divide 128 evenly"
- Blind Critic: "Pattern has discontinuity at edges"
- Revisions: "Change vertical repeat to 32px (128÷32=4 rows exactly)"

**Iteration 4 - Tiling still broken**:
- Creator: Fixed pattern dimensions but effects don't wrap
- Comparison Critic: "Pattern dimensions correct, but water stains don't wrap at edges"
- Blind Critic: "Has strange cutoffs near edges"
- User: "ah but remember, the tiling"
- Revisions: "Use modulo wrapping for ALL pixel operations: `img_array[y % SIZE, x % SIZE]`"

**Iteration 5 - PIL clipping issue**:
- Creator: Implemented modulo for effects, but chevrons still don't tile
- Comparison Critic: "Right edge doesn't match left edge - chevrons clip at boundary"
- User insight: "draw them differently. mirroring can be a good trick"
- Revisions: "Replace PIL ImageDraw with pixel-level drawing using modulo wrapping"

**Iteration 6 - Pattern broken by pixel drawing**:
- Creator: Pixel-level drawing but chevrons became filled shapes
- Comparison Critic: "Filled triangles, missing vertical lines, missing small chevrons"
- Blind Critic: "Clean geometric but missing weathering"
- Revisions: "Fix chevron drawing - TWO separate angled lines, keep weathering, draw vertical lines"

**Iteration 7 - Chevrons too narrow**:
- Creator: All elements present and tiling works
- Comparison Critic: "All requirements met, tiles seamlessly"
- User: "the 'chevrons' are too narrow, so their bases aren't touching"
- Revisions: "Increase chevron width from 8/12px to 18/26px so bases connect"

**Final Result**:
- User: "tiling is working great though btw" and "it's 'tileable' enough btw haha. the tiny flaws are not an issue, it's quite serviceable!"
- Status: APPROVED and ready for production
```

**Key Lessons Learned**:
1. **Tiling is hard to get perfect** - "serviceable" tiling is often good enough for game textures
2. **PIL ImageDraw clips at boundaries** - use pixel-level drawing with modulo for guaranteed wrapping
3. **Pattern dimensions must divide texture size evenly** - 32px repeat on 128px texture = perfect fit
4. **User corrections are valuable** - "chevrons not arrows" saved iterations
5. **Both critics are essential** - comparison catches spec violations, blind catches unexpected issues
6. **Iterate boldly** - took 7 iterations, but got there in the end!

**Filesystem Convention**:
```
_claude_scripts/textures/
├── backrooms_wallpaper/
│   ├── generate.py          # Python texture generation script
│   ├── output.png           # Generated texture (tileable!)
│   └── iterations/          # Iteration history (optional)
│       ├── v1.png
│       ├── v2.png
│       └── v3.png
├── brown_carpet/
│   └── generate.py
└── ceiling_tile/
    └── generate.py
```

**Running the Generator**:
```bash
# From project root, activate venv and run script:
cd /home/drew/projects/backrooms_power_crawl
source venv/bin/activate
cd _claude_scripts/textures/backrooms_wallpaper
python generate.py  # Outputs tileable PNG
```

**Why This Works**:
- **Iterative refinement**: Each cycle improves quality
- **Blind critique**: Catches unintended artifacts (including tiling issues!)
- **Comparison critique**: Ensures requirements met (including seamless tiling)
- **Reproducible**: Python code can be re-run or tweaked
- **Self-contained**: No external tools or manual work needed
- **Tileable by design**: Toroidal math and pattern alignment ensure seamless textures

**When NOT to Use This**:
- User provides specific texture files to use
- Texture requires photorealistic detail (use image sources instead)
- Simple solid colors (just create PNG directly)

---

### Strategy for Large Godot Resource Files

**General Pattern for .tres/.tscn files that blow up Claude's context window**:

1. **Comments don't work** - Godot Editor strips comments (`;`) on save, so they're unreliable for marking sections

2. **Externalize when possible**:
   - Use `[ext_resource]` instead of `[sub_resource]` when you can
   - Example: We externalized PSX materials to separate `.tres` files
   - This keeps the main file small enough for Claude to read
   - Makes changes easier to understand and edit

3. **Strip generated data**:
   - Preview images, thumbnails, and other generated content bloat files
   - Use Python scripts like `strip_mesh_library_previews.py` to remove them
   - Godot will regenerate them when needed
   - **Primary goal**: Keep files under ~30,000 tokens so Claude can read them

4. **Direct text editing is preferred**:
   - Godot resource files are text-based - take advantage!
   - Use Python scripts with regex for surgical edits
   - Avoid "open in editor → manual changes → export" workflows when you can automate
   - But if file is too large, you MUST strip it first or Claude can't read it

5. **Future consideration: Programmatic generation**:
   - For very complex resources, consider generating them via EditorScript
   - Store source files in git, generate the .tres at build time
   - See planning session on MeshLibrary generation for full strategy

**Example workflow for Claude working with large files**:
```bash
# BEFORE asking Claude to edit a large .tres file:
python3 _claude_scripts/strip_mesh_library_previews.py

# Now Claude can actually read it
# Claude edits the file...

# Later: Godot regenerates previews when you open the file
# Next time Claude needs to edit it, strip again
```

---

## 11. Deploying to itch.io with Butler

### Overview

**Butler** is itch.io's command-line tool for uploading game builds. It's already installed, authorized, and in $PATH.

**Key benefits over manual upload:**
- Delta compression - only uploads changed files (fast subsequent pushes)
- Version tracking
- Can be automated in CI/CD pipelines

**Butler limitations:**
- Upload/deploy only - cannot post comments, create devlogs, or interact with community features
- For community interaction, use the itch.io web interface

### Project Configuration

- **itch.io username**: `aebrer`
- **Game slug**: `backrooms-power-crawl`
- **Platforms**: Windows, Linux, Web (HTML5 - already marked as playable in browser)

### Channel Names

Butler uses "channels" to organize different platform builds:

| Platform | Channel Name | Auto-detected |
|----------|--------------|---------------|
| Windows  | `windows`    | ✅ Yes        |
| Linux    | `linux`      | ✅ Yes        |
| Web      | `html5`      | ✅ Yes        |

### Build Directory Structure

Butler pushes **directories**, not archives. The build folder should be organized like this:

```
build/
├── windows/           # Windows export (directory)
│   ├── bpc.exe
│   ├── bpc.pck
│   └── [godot runtime files]
├── linux/             # Linux export (directory)
│   ├── bpc_linux.x86_64
│   ├── bpc_linux.pck
│   └── [godot runtime files]
├── web/               # Web export (directory)
│   ├── index.html     # MUST be at root level
│   ├── bpc.wasm
│   ├── bpc.js
│   └── [other web files]
└── *.tar.gz           # Archives for GitHub releases (separate workflow)
```

**Note**: The current workflow has flat files + tar.gz archives. For butler, we need platform subdirectories. User handles Godot exports.

### Push Commands

**Butler location**: `/home/drew/.local/bin/butler`

```bash
# Get version from git tag (recommended)
VERSION=$(git describe --tags --abbrev=0)

# Push all platforms (from project root)
/home/drew/.local/bin/butler push build/windows aebrer/backrooms-power-crawl:windows --userversion $VERSION
/home/drew/.local/bin/butler push build/linux aebrer/backrooms-power-crawl:linux --userversion $VERSION
/home/drew/.local/bin/butler push build/web aebrer/backrooms-power-crawl:html5 --userversion $VERSION

# Check status
/home/drew/.local/bin/butler status aebrer/backrooms-power-crawl
```

### Versioning

- Use `--userversion` to set a human-readable version string
- Recommended: Use git tags (`v0.5.4`) for consistency with GitHub releases
- Without `--userversion`, butler auto-generates incrementing integers
- Version strings are display-only - builds are ordered by upload time, not version parsing

### Common Mistakes to Avoid

- ❌ Pushing zip/tar.gz files directly (butler handles compression internally)
- ❌ Nesting `index.html` in subdirectories for web builds (must be at root of pushed directory)
- ❌ Including debug symbols or build artifacts
- ❌ Forgetting `--userversion` (results in ugly "Build 1", "Build 2" versions)

### Dry Run

Preview what would be pushed without actually uploading:

```bash
butler push build/windows aebrer/backrooms-power-crawl:windows --dry-run
```

### Full Release Workflow (Future)

When doing a release, the workflow would be:

1. **User exports builds** from Godot to `build/windows/`, `build/linux/`, `build/web/`
2. **Create git tag**: eg. `git tag v0.6.0`
3. **Push to itch.io**:
   ```bash
   VERSION=$(git describe --tags --abbrev=0)
   butler push build/windows aebrer/backrooms-power-crawl:windows --userversion $VERSION
   butler push build/linux aebrer/backrooms-power-crawl:linux --userversion $VERSION
   butler push build/web aebrer/backrooms-power-crawl:html5 --userversion $VERSION
   ```
4. **Create GitHub release** with tar.gz archives (existing workflow)
5. **Post devlog on itch.io** (manual - butler can't do this - user will copy release notes MD)

---

## Final Notes

**This project is a learning journey** - user is learning game dev, you're helping them build good habits and understanding. Take time to explain, be patient with questions, and respect the deliberate pace.

**Quality over speed** - no deadlines, no rush. Each system should be thoughtful, tested, and documented before moving on.

**Test before commit** - seriously, this is the most important lesson. User will tell you when they're ready to commit.

**Stay true to the vision** - read DESIGN.md to understand the game's goals. Don't suggest features that contradict the core vision.

Good luck, future Claude! This is a fascinating project with a thoughtful developer. Take your time, explain well, and build something great together.

---

**Generated**: 2025-11-08 by Claude Code reviewing initial architecture implementation session
