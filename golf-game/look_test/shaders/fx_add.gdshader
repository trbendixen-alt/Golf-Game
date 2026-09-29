shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Additive HDR particles (sparks, ball trail, wind streaks). Values above 1.0 bloom.

uniform float energy = 4.0;
uniform bool billboard = false;
uniform bool soft = false;

void vertex() {
	if (billboard) {
		mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		mat4 scale = mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * face * scale;
	}
}

void fragment() {
	float a = COLOR.a;
	if (soft) {
		a *= smoothstep(0.5, 0.05, length(UV - vec2(0.5)));
	}
	ALBEDO = COLOR.rgb * energy * a;
	ALPHA = a;
}
