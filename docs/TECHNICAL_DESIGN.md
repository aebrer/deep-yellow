# Technical Design Document

## Ceiling Visibility System for Top-Down 3D View

### Problem Statement

In a top-down 3D tactical camera view of maze-like environments (Backrooms), ceiling tiles obstruct the player's view of the gameplay area below. We need a system that:

1. Makes ceilings invisible in the center 80% of the screen (gameplay focus area)
2. Keeps ceilings visible at screen edges for spatial awareness and atmosphere
3. Integrates seamlessly with existing PSX shader pipeline
4. Maintains acceptable performance on GridMap-based levels
5. Provides smooth, non-distracting transitions

---

## Research Summary

### Industry Approaches

**Top-Down Games with Ceilings:**
- **Divinity: Original Sin 2** - Fades out roofs when camera is overhead
- **Baldur's Gate 3** - Complete ceiling removal in tactical view
- **XCOM series** - Removes ceilings entirely, shows outline only
- **Tactics Ogre** - No ceilings in top-down view, shows them in cutscenes

**Common Patterns:**
1. **Proximity Fade** - Objects near camera become transparent
2. **Screen-Space Masking** - Radial vignette determines visibility
3. **Camera Angle Detection** - Fade based on view angle
4. **Dithered Transparency** - PSX-era style ordered dithering

### Godot 4 Technical Capabilities

**Spatial Shader Built-ins (Godot 4.x):**
- `FRAGCOORD` - Fragment coordinates in pixels
- `SCREEN_UV` - Normalized screen coordinates (0.0 to 1.0)
- `VIEWPORT_SIZE` - Current viewport dimensions
- `VERTEX` - Vertex position in view space
- `INV_VIEW_MATRIX` - Camera transform (replaces CAMERA_MATRIX in Godot 3.x)

**Render Modes for Transparency:**
```glsl
render_mode blend_mix;                    // Standard alpha blending
render_mode depth_draw_alpha_prepass;     // Draw depth, then blend (best for foliage)
render_mode depth_draw_opaque;            // No depth for transparent parts
render_mode cull_disabled;                // Show both sides of geometry
```

---

## Recommended Approach: Screen-Space Radial Vignette Mask

### Why This Approach?

**Pros:**
- ✅ Screen-space calculation (independent of world position)
- ✅ Works with any camera angle/zoom level
- ✅ Integrates cleanly with PSX shader pipeline
- ✅ Configurable falloff curve
- ✅ No per-object setup required
- ✅ Maintains PSX aesthetic with optional dithering
- ✅ Minimal performance overhead (single distance calculation)

**Cons:**
- ❌ Affects ALL ceiling tiles uniformly (can't make exceptions)
- ❌ Circular falloff may not match rectangular viewports perfectly
- ❌ Requires shader modification for ceiling materials

**Alternatives Considered:**
1. **Proximity Fade (Camera Distance)** - Too abrupt, doesn't match screen focus
2. **Camera Cull Layers** - All-or-nothing, no gradual transition
3. **Post-Process Shader** - More complex, requires depth buffer access
4. **Per-Tile Script** - Terrible performance, breaks batching

---

## Technical Implementation

### Approach 1: Integrated PSX Shader (RECOMMENDED)

Modify the existing `psx_base.gdshaderinc` to add ceiling fade functionality.

#### Modified Fragment Shader

```glsl
// Add to psx_base.gdshaderinc

// Ceiling fade uniforms (optional, controlled per-material)
#ifdef CEILING_FADE
uniform bool enable_ceiling_fade = true;
uniform float fade_inner_radius : hint_range(0.0, 1.0) = 0.4;  // 40% from center = fully visible
uniform float fade_outer_radius : hint_range(0.0, 1.0) = 0.9;  // 90% from center = fully transparent
uniform float fade_power : hint_range(0.1, 4.0) = 2.0;         // Falloff curve (higher = sharper transition)
uniform bool use_dithered_fade = true;                         // PSX-style ordered dither vs smooth alpha

// Bayer 4x4 dithering matrix for PSX aesthetic
const float bayer_matrix[16] = float[](
    0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
   12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
    3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
   15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

float get_bayer_dither(vec2 screen_pos) {
    int x = int(mod(screen_pos.x, 4.0));
    int y = int(mod(screen_pos.y, 4.0));
    return bayer_matrix[y * 4 + x];
}

float calculate_ceiling_fade() {
    // Calculate distance from screen center (0.5, 0.5)
    vec2 screen_center = vec2(0.5, 0.5);
    vec2 uv_from_center = SCREEN_UV - screen_center;
    float dist_from_center = length(uv_from_center);
    
    // Normalize to 0.0 (center) to 1.0 (corner)
    // Diagonal distance to corner is ~0.707, normalize to 1.0
    dist_from_center = dist_from_center / 0.707;
    
    // Smooth falloff between inner and outer radius
    float fade_factor = smoothstep(fade_inner_radius, fade_outer_radius, dist_from_center);
    
    // Apply power curve for sharper/softer transitions
    fade_factor = pow(fade_factor, fade_power);
    
    return fade_factor;
}
#endif

void fragment()
{
    // ... existing PSX shader code ...
    
#ifdef CEILING_FADE
    if (enable_ceiling_fade) {
        float fade = calculate_ceiling_fade();
        
        if (use_dithered_fade) {
            // PSX-style ordered dithering
            float dither_threshold = get_bayer_dither(FRAGCOORD.xy);
            if (fade > dither_threshold) {
                discard;  // Fully discard pixel (no blending, better performance)
            }
            // else: keep pixel fully opaque
        } else {
            // Smooth alpha blending (less PSX-authentic but smoother)
            ALPHA *= (1.0 - fade);
        }
    }
#endif

    // ... rest of fragment shader ...
}
```

#### New Ceiling Shader Definition

Create `shaders/psx_ceiling.gdshader`:

```glsl
shader_type spatial;

#define LIT diffuse_lambert, vertex_lighting
#define CULL cull_back
#define DEPTH depth_draw_opaque
#define BLEND blend_mix
#define CEILING_FADE  // Enable ceiling fade functionality

#include "psx_base.gdshaderinc"
```

#### Material Setup

1. **Create Ceiling Material** (`materials/ceiling_psx.tres`):
```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/psx_ceiling.gdshader" id="1"]

[resource]
shader = ExtResource("1")
shader_parameter/enable_ceiling_fade = true
shader_parameter/fade_inner_radius = 0.4
shader_parameter/fade_outer_radius = 0.9
shader_parameter/fade_power = 2.0
shader_parameter/use_dithered_fade = true
shader_parameter/modulate_color = Color(1, 1, 1, 1)
shader_parameter/uv_scale = Vector2(1, 1)
shader_parameter/uv_offset = Vector2(0, 0)
shader_parameter/uv_pan_velocity = Vector2(0, 0)
```

2. **Assign to GridMap Ceiling Tiles**:
   - In GridMap MeshLibrary, set ceiling tile materials to `ceiling_psx.tres`
   - Floor/wall tiles continue using standard PSX materials

---

### Approach 2: Post-Process Shader (ALTERNATIVE)

If modifying base shaders is undesirable, use a full-screen post-process effect.

#### Post-Process Vignette Mask

```glsl
shader_type canvas_item;

uniform float fade_inner_radius : hint_range(0.0, 1.0) = 0.4;
uniform float fade_outer_radius : hint_range(0.0, 1.0) = 0.9;
uniform float fade_power : hint_range(0.1, 4.0) = 2.0;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    
    // Calculate radial distance from center
    vec2 uv_from_center = UV - vec2(0.5, 0.5);
    float dist = length(uv_from_center) / 0.707;
    
    // Calculate fade
    float fade = smoothstep(fade_inner_radius, fade_outer_radius, dist);
    fade = pow(fade, fade_power);
    
    // Darken/mask based on fade
    // Note: This masks EVERYTHING, not just ceilings
    // Would need depth/stencil approach to target ceilings only
    COLOR = color;
    COLOR.a *= (1.0 - fade);
}
```

**Why Not Recommended:**
- Affects all geometry, not just ceilings
- Requires complex depth buffer reads to isolate ceilings
- Breaks layering with other post-process effects (dithering, etc.)
- More expensive than per-material approach

---

### Approach 3: Camera Distance Proximity Fade

Built-in Godot feature, less control than screen-space approach.

#### Shader Implementation

```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass;

uniform float proximity_fade_distance = 5.0;

void fragment() {
    // Calculate distance from camera
    vec3 vertex_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 camera_world = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float dist = distance(vertex_world, camera_world);
    
    // Fade based on proximity
    float fade = smoothstep(0.0, proximity_fade_distance, dist);
    
    ALPHA = fade;
}
```

**Why Not Recommended for This Use Case:**
- Fades based on 3D distance, not screen position
- Camera zoom/angle changes affect fade inconsistently
- Doesn't create "center clear, edges visible" pattern
- Better suited for player occlusion (grass, foliage)

---

## Integration Plan

### Step 1: Shader Setup (Estimated: 30 min)

1. ✅ Modify `shaders/psx_base.gdshaderinc`:
   - Add `#ifdef CEILING_FADE` block
   - Implement `calculate_ceiling_fade()` function
   - Add Bayer dithering for PSX aesthetic
   - Add uniforms for tuneable parameters

2. ✅ Create `shaders/psx_ceiling.gdshader`:
   - Define `#define CEILING_FADE` before include
   - Use same PSX rendering settings as walls/floors

3. ✅ Test shader compilation:
   - Verify no syntax errors
   - Check uniforms appear in Inspector

### Step 2: Material Creation (Estimated: 15 min)

1. ✅ Create `materials/ceiling_psx.tres`:
   - Assign `psx_ceiling.gdshader`
   - Set default fade parameters
   - Test with placeholder cube/plane

2. ✅ Fine-tune parameters:
   - Adjust `fade_inner_radius` (start of fade)
   - Adjust `fade_outer_radius` (full transparency)
   - Adjust `fade_power` (transition curve)
   - Toggle `use_dithered_fade` (PSX vs smooth)

### Step 3: GridMap Integration (Estimated: 20 min)

1. ✅ Open GridMap MeshLibrary:
   - Locate ceiling tile meshes
   - Replace materials with `ceiling_psx.tres`

2. ✅ Test in scene:
   - Place camera at tactical angle
   - Move camera to test edge visibility
   - Verify center is clear, edges show ceilings

3. ✅ Iterate on parameters:
   - Play with fade radii
   - Test different camera distances
   - Validate with controller input

### Step 4: Performance Validation (Estimated: 15 min)

1. ✅ Profile frame time:
   - Compare before/after shader modification
   - Check GPU overhead (should be <1ms)
   - Monitor draw calls (should not change)

2. ✅ Test on target hardware:
   - Linux/WSL2 (developer environment)
   - Windows (user test environment)
   - Verify compatibility mode (GL Compatibility)

### Step 5: Fallback Options (Estimated: 10 min)

1. ✅ Add material toggle:
   - `enable_ceiling_fade` uniform allows disable
   - Test with fade disabled (full ceiling visibility)

2. ✅ Add accessibility option:
   - Player preference to disable effect
   - Some users may find fade distracting

---

## Performance Considerations

### Computational Cost

**Per-Fragment Operations:**
```
1. SCREEN_UV read                 - 1 texture fetch (fast)
2. Distance calculation           - 2 subtractions, 1 length() (~5 ops)
3. Normalize distance             - 1 division
4. smoothstep()                   - ~6 ops (clamped polynomial)
5. pow()                          - ~8 ops (depends on hardware)
6. Bayer dither (optional)        - 2 mod, 1 array lookup (~4 ops)
7. Alpha multiply or discard      - 1 op

Total: ~25-30 shader operations per pixel
```

**Impact:**
- Modern GPUs: Negligible (<0.5ms for 640x480 viewport)
- Integrated GPUs: Acceptable (<2ms)
- Mobile: May need optimization (consider disabling `pow()`)

**Optimization Options:**
1. **Discard vs Alpha Blend**: 
   - `discard` is faster (skips rest of fragment shader)
   - Dithered fade uses `discard` for binary visibility
   
2. **Simplified Distance**:
   - Use `max(abs(x), abs(y))` instead of `length()` for square falloff
   - Saves 1 sqrt operation (~4-8 cycles)

3. **Pre-computed LUT**:
   - Store fade values in small texture (16x16)
   - Sample based on SCREEN_UV
   - Trades computation for texture bandwidth

### Batching Impact

**GridMap Batching:**
- Material change breaks batching
- All ceiling tiles share same material = batch preserved
- All floor/wall tiles share different material = separate batch
- Expected: 2 draw calls (ceiling batch + floor/wall batch)

**Transparency Sorting:**
- Dithered fade uses `discard`, no sorting needed
- Smooth alpha fade requires back-to-front sorting
- **Recommendation**: Use dithered fade for PSX aesthetic + performance

### Memory Footprint

**Additional Shader Uniforms:**
```
- enable_ceiling_fade:    1 bit (bool)
- fade_inner_radius:      4 bytes (float)
- fade_outer_radius:      4 bytes (float)
- fade_power:             4 bytes (float)
- use_dithered_fade:      1 bit (bool)

Total per material: ~16 bytes
```

Negligible impact.

---

## Alternative Approaches (For Reference)

### 1. Layer-Based Visibility (Simplest)

**Implementation:**
```gdscript
# On camera node
camera.cull_mask = 0b11111111111111111111  # All layers except ceiling
# Ceiling tiles on layer 20
ceiling_tiles.layers = 1 << 19  # Layer 20
```

**Pros:**
- ✅ Extremely simple
- ✅ No shader modification
- ✅ Zero performance cost

**Cons:**
- ❌ All-or-nothing (no edge visibility)
- ❌ Loses spatial awareness
- ❌ Can't see ceiling details/decorations

### 2. Depth-Based Post-Process

**Concept:**
- Read depth buffer in post-process shader
- Identify ceiling geometry by depth range
- Mask based on screen position

**Pros:**
- ✅ Doesn't require per-material setup
- ✅ Works with any shader

**Cons:**
- ❌ Requires depth buffer access (not trivial in GL Compatibility)
- ❌ Depth-only approach can't distinguish ceiling from walls
- ❌ More complex implementation
- ❌ Higher performance cost

### 3. Mesh-Based Solution (No Shader)

**Concept:**
- Generate ceiling meshes with vertex colors encoding screen-space UVs
- Use vertex colors in material to fade

**Pros:**
- ✅ Works without custom shaders
- ✅ Per-vertex control

**Cons:**
- ❌ Requires mesh regeneration/modification
- ❌ Poor resolution (vertex-level, not pixel-level)
- ❌ Doesn't work with GridMap (uniform meshes)
- ❌ Complex to maintain

---

## Testing Strategy

### Visual Tests

1. **Center Clarity**:
   - ✅ Player visible at center screen
   - ✅ No ceiling obstruction within inner radius
   - ✅ Movement in center is unobstructed

2. **Edge Visibility**:
   - ✅ Ceilings visible at screen edges
   - ✅ Spatial context maintained
   - ✅ Gradual transition, not jarring

3. **Camera Movement**:
   - ✅ Rotate camera - fade follows screen space
   - ✅ Zoom in/out - fade radius adjusts proportionally
   - ✅ Move player - fade stays screen-relative

4. **PSX Aesthetic**:
   - ✅ Dithered fade matches vertex wobble/affine textures
   - ✅ No modern-looking smooth gradients (unless disabled)
   - ✅ Maintains retro look

### Performance Tests

1. **Frame Time**:
   - Measure before/after shader change
   - Target: <1ms increase on mid-range GPU
   - Profile with Godot's built-in profiler

2. **Draw Calls**:
   - Verify batching preserved (2 calls: ceiling + floor/walls)
   - Check transparency sorting (should be none with dithering)

3. **Scalability**:
   - Test with full 128x128 grid visible (stress test)
   - Verify viewport culling still active
   - Monitor GPU/CPU usage

### User Experience Tests

1. **Gameplay Clarity**:
   - Can player easily see character?
   - Can player see movement indicator?
   - Is spatial awareness maintained?

2. **Distraction Level**:
   - Is fade transition smooth enough?
   - Does dithering create visual noise?
   - Test with sensitive users (motion sickness)

3. **Accessibility**:
   - Provide toggle to disable effect
   - Test with colorblind modes
   - Ensure high-contrast areas remain clear

---

## Configuration Recommendations

### Default Values (Good Starting Point)

```gdscript
# For 640x480 viewport with tactical camera
enable_ceiling_fade = true
fade_inner_radius = 0.35      # 35% from center
fade_outer_radius = 0.85      # 85% from center
fade_power = 2.0              # Quadratic falloff
use_dithered_fade = true      # PSX aesthetic
```

### Tuning Guidelines

**fade_inner_radius** (where fade starts):
- **0.0-0.3** - Very aggressive, minimal ceiling visibility
- **0.3-0.5** - Balanced (RECOMMENDED)
- **0.5-0.7** - Conservative, more edge visibility
- **0.7+** - Minimal fade, mostly visible

**fade_outer_radius** (where fully transparent):
- **0.6-0.8** - Sharp transition, clear boundary
- **0.8-0.95** - Gradual transition (RECOMMENDED)
- **0.95+** - Very soft, ceilings visible almost to edge

**fade_power** (transition curve):
- **0.5-1.5** - Linear/soft fade
- **1.5-2.5** - Smooth S-curve (RECOMMENDED)
- **2.5-4.0** - Sharp snap from visible to invisible

**use_dithered_fade**:
- **true** - PSX aesthetic, better performance, binary transparency
- **false** - Smooth modern look, slight performance cost, alpha blending

---

## Future Enhancements

### 1. Dynamic Radius Based on Camera Zoom

```glsl
uniform float zoom_influence : hint_range(0.0, 1.0) = 0.5;

float calculate_ceiling_fade() {
    // Get camera Z distance (simplified)
    float camera_height = abs(VERTEX.z);
    float zoom_factor = clamp(camera_height / 10.0, 0.5, 2.0);
    
    float adjusted_inner = fade_inner_radius * mix(1.0, zoom_factor, zoom_influence);
    float adjusted_outer = fade_outer_radius * mix(1.0, zoom_factor, zoom_influence);
    
    // ... rest of calculation
}
```

**Benefit**: Closer camera = larger fade radius (more ceiling removed)

### 2. Elliptical Fade (Non-Circular)

```glsl
uniform vec2 fade_aspect_ratio = vec2(1.0, 0.75);  // 4:3 viewport

float calculate_ceiling_fade() {
    vec2 uv_from_center = (SCREEN_UV - vec2(0.5, 0.5)) / fade_aspect_ratio;
    float dist = length(uv_from_center) / 0.707;
    // ... rest of calculation
}
```

**Benefit**: Matches viewport shape, less ceiling at top/bottom

### 3. Player-Relative Fade (Not Screen-Center)

```gdscript
# Pass player screen position as uniform
uniform vec2 player_screen_pos = vec2(0.5, 0.5);

float calculate_ceiling_fade() {
    vec2 uv_from_player = SCREEN_UV - player_screen_pos;
    // ... rest of calculation
}
```

**Benefit**: Fade follows player, not screen center (for off-center cameras)

### 4. Ceiling Height Detection

Add vertex color or material parameter to control fade per-tile:

```glsl
uniform float ceiling_height_influence : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    float base_fade = calculate_ceiling_fade();
    float height_factor = COLOR.r;  // Red channel = height (0=low, 1=high)
    
    float adjusted_fade = mix(base_fade, base_fade * height_factor, ceiling_height_influence);
    // ... use adjusted_fade
}
```

**Benefit**: Higher ceilings stay visible longer, lower ceilings fade faster

---

## Known Limitations

### 1. Uniform Fade Across All Ceiling Tiles

**Issue**: All ceiling tiles fade identically, can't make exceptions for important ceiling details.

**Workaround**: 
- Use separate material for special ceiling tiles (boss rooms, decorations)
- Set `enable_ceiling_fade = false` on specific materials

### 2. Circular Falloff on Rectangular Viewports

**Issue**: 640x480 (4:3) viewport has circular fade, corners may have unexpected visibility.

**Workaround**:
- Adjust `fade_outer_radius` to compensate
- Implement elliptical fade (see Future Enhancements)

### 3. PSX Shader Dithering + Ceiling Dithering = Moiré

**Issue**: Overlapping dither patterns can create visual artifacts.

**Workaround**:
- Use different dither patterns (Bayer 4x4 for ceiling, 2x2 for color)
- Offset dither phase by screen position
- Use smooth alpha fade instead of dithered (less PSX-authentic)

### 4. Doesn't Work with Dynamic Lighting

**Issue**: Fully discarded pixels don't cast shadows or receive lighting.

**Workaround**:
- Use `depth_draw_alpha_prepass` render mode (keeps depth buffer)
- Switch to alpha blending instead of discard
- Accept limitation (PSX games didn't have dynamic shadows anyway)

---

## Conclusion

**Recommended Implementation**: Screen-Space Radial Vignette with Bayer Dithering

**Key Benefits**:
- ✅ Preserves PSX aesthetic
- ✅ Minimal performance cost
- ✅ Easy integration with existing shaders
- ✅ Highly configurable
- ✅ Screen-space logic matches player perception

**Next Steps**:
1. Implement shader modification to `psx_base.gdshaderinc`
2. Create `psx_ceiling.gdshader` with `CEILING_FADE` define
3. Set up ceiling material with default parameters
4. Test in GridMap scene with tactical camera
5. Iterate on fade parameters based on gameplay feel
6. Add accessibility toggle for players who find it distracting

**Estimated Implementation Time**: 90 minutes (1.5 hours)

**Risk Level**: Low - Fallback is simple (disable uniform or use old material)

---

**Document Version**: 1.0  
**Last Updated**: 2025-11-09  
**Author**: Research by Claude (Sonnet 4.5) for Backrooms Power Crawl
