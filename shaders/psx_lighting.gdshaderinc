// ============================================================================
// LIGHTMAP-BASED POINT LIGHTING
// ============================================================================
// Pre-baked 2D lightmap replaces per-fragment point light evaluation.
// Fixture lights are baked into a texture when chunks load/unload.
// Player light remains per-fragment (it moves every frame).
//
// Performance: 1 texture sample per fragment instead of 16 light evaluations.
// The lightmap is rebuilt only when chunks change (fixtures are static).
//
// Usage: #include in any spatial shader, call calculate_point_lighting() in
// fragment() and multiply result into ALBEDO.
// ============================================================================

// Lightmap texture — baked by Grid3D when chunks load/unload.
// Contains ambient + fixture light contributions as RGB color.
// Uses filter_linear for smooth bilinear interpolation between pixels.
uniform sampler2D lightmap_tex : filter_linear, repeat_disable;
uniform vec2 lightmap_origin;     // World XZ of lightmap pixel (0,0)
uniform vec2 lightmap_inv_size;   // 1.0 / (pixel_count * cell_size) — maps world XZ to UV

// Player-carried light (always active, per-fragment — moves every frame)
uniform vec3 player_light_pos;
uniform vec3 player_light_color = vec3(0.0);
uniform float player_light_range = 0.0;

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
	// Sample lightmap for ambient + fixture lighting (pre-baked, 1 texture fetch)
	vec2 lm_uv = (frag_world_pos.xz - lightmap_origin) * lightmap_inv_size;
	vec3 total_light = texture(lightmap_tex, lm_uv).rgb;

	// Player light (per-fragment, Lambert diffuse with wrap lighting)
	if (player_light_range > 0.0) {
		vec3 pl_dir = player_light_pos - frag_world_pos;
		float pl_dist = length(pl_dir);
		if (pl_dist < player_light_range) {
			float pl_att = _attenuation(pl_dist, player_light_range);
			float pl_ndl = 1.0;
			vec3 frag_normal = world_normal_for_lighting;
			if (length(frag_normal) > 0.5) {
				pl_ndl = max(dot(normalize(frag_normal), normalize(pl_dir)), 0.0);
				pl_ndl = pl_ndl * 0.7 + 0.3;  // Wrap lighting
			}
			total_light += player_light_color * pl_att * pl_ndl;
		}
	}

	return total_light;
}
