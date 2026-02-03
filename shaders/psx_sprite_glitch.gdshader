shader_type spatial;

// Must include billboard_mode for Sprite3D material_override (node billboard is bypassed)
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, blend_mix, billboard_enabled;

// Base sprite texture (set manually via set_shader_parameter)
uniform sampler2D albedoTex : source_color, filter_nearest, repeat_enable;
uniform float alpha_scissor : hint_range(0, 1) = 0.1;

// Glitch parameters
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 corrupt_tint : source_color = vec4(1.0, 0.9, 0.3, 1.0);  // Corruption yellow

void fragment() {
	vec2 uv = UV;

	// Scanline offset (horizontal UV displacement)
	float scan_time = TIME * 3.0;
	float scanline = step(0.92 - glitch_intensity * 0.15, fract(sin(floor(uv.y * 8.0) + scan_time) * 43758.5453));
	uv.x += scanline * 0.08 * glitch_intensity;

	// Chromatic aberration (RGB channel separation)
	float aberration = glitch_intensity * 0.02;
	float r = texture(albedoTex, uv + vec2(aberration, 0.0)).r;
	float g = texture(albedoTex, uv).g;
	float b = texture(albedoTex, uv - vec2(aberration, 0.0)).b;
	float a = texture(albedoTex, uv).a;

	vec3 color = vec3(r, g, b);

	// Subtle corrupt tint
	color = mix(color, color * corrupt_tint.rgb, glitch_intensity * 0.3);

	// Occasional horizontal glitch bars
	float bar = step(0.97 - glitch_intensity * 0.05, fract(sin(floor(uv.y * 20.0 + TIME * 7.0)) * 12345.6789));
	color = mix(color, corrupt_tint.rgb, bar * 0.6);

	ALBEDO = color;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}

void vertex() {
	// Vertex wobble
	float wobble = sin(TIME * 5.0 + VERTEX.y * 3.0) * 0.02;
	VERTEX.x += wobble;
}
