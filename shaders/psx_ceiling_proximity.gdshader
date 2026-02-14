shader_type spatial;
// ============================================================================
// CEILING PROXIMITY FADE SHADER - For ceilings ONLY!
// ============================================================================
// Ceilings use cull_disabled (visible from both sides)
// ALWAYS VISIBLE from below (no transparency when looking up)
// Fades when viewed from ABOVE (proximity tunnel when looking down)
// ============================================================================
// CRITICAL: depth_prepass_alpha fixes culling issues when using transparency
// Without it: depth buffer + discard/alpha interaction causes missing faces
// Uses unshaded + custom point lighting (replaces vertex_lighting).
// vertex_lighting caused hard rectangular borders at GridMap cell boundaries.
render_mode vertex_lighting, cull_disabled, depth_prepass_alpha, blend_mix, specular_disabled, shadows_disabled;

// Global uniforms
global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;

// Base PSX uniforms
uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_pan_velocity = vec2(0.0);

// Line-of-sight proximity fade settings
uniform bool enable_proximity_fade = true;
uniform float sightline_fade_radius : hint_range(0.0, 10.0) = 2.0;  // Distance from camera→player line
uniform bool use_dithered_fade = true;
uniform vec3 player_position;  // World space position of player (set by Grid)

// CRITICAL: Pass world position from vertex shader to fragment shader
// VERTEX is only valid in vertex shader, not fragment shader!
varying vec3 world_position;

// Custom point lighting
#include "psx_lighting.gdshaderinc"

// Bayer 4x4 dithering matrix
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
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;

	// Calculate world position and normal for proximity fade AND point lighting
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos_for_lighting = world_position;
	world_normal_for_lighting = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	//POSITION /= abs(POSITION.w);  // disabled: causes severe texture distortion near camera

	VERTEX = VERTEX;  // Critical - don't remove
}

void fragment() {
	vec4 color_base = COLOR * modulate_color;
	vec4 texture_color = texture(albedoTex, UV);
	ALBEDO = (color_base * texture_color).rgb;

	// Add lightmap point lighting on top of Godot's vertex_lighting
	vec3 point_light = calculate_point_lighting(world_position);
	ALBEDO += texture_color.rgb * modulate_color.rgb * point_light;

	// ALWAYS set ALPHA first (critical for correct rendering)
	ALPHA = texture_color.a * color_base.a;

	if (enable_proximity_fade) {
		// ========================================================================
		// LINE-OF-SIGHT PROXIMITY FADE (WITH CEILING HEIGHT CHECK)
		// ========================================================================
		// Fade ceiling that is close to the camera→player sightline.
		// BUT: Only fade when camera is ABOVE ceiling (looking down)
		//      Always opaque when camera is BELOW ceiling (looking up)

		// Get fragment position in world space (from varying - calculated in vertex shader)
		vec3 fragment_world_pos = world_position;

		// Get camera position in world space (extract from inverse view matrix)
		vec3 camera_pos = INV_VIEW_MATRIX[3].xyz;

		// ========================================================================
		// CEILING HEIGHT CHECK: Disable fade if camera below ceiling
		// ========================================================================
		// Ceiling Y is approximately the fragment Y (ceiling is flat horizontal)
		float ceiling_y = fragment_world_pos.y;
		float camera_y = camera_pos.y;

		float fade = 1.0;  // Default: fully opaque

		// Only apply proximity fade if camera is ABOVE ceiling
		if (camera_y > ceiling_y) {
			// Camera is above ceiling (looking down) - apply proximity fade

			// Calculate camera→player line direction
			vec3 line_direction = normalize(player_position - camera_pos);

			// Project fragment onto camera→player line
			vec3 fragment_to_camera = fragment_world_pos - camera_pos;
			float projection = dot(fragment_to_camera, line_direction);

			// For ceiling: Fade ALL fragments near the line, not just between camera and player
			// This creates a full cylinder around the camera→player line
			vec3 closest_point = camera_pos + line_direction * projection;
			float dist_to_sightline = length(fragment_world_pos - closest_point);

			// Fade based on distance to sightline
			// fade = 0.0 when on sightline (fully transparent)
			// fade = 1.0 when far from sightline (fully opaque)
			fade = smoothstep(0.0, sightline_fade_radius, dist_to_sightline);
		}
		// else: Camera is below ceiling (looking up) - keep fade = 1.0 (fully opaque)

		// Apply transparency based on fade value
		if (use_dithered_fade) {
			// PSX-style dithered transparency using binary alpha (no discard!)
			// This avoids depth buffer holes that cause culling issues
			float dither_threshold = get_bayer_dither(FRAGCOORD.xy);
			if (fade < dither_threshold) {
				ALPHA = 0.0;  // Fully transparent pixel
			} else {
				ALPHA = 1.0;  // Fully opaque pixel
			}
		} else {
			// Smooth alpha blending
			ALPHA *= fade;
		}
	}
}
