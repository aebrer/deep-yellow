# Pending Features - Backrooms Power Crawl

**Last Updated**: 2025-11-13
**Status**: Design Notes for Future Implementation

---

## Ceiling Texture (Level 0)

### Concept
Acoustic ceiling tiles with fluorescent light panels, typical of 1970s-80s office buildings. Should match the Backrooms aesthetic.

### Reference Description
From Backrooms wiki:
- Fluorescent lighting (inconsistently placed)
- Acoustic ceiling tiles (suspended ceiling grid system)
- Yellowed/aged appearance
- Some tiles may be stained or damaged

### Texture Specifications
- **Size**: 128×128 pixels, tileable
- **Style**: Acoustic ceiling tile texture
- **Color**: Off-white/beige/yellowed (#D8D0C0 to #F0E8D8 range)
- **Pattern**: Subtle perforation pattern (acoustic holes)
- **Details**:
  - Water stains and discoloration
  - Aged, yellowed appearance
  - Fine texture from perforations
  - Subtle grid lines (tile edges)

### Generation Approach
Use the same multi-agent workflow as wallpaper and carpet:
1. Spawn creator agent with ceiling tile description
2. Generate with Python/PIL using modulo wrapping for tiling
3. Run comparison and blind critics
4. Iterate until approved
5. Integrate into assets/levels/level_00/

### Integration
- Create `assets/levels/level_00/textures/ceiling_acoustic.png`
- Create `assets/levels/level_00/ceiling_acoustic.tres` (PSX shader material)
- Update MeshLibrary or add ceiling mesh if needed

### Notes
- Fluorescent light panels would be separate mesh items, not part of ceiling texture
- Focus on the acoustic tile portion
- Should be subtler than walls/floor (ceiling is less prominent)

**Current Status**: Not yet started
**Priority**: Next (part of Level 0 environment completion)
**Dependencies**: None
**Estimated Time**: 1-2 hours (texture generation + integration)

---

## Ceiling Transparency System

### Reference
See **docs/TECHNICAL_DESIGN.md** for complete specification.

### Summary
When the camera tilts up past a certain angle, the ceiling becomes transparent (fades out) to allow the player to see without obstruction.

### Key Features
- Angle-based transparency (>45° from horizontal)
- Smooth fade transition
- Shader-based implementation
- Preserves shadows/lighting

**Current Status**: Not yet started
**Priority**: After ceiling texture
**Full Spec**: docs/TECHNICAL_DESIGN.md
**Estimated Time**: 2-3 hours

---

## Implementation Priority

Based on remaining work:

1. **Ceiling Texture** (Next) - Complete Level 0 environment visuals
2. **Ceiling Transparency System** (After above) - See docs/TECHNICAL_DESIGN.md for spec

---

## Completed Features

The following features have been implemented and merged:

- ✅ **Look Mode** (Merged) - Examination mode with first-person camera, crosshair, and SCP-style tooltips
- ✅ **Player Character Visual** (PR #3) - Billboard sprite with hazmat suit texture
- ✅ **Action Preview UI** (PR #4) - Real-time action preview with input device detection

---

**End of Document**
