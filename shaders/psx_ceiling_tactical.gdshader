shader_type spatial;
// ============================================================================
// CEILING SHADER - ONLY USE THIS FOR CEILINGS, NOT WALLS!
// ============================================================================
// CRITICAL: cull_front means ceiling ONLY visible from BELOW (when inside room)
// When camera is ABOVE (tactical view), ceiling is invisible so you can see floor!
// This is intentional and solves the "can't see floor to make movement decisions" problem.
// Future agents: DO NOT change to cull_back or cull_disabled!
// ============================================================================
render_mode diffuse_lambert, vertex_lighting, cull_front, depth_draw_opaque, blend_mix, specular_disabled, shadows_disabled;

// ============================================================================
// PSX PROXIMITY FADE SHADER
// ============================================================================
// Automatically fades walls/ceilings when they get close to the camera.
// Uses depth texture to detect proximity to ANY geometry (including player).
// Optional PSX-style dithered transparency for retro aesthetic.
//
// USAGE:
// - Apply to wall/ceiling materials in MeshLibrary
// - Tune proximity_fade_distance per material (walls vs ceiling)
// - Toggle use_dithered_fade for PSX look vs smooth blend
// ============================================================================

// Global uniforms
global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;

// Base PSX uniforms
uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_pan_velocity = vec2(0.0);

// Proximity fade settings (DEPTH_TEXTURE removed due to Godot 4.5.1 gl_compatibility bug)
uniform bool enable_proximity_fade = false;  // Enable/disable proximity fade (disabled until depth texture bug fixed)
uniform float proximity_fade_distance : hint_range(0.0, 20.0) = 5.0;  // Distance before full fade
uniform bool use_dithered_fade = true;  // PSX-style dithering vs smooth alpha

// Bayer 4x4 dithering matrix (PSX aesthetic)
const float bayer_matrix[16] = float[](
	0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
	12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
	3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
	15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0
);

float get_bayer_dither(vec2 screen_pos) {
	int x = int(mod(screen_pos.x, 4.0));
	int y = int(mod(screen_pos.y, 4.0));
	return bayer_matrix[y * 4 + x];
}

// PSX vertex snapping
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
	// UV transformations
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;

	// PSX vertex snapping
	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION /= abs(POSITION.w);

	// CRITICAL: Required for shader to work (from working psx_base.gdshaderinc)
	VERTEX = VERTEX;  // it breaks without this - not sure why
}

void fragment() {
	// Base PSX rendering
	vec4 color_base = COLOR * modulate_color;
	vec4 texture_color = texture(albedoTex, UV);
	ALBEDO = (color_base * texture_color).rgb;

	// ========================================================================
	// SET ALPHA IMMEDIATELY (CRITICAL: Must be set before any conditional logic)
	// ========================================================================
	// Default: Use texture and modulate alpha (fully opaque if texture has no alpha)
	ALPHA = texture_color.a * color_base.a;

	// ========================================================================
	// PROXIMITY FADE CALCULATION (Disabled due to Godot 4.5.1 gl_compatibility bug)
	// ========================================================================
	// NOTE: DEPTH_TEXTURE uniform causes black screen in gl_compatibility renderer
	// This is a known Godot 4.5.1 bug, fixed in Godot 4.6+
	// Proximity fade functionality will be re-enabled after engine upgrade
	//
	// For now, materials render normally with ALPHA set above
}
