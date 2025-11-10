shader_type spatial;
render_mode diffuse_lambert, vertex_lighting, cull_disabled, shadows_disabled, depth_prepass_alpha, blend_mix, specular_disabled;

// Global uniforms
global uniform float precision_multiplier : hint_range(0.0, 1.0) = 1.0;

// Base PSX uniforms
uniform vec4 modulate_color : source_color = vec4(1.0);
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_pan_velocity = vec2(0.0);

// Camera→Player obstruction (raycast-based)
uniform bool enable_obstruction_fade = true;
uniform vec3 player_world_position = vec3(0.0);  // For player cylinder
uniform int obstructed_cell_count = 0;  // Number of cells in obstructed_cells array
uniform vec3 obstructed_cells[256];  // Grid cell positions that are obstructed (populated by raycasting)
uniform float cell_size = 2.0;  // Size of one grid cell

// Player cylinder (XZ-only, ignores Y)
uniform float player_fade_inner_radius : hint_range(0.0, 20.0) = 3.0;
uniform float player_fade_outer_radius : hint_range(0.0, 20.0) = 8.0;
uniform float player_fade_power : hint_range(0.1, 4.0) = 2.0;

// Ceiling-specific: disable fade when viewing from below
uniform bool is_ceiling = false;  // Set to true for ceiling tiles

// Wireframe rendering for obstructed objects
uniform vec4 wireframe_color : source_color = vec4(0.0, 1.0, 0.8, 0.3);
uniform float wire_width : hint_range(0.0, 40.0) = 1.0;
uniform float wire_smoothness : hint_range(0.0, 0.1) = 0.01;
uniform float wireframe_threshold : hint_range(0.0, 1.0) = 0.8;
uniform float grid_scale : hint_range(0.1, 10.0) = 1.0;

// Varying variables
varying vec3 world_position;
varying vec2 screen_uv;

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

float calculate_distance_to_line(vec3 point, vec3 line_start, vec3 line_end) {
	// Calculate distance from point to line segment (camera→player)
	vec3 line_dir = line_end - line_start;
	float line_length = length(line_dir);

	if (line_length < 0.001) {
		return length(point - line_start);
	}

	vec3 line_norm = line_dir / line_length;

	// Project point onto line
	float t = dot(point - line_start, line_norm);
	t = clamp(t, 0.0, line_length);  // Clamp to line segment

	// Find closest point on line
	vec3 closest_point = line_start + line_norm * t;

	// Return distance from point to closest point on line
	return length(point - closest_point);
}

float calculate_player_cylinder_fade() {
	// Player cylinder: XZ-only distance (ignores Y, extends infinitely up/down)
	vec2 player_pos_xz = player_world_position.xz;
	vec2 world_pos_xz = world_position.xz;
	float dist_from_player = length(world_pos_xz - player_pos_xz);
	float fade_factor = smoothstep(player_fade_inner_radius, player_fade_outer_radius, dist_from_player);
	fade_factor = pow(fade_factor, player_fade_power);
	return fade_factor;
}

void vertex() {
	// UV panning
	UV = UV * uv_scale + uv_offset;
	UV += uv_pan_velocity * TIME;

	// World position for obstruction check
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// PSX vertex snapping
	POSITION = get_snapped_pos(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION /= abs(POSITION.w);

	// Calculate screen UV
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 ndc = clip_pos.xyz / clip_pos.w;
	screen_uv = ndc.xy * 0.5 + 0.5;

	VERTEX = VERTEX;
}

void fragment() {
	// Base PSX rendering
	vec4 color_base = COLOR * modulate_color;
	vec4 texture_color = texture(albedoTex, UV);
	ALBEDO = (color_base * texture_color).rgb;
	ALPHA = texture_color.a * color_base.a;

	// DEBUG: Visualize obstructed cells
	bool debug_obstruction = false;
	if (debug_obstruction) {
		// Calculate which grid cell this fragment belongs to (XZ only, ignore Y)
		vec3 my_cell = floor(world_position / cell_size);

		// Check if this cell is in the obstructed cells array
		// NOTE: Only compare X and Z! Grid cells are at Y=0 or Y=1, but fragments extend upward
		bool is_cell_obstructed = false;
		for (int i = 0; i < obstructed_cell_count; i++) {
			vec2 diff_xz = abs(my_cell.xz - obstructed_cells[i].xz);
			if (diff_xz.x < 0.1 && diff_xz.y < 0.1) {
				is_cell_obstructed = true;
				break;
			}
		}

		if (is_cell_obstructed) {
			ALBEDO = vec3(1.0, 0.0, 1.0);  // Magenta = obstructed by raycast
		} else if (is_ceiling) {
			ALBEDO = vec3(1.0, 0.0, 0.0);  // Red = ceiling (not obstructed)
		} else {
			ALBEDO = vec3(0.0, 0.0, 1.0);  // Blue = wall (not obstructed)
		}
	} else if (enable_obstruction_fade) {
		// Check if viewing ceiling from below - skip obstruction effects
		bool skip_obstruction = false;
		if (is_ceiling) {
			float view_dot_normal = dot(VIEW, NORMAL);
			// Viewing from below (positive dot product with downward normal)
			skip_obstruction = (view_dot_normal > 0.0);
		}

		if (!skip_obstruction) {
			// Calculate BOTH transparency effects:
			// 1. Raycast obstruction - check if this fragment's cell is in obstructed array
			// 2. Player cylinder - distance-based fade around player (ceiling only)

			// Calculate which grid cell this fragment belongs to (XZ only, ignore Y)
			vec3 my_cell = floor(world_position / cell_size);

			// Check if this cell is in the obstructed cells array
			// NOTE: Only compare X and Z! Grid cells are at Y=0 or Y=1, but fragments extend upward
			float raycast_fade = 1.0;  // Default: not obstructed
			for (int i = 0; i < obstructed_cell_count; i++) {
				// Check if fragment's XZ cell matches any obstructed cell's XZ
				vec2 diff_xz = abs(my_cell.xz - obstructed_cells[i].xz);
				if (diff_xz.x < 0.1 && diff_xz.y < 0.1) {
					raycast_fade = 0.0;  // This cell is obstructed!
					break;
				}
			}

			// Player cylinder (XZ-only distance) - DISABLED FOR NOW
			// TODO: Re-enable after raycasting is working
			float cylinder_fade = 1.0;  // 1.0 = no fade (disabled)

			// Combine: min() so EITHER effect makes transparent
			// Walls: only raycast applies (cylinder_fade = 1.0)
			// Ceiling: both raycast AND cylinder apply
			float fade = min(raycast_fade, cylinder_fade);

			// If inside either effect (fade < threshold), render as wireframe
			if (fade < wireframe_threshold) {
				// UV-based grid wireframe
				vec2 grid_uv = fract(UV * grid_scale);
				vec2 edge_dist = min(grid_uv, 1.0 - grid_uv);
				vec2 edge_proximity = edge_dist / fwidth(UV * grid_scale);
				float grid_line = min(edge_proximity.x, edge_proximity.y);
				float wire_mix = smoothstep(wire_width - wire_smoothness, wire_width + wire_smoothness, grid_line);

				ALBEDO = mix(wireframe_color.rgb, ALBEDO, wire_mix);
				ALPHA = mix(wireframe_color.a, 0.0, wire_mix);

				if (ALPHA < 0.01) {
					discard;
				}
			} else {
				// Outside both effects, fade in normally
				ALPHA *= fade;
				if (ALPHA < 0.01) {
					discard;
				}
			}
		}
	}
}
