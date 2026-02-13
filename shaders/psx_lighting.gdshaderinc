// ============================================================================
// SHADER-BASED POINT LIGHTING
// ============================================================================
// Replaces Godot's built-in vertex_lighting with custom per-fragment lighting.
// Solves two problems:
// 1. GridMap cells don't share vertices, causing hard rectangular light borders
//    with vertex_lighting. Per-fragment calculation is smooth across tile edges.
// 2. Performance: Zero OmniLight3D nodes needed. Light positions are passed as
//    uniform arrays and evaluated entirely in the shader.
//
// Usage: #include in any spatial shader, call calculate_point_lighting() in
// fragment() and multiply result into ALBEDO.
// ============================================================================

// Maximum lights the shader can evaluate per fragment.
// GDScript must pad arrays to this size (unused entries have range=0).
const int MAX_LIGHTS = 16;

// Light data arrays — set per-frame by Grid3D._process()
uniform int light_count : hint_range(0, 16) = 0;
uniform vec3 light_positions[MAX_LIGHTS];
uniform vec3 light_colors[MAX_LIGHTS];     // RGB pre-multiplied by energy
uniform float light_ranges[MAX_LIGHTS];

// Player-carried light (always active, separate from fixture array)
uniform vec3 player_light_pos;
uniform vec3 player_light_color = vec3(0.0);
uniform float player_light_range = 0.0;

// Ambient light (replaces Godot's ambient since we use render_mode unshaded).
// Set per-level by Grid3D from LevelConfig ambient_light_color * intensity.
uniform vec3 ambient_light = vec3(0.08);

// World position varying — must be set in vertex():
//   world_pos_for_lighting = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
varying vec3 world_pos_for_lighting;

// World-space normal varying — must be set in vertex():
//   world_normal_for_lighting = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
// CRITICAL: Godot transforms NORMAL to view space between vertex() and fragment().
// We need world-space normals for correct Lambert with world-space light directions.
varying vec3 world_normal_for_lighting;

float _attenuation(float dist, float range) {
	// Smooth quadratic falloff, reaches 0 at range
	float ratio = clamp(dist / range, 0.0, 1.0);
	float att = 1.0 - ratio;
	return att * att;  // Quadratic for soft edges
}

vec3 calculate_point_lighting(vec3 frag_world_pos) {
	// Accumulate light contributions from all active point lights.
	// Returns light color (ambient + point lights) to multiply with albedo.
	// Uses world_normal_for_lighting varying (set in vertex shader).

	vec3 frag_normal = world_normal_for_lighting;
	vec3 total_light = ambient_light;

	// Fixture lights
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) break;

		float range = light_ranges[i];
		if (range <= 0.0) continue;

		vec3 light_dir = light_positions[i] - frag_world_pos;
		float dist = length(light_dir);

		if (dist >= range) continue;

		float att = _attenuation(dist, range);

		// Lambert diffuse with world-space normal
		float ndl = 1.0;
		if (length(frag_normal) > 0.5) {
			ndl = max(dot(normalize(frag_normal), normalize(light_dir)), 0.0);
			// Wrap lighting: soften the terminator so back faces aren't pitch black
			ndl = ndl * 0.7 + 0.3;
		}

		total_light += light_colors[i] * att * ndl;
	}

	// Player light
	if (player_light_range > 0.0) {
		vec3 pl_dir = player_light_pos - frag_world_pos;
		float pl_dist = length(pl_dir);
		if (pl_dist < player_light_range) {
			float pl_att = _attenuation(pl_dist, player_light_range);
			float pl_ndl = 1.0;
			if (length(frag_normal) > 0.5) {
				pl_ndl = max(dot(normalize(frag_normal), normalize(pl_dir)), 0.0);
				pl_ndl = pl_ndl * 0.7 + 0.3;
			}
			total_light += player_light_color * pl_att * pl_ndl;
		}
	}

	return total_light;
}
