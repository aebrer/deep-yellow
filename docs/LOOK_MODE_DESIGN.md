# Look Mode Design - First-Person Examination System

**Project**: Backrooms Power Crawl  
**Feature**: First-Person Look/Examination Mode  
**Version**: 1.0  
**Created**: 2025-11-09  
**Status**: Design Phase

---

## Table of Contents

1. [Overview](#overview)
2. [Design Goals](#design-goals)
3. [Technical Architecture](#technical-architecture)
4. [Input Handling](#input-handling)
5. [Examination System](#examination-system)
6. [UI Design](#ui-design)
7. [Code Examples](#code-examples)
8. [Integration Plan](#integration-plan)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Testing Strategy](#testing-strategy)

---

## Overview

Look Mode is a first-person examination system that allows players to inspect their surroundings in detail while maintaining the turn-based tactical gameplay. It provides a seamless transition between the tactical third-person camera and immersive first-person perspective for gathering information about entities, hazards, and the environment.

### Core Concept

- **Trigger**: Hold LT (gamepad) or Right Mouse Button (mouse+keyboard)
- **Dual Camera System**: Tactical third-person ↔ First-person look camera
- **Turn-Based**: Look mode PAUSES turn progression - examination takes no turns
- **Raycast Detection**: Center-screen crosshair detects Examinable objects
- **SCP-Style UI**: Clinical documentation panels with progressive information revelation
- **Knowledge Integration**: Examination increases discovery level and unlocks information

### Key Features

- **Instant camera switch** when trigger held/released
- **Free look rotation** with mouse or right stick (same controls as tactical camera)
- **Raycast-based detection** of Examinable objects in view
- **Dynamic examination UI** that appears when looking at examinable objects
- **Progressive information revelation** based on player knowledge and clearance
- **Turn-neutral**: Entering/exiting look mode does NOT consume turns
- **State machine integration** via new LookModeState

---

## Design Goals

### 1. **Input Parity (NON-NEGOTIABLE)**
- Gamepad and Mouse+Keyboard must have IDENTICAL functionality
- Same camera rotation controls in both tactical and look modes
- Perfect 1:1 mapping between control schemes

### 2. **Seamless Transition**
- Instant camera switch (no animation delay)
- Smooth control handoff between camera modes
- Clear visual feedback when entering/exiting look mode
- No interruption to game flow

### 3. **Information-First Design**
- Examination is the primary way to learn about entities and hazards
- Knowledge progression through observation
- Encourages exploration and curiosity
- Rewards careful examination with tactical advantages

### 4. **SCP Foundation Aesthetic**
- Monospace font (IBM Plex Mono)
- Clinical documentation style
- Redaction bars (████) for unknown information
- Clearance-based information revelation
- Object Class designations (Safe, Euclid, Keter, etc.)

### 5. **Turn-Based Respect**
- Look mode does NOT consume turns
- World is frozen while examining (turn-based = no real-time pressure)
- Can examine at leisure without penalty
- Encourages thoughtful tactical planning

---

## Technical Architecture

### Dual Camera System

```
Player3D (CharacterBody3D)
├── CameraRig (TacticalCamera)  ← Existing tactical camera
│   └── HorizontalPivot
│       └── VerticalPivot
│           └── SpringArm3D
│               └── Camera3D (tactical_camera)
│
└── FirstPersonCamera (NEW)
    └── HorizontalPivot
        └── VerticalPivot
            └── Camera3D (look_camera)
```

### Camera Switching Strategy

**Option A: Dual Camera Nodes (RECOMMENDED)**
- Two separate Camera3D nodes: `tactical_camera` and `look_camera`
- Only one has `current = true` at any time
- Switch by toggling `.current` property
- **Pros**: Clean separation, no transform juggling, easy to debug
- **Cons**: Slight memory overhead (negligible)

**Option B: Single Camera with Parent Switching**
- One Camera3D node that changes parents
- **Pros**: Single camera instance
- **Cons**: Complex, error-prone, harder to debug

**Decision: Use Option A** - Two camera nodes with `.current` toggle

### Camera Positioning

**Tactical Camera**:
- Positioned above and behind player (existing TacticalCamera)
- SpringArm distance: 8.0 - 25.0 units
- Pitch: -10° to -80° (looking down)
- Controlled by TacticalCamera script

**First-Person Camera**:
- Positioned at player eye height (~1.6 units above grid position)
- No SpringArm (direct child of VerticalPivot)
- Pitch: -90° to +90° (full vertical range)
- Controlled by FirstPersonCamera script

### State Machine Integration

```
InputStateMachine
├── IdleState          (current)
├── ExecutingTurnState (current)
└── LookModeState      (NEW)
```

**State Transitions**:
```
IdleState
  ├─ LT/RMB pressed → LookModeState
  └─ RT/Space/Click + valid → ExecutingTurnState

LookModeState
  ├─ LT/RMB released → IdleState
  └─ (turn progression paused, examine environment)

ExecutingTurnState
  └─ turn_complete → IdleState
```

### Raycast Detection System

```gdscript
# Raycast from camera center
var camera = first_person_camera.camera
var viewport = get_viewport()
var screen_center = viewport.get_visible_rect().size / 2

var ray_origin = camera.project_ray_origin(screen_center)
var ray_direction = camera.project_ray_normal(screen_center)
var ray_length = 10.0  # Maximum examination distance

# Perform raycast
var space_state = get_world_3d().direct_space_state
var query = PhysicsRayQueryParameters3D.create(
    ray_origin,
    ray_origin + ray_direction * ray_length
)
query.collision_mask = 8  # Examinable layer (layer 4)

var result = space_state.intersect_ray(query)
```

### Examinable Component

Objects that can be examined have an `Examinable` component (Node attached to entity):

```gdscript
class_name Examinable
extends Node3D

@export var entity_id: String  # e.g., "skin_stealer", "almond_water"
@export var entity_type: EntityType = EntityType.UNKNOWN
@export var base_threat_level: int = 0  # 0-5 scale
@export var requires_clearance: int = 0  # Minimum clearance to examine

enum EntityType {
    UNKNOWN,
    ENTITY_HOSTILE,
    ENTITY_NEUTRAL,
    ENTITY_FRIENDLY,
    HAZARD,
    ITEM,
    ENVIRONMENT
}
```

---

## Input Handling

### Input Actions (project.godot)

**NEW ACTIONS**:
```gdscript
# Look Mode Toggle
"look_mode": {
    "deadzone": 0.5,
    "events": [
        # Gamepad: Left Trigger (L2)
        InputEventJoypadButton (device: -1, button_index: 6),
        # Mouse+Keyboard: Right Mouse Button
        InputEventMouseButton (device: -1, button_index: 2)
    ]
}
```

**EXISTING ACTIONS** (used in look mode):
- Camera rotation: Right stick / Mouse movement (same as tactical camera!)
- Zoom: `camera_zoom_in` / `camera_zoom_out` (LB/RB + mouse wheel)

### Gamepad Controls (Look Mode Active)

| Input | Action |
|-------|--------|
| **Hold LT** | Enter/Stay in Look Mode |
| **Release LT** | Exit Look Mode → Return to Tactical |
| **Right Stick** | Rotate first-person camera (yaw + pitch) |
| **LB / RB** | Zoom FOV in/out (optional) |
| **Left Stick** | (Disabled in look mode - no movement) |
| **RT** | (Disabled in look mode - no turn actions) |

### Mouse+Keyboard Controls (Look Mode Active)

| Input | Action |
|-------|--------|
| **Hold RMB** | Enter/Stay in Look Mode |
| **Release RMB** | Exit Look Mode → Return to Tactical |
| **Mouse Movement** | Rotate first-person camera (yaw + pitch) |
| **Mouse Wheel** | Zoom FOV in/out (optional) |
| **WASD** | (Disabled in look mode - no movement) |
| **Space** | (Disabled in look mode - no turn actions) |

### Input Parity Validation

**Identical Functionality Checklist**:
- ✅ Same trigger input pattern (hold to activate)
- ✅ Same camera rotation input (right stick = mouse movement)
- ✅ Same zoom controls (shoulder buttons = mouse wheel)
- ✅ Same transition behavior (instant switch on trigger)
- ✅ Same examination raycast detection
- ✅ Same UI presentation

---

## Examination System

### Knowledge Database Integration

Look Mode integrates with the existing Knowledge system (from DESIGN.md):

```gdscript
# Singleton autoload
class_name KnowledgeDB
extends Node

# Player's knowledge state
var discovered_entities: Dictionary = {}  # entity_id -> discovery_level (0-3)
var clearance_level: int = 0  # 0-5 (0 = no clearance, 5 = maximum)
var researcher_classification: int = 0  # Total research score

# Called when player examines an entity
func examine_entity(entity_id: String) -> void:
    var current_level = discovered_entities.get(entity_id, 0)
    if current_level < 3:  # Max discovery level
        discovered_entities[entity_id] = current_level + 1
        researcher_classification += 1
        Log.info("Entity examined: %s (level %d)" % [entity_id, current_level + 1])

# Get display information for entity
func get_entity_info(entity_id: String) -> Dictionary:
    var discovery = discovered_entities.get(entity_id, 0)
    return EntityRegistry.get_info(entity_id, discovery, clearance_level)
```

### Entity Registry (Data-Driven)

Entity information is stored in JSON files (future) or GDScript resources:

```gdscript
# res://data/entities/skin_stealer.tres
class_name EntityInfo
extends Resource

@export var entity_id: String = "skin_stealer"

# Progressive name revelation (discovery level 0-3)
@export var name_levels: Array[String] = [
    "████████",                    # Discovery 0: Unknown
    "???",                         # Discovery 1: Detected
    "Humanoid Entity",             # Discovery 2: Identified
    "Skin-Stealer"                 # Discovery 3: Fully Known
]

# Progressive description revelation
@export var description_levels: Array[String] = [
    "[DATA EXPUNGED]",
    "Hostile entity detected. Approach with caution. [REDACTED]",
    "Hostile humanoid entity. Mimics human appearance. [FURTHER DATA REQUIRES CLEARANCE 2]",
    "Hostile humanoid entity. Mimics human appearance to lure victims. Attracted to sound and movement. Weakness: bright light causes disorientation. Containment: Non-lethal capture requires tranquilizer and reality cage."
]

# Clearance requirements for each level
@export var clearance_required: Array[int] = [0, 0, 2, 3]

# Threat classification
@export var object_class_levels: Array[String] = [
    "[REDACTED]",
    "Unknown",
    "Euclid",
    "Euclid"
]

@export var threat_level: int = 4  # 0-5 scale
```

### Examination Flow

```
1. Player enters Look Mode (hold LT/RMB)
2. Camera switches to first-person
3. Raycast checks center of screen every frame
4. If Examinable detected:
   a. Get entity_id from Examinable component
   b. Query KnowledgeDB for current discovery level
   c. Fetch EntityInfo from registry
   d. Display appropriate information level in UI
   e. On first examination: Increment discovery level
5. Player releases LT/RMB
6. Camera switches back to tactical
7. Return to IdleState
```

### Discovery Level Progression

| Level | Name | How to Achieve | Information Revealed |
|-------|------|----------------|---------------------|
| **0** | Unknown | Never seen before | Redacted name, no description |
| **1** | Detected | First examination | Partial name, vague description |
| **2** | Identified | Multiple examinations OR combat encounter | Full name, basic behavior, some tactics |
| **3** | Fully Known | Repeated examination + item unlock | Complete dossier, weaknesses, containment |

**Note**: Some information also requires clearance level (independent of discovery)

---

## UI Design

### Examination Panel (SCP-Style)

**Layout**:
```
┌─────────────────────────────────────────┐
│ OBJECT EXAMINATION REPORT               │
│ Document ID: BPC-████-█████              │
├─────────────────────────────────────────┤
│                                         │
│ Entity: [NAME FROM DISCOVERY LEVEL]     │
│ Class: [OBJECT CLASS]                   │
│ Threat: [THREAT LEVEL 0-5]              │
│                                         │
│ ─────────────────────────────────────── │
│                                         │
│ [DESCRIPTION FROM DISCOVERY LEVEL]      │
│                                         │
│ [Additional information based on       │
│  clearance and discovery...]           │
│                                         │
└─────────────────────────────────────────┘
```

**Visual Style**:
- Font: IBM Plex Mono (existing)
- Background: Black with 10% opacity (see-through to world)
- Border: White 2px line
- Text color: 
  - White for normal text
  - Yellow for warnings
  - Red for high-threat entities
  - Gray for [REDACTED] sections
- Redaction: `████` characters in gray

### Crosshair Design

**Center-screen indicator**:
- Small dot (2-3 pixels) when nothing targeted
- Expands to reticle (8-10 pixels) when Examinable detected
- Color changes based on entity type:
  - White: Environment/neutral
  - Yellow: Item
  - Orange: Non-hostile entity
  - Red: Hostile entity
  - Purple: Anomalous/special

### UI Visibility States

**1. Look Mode Inactive (Tactical Camera)**:
- No crosshair visible
- No examination panel

**2. Look Mode Active + No Target**:
- Crosshair visible (small dot)
- No examination panel
- Optional hint text: "Look at objects to examine"

**3. Look Mode Active + Target Detected**:
- Crosshair expands and changes color
- Examination panel fades in (0.2s transition)
- Panel positioned bottom-center or right side
- Panel updates in real-time as camera pans across objects

### Accessibility Considerations

- **Font size**: Minimum 14pt for readability
- **Contrast**: White on black with border for clarity
- **Animation**: Fade transitions keep frame rate high (no stuttering)
- **Panel position**: Configurable (bottom-center default, can move to side)
- **Colorblind mode**: Add symbols/icons in addition to color coding

---

## Code Examples

### FirstPersonCamera.gd

```gdscript
class_name FirstPersonCamera
extends Node3D
## First-person look camera for examination mode
##
## Attached to Player3D, activated when LT/RMB held.
## Shares rotation controls with TacticalCamera for input parity.

# Camera configuration
@export var rotation_speed: float = 360.0  # Same as TacticalCamera
@export var mouse_sensitivity: float = 0.15  # Same as TacticalCamera
@export var rotation_deadzone: float = 0.3  # Right stick deadzone

# Vertical rotation limits (full range for first-person)
@export var pitch_min: float = -89.0  # Look down
@export var pitch_max: float = 89.0   # Look up

# FOV (field of view)
@export var default_fov: float = 75.0
@export var fov_min: float = 60.0
@export var fov_max: float = 90.0
@export var fov_zoom_speed: float = 5.0

# Node references
@onready var h_pivot: Node3D = $HorizontalPivot
@onready var v_pivot: Node3D = $HorizontalPivot/VerticalPivot
@onready var camera: Camera3D = $HorizontalPivot/VerticalPivot/Camera3D

# State
var active: bool = false  # Controlled by LookModeState

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
    # Position at player eye height (set by parent Player3D)
    position = Vector3(0, 1.6, 0)  # Eye height
    
    # Initial rotation (facing forward)
    h_pivot.rotation_degrees.y = 0.0
    v_pivot.rotation_degrees.x = 0.0
    
    # Camera settings
    camera.fov = default_fov
    camera.current = false  # Start inactive
    
    Log.camera("FirstPersonCamera initialized - FOV: %.1f" % default_fov)

func _process(delta: float) -> void:
    if not active:
        return
    
    # Handle right stick camera controls (SAME AS TACTICAL CAMERA!)
    var right_stick_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
    var right_stick_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
    
    # Right stick X = horizontal rotation (yaw)
    if abs(right_stick_x) > rotation_deadzone:
        h_pivot.rotation_degrees.y -= right_stick_x * rotation_speed * delta
        h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)
    
    # Right stick Y = vertical rotation (pitch)
    if abs(right_stick_y) > rotation_deadzone:
        v_pivot.rotation_degrees.x -= right_stick_y * rotation_speed * delta
        v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)

func _unhandled_input(event: InputEvent) -> void:
    if not active:
        return
    
    # Mouse camera control (SAME AS TACTICAL CAMERA!)
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        # Mouse X = horizontal rotation (yaw)
        h_pivot.rotation_degrees.y -= event.relative.x * mouse_sensitivity
        h_pivot.rotation_degrees.y = fmod(h_pivot.rotation_degrees.y, 360.0)
        
        # Mouse Y = vertical rotation (pitch)
        v_pivot.rotation_degrees.x -= event.relative.y * mouse_sensitivity
        v_pivot.rotation_degrees.x = clamp(v_pivot.rotation_degrees.x, pitch_min, pitch_max)
        
        get_viewport().set_input_as_handled()
    
    # FOV zoom (optional - LB/RB or mouse wheel)
    if event.is_action_pressed("camera_zoom_in"):
        adjust_fov(-fov_zoom_speed)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("camera_zoom_out"):
        adjust_fov(fov_zoom_speed)
        get_viewport().set_input_as_handled()

# ============================================================================
# CAMERA CONTROL
# ============================================================================

func activate() -> void:
    """Switch to first-person camera"""
    active = true
    camera.current = true
    Log.camera("First-person camera activated")

func deactivate() -> void:
    """Switch back to tactical camera"""
    active = false
    camera.current = false
    Log.camera("First-person camera deactivated")

func adjust_fov(delta: float) -> void:
    """Adjust field of view (zoom effect)"""
    camera.fov = clampf(camera.fov + delta, fov_min, fov_max)

func reset_rotation() -> void:
    """Reset camera to forward facing (optional utility)"""
    h_pivot.rotation_degrees.y = 0.0
    v_pivot.rotation_degrees.x = 0.0

# ============================================================================
# RAYCAST UTILITIES
# ============================================================================

func get_look_raycast() -> Dictionary:
    """Perform raycast from camera center, return hit info"""
    var viewport = get_viewport()
    var screen_center = viewport.get_visible_rect().size / 2.0
    
    var ray_origin = camera.project_ray_origin(screen_center)
    var ray_direction = camera.project_ray_normal(screen_center)
    var ray_length = 10.0  # Maximum examination distance
    
    var space_state = get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(
        ray_origin,
        ray_origin + ray_direction * ray_length
    )
    query.collision_mask = 8  # Layer 4 = Examinable objects
    
    var result = space_state.intersect_ray(query)
    return result  # Empty dict if no hit, else {position, normal, collider, etc.}

func get_current_target() -> Examinable:
    """Get Examinable component from raycast target (or null)"""
    var hit = get_look_raycast()
    if hit.is_empty():
        return null
    
    var collider = hit.get("collider")
    if not collider:
        return null
    
    # Check if collider has Examinable component
    if collider is Examinable:
        return collider
    
    # Check if collider has Examinable as child node
    for child in collider.get_children():
        if child is Examinable:
            return child
    
    return null
```

### LookModeState.gd

```gdscript
class_name LookModeState
extends PlayerInputState
## State for first-person examination mode
##
## Entered when player holds LT/RMB.
## Exits when player releases LT/RMB.
## Turn progression is PAUSED during look mode.

@onready var first_person_camera: FirstPersonCamera = player.get_node("FirstPersonCamera")
@onready var tactical_camera: TacticalCamera = player.camera_rig
@onready var examination_ui: ExaminationUI = player.get_node("/root/Game/UI/ExaminationUI")

var current_target: Examinable = null

# ============================================================================
# STATE LIFECYCLE
# ============================================================================

func enter() -> void:
    Log.state("Entering LookModeState")
    
    # Switch cameras
    tactical_camera.camera.current = false
    first_person_camera.activate()
    
    # Show examination UI
    examination_ui.show_crosshair()
    
    # Hide tactical UI elements
    player.hide_move_indicator()

func exit() -> void:
    Log.state("Exiting LookModeState")
    
    # Switch back to tactical camera
    first_person_camera.deactivate()
    tactical_camera.camera.current = true
    
    # Hide examination UI
    examination_ui.hide_crosshair()
    examination_ui.hide_panel()
    
    # Restore tactical UI
    player.update_move_indicator()

func handle_input(event: InputEvent) -> void:
    # Exit look mode when trigger released
    if event.is_action_released("look_mode"):
        state_transition_requested.emit("IdleState")
        return
    
    # Block all other inputs while in look mode
    # (Camera rotation handled by FirstPersonCamera directly)

func process_frame(delta: float) -> void:
    # Update raycast and examination target
    var new_target = first_person_camera.get_current_target()
    
    if new_target != current_target:
        _on_target_changed(new_target)
        current_target = new_target
    
    # Update UI based on current target
    if current_target:
        examination_ui.show_panel(current_target)
    else:
        examination_ui.hide_panel()

# ============================================================================
# TARGET HANDLING
# ============================================================================

func _on_target_changed(new_target: Examinable) -> void:
    """Called when raycast target changes"""
    if new_target:
        Log.trace("Looking at: %s" % new_target.entity_id)
        examination_ui.set_target(new_target)
        
        # Increment discovery level on first examination
        KnowledgeDB.examine_entity(new_target.entity_id)
    else:
        Log.trace("No target in view")
        examination_ui.clear_target()
```

### ExaminationUI.gd

```gdscript
class_name ExaminationUI
extends Control
## UI overlay for look mode examination
##
## Shows crosshair and SCP-style examination panel

# Node references
@onready var crosshair: TextureRect = $Crosshair
@onready var panel: PanelContainer = $ExaminationPanel
@onready var entity_name_label: Label = $ExaminationPanel/VBox/EntityName
@onready var object_class_label: Label = $ExaminationPanel/VBox/ObjectClass
@onready var threat_level_label: Label = $ExaminationPanel/VBox/ThreatLevel
@onready var description_label: RichTextLabel = $ExaminationPanel/VBox/Description

# State
var current_target: Examinable = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
    # Hide everything by default
    crosshair.visible = false
    panel.visible = false
    
    # Position crosshair at screen center
    crosshair.position = get_viewport_rect().size / 2.0 - crosshair.size / 2.0
    
    # Style panel (SCP aesthetic)
    _setup_panel_style()

func _setup_panel_style() -> void:
    """Configure SCP-style panel appearance"""
    # Panel background
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0, 0, 0, 0.85)  # Nearly opaque black
    style.border_color = Color(1, 1, 1, 1)  # White border
    style.border_width_left = 2
    style.border_width_right = 2
    style.border_width_top = 2
    style.border_width_bottom = 2
    panel.add_theme_stylebox_override("panel", style)
    
    # Font (IBM Plex Mono already set globally)
    # Colors handled per-label

# ============================================================================
# CROSSHAIR
# ============================================================================

func show_crosshair() -> void:
    crosshair.visible = true
    crosshair.modulate = Color.WHITE  # Default color

func hide_crosshair() -> void:
    crosshair.visible = false

func set_crosshair_color(color: Color) -> void:
    """Change crosshair color based on target type"""
    crosshair.modulate = color

# ============================================================================
# EXAMINATION PANEL
# ============================================================================

func show_panel(target: Examinable) -> void:
    """Display examination info for target"""
    if not target:
        hide_panel()
        return
    
    # Get entity info from knowledge database
    var info = KnowledgeDB.get_entity_info(target.entity_id)
    
    # Update labels
    entity_name_label.text = info.get("name", "Unknown")
    object_class_label.text = "Class: " + info.get("object_class", "[REDACTED]")
    threat_level_label.text = "Threat: " + _format_threat_level(info.get("threat_level", 0))
    description_label.text = info.get("description", "[DATA EXPUNGED]")
    
    # Set colors based on threat
    var threat = info.get("threat_level", 0)
    _set_threat_colors(threat)
    
    # Set crosshair color
    var entity_type = target.entity_type
    set_crosshair_color(_get_entity_type_color(entity_type))
    
    # Show panel
    panel.visible = true

func hide_panel() -> void:
    panel.visible = false

func set_target(target: Examinable) -> void:
    current_target = target

func clear_target() -> void:
    current_target = null

# ============================================================================
# FORMATTING HELPERS
# ============================================================================

func _format_threat_level(level: int) -> String:
    """Convert threat level to display string"""
    match level:
        0: return "Minimal"
        1: return "Low"
        2: return "Moderate"
        3: return "High"
        4: return "Severe"
        5: return "Critical"
        _: return "Unknown"

func _set_threat_colors(threat: int) -> void:
    """Set label colors based on threat level"""
    var color: Color
    match threat:
        0, 1: color = Color.WHITE
        2: color = Color.YELLOW
        3, 4: color = Color.ORANGE
        5: color = Color.RED
        _: color = Color.GRAY
    
    threat_level_label.add_theme_color_override("font_color", color)

func _get_entity_type_color(entity_type: Examinable.EntityType) -> Color:
    """Get crosshair color for entity type"""
    match entity_type:
        Examinable.EntityType.ENTITY_HOSTILE:
            return Color.RED
        Examinable.EntityType.ENTITY_NEUTRAL:
            return Color.ORANGE
        Examinable.EntityType.ENTITY_FRIENDLY:
            return Color.GREEN
        Examinable.EntityType.HAZARD:
            return Color.YELLOW
        Examinable.EntityType.ITEM:
            return Color.CYAN
        Examinable.EntityType.ENVIRONMENT:
            return Color.WHITE
        _:
            return Color.GRAY
```

### Examinable.gd

```gdscript
class_name Examinable
extends Area3D
## Component for objects that can be examined in Look Mode
##
## Attach to entities, items, hazards, or environment objects.
## Must be on collision layer 4 (mask = 8) for raycast detection.

@export_group("Entity Information")
@export var entity_id: String = ""  ## Unique ID, e.g., "skin_stealer"
@export var entity_type: EntityType = EntityType.UNKNOWN

@export_group("Requirements")
@export var requires_clearance: int = 0  ## Min clearance to examine (0 = no requirement)
@export var requires_discovery: int = 0  ## Min discovery level to show info

enum EntityType {
    UNKNOWN,
    ENTITY_HOSTILE,
    ENTITY_NEUTRAL,
    ENTITY_FRIENDLY,
    HAZARD,
    ITEM,
    ENVIRONMENT
}

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
    # Ensure Area3D is configured correctly
    collision_layer = 8  # Layer 4
    collision_mask = 0   # Doesn't collide with anything, just detects raycasts
    
    # Add collision shape if not present (for raycast detection)
    if get_child_count() == 0:
        _add_default_collision_shape()
    
    if entity_id.is_empty():
        push_warning("Examinable has no entity_id set: %s" % get_parent().name)

func _add_default_collision_shape() -> void:
    """Add a default box collision shape if none exists"""
    var shape = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = Vector3(1, 2, 1)  # Human-sized default
    shape.shape = box
    add_child(shape)

# ============================================================================
# EXAMINATION API
# ============================================================================

func can_examine() -> bool:
    """Check if player meets requirements to examine this object"""
    return KnowledgeDB.clearance_level >= requires_clearance

func get_display_info() -> Dictionary:
    """Get information to display in examination UI"""
    if not can_examine():
        return {
            "name": "[INSUFFICIENT CLEARANCE]",
            "object_class": "[REDACTED]",
            "threat_level": 0,
            "description": "CLEARANCE LEVEL %d REQUIRED" % requires_clearance
        }
    
    return KnowledgeDB.get_entity_info(entity_id)
```

---

## Integration Plan

### Phase 1: Camera Setup (1-2 hours)

1. **Create FirstPersonCamera node**:
   - Add to Player3D scene as sibling to CameraRig
   - Set up HorizontalPivot → VerticalPivot → Camera3D hierarchy
   - Position at eye height (1.6 units above player)

2. **Implement FirstPersonCamera.gd**:
   - Copy rotation logic from TacticalCamera (input parity!)
   - Add activate/deactivate functions
   - Implement raycast utilities

3. **Test camera switching**:
   - Manual toggle in debug mode
   - Verify smooth transition
   - Verify input parity (gamepad + mouse)

### Phase 2: State Machine Integration (1-2 hours)

1. **Create LookModeState.gd**:
   - Extend PlayerInputState
   - Handle state entry/exit
   - Camera activation/deactivation
   - Input handling (detect trigger release)

2. **Add state transitions**:
   - IdleState: Detect LT/RMB press → transition to LookModeState
   - LookModeState: Detect LT/RMB release → transition to IdleState

3. **Test state machine**:
   - Enter/exit look mode smoothly
   - Verify turn progression pauses in look mode
   - Verify return to idle state works

### Phase 3: Examinable Component (2-3 hours)

1. **Create Examinable.gd**:
   - Extend Area3D
   - Set collision layer to 4 (mask = 8)
   - Export entity_id, entity_type, requirements

2. **Add Examinable to test entities**:
   - Create simple test cube entity
   - Add Examinable component
   - Configure entity_id and type

3. **Test raycast detection**:
   - Verify raycast hits Examinable collision
   - Log entity_id when looking at object
   - Verify raycast ignores non-examinable objects

### Phase 4: Knowledge Database (3-4 hours)

1. **Create KnowledgeDB autoload**:
   - Singleton for player knowledge state
   - Discovery level tracking (Dictionary)
   - Clearance level (int)
   - examine_entity() function

2. **Create EntityRegistry**:
   - Singleton for entity definitions
   - Load EntityInfo resources
   - get_info() function with discovery/clearance filtering

3. **Create test EntityInfo resources**:
   - Define 2-3 test entities
   - Set up progressive revelation arrays
   - Test discovery level progression

4. **Test knowledge system**:
   - Examine entity → discovery level increases
   - Re-examine → info becomes more detailed
   - Verify clearance requirements

### Phase 5: Examination UI (4-5 hours)

1. **Create ExaminationUI scene**:
   - Control node covering full viewport
   - Crosshair (TextureRect, center-screen)
   - ExaminationPanel (PanelContainer, bottom-center)
   - Labels for name, class, threat, description

2. **Implement ExaminationUI.gd**:
   - show_crosshair() / hide_crosshair()
   - show_panel() / hide_panel()
   - Color coding by threat/type
   - SCP-style formatting

3. **Integrate with LookModeState**:
   - Update UI each frame based on raycast
   - Show panel when target detected
   - Hide panel when no target

4. **Test UI**:
   - Look at entity → panel appears
   - Look away → panel disappears
   - Verify color coding
   - Verify redaction works

### Phase 6: Polish & Testing (2-3 hours)

1. **Input parity validation**:
   - Test gamepad controls
   - Test mouse+keyboard controls
   - Verify identical functionality

2. **Performance optimization**:
   - Profile raycast frequency (should be fine at 60 FPS)
   - Optimize UI updates (only update on change)

3. **Visual polish**:
   - Smooth panel fade in/out
   - Crosshair animations
   - Sound effects (optional)

4. **Documentation**:
   - Update ARCHITECTURE.md
   - Add inline code comments
   - Update project README

### Phase 7: Content Integration (Ongoing)

1. **Add Examinable to game entities**:
   - Walls, floors, ceiling tiles
   - Items (almond water, etc.)
   - Hazards (liquid pools, etc.)
   - Future: Hostile entities when implemented

2. **Create EntityInfo resources**:
   - One per entity type
   - Progressive revelation text
   - Clearance requirements

3. **Balance discovery progression**:
   - How many examinations to reach level 3?
   - Clearance level gating
   - Reward exploration

---

## Implementation Roadmap

### Sprint 1: Core Camera System (Week 1)

**Goal**: Get first-person camera working with input parity

**Tasks**:
- ✅ Create FirstPersonCamera node hierarchy
- ✅ Implement FirstPersonCamera.gd (rotation, activation)
- ✅ Add LookModeState to state machine
- ✅ Test camera switching (manual toggle)
- ✅ Verify input parity (gamepad + mouse)

**Deliverable**: Can toggle between tactical and first-person cameras

---

### Sprint 2: Raycast & Examinable (Week 1-2)

**Goal**: Detect objects in first-person view

**Tasks**:
- ✅ Implement raycast system in FirstPersonCamera
- ✅ Create Examinable component (Area3D)
- ✅ Add Examinable to test entity
- ✅ Log entity_id when looking at object
- ✅ Test collision layers (layer 4 for examinables)

**Deliverable**: Can detect when looking at examinable objects

---

### Sprint 3: Knowledge System (Week 2)

**Goal**: Track player knowledge and discovery

**Tasks**:
- ✅ Create KnowledgeDB autoload
- ✅ Create EntityRegistry autoload
- ✅ Create EntityInfo resource class
- ✅ Create 2-3 test entities with progressive info
- ✅ Test discovery level progression

**Deliverable**: Entity information reveals progressively

---

### Sprint 4: Examination UI (Week 2-3)

**Goal**: Display examination information

**Tasks**:
- ✅ Create ExaminationUI scene
- ✅ Implement crosshair display
- ✅ Implement SCP-style panel
- ✅ Color coding by threat/type
- ✅ Integrate with LookModeState

**Deliverable**: Full examination UI functional

---

### Sprint 5: Polish & Integration (Week 3)

**Goal**: Refine and integrate into main game

**Tasks**:
- ✅ Input parity testing (gamepad + M+KB)
- ✅ Performance optimization
- ✅ Visual polish (animations, transitions)
- ✅ Add Examinable to all game entities
- ✅ Update documentation

**Deliverable**: Look Mode fully integrated and tested

---

### Sprint 6: Content Creation (Week 4+)

**Goal**: Create entity documentation content

**Tasks**:
- Create EntityInfo for all entities
- Write SCP-style descriptions
- Balance discovery progression
- Create redaction system
- Add clearance requirements

**Deliverable**: Rich examination content

---

## Testing Strategy

### Unit Tests

**FirstPersonCamera**:
- ✅ Camera activates/deactivates correctly
- ✅ `.current` property switches between cameras
- ✅ Rotation inputs work (gamepad + mouse)
- ✅ Raycast returns correct results
- ✅ get_current_target() finds Examinable

**LookModeState**:
- ✅ State enters when LT/RMB pressed
- ✅ State exits when LT/RMB released
- ✅ Transitions to IdleState on exit
- ✅ Turn progression paused during look mode

**Examinable**:
- ✅ Collision layer set to 4 (mask = 8)
- ✅ Raycast detects Examinable
- ✅ can_examine() respects clearance
- ✅ get_display_info() returns correct data

**KnowledgeDB**:
- ✅ Discovery level increments on examine
- ✅ Discovery level caps at 3
- ✅ Clearance requirements respected
- ✅ get_entity_info() returns appropriate level

### Integration Tests

**Camera Switching**:
- ✅ Hold LT → first-person camera active
- ✅ Release LT → tactical camera active
- ✅ No visual glitches during transition
- ✅ Mouse still captured in both modes

**Examination Flow**:
- ✅ Look at entity → crosshair changes color
- ✅ Look at entity → panel appears
- ✅ Look away → panel disappears
- ✅ Multiple targets in view → updates correctly

**Input Parity**:
- ✅ Gamepad: LT + right stick works
- ✅ M+KB: RMB + mouse movement works
- ✅ Both control schemes produce identical results
- ✅ Zoom controls work in both modes

**Knowledge Progression**:
- ✅ First examination: Discovery 0 → 1
- ✅ Repeated examination: Discovery 1 → 2 → 3
- ✅ Higher discovery = more info revealed
- ✅ Clearance gates some information

### Playtest Scenarios

**Scenario 1: First-time Examination**
1. Player enters game (discovery level 0 for all entities)
2. Player holds LT to enter look mode
3. Player looks at test entity (Skin-Stealer)
4. **Expected**: Crosshair turns red, panel shows "████████" name
5. Player releases LT to exit look mode
6. Player re-enters look mode and looks at same entity
7. **Expected**: Panel now shows "???" name (discovery level 1)

**Scenario 2: Clearance Requirements**
1. Player has clearance level 1
2. Player examines entity requiring clearance 2
3. **Expected**: Panel shows "[INSUFFICIENT CLEARANCE]"
4. Player gains clearance level 2 (via gameplay)
5. Player examines same entity again
6. **Expected**: Panel now shows entity information

**Scenario 3: Input Parity**
1. Tester uses gamepad: Hold LT, use right stick to rotate
2. Tester switches to M+KB: Hold RMB, use mouse to rotate
3. **Expected**: Both control schemes feel identical
4. **Expected**: Camera rotation speed and sensitivity match

**Scenario 4: Performance**
1. Player rapidly enters/exits look mode (spam LT)
2. **Expected**: No frame drops, smooth transitions
3. Player looks at 10+ examinable objects in quick succession
4. **Expected**: UI updates without lag
5. Player examines while moving (if allowed)
6. **Expected**: Raycast and UI remain accurate

### Acceptance Criteria

**MUST HAVE** (Critical for release):
- ✅ Perfect input parity between gamepad and M+KB
- ✅ Smooth camera switching (no visual glitches)
- ✅ Raycast detects Examinable objects reliably
- ✅ Knowledge system tracks discovery correctly
- ✅ Examination UI displays correct information
- ✅ Turn progression pauses during look mode
- ✅ No performance issues (60 FPS maintained)

**SHOULD HAVE** (Important but not blocking):
- ✅ SCP-style UI aesthetic matches design
- ✅ Color coding for entity types
- ✅ Smooth panel fade in/out
- ✅ Crosshair animation on target
- ✅ Sound effects on examine

**NICE TO HAVE** (Polish):
- Keyboard shortcuts for quick examine (hold E?)
- Gamepad rumble on examine discovery
- Screen shake on high-threat entity
- Glitch effects for anomalous entities
- Voiceover reading entity names

---

## Future Enhancements

### Dynamic Descriptions

Entity descriptions could change based on context:
- Proximity: "The entity is 3 meters away"
- State: "The entity appears agitated"
- Environment: "The entity is standing in almond water"

### Examination Mini-Games

For certain entities, require the player to:
- Hold crosshair steady on target for X seconds
- Trace outline of entity with crosshair
- Find weak points by examining specific body parts

### Photo Mode Integration

- Press button in look mode to capture screenshot
- Captured images stored in journal/database
- Images unlock additional lore entries

### Audio Logs

- Some entities have audio logs attached
- Automatically plays when examined (first time only)
- Voiceover narration of SCP documentation

### Multiplayer Examination

(Future if multiplayer added):
- One player examines, other sees what they're looking at
- Shared knowledge database
- Collaborative documentation

---

## Appendix: Design Alternatives Considered

### Alternative 1: Examination Without Camera Switch

**Idea**: Keep tactical camera, show tooltip on hover (like RTS)

**Pros**:
- Simpler implementation
- No camera switching complexity
- Faster to use (no mode change)

**Cons**:
- Less immersive
- Harder to see small details
- Doesn't fit SCP horror aesthetic
- Mouse hover doesn't work on gamepad

**Decision**: REJECTED - First-person is more immersive and fits theme

---

### Alternative 2: Hold Button to Examine, Press to Lock

**Idea**: Hold LT to enter look mode, press A to "lock" examination on target

**Pros**:
- Can examine while moving cursor to next target
- Locked panel stays visible

**Cons**:
- More complex state management
- Confusing UX (hold vs press distinction)
- Breaks "turn-based" philosophy (lock implies real-time)

**Decision**: REJECTED - Keep it simple (hold to look, release to exit)

---

### Alternative 3: Separate Examine Button (Not Camera Trigger)

**Idea**: LT enters first-person, separate button (X/E) examines target

**Pros**:
- Separates "look" from "examine"
- Could add other first-person interactions

**Cons**:
- Extra button required (complexity)
- Examination is passive (just looking), doesn't need action button
- Breaks input simplicity goal

**Decision**: REJECTED - Automatic examination on look is simpler

---

### Alternative 4: Top-Down Cursor Examination (No First-Person)

**Idea**: Use right stick to move cursor on tactical view, examine tile

**Pros**:
- No camera switching needed
- Works well for grid-based game
- Similar to Caves of Qud

**Cons**:
- Not as immersive for horror game
- Cursor movement less intuitive on 3D tactical view
- Doesn't show vertical details (walls, ceiling)

**Decision**: REJECTED - First-person better for horror/immersion

---

## Conclusion

Look Mode provides a crucial gameplay mechanic for Backrooms Power Crawl: the ability to inspect and learn about the dangerous world. By combining:

- **Dual camera system** (tactical ↔ first-person)
- **Perfect input parity** (gamepad = M+KB)
- **Progressive knowledge revelation** (SCP-style documentation)
- **Turn-based respect** (no turn cost to examine)

...we create an immersive examination system that rewards curiosity and supports the game's core loop of exploration, documentation, and tactical decision-making.

The system is designed to be:
- **Simple to use** (hold trigger to look, release to exit)
- **Immersive** (first-person perspective with SCP aesthetic)
- **Rewarding** (discovery progression unlocks knowledge)
- **Performant** (60 FPS, efficient raycasts)
- **Accessible** (works identically on all input devices)

Implementation is broken into 6 sprints over ~3-4 weeks, with each sprint delivering testable functionality. The system integrates cleanly with existing Player3D, InputStateMachine, and Logger systems.

---

**Document Status**: ✅ Complete - Ready for Implementation
**Next Step**: Begin Sprint 1 (Core Camera System)
**Estimated Total Time**: 15-20 hours (spread over 3-4 weeks)

