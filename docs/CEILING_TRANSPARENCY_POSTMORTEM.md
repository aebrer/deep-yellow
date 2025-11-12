# Ceiling Transparency System - Post-Mortem

**Date**: 2025-11-10
**Status**: ❌ NON-VIABLE - Multiple attempted approaches failed
**Current Solution**: Ceiling invisible from above (cull_front) - tactical workaround only

---

## Summary

After extensive research and multiple implementation attempts, **all approaches to ceiling transparency for tactical camera gameplay have been deemed non-viable** for this project's constraints.

---

## Approaches Attempted

### 1. ShapeCast3D Raycasting + Per-Cell Shader Arrays (FAILED)

**Implementation**:
- ShapeCast3D detecting obstructed cells between camera and player
- Shader uniform array of 256 Vector3 positions
- Per-fragment loop checking if cell is obstructed
- Wireframe rendering for obstructed cells

**Why It Failed**:
- Per-fragment grid cell comparison massacres GPU performance (thousands of pixels × 256 array checks)
- ShapeCast3D designed for physics collision, not visual occlusion (inconsistent detection)
- Per-frame uniform uploads destroyed GridMap batching (2-4ms GPU overhead)
- Flickering, inconsistent behavior, never reliable
- **Fundamentally fighting against how 3D rendering works**

**Code Deleted**: ~250 lines (commit d9af93c)

---

### 2. DEPTH_TEXTURE Proximity Fade (FAILED)

**Implementation**:
- Godot 4.6+ DEPTH_TEXTURE support (fixed engine bug from 4.5.1)
- Sample depth buffer to detect proximity to geometry
- Automatic fade when geometry gets close to camera/player
- PSX-style Bayer dithering for retro transparency

**Why It Failed**:
- **Depth reconstruction calculations fundamentally broken**
  - Coordinate space mismatches (view space vs world space vs clip space)
  - smoothstep logic inverted or wrong
  - Fade happens at wrong distances or not at all
- **Dithering looks terrible** in practice
  - PSX-style stippled pattern too aggressive/distracting
  - Doesn't match the aesthetic goal
- **Doesn't solve the actual problem**:
  - User needs to see **floor tiles** to make tactical decisions
  - Proximity fade makes ceiling transparent, but you still see ceiling texture, NOT floor
  - Wrong solution to the wrong problem

**User Feedback**: "it's utter shit...the calculations seem all wrong, the dithering is shitty"

**Code Status**: Present in `shaders/psx_proximity_dither.gdshader` but disabled and non-functional

**ROOT CAUSE ANALYSIS** (2025-11-10 deep dive):
The depth buffer approach was asking the **wrong spatial question**:
- **Asked**: "How far is something behind this wall pixel in the depth buffer?"
- **Should ask**: "Is this wall pixel between the camera and player?"

The shader compared wall depth to whatever was in the depth buffer (floor, other walls, far plane), without any concept of player position. This created bizarre patterns:
- Walls next to player (with floor behind) → small depth_diff → FADE (incorrect!)
- Walls obstructing player (with walls behind) → large depth_diff → NO FADE (incorrect!)
- Pattern: `FADE → NO FADE` instead of expected `NO FADE → FADE → NO FADE`

**The fundamental architectural flaw**: Depth buffer contains no information about "where the player is" - it's just closest surface at each pixel. Local depth comparisons cannot answer global spatial relationship questions.

---

### 3. Line-of-Sight Proximity Fade (IN TESTING - 2025-11-10)

**Implementation**:
- Pass player position as uniform to wall shader
- Calculate 3D distance from each wall fragment to camera→player line segment
- Fade only walls that obstruct the sightline (within threshold radius)
- Creates "tunnel of transparency" revealing player

**Correct Spatial Logic**:
```
For each wall fragment:
1. Get camera world position
2. Get player world position (uniform)
3. Calculate 3D line segment from camera to player
4. Calculate fragment's distance to that line
5. Fade if distance < threshold (e.g., 2.0 units)
```

**Expected Behavior** (see diagram: `screenshots/wall_fade_diagram.png`):
- Wall between camera and player → **FADE** ✓
- Walls not obstructing sightline → **NO FADE** ✓
- Player in room with multiple walls → **FADE ONLY obstructing wall** ✓
- Distance doesn't matter, obstruction does ✓

**Potential Issues**:
- ⚠️ Dithering still creates visual noise (may obscure floor/indicators)
- ⚠️ Still showing wall texture, not clean floor
- ⚠️ May need large fade radius to be useful

**Status**: Testing if line-of-sight math solves the pattern issue and provides acceptable gameplay visibility.

---

## The Fundamental Problem

**Goal**: In tactical top-down view, player needs to see the **floor grid** clearly to make informed movement decisions.

**Why Traditional Solutions Don't Work**:
1. **Transparent ceiling** still shows ceiling texture, blocks view of floor
2. **Proximity fade** creates visual noise, doesn't reveal floor layout
3. **Raycasting** has massive performance cost and unreliable detection
4. **Walls and ceiling need different culling** - cannot share same shader/approach

---

## Current Working Solution

**Approach**: Ceiling uses `cull_front` render mode
- **From tactical view (camera above)**: Ceiling completely invisible, floor fully visible ✅
- **From inside (camera below)**: Ceiling renders normally, spatial awareness maintained ✅
- **Walls**: Use separate shader with `cull_back` (solid, opaque) ✅

**Tradeoffs**:
- ✅ Simple, zero performance cost
- ✅ Solves actual gameplay problem (can see floor to navigate)
- ✅ No visual noise or distracting effects
- ❌ Ceiling not visible from above at all (but this is arguably correct for tactics gameplay)

**Code**:
- Ceiling: `shaders/psx_ceiling_tactical.gdshader` (clean PSX shader with cull_front, no proximity fade)
- Walls: `shaders/psx_wall_proximity.gdshader` (TESTING line-of-sight proximity fade with cull_back)

**Note**: As of 2025-11-10, testing line-of-sight based proximity fade on walls (see Approach 3 above). Ceiling remains simple with cull_front.

---

## Why Walls and Ceiling Cannot Share Shaders

**CRITICAL**: Walls and ceiling have **incompatible rendering requirements**:

| Requirement | Walls | Ceiling |
|-------------|-------|---------|
| **Culling** | `cull_back` (solid from all angles) | `cull_front` (invisible from above) |
| **Tactical View** | Always visible (show maze layout) | Invisible (reveal floor) |
| **Inside View** | Always visible (show enclosure) | Visible (show room bounds) |

**Result**: They **MUST use separate shaders** with different render modes. Any attempt to unify them will break one or the other.

---

## Lessons Learned

### What Doesn't Work in Godot GridMap Tactical Games:

1. **Per-cell shader logic** - Too expensive, breaks batching
2. **ShapeCast3D for visual effects** - Wrong tool, physics ≠ rendering
3. **Complex depth texture calculations** - Hard to get right, fragile
4. **PSX dithering for gameplay-critical transparency** - Too distracting
5. **Trying to make walls and ceiling share shaders** - Incompatible requirements

### What Does Work:

1. **Simple render mode changes** (`cull_front` for ceiling)
2. **Separate shaders for separate needs** (walls ≠ ceiling)
3. **Accepting limitations** (invisible ceiling from above is fine for tactics)
4. **Zero-cost solutions over complex hacks**

---

## Alternative Approaches NOT Pursued

### Camera Distance-Based Fade
**Idea**: Fade geometry based on distance from camera (not depth texture)
**Why Not**: Still doesn't solve "need to see floor" problem, simpler to just hide ceiling

### Remove Ceiling Entirely
**Idea**: Don't place ceiling tiles at all
**Why Not**: Loses spatial awareness when inside rooms, current solution better

### Layer-Based Visibility Toggle
**Idea**: Toggle ceiling layer on/off based on camera height
**Why Not**: Binary on/off, current cull_front already does this automatically

### Post-Process Screen-Space Cutout
**Idea**: Cut circular hole in ceiling at player screen position
**Why Not**: Complex, per-frame uniform updates, still shows ceiling texture not floor

---

## Recommendations for Future Agents

### DO:
- ✅ Keep current solution (cull_front ceiling, cull_back walls)
- ✅ Use separate shaders for walls and ceiling
- ✅ Maintain LOUD comments warning about shader incompatibility
- ✅ Accept that tactics games don't need visible ceiling from above

### DO NOT:
- ❌ Try to implement DEPTH_TEXTURE depth buffer comparisons (asks wrong spatial question, see root cause analysis)
- ❌ Attempt per-cell raycasting/shader arrays (performance disaster)
- ❌ Make walls and ceiling share the same shader (incompatible requirements)
- ❌ Over-engineer solutions - simple is better

### CURRENTLY TESTING (2025-11-10):
- 🧪 Line-of-sight proximity fade (distance to camera→player line segment)
- 🧪 Requires player position uniform passed to shader
- 🧪 May still have issues with dithering visual noise
- 🧪 Verdict pending user testing

### If User Demands Ceiling Transparency:
1. First, clarify the **actual problem** (need to see floor? need to see player? decorative?)
2. If "need to see floor": Current solution already works, ceiling is invisible from above
3. If "need to see player through ceiling": Use billboard sprite + always-on-top rendering
4. If decorative: Not worth the complexity, keep current solution

---

## Current File Status

**Working Files**:
- `shaders/psx_lit.gdshader` - Walls (cull_back)
- `shaders/psx_proximity_dither.gdshader` - Ceiling (cull_front, proximity fade disabled)
- `assets/levels/level_00/wall_yellow.tres` - Wall material with CRITICAL warning
- `assets/levels/level_00/ceiling_acoustic.tres` - Ceiling material

**Deleted Files** (commit d9af93c):
- `shaders/psx_wall_obstruction.gdshader` - Broken raycasting approach
- `docs/ceiling-transparency-fixes/*.md` - 6 files, outdated implementation notes

---

## Conclusion

After comprehensive research, multiple implementations, and user testing:

**Verdict**: Ceiling transparency via DEPTH_TEXTURE proximity fade is **non-viable** for this project.

**Current solution works**: Ceiling invisible from above (cull_front) solves the gameplay problem with zero complexity.

**Future agents**: Do not attempt to "fix" or "improve" this. The current solution is correct.

---

**Document Author**: Claude (Sonnet 4.5)
**Last Updated**: 2025-11-10
**Related Commits**: d9af93c (cleanup), 9e25c81-442f8ce (failed attempts)
