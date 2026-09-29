shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;
// Soft billboard puffs (dust on landing, turf spray).

global uniform vec4 sun_color;

void vertex() {
	mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 scale = mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face * scale;
}

void fragment() {
	float d = length(UV - vec2(0.5));
	ALBEDO = COLOR.rgb * mix(vec3(0.6), sun_color.rgb, 0.5);
	ALPHA = COLOR.a * smoothstep(0.5, 0.1, d);
}
