# Visual Design Document - Backrooms Power Crawl

## Overview

This document covers the visual design implementation for Backrooms Power Crawl, focusing on achieving a hybrid aesthetic that combines:
- **PSX-era rendering**: Low-poly geometry, vertex snapping, affine texture mapping, color banding
- **90s VR/Cyberspace wireframe grids**: Tron-style neon grids, terminal interfaces, retro-futuristic UI
- **Liminal horror atmosphere**: Dim lighting, subtle corruption, unsettling spaces

---

## 90s Wireframe Grid Visualization

### Aesthetic Reference

**Historical Context:**
The 90s computer graphics wireframe grid is an iconic visual element that emerged from early 3D graphics and virtual reality visualization. Key influences include:

- **Tron (1982)**: Pioneered the laser grid aesthetic with dark backgrounds and glowing primary-colored lines converging on vanishing points
- **Battlezone (1980)**: Wireframe vector graphics with green lines against black backgrounds, defining early VR aesthetics
- **The Black Hole (1979)**: POV shots roaming through green laser grids suspended in dark space
- **Early VR Interfaces**: Terminal-style displays, grid-based environments, monochrome phosphor glow

**Visual Characteristics:**
- Central vanishing point perspective
- Dark or black background
- Thin lines in primary colors (green, cyan, magenta)
- Grid-based floor/environment
- Optional: CRT scanlines, phosphor glow, chromatic aberration
- Neon/emissive properties on wireframe edges

### Technical Approach: Barycentric Wireframe Shader

Wireframe rendering in modern 3D engines can be achieved through barycentric coordinate-based fragment shaders. This technique draws wireframe lines along triangle edges without requiring geometry shaders or duplicate geometry.

**Method**: Use `VERTEX_ID` in vertex shader to assign barycentric coordinates, then use `fwidth()` in fragment shader to detect proximity to edges.

**Advantages:**
- Single material pass (no geometry shader needed)
- Adjustable wireframe width and smoothness
- Can blend with or replace existing textures
- Performance-friendly for moderate mesh complexity

**Limitations:**
- Works best with flat-shaded or non-indexed geometry
- `VERTEX_ID` may be unreliable with smooth-shaded meshes
- Requires Godot 4.0+ for `VERTEX_ID` access
- Performance scales with triangle count (not ideal for extremely dense meshes)

---

## Shader Implementation

### Option 1: Pure Wireframe Shader (Grid Overlay)

This shader creates a pure wireframe visualization, ideal for grid floors or highlighting specific geometry.

```gdscript
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Wireframe parameters
uniform vec4 wireframe_color : source_color = vec4(0.0, 1.0, 0.8, 1.0); // Cyan glow
uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 0.0); // Transparent/dark fill
uniform float wire_width : hint_range(0.0, 40.0) = 8.0;
uniform float wire_smoothness : hint_range(0.0, 0.1) = 0.01;

// Glow/emission parameters
uniform bool enable_emission : hint_default = true;
uniform float emission_strength : hint_range(0.0, 10.0) = 2.0;
uniform bool enable_pulse : hint_default = false;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0;

varying vec3 barys;

void vertex() {
	// Assign barycentric coordinates based on vertex position in triangle
	int index = VERTEX_ID % 3;
	switch (index) {
		case 0:
			barys = vec3(1.0, 0.0, 0.0);
			break;
		case 1:
			barys = vec3(0.0, 1.0, 0.0);
			break;
		case 2:
			barys = vec3(0.0, 0.0, 1.0);
			break;
	}
}

void fragment() {
	// Calculate edge proximity using barycentric coordinates
	vec3 deltas = fwidth(barys);
	vec3 barys_s = smoothstep(
		deltas * wire_width - wire_smoothness,
		deltas * wire_width + wire_smoothness,
		barys
	);
	
	// Minimum value = closest to an edge
	float wire_mix = min(barys_s.x, min(barys_s.y, barys_s.z));
	
	// Mix wireframe and fill colors
	vec3 base_color = mix(wireframe_color.rgb, fill_color.rgb, wire_mix);
	float base_alpha = mix(wireframe_color.a, fill_color.a, wire_mix);
	
	ALBEDO = base_color;
	ALPHA = base_alpha;
	
	// Optional: Add emission for neon glow effect
	if (enable_emission) {
		float pulse_factor = 1.0;
		if (enable_pulse) {
			pulse_factor = 0.7 + 0.3 * sin(TIME * pulse_speed);
		}
		EMISSION = wireframe_color.rgb * emission_strength * (1.0 - wire_mix) * pulse_factor;
	}
}
```

**Usage:**
- Apply to GridMap floor tiles for Tron-style grid
- Set `fill_color` alpha to 0.0 for transparent grid
- Adjust `wire_width` based on distance (larger values for far tiles)
- Enable `enable_pulse` for subtle animation

---

### Option 2: PSX Hybrid Wireframe Shader

This shader combines PSX affine texture mapping with optional wireframe overlay, allowing you to toggle between solid PSX aesthetic and wireframe visualization.

```gdscript
shader_type spatial;
render_mode diffuse_lambert, vertex_lighting, cull_back, shadows_disabled, depth_draw_opaque, blend_mix, specular_disabled;

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;

// PSX parameters
uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Wireframe parameters
uniform bool enable_wireframe : hint_default = false;
uniform vec4 wireframe_color : source_color = vec4(0.0, 1.0, 0.5, 1.0); // Green
uniform float wire_width : hint_range(0.0, 40.0) = 5.0;
uniform float wire_smoothness : hint_range(0.0, 0.1) = 0.01;
uniform float wireframe_blend : hint_range(0.0, 1.0) = 0.8; // How much wireframe replaces texture

varying vec3 barys;

// PSX vertex snapping (from psx_base.gdshaderinc)
const vec2 base_snap_res = vec2(160.0, 120.0);
vec4 get_snapped_pos(vec4 base_pos) {
	vec4 snapped_pos = base_pos;
	snapped_pos.xyz = base_pos.xyz / base_pos.w;
	vec2 snap_res = floor(base_snap_res * precision_multiplier);
	snapped_pos.x = floor(snap_res.x * snapped_pos.x) / snap_res.x;
	snapped_pos.y = floor(snap_res.y * snapped_pos.y) / snap_res.y;
	snapped_pos.xyz *= base_pos.w;
	return snapped_pos;
}

void vertex() {
	// Apply PSX vertex snapping
	UV = UV * uv_scale + uv_offset;
	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION /= abs(POSITION.w); // Affine texture mapping (discard depth)
	
	// Assign barycentric coordinates
	if (enable_wireframe) {
		int index = VERTEX_ID % 3;
		switch (index) {
			case 0:
				barys = vec3(1.0, 0.0, 0.0);
				break;
			case 1:
				barys = vec3(0.0, 1.0, 0.0);
				break;
			case 2:
				barys = vec3(0.0, 0.0, 1.0);
				break;
		}
	}
	
	VERTEX = VERTEX; // Prevents shader breakage
}

void fragment() {
	// Base PSX textured appearance
	vec4 color_base = COLOR * modulate_color;
	vec4 texture_color = texture(albedoTex, UV);
	vec3 base_albedo = (color_base * texture_color).rgb;
	
	// Apply wireframe overlay if enabled
	if (enable_wireframe) {
		vec3 deltas = fwidth(barys);
		vec3 barys_s = smoothstep(
			deltas * wire_width - wire_smoothness,
			deltas * wire_width + wire_smoothness,
			barys
		);
		float wire_mix = min(barys_s.x, min(barys_s.y, barys_s.z));
		
		// Blend wireframe with texture based on wireframe_blend parameter
		ALBEDO = mix(
			mix(wireframe_color.rgb, base_albedo, wire_mix), // Wireframe mode
			base_albedo, // Texture mode
			wireframe_blend
		);
	} else {
		ALBEDO = base_albedo;
	}
}
```

**Usage:**
- Default: PSX-shaded solid geometry
- Set `enable_wireframe = true` to overlay grid lines
- Adjust `wireframe_blend` to control texture vs wireframe visibility
- Can be toggled at runtime via script for gameplay mechanics (corrupted vision, scanner mode, etc.)

---

### Option 3: Distance-Based Wireframe (Depth Fade)

For more subtle integration, wireframes can fade in/out based on distance from camera or other criteria.

```gdscript
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

uniform vec4 wireframe_color : source_color = vec4(0.0, 1.0, 0.8, 1.0);
uniform vec4 fill_color : source_color = vec4(0.1, 0.1, 0.15, 0.8);
uniform float wire_width : hint_range(0.0, 40.0) = 6.0;
uniform float wire_smoothness : hint_range(0.0, 0.1) = 0.01;

// Distance fade parameters
uniform float fade_near : hint_range(0.0, 100.0) = 5.0;
uniform float fade_far : hint_range(0.0, 100.0) = 30.0;
uniform bool invert_fade : hint_default = false; // True: show wireframe when far

varying vec3 barys;
varying float vertex_distance;

void vertex() {
	int index = VERTEX_ID % 3;
	switch (index) {
		case 0:
			barys = vec3(1.0, 0.0, 0.0);
			break;
		case 1:
			barys = vec3(0.0, 1.0, 0.0);
			break;
		case 2:
			barys = vec3(0.0, 0.0, 1.0);
			break;
	}
	
	// Calculate distance to camera
	vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vertex_distance = length(world_pos.xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	// Edge detection
	vec3 deltas = fwidth(barys);
	vec3 barys_s = smoothstep(
		deltas * wire_width - wire_smoothness,
		deltas * wire_width + wire_smoothness,
		barys
	);
	float wire_mix = min(barys_s.x, min(barys_s.y, barys_s.z));
	
	// Distance-based fade
	float distance_fade = smoothstep(fade_near, fade_far, vertex_distance);
	if (invert_fade) {
		distance_fade = 1.0 - distance_fade;
	}
	
	// Apply fade to wireframe visibility
	vec3 final_color = mix(wireframe_color.rgb, fill_color.rgb, wire_mix);
	float wireframe_strength = (1.0 - wire_mix) * distance_fade;
	
	ALBEDO = mix(fill_color.rgb, wireframe_color.rgb, wireframe_strength);
	ALPHA = mix(fill_color.a, wireframe_color.a, wireframe_strength);
}
```

**Usage:**
- Set `invert_fade = false`: Wireframes appear on nearby tiles (tactical proximity indicator)
- Set `invert_fade = true`: Wireframes appear on distant tiles (fade to abstraction)
- Adjust fade ranges based on grid visibility and atmosphere needs

---

## Material Setup for GridMap

### Method 1: Dedicated Wireframe MeshLibrary Items

Create separate mesh library entries for wireframe-specific tiles.

**Steps:**
1. Open `assets/mesh_library_source.tscn` in text editor
2. Duplicate floor/wall mesh entries
3. Create new materials using wireframe shaders:

```gdscript
# /assets/materials/wireframe_floor.tres
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/wireframe_pure.gdshader" id="1"]

[resource]
shader = ExtResource("1")
shader_parameter/wireframe_color = Color(0.0, 1.0, 0.8, 1.0)  # Cyan
shader_parameter/fill_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
shader_parameter/wire_width = 8.0
shader_parameter/wire_smoothness = 0.01
shader_parameter/enable_emission = true
shader_parameter/emission_strength = 3.0
shader_parameter/enable_pulse = false
shader_parameter/pulse_speed = 1.0
```

4. Assign to mesh library items (e.g., `item_id = 3` for wireframe floor)
5. Place wireframe tiles in grid using Grid3D script

**Advantages:**
- Clean separation of visual styles
- Easy to mix solid and wireframe tiles
- No runtime shader toggling needed

**Disadvantages:**
- Increases mesh library size
- Can't dynamically transition solid → wireframe

### Method 2: Runtime Material Override

Dynamically switch materials on existing GridMap cells.

**Implementation in `/scripts/grid_3d.gd`:**

```gdscript
class_name Grid3D
extends Node3D

@onready var grid_map: GridMap = $GridMap
var wireframe_material: ShaderMaterial
var solid_material: ShaderMaterial

func _ready():
	wireframe_material = preload("res://assets/materials/wireframe_floor.tres")
	solid_material = preload("res://assets/materials/psx_floor.tres")

func set_tile_wireframe(grid_pos: Vector2i, wireframe: bool) -> void:
	var cell = Vector3i(grid_pos.x, 0, grid_pos.y)
	var item_id = grid_map.get_cell_item(cell)
	if item_id == -1:
		return
	
	# Get mesh instance for this cell (requires GridMap manipulation)
	# Note: GridMap doesn't expose per-cell material override easily
	# Alternative: Use MeshInstance3D array instead of GridMap
```

**Note:** GridMap doesn't support per-cell material overrides easily. For dynamic material switching, consider:
- Using MultiMeshInstance3D instead of GridMap
- Creating separate GridMap layers for wireframe tiles
- Switching entire GridMap mesh library at runtime

### Method 3: Hybrid PSX Shader with Toggle

Use the PSX Hybrid shader (Option 2 above) and toggle `enable_wireframe` parameter at runtime.

**Material setup:**

```gdscript
# /assets/materials/psx_floor_hybrid.tres
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/psx_hybrid_wireframe.gdshader" id="1"]
[ext_resource type="Texture2D" path="res://assets/textures/floor_tile.png" id="2"]

[resource]
shader = ExtResource("1")
shader_parameter/modulate_color = Color(0.82, 0.71, 0.55, 1)
shader_parameter/albedoTex = ExtResource("2")
shader_parameter/uv_scale = Vector2(1, 1)
shader_parameter/uv_offset = Vector2(0, 0)
shader_parameter/enable_wireframe = false  # Toggle this at runtime
shader_parameter/wireframe_color = Color(0.0, 1.0, 0.5, 1.0)
shader_parameter/wire_width = 5.0
shader_parameter/wire_smoothness = 0.01
shader_parameter/wireframe_blend = 0.8
```

**Runtime toggle via script:**

```gdscript
# Toggle wireframe mode (e.g., for scanner ability or corruption effect)
func enable_wireframe_mode(enabled: bool) -> void:
	var mesh_lib = grid_map.mesh_library as MeshLibrary
	for i in mesh_lib.get_item_list():
		var material = mesh_lib.get_item_mesh(i).surface_get_material(0) as ShaderMaterial
		if material and material.shader.resource_path.contains("hybrid"):
			material.set_shader_parameter("enable_wireframe", enabled)
```

**Advantages:**
- Single shader handles both modes
- Can toggle per-material at runtime
- Smooth transition possible (animate wireframe_blend)

**Disadvantages:**
- Requires mesh library iteration to update all materials
- All tiles using material will update together

---

## Integration with Existing PSX Rendering Pipeline

### Current Pipeline

The project currently uses:
- **Vertex shader**: PSX-style vertex snapping (`psx_base.gdshaderinc`)
- **Fragment shader**: Affine texture mapping (depth discarded in vertex shader)
- **Post-process**: Color banding and dithering (`pp_band-dither.gdshader`)
- **Viewport**: 640x480 internal resolution with nearest-neighbor filtering
- **Lighting**: Vertex lighting with low color depth

### Wireframe Integration Strategies

**Strategy 1: Separate Wireframe Layer**
- GridMap layer 1: Solid PSX-shaded geometry
- GridMap layer 2: Wireframe overlay at same grid positions
- Layer 2 uses additive or alpha blending

**Pros:**
- Clean separation
- Can toggle entire layer visibility
- No shader modification needed

**Cons:**
- Doubles draw calls for wireframe tiles
- Potential z-fighting if not offset slightly

**Strategy 2: Hybrid Shader (Recommended)**
- Modify existing PSX shaders to include optional wireframe rendering
- Use shader parameters to toggle at runtime
- Maintains single draw call per tile

**Pros:**
- Efficient rendering
- Flexible control (per-material toggle)
- Can blend wireframe with PSX texture

**Cons:**
- More complex shader code
- Requires barycentric coordinate support (Godot 4.0+)

**Strategy 3: Post-Process Wireframe**
- Render solid PSX geometry normally
- Apply edge detection in post-process pass
- Draw lines over detected edges

**Pros:**
- Works on any geometry
- No barycentric coordinates needed
- Can apply to entire scene

**Cons:**
- Less control (can't choose which objects get wireframe)
- Edge detection may pick up unwanted edges
- Performance cost of full-screen pass

### Recommended Approach for Backrooms Power Crawl

**Use Hybrid PSX Shader (Strategy 2) with distance-based toggle:**

1. Create `psx_hybrid_wireframe.gdshader` (see Option 2 shader above)
2. Apply to floor tiles that need wireframe capability
3. Default: `enable_wireframe = false` (normal PSX appearance)
4. Activate wireframe for gameplay mechanics:
   - Scanner ability reveals grid structure
   - Corruption/glitch effects distort geometry to wireframe
   - Reality instability shows underlying grid
   - Proximity to certain entities reveals "true" wireframe nature

**Visual Mockup Description:**
```
Normal State (enable_wireframe = false):
┌─────────────────────────────────┐
│ Solid PSX floor tiles           │
│ - Vertex wobble                 │
│ - Affine texture warping        │
│ - Color banding                 │
│ - Dim lighting                  │
└─────────────────────────────────┘

Scanner Active (enable_wireframe = true, wireframe_blend = 0.3):
┌─────────────────────────────────┐
│ PSX floor with cyan grid overlay│
│ - Neon lines trace tile edges  │
│ - Subtle emission glow          │
│ - Texture still visible beneath │
│ - Terminal/diagnostic aesthetic │
└─────────────────────────────────┘

Full Corruption (enable_wireframe = true, wireframe_blend = 0.0):
┌─────────────────────────────────┐
│ Pure wireframe grid             │
│ - Bright green/cyan edges       │
│ - Dark/transparent fill         │
│ - Tron-style cyberspace         │
│ - Reality breakdown effect      │
└─────────────────────────────────┘
```

---

## Performance Considerations

### Barycentric Wireframe Performance

**Vertex Shader Cost:**
- Minimal: Simple switch statement based on `VERTEX_ID % 3`
- No additional vertex data required

**Fragment Shader Cost:**
- Moderate: `fwidth()` computes screen-space derivatives (built-in GPU function)
- `smoothstep()` is efficient
- Cost scales with fragment count, not vertex count

**Optimization for Large Grids:**

Given the project uses a 128×128 grid with viewport culling (~400 tiles rendered):

1. **Flat shading**: Disable smooth normals for geometry using wireframe shader
   - Improves `VERTEX_ID` reliability
   - Reduces vertex attribute interpolation cost

2. **LOD-based wireframe width**: Increase `wire_width` for distant tiles
   - Prevents thin lines from disappearing at distance
   - Can be controlled via shader parameter or vertex color

3. **Culling optimization**: Already implemented viewport culling is sufficient
   - ~400 tiles × 2 triangles/tile × 3 vertices/triangle = ~2,400 vertices
   - Well within performance budget for barycentric technique

4. **Selective wireframe**: Only apply to specific tile types
   - Floor tiles: wireframe capable
   - Walls/ceiling: solid PSX shader (no barycentric overhead)

**Estimated Performance Impact:**
- **Minimal** for viewport-culled 128×128 grid
- Fragment shader cost < 1ms at 640×480 resolution (internal viewport)
- Vertex shader cost negligible
- Post-process dithering pass is likely more expensive than wireframe

**Benchmark Targets:**
- 60 FPS at 640×480 internal resolution (PSX-authentic framerate)
- Wireframe overlay should add < 10% frame time
- If targeting 30 FPS (more PSX-authentic), even more headroom

### Memory Considerations

**Shader Variants:**
- Pure wireframe: ~2 KB shader code
- Hybrid PSX wireframe: ~4 KB shader code (includes PSX base)
- Negligible memory impact

**Material Instances:**
- 3-4 materials for floor/wall/ceiling variants
- Each ShaderMaterial: ~200 bytes + parameter data
- Total: < 1 KB for all wireframe materials

---

## Optional Enhancements

### 1. CRT Scanline Effect

Add horizontal scanlines to enhance retro monitor aesthetic.

**Post-Process Shader** (`scanlines.gdshader`):

```gdscript
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count : hint_range(100.0, 1000.0) = 480.0; // Match vertical res

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);
	
	// Calculate scanline pattern
	float scanline = sin(SCREEN_UV.y * scanline_count * 3.14159) * 0.5 + 0.5;
	scanline = mix(1.0, scanline, scanline_intensity);
	
	COLOR.rgb = color.rgb * scanline;
	COLOR.a = color.a;
}
```

**Apply after dithering pass** in UI layer for authentic CRT monitor look.

### 2. Phosphor Glow (Bloom for Wireframes)

Add subtle glow around emissive wireframe edges.

**Requirements:**
- Enable Environment → Glow in WorldEnvironment
- Set Glow Intensity: 0.5
- Set Glow Strength: 0.8
- Set Glow Blend Mode: Additive
- Adjust HDR Threshold to capture wireframe emission

**Material adjustment:**

```gdscript
# In wireframe shader, increase emission strength
shader_parameter/emission_strength = 5.0  # Stronger glow
```

Glow will naturally bloom around bright wireframe edges, creating phosphor monitor effect.

### 3. Chromatic Aberration (Corruption Effect)

Separate RGB channels slightly for glitch/corruption aesthetic.

**Post-Process Shader** (`chromatic_aberration.gdshader`):

```gdscript
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float aberration_amount : hint_range(0.0, 0.01) = 0.002;

void fragment() {
	vec2 offset = vec2(aberration_amount, 0.0);
	
	float r = texture(screen_texture, SCREEN_UV - offset).r;
	float g = texture(screen_texture, SCREEN_UV).g;
	float b = texture(screen_texture, SCREEN_UV + offset).b;
	
	COLOR = vec4(r, g, b, 1.0);
}
```

Can be animated/increased when player is near corrupted entities or reality instability is high.

### 4. Grid Pulse Animation

Animate wireframe edges for dynamic visual interest.

**Already included** in Option 1 shader via `enable_pulse` and `pulse_speed` parameters.

**Advanced pulse patterns:**

```gdscript
// In fragment shader
float distance_to_player = length(VERTEX.xz - player_position.xz);
float pulse_phase = TIME * pulse_speed - distance_to_player * 0.1;
float pulse_factor = 0.7 + 0.3 * sin(pulse_phase);
EMISSION = wireframe_color.rgb * emission_strength * (1.0 - wire_mix) * pulse_factor;
```

Creates ripple effect emanating from player position (requires passing player position as uniform).

### 5. Depth-Based Color Shift

Shift wireframe color based on depth for atmospheric depth perception.

**Add to wireframe shader:**

```gdscript
uniform vec4 wireframe_color_near : source_color = vec4(0.0, 1.0, 0.8, 1.0); // Cyan
uniform vec4 wireframe_color_far : source_color = vec4(0.5, 0.0, 1.0, 1.0);  // Purple

varying float vertex_distance;

void vertex() {
	// ... existing code ...
	vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vertex_distance = length(world_pos.xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	// ... existing edge detection ...
	
	float depth_factor = smoothstep(5.0, 30.0, vertex_distance);
	vec4 depth_wireframe_color = mix(wireframe_color_near, wireframe_color_far, depth_factor);
	
	ALBEDO = mix(depth_wireframe_color.rgb, fill_color.rgb, wire_mix);
	// ... rest of shader
}
```

Creates visual depth gradient: nearby tiles = cyan, distant tiles = purple (classic retrowave palette).

---

## Configuration Options for Artists

All shader parameters exposed via material inspector:

**Wireframe Appearance:**
- `wireframe_color`: Color of wireframe lines (Color picker)
- `fill_color`: Color of triangle interior (Color picker, alpha supported)
- `wire_width`: Thickness of wireframe lines (0.0 - 40.0)
- `wire_smoothness`: Anti-aliasing amount (0.0 - 0.1)

**Emission/Glow:**
- `enable_emission`: Toggle neon glow effect (bool)
- `emission_strength`: Brightness of glow (0.0 - 10.0)
- `enable_pulse`: Animate glow intensity (bool)
- `pulse_speed`: Animation speed (0.1 - 5.0)

**Hybrid Mode:**
- `enable_wireframe`: Toggle wireframe overlay (bool)
- `wireframe_blend`: Texture visibility (0.0 = full wireframe, 1.0 = full texture)

**Distance Fade:**
- `fade_near`: Distance where fade begins (world units)
- `fade_far`: Distance where fade completes (world units)
- `invert_fade`: Reverse fade direction (bool)

**Depth Color Shift:**
- `wireframe_color_near`: Color for nearby geometry
- `wireframe_color_far`: Color for distant geometry

**Usage Examples:**

```gdscript
# Scanner ability: reveal grid structure
func activate_scanner():
	material.set_shader_parameter("enable_wireframe", true)
	material.set_shader_parameter("wireframe_blend", 0.3)
	material.set_shader_parameter("wireframe_color", Color(0, 1, 0.8))
	material.set_shader_parameter("emission_strength", 4.0)

# Corruption effect: reality breakdown
func apply_corruption(intensity: float):
	material.set_shader_parameter("enable_wireframe", true)
	material.set_shader_parameter("wireframe_blend", intensity)  # 0.0 = full corruption
	material.set_shader_parameter("enable_pulse", true)
	material.set_shader_parameter("pulse_speed", 2.0 + intensity * 3.0)  # Faster when corrupted

# Tactical highlight: show movement range
func highlight_movement_range(tiles: Array[Vector2i]):
	for tile in tiles:
		var mat = get_tile_material(tile)
		mat.set_shader_parameter("wireframe_color", Color(0, 1, 0))  # Green
		mat.set_shader_parameter("enable_wireframe", true)
		mat.set_shader_parameter("wireframe_blend", 0.5)  # Semi-transparent
```

---

## Visual Style Combinations

### Preset 1: Classic Tron Grid
```gdscript
wireframe_color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan
fill_color = Color(0.0, 0.0, 0.1, 0.8)       # Dark blue fill
wire_width = 8.0
enable_emission = true
emission_strength = 3.0
enable_pulse = false
```

**Aesthetic**: Clean, geometric, high-contrast. Ideal for clean "cyberspace" areas or tutorial zones.

### Preset 2: VR Terminal Interface
```gdscript
wireframe_color = Color(0.0, 1.0, 0.5, 1.0)  # Green phosphor
fill_color = Color(0.0, 0.0, 0.0, 0.0)       # Transparent
wire_width = 6.0
enable_emission = true
emission_strength = 5.0
enable_pulse = true
pulse_speed = 1.5
scanlines_enabled = true  # Via post-process
```

**Aesthetic**: Terminal/monitor display. Ideal for scanner ability or examination mode.

### Preset 3: Corrupted Reality
```gdscript
wireframe_color = Color(1.0, 0.0, 0.8, 1.0)  # Magenta glitch
fill_color = Color(0.0, 0.0, 0.0, 0.5)       # Semi-transparent dark
wire_width = 4.0 (varies with noise)
enable_emission = true
emission_strength = 6.0
enable_pulse = true
pulse_speed = 5.0  # Rapid flickering
chromatic_aberration = 0.005  # Via post-process
```

**Aesthetic**: Unstable, glitchy, dangerous. Ideal for high-corruption zones or entity proximity.

### Preset 4: Subtle Tactical Overlay
```gdscript
wireframe_color = Color(0.0, 1.0, 0.0, 0.6)  # Semi-transparent green
fill_color = Color(0.0, 0.0, 0.0, 0.0)       # Transparent
wire_width = 5.0
wireframe_blend = 0.7  # Mostly texture, subtle grid
enable_emission = false
fade_near = 5.0
fade_far = 15.0
```

**Aesthetic**: Minimal HUD-like overlay. Ideal for showing movement ranges or interactive tiles without obscuring PSX textures.

---

## Implementation Checklist

- [ ] Create shader files:
  - [ ] `shaders/wireframe_pure.gdshader` (Option 1)
  - [ ] `shaders/psx_hybrid_wireframe.gdshader` (Option 2)
  - [ ] `shaders/wireframe_distance_fade.gdshader` (Option 3)

- [ ] Create material resources:
  - [ ] `assets/materials/wireframe_floor.tres`
  - [ ] `assets/materials/wireframe_wall.tres`
  - [ ] `assets/materials/psx_floor_hybrid.tres`

- [ ] Test with GridMap:
  - [ ] Assign wireframe materials to mesh library items
  - [ ] Verify barycentric coordinates work correctly
  - [ ] Test performance with 400-tile viewport culling

- [ ] Optional enhancements:
  - [ ] Scanline post-process shader
  - [ ] Chromatic aberration shader
  - [ ] Glow/bloom settings in WorldEnvironment
  - [ ] Depth-based color shift

- [ ] Gameplay integration:
  - [ ] Scanner ability toggles wireframe
  - [ ] Corruption effects increase wireframe visibility
  - [ ] Movement range highlighting uses wireframe overlay
  - [ ] Reality instability events trigger wireframe glitches

- [ ] Documentation:
  - [ ] Update ARCHITECTURE.md with wireframe rendering
  - [ ] Document shader parameters for artists
  - [ ] Add visual style presets to design guide

---

## References

**Historical/Aesthetic:**
- Tron (1982) - Original laser grid aesthetic
- Battlezone (1980) - Wireframe vector graphics
- 80s Grid History: https://indieground.net/blog/80s-grid-history/
- Vanishing Point: 1980s Futurism Grid: https://wearethemutants.com/2017/02/16/

**Technical:**
- GodotShaders.com - Wireframe Shader (Godot 4.0): https://godotshaders.com/shader/wireframe-shader-godot-4-0/
- Barycentric Wireframes: https://tchayen.github.io/posts/wireframes-with-barycentric-coordinates
- PSX Affine Texture Mapping: https://danielilett.com/2021-11-06-tut5-21-ps1-affine-textures/
- Godot 4 Spatial Shader Docs: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html

**Existing Project Files:**
- `/shaders/psx_base.gdshaderinc` - PSX vertex snapping and affine mapping
- `/shaders/psx_lit.gdshader` - Current lit shader
- `/shaders/pp_band-dither.gdshader` - Post-process dithering
- `/assets/materials/psx_floor.tres` - Current floor material

---

**Last Updated**: 2025-11-09
**Author**: Claude Code (research compilation)
**Status**: Design phase - implementation pending user approval
