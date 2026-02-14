# Refactor Plan: FPV-Default Camera Mode

**Date**: 2026-01-21
**Branch**: `feat/performance-profiling-speedups`
**Status**: Planning

---

## Summary

Change the default camera mode from tactical (third-person overhead) to FPV (first-person view), with a toggle to switch between them. This inverts the current "hold to enter FPV" pattern to "FPV is always on, toggle for tactical".

---

## Current Behavior

| Aspect | Current State |
|--------|---------------|
| **Default camera** | Tactical (third-person overhead) |
| **FPV activation** | HOLD RMB/LT to enter look mode |
| **FPV deactivation** | RELEASE RMB/LT returns to tactical |
| **Movement indicator** | Always visible in tactical, hidden in FPV |
| **Examination** | Only active while holding RMB/LT in FPV |
| **RT/LMB in tactical** | Move forward |
| **RT/LMB in FPV** | Wait (pass turn) |
| **RMB/LT in tactical** | Enter FPV (hold) |
| **Pause** | START/ESC/MMB → exits FPV, enters pause UI |

---

## Target Behavior

| Aspect | New State |
|--------|-----------|
| **Default camera** | FPV (first-person view) |
| **Camera toggle** | C key / SELECT button toggles between FPV ↔ Tactical |
| **Movement indicator** | Hidden in FPV (for now), visible in tactical |
| **Examination** | Always active in FPV (default state) |
| **RT/LMB in FPV** | Move forward (in camera look direction) |
| **RT/LMB in tactical** | Move forward (unchanged) |
| **RMB/LT in FPV** | Wait (pass turn) |
| **RMB/LT in tactical** | Wait (pass turn) - same as FPV now |
| **Pause** | START/ESC/MMB → pause UI (does NOT exit FPV) |

### Key Changes Summary
1. **FPV is default** - Game loads into FPV, not tactical
2. **Controls are unified** - RT/LMB = move, RMB/LT = wait, in BOTH modes
3. **Toggle replaces hold** - C/SELECT toggles camera instead of holding RMB/LT
4. **Examination always on in FPV** - No need to hold anything
5. **Pause doesn't change camera** - Pausing keeps current camera mode

---

## Architecture Analysis

### Current State Machine Flow

```
Game Start
    ↓
IdleState (tactical camera)
    │
    ├── RMB/LT PRESS → LookModeState (FPV camera)
    │                       │
    │                       ├── RMB/LT RELEASE → IdleState
    │                       └── RT/LMB → Wait → PreTurnState → ... → LookModeState
    │
    └── RT/LMB → Move → PreTurnState → ExecutingTurnState → PostTurnState → IdleState
```

### New State Machine Flow

```
Game Start
    ↓
IdleState (FPV camera by default, or tactical if toggled)
    │
    ├── C/SELECT → Toggle camera_mode (FPV ↔ Tactical)
    │
    ├── RT/LMB → Move forward → PreTurnState → ... → IdleState
    │
    └── RMB/LT → Wait → PreTurnState → ... → IdleState
```

**Key insight**: We can SIMPLIFY the state machine. `LookModeState` becomes unnecessary as a separate state. Instead, `IdleState` handles both camera modes with a `camera_mode` variable.

---

## Implementation Plan

### Phase 1: Input Action Setup

**File**: `project.godot`

1. **Add new input action**: `toggle_camera`
   - Keyboard: `C` key
   - Gamepad: `JOY_BUTTON_BACK` (SELECT button, index 4)

2. **Repurpose `look_mode` action** → rename to `wait_action` (optional, or just document the semantic change)
   - Still uses RMB/LT
   - Now means "wait" instead of "enter look mode"

### Phase 2: Merge LookModeState into IdleState

**Files to modify**:
- `scripts/player/states/idle_state.gd`
- `scripts/player/states/look_mode_state.gd` (DELETE after merge)
- `scripts/player/input_state_machine.gd`

**Changes to `idle_state.gd`**:

```gdscript
# NEW: Camera mode enum
enum CameraMode { FPV, TACTICAL }
var camera_mode: CameraMode = CameraMode.FPV  # FPV is default!

# NEW: Camera references (moved from LookModeState)
var first_person_camera: FirstPersonCamera = null
var tactical_camera: TacticalCamera = null
var examination_crosshair: ExaminationCrosshair = null
var examination_panel: ExaminationPanel = null

func enter() -> void:
    super.enter()
    # Initialize camera refs if needed
    _init_camera_refs()
    # Apply current camera mode
    _apply_camera_mode()
    # Update UI
    # (action preview removed)

func handle_input(event: InputEvent) -> void:
    # Camera toggle (C / SELECT)
    if event.is_action_pressed("toggle_camera"):
        _toggle_camera()
        return

    # Wait action (RMB / LT) - works in both modes
    if event.is_action_pressed("look_mode"):  # Repurposed: now means "wait"
        _execute_wait_action()
        return

    # Move forward handled in process_frame (hold-to-repeat)

func _toggle_camera() -> void:
    if camera_mode == CameraMode.FPV:
        camera_mode = CameraMode.TACTICAL
    else:
        camera_mode = CameraMode.FPV
    _apply_camera_mode()
    # (action preview removed)

func _apply_camera_mode() -> void:
    match camera_mode:
        CameraMode.FPV:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            tactical_camera.camera.current = false
            first_person_camera.activate()
            if player:
                player.hide_move_indicator()
            if examination_crosshair:
                examination_crosshair.show_crosshair()
        CameraMode.TACTICAL:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            first_person_camera.deactivate()
            tactical_camera.camera.current = true
            if player:
                player.update_move_indicator()
            if examination_crosshair:
                examination_crosshair.hide_crosshair()
            if examination_panel:
                examination_panel.hide_panel()

func process_frame(delta: float) -> void:
    # ... existing move forward logic ...

    # FPV-specific: Update examination raycast
    if camera_mode == CameraMode.FPV:
        _update_examination_target()

    # Update action preview
    # (action preview removed)
```

**Delete**: `scripts/player/states/look_mode_state.gd`

**Update `input_state_machine.gd`**:
- Remove LookModeState registration
- Update any references to LookModeState

### Phase 3: Update Camera Behavior

**File**: `scripts/player/first_person_camera.gd`

**Changes**:
- Always keep examination cache warm (don't clear on "deactivate" since we'll switch back)
- Or: keep cache management as-is but make activate/deactivate lighter

**File**: `scripts/player/tactical_camera.gd`

**No changes needed** - already handles rotation/zoom correctly.

### Phase 5: FPV FOV Adjustment

**File**: `scripts/player/first_person_camera.gd`

Since FPV is now the default mode, increase the default FOV for a more immersive feel.

**Current values**:
```gdscript
@export var default_fov: float = 95.0
@export var fov_min: float = 60.0
@export var fov_max: float = 110.0
```

**New values** (more generous range, higher default):
```gdscript
@export var default_fov: float = 90.0   # Was 75 - wider for immersion
@export var fov_min: float = 60.0       # Keep min (zoom in)
@export var fov_max: float = 110.0      # Was 90 - allow wider peripheral
```

The `@export` vars mean these can be tweaked in the editor without code changes.

### Phase 6: Pause System Update

**File**: `scripts/player/input_state_machine.gd`

**Current behavior** (lines 108-109):
```gdscript
func _on_pause_toggled(is_paused: bool) -> void:
    if is_paused and current_state and current_state.state_name == "LookModeState":
        change_state("IdleState")  # Exit look mode when pausing
```

**New behavior**:
```gdscript
func _on_pause_toggled(is_paused: bool) -> void:
    # Camera mode persists through pause - no state change needed
    pass
```

### Phase 7: Documentation Updates

**File**: `CLAUDE.md`

Update **Definitive Control Mappings** section:

```markdown
**Controller:**
- RT → Move forward (in camera look direction)
- LT → Wait (pass turn)
- Right stick → Camera rotation
- Left stick → Navigate HUD when paused
- START → Toggle pause
- SELECT → Toggle camera mode (FPV ↔ Tactical)
- LB + RB → Zoom

**Mouse + Keyboard:**
- LMB → Move forward (in camera look direction)
- RMB → Wait (pass turn)
- Mouse movement → Camera rotation
- ESC or MMB → Toggle pause
- C → Toggle camera mode (FPV ↔ Tactical)
- Mouse wheel → Zoom
- Mouse hover → Navigate HUD when paused
```

Update **Forward Indicator Movement System** section:
- Note that indicator is hidden in FPV mode
- Explain camera toggle behavior

Update **Key Files** section:
- Remove `look_mode_state.gd` reference
- Update `idle_state.gd` description
- Ensure missing files from other PRs are referenced (it's currently out of date)

---

## Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `project.godot` | Edit | Add `toggle_camera` input action |
| `scripts/player/states/idle_state.gd` | Major edit | Add camera mode, merge LookModeState logic |
| `scripts/player/states/look_mode_state.gd` | **DELETE** | Functionality merged into IdleState |
| `scripts/player/input_state_machine.gd` | Edit | Remove LookModeState, update pause handler |
| `scripts/player/first_person_camera.gd` | Edit | Increase default FOV (75→90), expand max (90→110) |
| `CLAUDE.md` | Edit | Update control mappings, key files, design patterns |

---

## Testing Checklist

### Functional Tests
- [ ] Game loads in FPV mode
- [ ] RT/LMB moves forward in FPV
- [ ] RT/LMB moves forward in Tactical
- [ ] RMB/LT waits in FPV
- [ ] RMB/LT waits in Tactical
- [ ] C/SELECT toggles camera mode
- [ ] Camera rotation works in both modes (mouse + gamepad)
- [ ] Examination crosshair shows in FPV
- [ ] Examination panel updates when looking at things in FPV
- [ ] Examination hidden in Tactical mode
- [ ] Move indicator hidden in FPV, visible in Tactical
- [ ] Pause works in both modes (doesn't change camera)
- [ ] Unpause returns to correct camera mode
- [ ] Hold-to-repeat movement works in both modes

### Input Parity Tests
- [ ] All controls work identically on gamepad
- [ ] All controls work identically on mouse+keyboard
- [ ] Device switching mid-game works correctly

### Edge Cases
- [ ] Toggling camera during turn execution
- [ ] Toggling camera while paused
- [ ] Fast camera toggles don't break state
- [ ] Pre-turn/post-turn states preserve camera mode

---

## Rollback Plan

If issues arise:
1. Keep `look_mode_state.gd` until fully tested
2. Use feature flag for new behavior: `const USE_FPV_DEFAULT := true`
3. Can revert to old behavior by setting flag to false

---

## User Decisions (Answered)

1. **Movement in FPV**: Just move immediately, no indicator flash needed ✓
2. **Tactical wait**: Yes, RMB/LT = wait in both modes (unified controls) ✓
3. **Examination in tactical**: FPV only for now ✓

---

## Notes

- This simplifies the state machine by removing a state
- Control scheme becomes more consistent (same actions in both modes)
- FPV-first design matches user's stated preference
- Examination becomes "always on" in FPV, more discoverable
