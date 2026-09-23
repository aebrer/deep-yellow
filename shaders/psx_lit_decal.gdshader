shader_type spatial;

// Floor decals (exit holes, stairs) lie flat on the floor, so they must brighten
// and darken exactly like the tiles around them. Same lit path as the floor:
// vertex_lighting (ambient/directional) + baked lightmap fixtures + player light,
// plus the shared pixel_snap_resolution so texel size matches the floor tile.
// ALPHA_SCISSOR gives the cut-out without alpha blending, so depth writes stay on.
#define POINT_LIGHTING
#define LIT vertex_lighting
#define CULL cull_disabled
#define DEPTH depth_draw_opaque
#define BLEND blend_mix
#define ALPHA_SCISSOR

#include "psx_base.gdshaderinc"