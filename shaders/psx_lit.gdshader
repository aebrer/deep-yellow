shader_type spatial;

// Lightmap-based point lighting on top of Godot's vertex_lighting.
// vertex_lighting handles ambient+directional natively (no cell boundary
// artifacts since those lights are uniform). Lightmap adds point lights
// per-fragment via texture sample (smooth across cell edges).
#define POINT_LIGHTING
#define LIT vertex_lighting
#define CULL cull_back
#define DEPTH depth_draw_opaque
#define BLEND blend_mix

#include "psx_base.gdshaderinc"
