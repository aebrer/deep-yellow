shader_type spatial;

// Same as psx_lit but double-sided (cull_disabled) for wall top caps
#define POINT_LIGHTING
#define LIT vertex_lighting
#define CULL cull_disabled
#define DEPTH depth_draw_opaque
#define BLEND blend_mix

#include "psx_base.gdshaderinc"
