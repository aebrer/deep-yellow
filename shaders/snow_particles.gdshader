shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Simple white circle billboard for snow particles
// Used with GPUParticles3D + ParticleProcessMaterial

uniform vec4 snow_color : source_color = vec4(0.9, 0.92, 0.95, 0.7);

void vertex() {
	// Billboard: always face camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MODELVIEW_MATRIX[2].xyz)), 0.0),
		vec4(vec3(0.0, 1.0, 0.0), 0.0),
		vec4(normalize(cross(MODELVIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// Soft circle
	float dist = length(UV - vec2(0.5));
	float alpha = smoothstep(0.5, 0.3, dist);
	ALBEDO = snow_color.rgb;
	ALPHA = alpha * snow_color.a * COLOR.a;
}
