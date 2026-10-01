// Shared by building.gdshader (near, full detail) and building_lite.gdshader (far).
// Procedural facade for box buildings: storefront glass on the ground floor, a window
// grid above, cornice + floor bands, and a cheap fake sun glint on the glass. Each pane
// is tilted a hair differently (old glass is never flat), so panes flash one by one as
// the camera moves.
//
// Adapted from Julian's look_test/shaders/building.gdshader. The one structural change:
// instead of per-object "instance uniforms", each building's settings travel inside the
// mesh itself, so hundreds of buildings can be merged into ONE mesh and drawn in one go:
//   COLOR        = wall colour
//   CUSTOM0      = building size (x, y, z) and storefront flag (w)
//   CUSTOM1      = trim colour (rgb) and a random seed (a)
//   CUSTOM2.xyz  = building centre

global uniform vec3 sun_dir;    // world space, points toward the sun
global uniform vec4 sun_color;  // rgb colour, a = energy

uniform vec3 glass_tint : source_color = vec3(0.16, 0.22, 0.28);
uniform float lit_ratio = 0.10;
uniform vec3 interior_color : source_color = vec3(1.0, 0.72, 0.42);
uniform float interior_energy = 0.8;
uniform float glint_strength = 9.0;
uniform float glint_sharpness = 600.0;
uniform float floor_height = 3.2;
uniform float ground_floor_height = 3.8;
uniform float window_spacing = 2.6;

varying vec3 l_pos;
varying vec3 l_nrm;
varying flat vec4 v_size;
varying flat vec4 v_trim;
varying flat vec3 v_wall;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	l_pos = VERTEX - CUSTOM2.xyz;
	l_nrm = NORMAL;
	v_size = CUSTOM0;
	v_trim = CUSTOM1;
	v_wall = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(l_nrm);
	vec3 size = v_size.xyz;
	float storefront = v_size.w;
	float seed = v_trim.a;
	vec3 trim = v_trim.rgb;
	vec3 hs = size * 0.5;
	float v = l_pos.y + hs.y;
	float top = size.y;

	vec3 alb;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emis = vec3(0.0);

	if (n.y > 0.5) {
		// Roof: tar / gravel
#ifdef LITE
		alb = vec3(0.24, 0.23, 0.22);
#else
		float g = vnoise(l_pos.xz * 3.0);
		alb = vec3(0.24, 0.23, 0.22) * (0.8 + 0.4 * g);
#endif
		rough = 0.95;
	} else if (n.y < -0.5) {
		alb = vec3(0.1);
	} else {
		bool x_face = abs(n.x) > 0.5;
		float width = x_face ? size.z : size.x;
		float u = (x_face ? l_pos.z : l_pos.x) + width * 0.5;

		float is_win = 0.0;
		float frame = 0.0;
		vec2 cell = vec2(0.0);

		if (v > ground_floor_height && v < top - 0.9) {
			float count = max(floor(width / window_spacing), 1.0);
			float margin = (width - count * window_spacing) * 0.5;
			float fu_raw = (u - margin) / window_spacing;
			float fu = fract(fu_raw);
			float fv_raw = (v - ground_floor_height) / floor_height;
			float row = floor(fv_raw);
			float fv = fract(fv_raw);
			cell = vec2(floor(fu_raw), row + 1.0);
			bool in_cols = fu_raw >= 0.0 && fu_raw < count;
			bool fits = ground_floor_height + (row + 0.84) * floor_height < top - 0.9;
			if (in_cols && fits) {
				float wx = step(0.25, fu) * step(fu, 0.75);
				float wy = step(0.22, fv) * step(fv, 0.8);
				float fx = step(0.2, fu) * step(fu, 0.8);
				float fy = step(0.15, fv) * step(fv, 0.85);
				is_win = wx * wy;
				frame = fx * fy - is_win;
#ifndef LITE
				// centre mullion + transom
				if (is_win > 0.5 && (abs(fu - 0.5) < 0.012 || abs(fv - 0.62) < 0.012)) {
					is_win = 0.0;
					frame = 1.0;
				}
#endif
			}
		} else if (v <= ground_floor_height && storefront > 0.5) {
			float sx = step(0.7, u) * step(u, width - 0.7);
			float fr = fract(u / 1.8);
			float mullion = step(fr, 0.025) + step(0.975, fr);
			float glass = sx * step(0.6, v) * step(v, 2.95);
			is_win = glass * (1.0 - clamp(mullion, 0.0, 1.0));
			frame = sx * step(0.45, v) * step(v, 3.05) - is_win;
			cell = vec2(floor(u / 1.8), 0.0);
		}

		// Wall: plaster / brick variation, subtle courses, floor bands and cornice
#ifdef LITE
		vec3 base = v_wall * 0.95;
#else
		float nz = vnoise(vec2(u, v) * 1.1 + seed * 10.0) * 0.6 + vnoise(vec2(u, v) * 7.0) * 0.4;
		vec3 base = v_wall * (0.82 + 0.3 * nz);
		base *= 1.0 - step(0.9, fract(v * 12.5)) * 0.07;
#endif
		float cornice = step(top - 0.7, v);
		float band = step(ground_floor_height - 0.3, v) * step(v, ground_floor_height);
		float sign_band = storefront * step(3.1, v) * step(v, ground_floor_height - 0.3);
		base = mix(base, trim, max(cornice, band));
		base = mix(base, trim * 0.35, sign_band * 0.85);
		// contact shadow at street level
		base *= mix(0.55, 1.0, smoothstep(0.0, 1.4, v));
		alb = base;

		if (frame > 0.5) {
			alb = trim * 0.85;
			rough = 0.55;
		}
		if (is_win > 0.5) {
			float h1 = hash(cell + seed * 7.13);
			float h2 = hash(cell.yx + seed * 3.1 + 11.0);
#ifndef LITE
			vec3 t1 = x_face ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
			vec3 tn = normalize(n + t1 * (h1 - 0.5) * 0.14 + vec3(0.0, 1.0, 0.0) * (h2 - 0.5) * 0.08);
			NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(tn, 0.0))).xyz);
#endif
			alb = glass_tint * (0.55 + 0.45 * h2);
			metal = 0.55;
			rough = 0.06;
			vec3 sv = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
			vec3 rv = reflect(-VIEW, NORMAL);
			float d = max(dot(rv, sv), 0.0);
#ifdef LITE
			// far away: just a broad warm sheen, no sharp per-pane flashes
			float g = pow(d, 18.0) * 0.35;
#else
			// sharp glint (blooms) + broad warm sheen on panes angled toward the sun
			float g = pow(d, glint_sharpness) * glint_strength + pow(d, 18.0) * 0.35;
#endif
			emis += sun_color.rgb * sun_color.a * g;
			if (h1 < lit_ratio) {
				emis += interior_color * interior_energy * (0.55 + 0.45 * h2);
				alb *= 0.5;
			}
		}
	}

	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emis;
}
