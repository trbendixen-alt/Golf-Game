shader_type spatial;
// Tree canopies: lumpy displaced spheres that sway with the wind, and glow gold at
// the edges when backlit by a low sun (fake translucency).

global uniform vec3 sun_dir;
global uniform vec4 sun_color;
global uniform vec3 wind_vec;

uniform vec3 leaf_color : source_color = vec3(0.22, 0.36, 0.10);
uniform vec3 leaf_color_2 : source_color = vec3(0.35, 0.45, 0.12);

varying vec3 wpos;
varying float tint;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	// lumpy canopy
	float lump = sin(VERTEX.x * 5.0 + origin.x) * sin(VERTEX.y * 4.0 + origin.z) * sin(VERTEX.z * 5.0);
	VERTEX += NORMAL * lump * 0.12;
	// sway: stronger higher up and in stronger wind
	float w = length(wind_vec);
	float sway = sin(TIME * (1.2 + w * 0.12) + origin.x * 0.7 + origin.z * 0.3) * (0.03 + w * 0.012);
	vec3 wdir = w > 0.01 ? wind_vec / w : vec3(1.0, 0.0, 0.0);
	vec3 local_push = (inverse(mat3(MODEL_MATRIX)) * wdir) * sway * max(VERTEX.y + 0.6, 0.0);
	VERTEX += local_push;
	wpos = world;
	tint = hash3(floor(origin));
}

void fragment() {
	vec3 c = mix(leaf_color, leaf_color_2, tint);
	c *= 0.85 + 0.25 * sin(wpos.x * 3.1) * sin(wpos.y * 2.7 + wpos.z);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	vec3 sv = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float back = pow(max(dot(-VIEW, sv), 0.0), 5.0);
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0);
	EMISSION = sun_color.rgb * c * back * (0.3 + rim) * 0.7 * min(sun_color.a, 2.5);
}
