shader_type canvas_item;
// Fills a label's letters with a yellow-to-orange gradient. A Label can only fill with
// one flat colour, so this recolours just the "fill" pixels (the ones drawn white) and
// leaves the outline and drop shadow (drawn navy / black) alone.
// Put this shader in a Label's Material, and set the label's font colour to pure white.

uniform vec4 top_color : source_color = vec4(1.0, 0.92, 0.36, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.55, 0.10, 1.0);
// Where the gradient starts and how tall it is, in the label's own pixels. Labels set
// these to their text height, since the gradient should span the letters, not the box.
uniform float gradient_top = 0.0;
uniform float gradient_height = 190.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float is_fill = step(0.92, min(COLOR.r, min(COLOR.g, COLOR.b)));
	float t = clamp((local_y - gradient_top) / gradient_height, 0.0, 1.0);
	vec3 gradient = mix(top_color.rgb, bottom_color.rgb, t);
	COLOR.rgb = mix(COLOR.rgb, gradient, is_fill);
}
