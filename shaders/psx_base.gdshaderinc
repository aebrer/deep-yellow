render_mode LIT, CULL, shadows_disabled, DEPTH, BLEND, specular_disabled;

global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform vec4 modulate_color : source_color = vec4(1.0);

#ifdef POINT_LIGHTING
#include "psx_lighting.gdshaderinc"
#endif

#ifndef NO_TEXTURE
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
#endif

#if !defined(NO_TEXTURE) && !defined(METAL)  // METAL doesn't use UV, so no need for panning properties
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(.0, .0);
uniform vec2 uv_pan_velocity = vec2(0.0);
#endif

#ifdef ALPHA_SCISSOR
uniform bool billboard = false;
uniform bool y_billboard = false;
uniform float alpha_scissor : hint_range(0, 1) = 0.1;
#endif

#ifdef CEILING_FADE
// Dual vignette system: screen-space + world-space
uniform bool enable_ceiling_fade = true;

// Screen-space vignette (camera-based)
uniform float screen_fade_inner_radius : hint_range(0.0, 1.0) = 0.35;
uniform float screen_fade_outer_radius : hint_range(0.0, 1.0) = 0.85;
uniform float screen_fade_power : hint_range(0.1, 4.0) = 2.0;

// World-space vignette (player-based cylinder)
uniform vec3 player_world_position = vec3(0.0);
uniform float player_fade_inner_radius : hint_range(0.0, 20.0) = 3.0;
uniform float player_fade_outer_radius : hint_range(0.0, 20.0) = 8.0;
uniform float player_fade_power : hint_range(0.1, 4.0) = 2.0;

// Wireframe rendering (for faded geometry)
uniform vec4 wireframe_color : source_color = vec4(0.0, 1.0, 0.8, 0.3); // Cyan, semi-transparent
uniform float wire_width : hint_range(0.0, 40.0) = 6.0;
uniform float wire_smoothness : hint_range(0.0, 0.1) = 0.01;
uniform float wireframe_threshold : hint_range(0.0, 1.0) = 0.3; // Fade > this = wireframe

varying vec3 barys;  // Barycentric coordinates for wireframe
varying vec3 world_position;  // For world-space vignette

float calculate_screen_space_fade() {
	// Distance from screen center (0.5, 0.5)
	vec2 screen_center = vec2(0.5, 0.5);
	vec2 uv_from_center = SCREEN_UV - screen_center;
	float dist_from_center = length(uv_from_center);

	// Normalize to 0.0 (center) to 1.0 (corner)
	dist_from_center = dist_from_center / 0.707;  // Diagonal = ~0.707

	// Smooth falloff between inner and outer radius
	float fade_factor = smoothstep(screen_fade_inner_radius, screen_fade_outer_radius, dist_from_center);
	fade_factor = pow(fade_factor, screen_fade_power);

	return fade_factor;
}

float calculate_world_space_fade() {
	// Horizontal distance from player (cylinder, not sphere - ignore Y)
	vec2 player_pos_xz = player_world_position.xz;
	vec2 world_pos_xz = world_position.xz;
	float dist_from_player = length(world_pos_xz - player_pos_xz);

	// Smooth falloff between inner and outer radius
	float fade_factor = smoothstep(player_fade_inner_radius, player_fade_outer_radius, dist_from_player);
	fade_factor = pow(fade_factor, player_fade_power);

	return fade_factor;
}

float calculate_combined_fade() {
	float screen_fade = calculate_screen_space_fade();
	float world_fade = calculate_world_space_fade();

	// Use MINIMUM (most opaque wins) - if either vignette says "show", we show
	return min(screen_fade, world_fade);
}
#endif

// https://github.com/dsoft20/psx_retroshader/blob/master/Assets/Shaders/psx-vertexlit.shader
const vec2 base_snap_res = vec2(160.0, 120.0);
vec4 get_snapped_pos(vec4 base_pos)
{
	vec4 snapped_pos = base_pos;
	snapped_pos.xyz = base_pos.xyz / base_pos.w; // convert to normalised device coordinates (NDC)
	vec2 snap_res = floor(base_snap_res * precision_multiplier);  // increase "snappy-ness"
	snapped_pos.x = floor(snap_res.x * snapped_pos.x) / snap_res.x;  // snap the base_pos to the lower-vertex_resolution grid
	snapped_pos.y = floor(snap_res.y * snapped_pos.y) / snap_res.y;
	snapped_pos.xyz *= base_pos.w;  // convert back to projection-space
	return snapped_pos;
}

void vertex()
{
#if !defined(NO_TEXTURE) && !defined(METAL)  // METAL doesn't use UV, so no need to pan UVs
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;
#endif

#ifdef ALPHA_SCISSOR
	if (y_billboard)
	{
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0 / length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
	else if (billboard)
	{
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
#endif

#ifdef CEILING_FADE
	// Assign barycentric coordinates for wireframe rendering
	int index = VERTEX_ID % 3;
	if (index == 0) {
		barys = vec3(1.0, 0.0, 0.0);
	} else if (index == 1) {
		barys = vec3(0.0, 1.0, 0.0);
	} else {
		barys = vec3(0.0, 0.0, 1.0);
	}

	// Calculate world position for world-space vignette
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif

#ifdef POINT_LIGHTING
	// World position and normal for custom point light calculation
	world_pos_for_lighting = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_for_lighting = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#endif

	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));  // snap position to grid
	//POSITION /= abs(POSITION.w);  // discard depth for affine mapping (disabled: causes severe texture distortion near camera)

#ifdef ALPHA_SCISSOR
	if (y_billboard)
	{
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
#endif

	VERTEX = VERTEX;  // it breaks without this - not sure why
}

void fragment()
{
#ifdef METAL
	vec2 texture_uv = vec2(NORMAL.x / 2.0 + 0.5, (-NORMAL.y) / 2.0 + 0.5);  // Special thanks to Adam McLaughlan
#elif !defined(NO_TEXTURE)
	vec2 texture_uv = UV;
#endif

	vec4 color_base = COLOR * modulate_color;

#ifdef NO_TEXTURE
	ALBEDO = color_base.rgb;
#else
	vec4 texture_color = texture(albedoTex, texture_uv);
	ALBEDO = (color_base * texture_color).rgb;
#endif

#ifdef POINT_LIGHTING
	// Apply custom point lighting (replaces Godot's vertex_lighting)
	vec3 point_light = calculate_point_lighting(world_pos_for_lighting);
	ALBEDO *= point_light;
#endif

#ifdef LIGHT_VOLUME
	ALPHA = 1.0 - UV.y;
#elif defined(ALPHA_BLEND) || defined(ALPHA_SCISSOR)
	ALPHA = texture_color.a * color_base.a;
#endif

#ifdef ALPHA_SCISSOR
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif

#ifdef CEILING_FADE
	if (enable_ceiling_fade) {
		float fade = calculate_combined_fade();

		// fade = 0.0 means "near center/player, should be transparent/wireframe"
		// fade = 1.0 means "at edges/far from player, should be opaque"
		// So opacity = fade (not 1.0 - fade!)

		// If fade is LOW (near center/player), render as wireframe
		if (fade < wireframe_threshold) {
			// Calculate edge proximity using barycentric coordinates
			vec3 deltas = fwidth(barys);
			vec3 barys_s = smoothstep(
				deltas * wire_width - wire_smoothness,
				deltas * wire_width + wire_smoothness,
				barys
			);

			// Minimum value = closest to an edge
			float wire_mix = min(barys_s.x, min(barys_s.y, barys_s.z));

			// Mix between wireframe and transparent
			// wire_mix = 0.0 at edges, 1.0 in center of triangle
			ALBEDO = mix(wireframe_color.rgb, ALBEDO, wire_mix);
			ALPHA = mix(wireframe_color.a, 0.0, wire_mix);  // Edges visible, center transparent

			// Discard fully transparent pixels for better performance
			if (ALPHA < 0.01) {
				discard;
			}
		} else {
			// Above wireframe threshold, fade in based on distance
			ALPHA *= fade;  // fade=0.3 → 30% opaque, fade=1.0 → fully opaque
			if (ALPHA < 0.01) {
				discard;
			}
		}
	}
#endif
}
