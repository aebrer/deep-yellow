# CLAUDE.md - Deep Yellow

**Project**: DEEP YELLOW - Turn-based Roguelike in Godot 4.6
**Developer**: Drew Brereton (aebrer) - Python/generative art background, learning game dev

General working style, communication preferences, debugging process, and commit conventions
are in the global `~/CLAUDE.md`. This file covers Deep Yellow-specific context only.

---

## Environment: CachyOS Native Linux

- Godot 4.6, custom-built with Tracy profiler integration
- Tracy-enabled binary: `/home/drew/projects/godot-tracy/godot-4.6/bin/godot.linuxbsd.editor.x86_64`
- Tracy viewer: `/home/drew/projects/godot-tracy/tracy/profiler/build/tracy-profiler`
- Tracy csvexport: `/home/drew/projects/godot-tracy/tracy/csvexport/build/tracy-csvexport`
- User handles all visual/interactive testing (GUI, controller, gameplay)

**Performance review (part of PR workflow):**
- Capture Tracy trace on the PR branch and compare against master branch baseline
- Export with: `tracy-csvexport trace.tracy | sort -t',' -k5 -rn | head -30` (top by total %)
- CSV columns: name, src_file, src_line, total_ns, total_perc, counts, mean_ns, min_ns, max_ns, std_ns
- Identify and crush any introduced bottlenecks before merging

**Headless commands Claude can run:**
```bash
godot --headless --quit 2>&1              # Validate project loads, autoloads init, no script errors
godot --headless --script test_script.gd  # Script validation
godot --headless --import                 # Trigger import of new scripts and textures
```

When ready for testing, say: "This is ready for you to test. When you run it, you should see [expected behavior]."

---

## Key Design Principles

**Controller-First, Input Parity is NON-NEGOTIABLE**
- All inputs have BOTH controller and keyboard+mouse mappings
- "Keyboard" means MOUSE MOVEMENT + keyboard, not just keyboard keys
- Test BOTH control schemes before considering a feature "done"
- Standard third-person controls: right stick OR mouse for camera rotation
- Don't reinvent camera controls — follow industry conventions (Fortnite/Gears of War)

**Turn-Based, Not Real-Time**
- NO `delta` time for gameplay logic (only for animations/polish)
- Pressure comes from resources/escalation, not timers
- Each action is discrete and turn-based

**Forward Indicator Movement**
- Green arrow shows 1 cell ahead in camera direction
- Rotate camera to aim, RT/LMB to move forward (with hold-to-repeat)
- DO NOT re-implement stick-based directional aiming — it was removed for better input parity

**Direct File Editing**
- Always edit Godot resource files (.tscn, .tres) directly when possible
- Don't make user manually import/export through Godot UI
- Godot files are text-based — take advantage of that

**Drew is learning game dev**
- Explain Godot-specific and game-dev-specific patterns when relevant
- Reference Python equivalents when helpful
- Don't assume knowledge of common game dev terminology

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 RAW INPUT LAYER                      │
│  Controller / Keyboard → Godot Input Actions         │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│            INPUTMANAGER (Autoload)                    │
│  Device abstraction, deadzone, analog → 8-dir grid   │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│            STATE MACHINE LAYER                       │
│  Player → InputStateMachine → Current State          │
│  States: Idle (FPV/Tactical), PreTurn, Executing,    │
│          PostTurn                                     │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────┐
│            ACTION LAYER (Command Pattern)             │
│  States create Actions → Actions validate & execute   │
│  Enables replays, AI, undo (future)                   │
└─────────────────────────────────────────────────────┘
```

**Why these patterns:**
- **InputManager (Autoload)**: Single source of truth for input, device abstraction, future replay/remapping
- **State Machine**: Turn-based game has distinct input modes; each state isolated, transitions via signals
- **Command Pattern**: Decouples intent from execution; AI can reuse same actions

---

## Control Mappings

**Do NOT add controls without explicit user request.**

Authoritative control list is in `scripts/ui/settings_panel.gd` (~line 510) — read that for current mappings. That's the single source of truth; don't duplicate it here.

**Camera System:**
- Game loads in FPV (first-person view) by default
- C/SELECT toggles FPV ↔ Tactical (third-person overhead)
- FOV: 90° default, range 60°-110°
- Examination crosshair in FPV, move indicator (green arrow) in Tactical

---

## 3D World Y Coordinates (Empirically Confirmed)

GridMap cell_size is `Vector3(2.0, 1.0, 2.0)` but visual Y doesn't map 1:1 to cell units.

| Y Value | What's There |
|---------|-------------|
| 4.4     | Ceiling surface (just below ceiling tiles) |
| 2.5     | Midpoint / eye level |
| 1.0     | Player / Entity billboards |
| 0.51    | Spraypaint floor text |
| 0.48    | Void-fill floor plane (black, hides under-wall void) |
| 0.0     | Bottom of floor cell (the void) |

Light fixture heights are per-level (defined in level config, not hardcoded).
Default lighting: ambient low + directional off (point lights provide all illumination).

---

## Key Files

**Autoloads** - `scripts/autoload/`
- `input_manager.gd` - Input normalization and device abstraction
- `logger.gd` / `logger_presets.gd` - Centralized logging with category/level filtering
- `level_manager.gd` - Level loading, LRU cache, transitions
- `entity_registry.gd` - Entity type definitions and spawning
- `knowledge_db.gd` - Examination/lore database
- `pathfinding_manager.gd` - A* pathfinding
- `pause_manager.gd` - Pause state and menu handling
- `ui_scale_manager.gd` - UI scaling for different resolutions
- `utilities.gd` - Common utility functions

**Player System** - `scripts/player/`
- `player_3d.gd` - 3D player controller, turn-based movement, stats
- `first_person_camera.gd` / `tactical_camera.gd` - Camera modes
- `input_state_machine.gd` + `states/` - State machine with idle, pre/executing/post turn states

**Actions** - `scripts/actions/`
- `action.gd` (base), `movement_action.gd`, `wait_action.gd`, `pickup_item_action.gd`, `toggle_item_action.gd`, `reorder_item_action.gd`, `sanity_damage_action.gd`

**Combat** - `scripts/combat/`
- `attack_executor.gd`, `attack_types.gd`, `pool_attack.gd`

**Entity/AI** - `scripts/ai/` and `scripts/world/`
- `entity_ai.gd` - Main AI controller
- `behaviors/` - Per-entity behaviors (bacteria_*, smiler_behavior)
- `world/world_entity.gd` - Entity data, `entity_renderer.gd` - Billboard rendering

**Items** - `scripts/items/` and `scripts/world/`
- `item.gd` (base), `item_pool.gd`, `item_rarity.gd`
- `world/world_item.gd`, `item_renderer.gd`, `item_spawner.gd`
- Individual items: `almond_water.gd`, `baseball_bat.gd`, `binoculars.gd`, etc.

**Procedural Generation** - `scripts/procedural/`
- `chunk_manager.gd` - Chunk streaming, infinite world
- `chunk.gd` / `sub_chunk.gd` / `chunk_generation_thread.gd` - Background generation
- `level_0_generator.gd` - WFC maze generator
- `level_config.gd` / `level_generator.gd` - Level configuration base classes
- `corruption_tracker.gd` - Corruption/difficulty scaling

**UI** - `scripts/ui/`
- `hud_element.gd` (base), `core_inventory.gd`, `stats_panel.gd`, `status_bars.gd`
- `examination_panel.gd`, `examination_crosshair.gd`, `minimap.gd`
- `exp_bar.gd`, `level_up_panel.gd`, `game_over_panel.gd`, `loading_screen.gd`, `start_menu.gd`

**Core** - `scripts/`
- `grid_3d.gd` - 3D grid with chunk streaming, proximity fade
- `game_3d.gd` - Main 3D scene coordinator
- `game.gd` - Main HUD layout with responsive design, embeds 3D viewport

**Shaders** - `shaders/`
- `psx_base.gdshaderinc` - Base PSX shader include (vertex snapping, UV)
- `psx_lit.gdshader` / `psx_lit_nocull.gdshader` - Standard lit PSX shaders
- `psx_unlit.gdshader` - Unlit variant
- `psx_wall_proximity.gdshader` / `psx_wall_proximity_nocull.gdshader` - Wall camera→player sightline cutout
- `psx_ceiling_proximity.gdshader` / `psx_ceiling_tactical.gdshader` - Ceiling proximity/tactical shaders
- `psx_sprite.gdshader` - Billboard sprite shader
- `pp_band-dither.gdshader` - Post-processing dither

**Components** - `scripts/components/`
- `examinable.gd` - Makes objects examinable via raycast
- `stat_block.gd` / `stat_modifier.gd` - Entity stats and temporary modifiers

---

## GDScript vs Python Gotchas

**Ternary evaluation** — GDScript evaluates BOTH sides before checking condition:
```gdscript
# ❌ Crashes if x is null:
var msg = x.entity_id if x else "null"
# ✅ Safe:
var msg = "null" if not x else x.entity_id
```

**Type system** — Static typing enforced at parse time, no forward references. Use untyped (Variant) to break circular dependencies.

**Other differences:**
- `null` not `None`; `%` string formatting (Python 2 style), no f-strings
- No list comprehensions — use loops or `map()`/`filter()` with lambdas
- Tabs for indentation (not spaces)

---

## Logging System

Accessed as `Log` autoload. Categories can be toggled on/off.

**Log levels:** TRACE → DEBUG → INFO → WARN → ERROR → NONE

**Category convenience methods** (most common usage):
```gdscript
Log.system("Game initialized")        # SYSTEM/INFO
Log.state("Entering IdleState")       # STATE/DEBUG
Log.movement("Moving to (5, 3)")      # MOVEMENT/DEBUG
Log.input(msg)  Log.action(msg)  Log.turn(msg)  Log.grid(msg)  Log.camera(msg)
```

**Cross-category level methods:**
```gdscript
Log.trace(Log.Category.STATE, "Frame update")
Log.warn(Log.Category.GRID, "Invalid cell")
Log.error(Log.Category.ACTION, "Action failed")
Log.msg(Log.Category.INPUT, Log.Level.DEBUG, "Stick moved")  # Generic
```

**Common mistake:** `Log.info()` doesn't exist — use category methods or `Log.msg()`.

---

## Texture Generation

Use the `generate-texture` skill when creating texture assets. It handles the full creator→critic→revision cycle with sub-agents.

Key rules:
- Main Claude instance NEVER writes `generate.py` or runs the script directly — delegate to sub-agents
- Blind critic gets ZERO context (no filenames, no requirements) — only a neutrally-named copy of the image
- Sequential flow: spawn creator → wait → spawn critics → wait → synthesize → repeat
- Scripts live in `_claude_scripts/textures/<name>/generate.py`, run in project venv
- Textures MUST be tileable (use modulo wrapping for all pixel operations)

---

## Deploying to itch.io

Use the `publish-deep-yellow` skill — it handles export, butler push, git tagging, and GitHub release creation.

Butler location: `/home/drew/.local/bin/butler`
Username: `aebrer` | Game slug: `deep-yellow` | Channels: `windows`, `linux`, `html5`
Build structure: `build/{windows,linux,web}/` — butler pushes directories, not archives. Web build must have `index.html` at root. Always use `--userversion` (git tags recommended).

---

## Godot 4 Gamepad Button Mapping

From Godot 4 engine source (`core/input/input_enums.h`):

| Index | Constant | Xbox | PlayStation |
|-------|----------|------|-------------|
| 0 | JOY_BUTTON_A | A | Cross (✕) |
| 1 | JOY_BUTTON_B | B | Circle (○) |
| 2 | JOY_BUTTON_X | X | Square (□) |
| 3 | JOY_BUTTON_Y | Y | Triangle (△) |
| 4 | JOY_BUTTON_BACK | Back/View | Share |
| **6** | **JOY_BUTTON_START** | **Start/Menu** | **Options** |
| 9 | JOY_BUTTON_LEFT_SHOULDER | LB | L1 |
| 10 | JOY_BUTTON_RIGHT_SHOULDER | RB | R1 |
| 11-14 | JOY_BUTTON_DPAD_* | D-Pad | D-Pad |

**Triggers are axes, not buttons:** Axis 4 = LT/L2, Axis 5 = RT/R2 (analog 0.0–1.0)
- Use `InputEventJoypadMotion` with axis 4/5, NOT `InputEventJoypadButton`
- A/B buttons are swapped between Xbox and Nintendo controllers
- **Start is button 6, NOT 11** (11 is D-Pad Up)

---

## Project Structure

```
/home/drew/projects/deep_yellow/
├── docs/              # Design and architecture docs
├── scenes/            # .tscn files
├── scripts/           # .gd files (autoload/, actions/, player/, ai/, etc.)
├── shaders/           # .gdshader files
├── assets/            # Art, audio, fonts, resources
├── _claude_scripts/   # Python maintenance/generation scripts
├── venv/              # Python virtual environment (gitignored)
└── build/             # Export output (gitignored)
```

File naming: scripts `snake_case.gd`, scenes `snake_case.tscn`, classes `PascalCase`, constants `UPPER_SNAKE_CASE`

---

## Notes

- Steam integration is a future goal — GodotSteam GDExtension, achievements tracked in `docs/achievement_brainstorming.md`
- Viewport culling active: 128x128 grid but only ~400 tiles rendered around player
- Python venv at `venv/` for maintenance scripts — activate with `source venv/bin/activate`
