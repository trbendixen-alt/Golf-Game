shader_type spatial;
render_mode cull_disabled;
// Pin flag rippling in the wind. The mesh's left edge (x = -0.5 * width) is the pole side.

global uniform vec3 wind_vec;
uniform vec3 color_a : source_color = vec3(0.95, 0.15, 0.1);
uniform vec3 color_b : source_color = vec3(1.0, 0.85, 0.2);
uniform float width = 0.9;

void vertex() {
	float t = (VERTEX.x / width) + 0.5;
	float w = length(wind_vec);
	float amp = 0.06 + w * 0.012;
	VERTEX.z += sin(TIME * (5.0 + w * 0.4) - t * 7.0) * amp * t;
	VERTEX.y += sin(TIME * 3.0 - t * 5.0) * amp * 0.3 * t;
}

void fragment() {
	// red flag with a yellow stripe across the middle
	ALBEDO = mix(color_a, color_b, step(abs(UV.y - 0.5), 0.1));
	ROUGHNESS = 0.7;
}
