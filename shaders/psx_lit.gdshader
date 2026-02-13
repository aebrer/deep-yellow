shader_type spatial;

// Custom shader-based point lighting replaces Godot's vertex_lighting.
// vertex_lighting caused hard rectangular borders at GridMap cell boundaries
// because cells don't share vertices. Our per-fragment calculation is smooth.
#define POINT_LIGHTING
#define LIT unshaded
#define CULL cull_back
#define DEPTH depth_draw_opaque
#define BLEND blend_mix

#include "psx_base.gdshaderinc"
