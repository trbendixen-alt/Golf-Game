shader_type spatial;
// Ground for the small-town holes. `kind` picks what the zone is:
//   0 street (asphalt, lane markings, crosswalks)   4 farmland (outside the playing area)
//   1 sidewalk (concrete slabs)                      5 fairway (mown stripes)
//   2 rough (long grass)                             6 tee box (mown, light)
//   3 putting green (fine, bright)
// Everything is procedural and drawn from the ground position, so zones need no UVs.
//
// BAKED LIGHTING: the sun's shadows from the buildings, cars, lamps and trees never
// change, so they were worked out once (tools/build_hole_scenery.gd) and saved in
// `sun_mask`: red = how much direct sun reaches this spot (0 = shadow, 1 = sunlit),
// green = how open to the sky it is (ambient occlusion). The real-time shadow pass is
// switched off for these holes, which is most of what the lighting would cost.
// Adapted from Julian's look_test/shaders/ground.gdshader.

uniform int kind = 0;
uniform float street_half = 5.0;
uniform float street_end_z = -82.0;
uniform vec2 crosswalk_z = vec2(-31.0, -78.0);

uniform sampler2D sun_mask : filter_linear, repeat_disable, hint_default_white;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x0, z0, width, length (metres)
uniform float mask_strength = 1.0;                   // 0 = ignore the baked mask

varying vec3 wpos;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// Baked mask lookup. Outside the baked area there is nothing to shade: fully sunlit.
vec2 baked(vec2 xz) {
	vec2 uv = (xz - mask_rect.xy) / mask_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec2(1.0);
	}
	return mix(vec2(1.0), texture(sun_mask, uv).rg, mask_strength);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * 0.35);
	float fine = vnoise(p * 9.0);
	vec3 col;
	float rough = 0.85;
	float spec = 0.04;  // grass and concrete barely shine; only asphalt does (below)

	if (kind == 0) {
		// Asphalt
		col = vec3(0.12, 0.12, 0.13) * (0.75 + 0.35 * n + 0.2 * fine);
		float patch = smoothstep(0.66, 0.7, vnoise(p * 0.07 + 3.0));
		col = mix(col, vec3(0.075, 0.075, 0.085), patch * 0.7);
		float crack = smoothstep(0.02, 0.0, abs(vnoise(p * 0.5) - 0.5)) * step(0.55, vnoise(p * 0.11));
		col = mix(col, vec3(0.05), crack * 0.6);
		rough = 0.72 - 0.12 * n + patch * 0.1;
		spec = 0.5;
		bool town = p.y > street_end_z;
		float ax = abs(p.x);
		float wear = 0.75 + 0.25 * vnoise(p * 3.0);
		// double yellow centre line
		float yl = step(0.08, ax) * step(ax, 0.19);
		col = mix(col, vec3(0.85, 0.62, 0.08) * wear, town ? yl : 0.0);
		// white kerb-side line, and parking stall ticks
		float wl = step(street_half - 0.42, ax) * step(ax, street_half - 0.3);
		float tick = step(street_half - 2.2, ax) * step(ax, street_half - 0.3) * step(fract(p.y / 6.5), 0.02);
		// crosswalks
		float cw = 0.0;
		if ((p.y < crosswalk_z.x + 2.0 && p.y > crosswalk_z.x - 2.0) || (p.y < crosswalk_z.y + 2.0 && p.y > crosswalk_z.y - 2.0)) {
			cw = step(0.5, fract(p.x / 1.1)) * step(ax, street_half - 0.3);
		}
		col = mix(col, vec3(0.82) * wear, max(max(wl, tick), cw) * (town ? 0.9 : 0.0));
	} else if (kind == 1) {
		// Concrete sidewalk slabs
		col = vec3(0.60, 0.58, 0.54) * (0.82 + 0.25 * n + 0.1 * fine);
		float jz = smoothstep(0.015, 0.0, abs(fract(p.y / 1.6) - 0.5) - 0.485);
		float jx = smoothstep(0.015, 0.0, abs(fract((abs(p.x) - 5.0) / 1.75) - 0.5) - 0.485);
		col *= 1.0 - max(jz, jx) * 0.35;
		float stain = smoothstep(0.6, 0.75, vnoise(p * 0.6 + 7.0));
		col *= 1.0 - stain * 0.15;
		rough = 0.88;
	} else if (kind == 2) {
		// Rough: long, dark, patchy grass
		col = mix(vec3(0.09, 0.26, 0.05), vec3(0.17, 0.40, 0.08), n);
		col *= 0.78 + 0.45 * fine;
		col *= 0.9 + 0.2 * vnoise(p * vec2(22.0, 3.0));  // streaky blades
		rough = 0.95;
	} else if (kind == 3) {
		// Green: bright, smooth, very fine mowing
		col = mix(vec3(0.20, 0.62, 0.12), vec3(0.28, 0.74, 0.16), n);
		col *= 1.0 + 0.10 * step(0.5, fract(p.y / 1.2));
		col *= 0.96 + 0.08 * fine;
		rough = 0.8;
	} else if (kind == 5) {
		// Fairway: bright mown grass with wide stripes across the line of play
		col = mix(vec3(0.20, 0.55, 0.10), vec3(0.27, 0.66, 0.13), n);
		col *= 1.0 + 0.16 * step(0.5, fract(p.y / 5.0)) - 0.06;
		col *= 0.94 + 0.12 * fine;
		rough = 0.85;
	} else if (kind == 6) {
		// Tee box: mown, a touch lighter than the fairway
		col = mix(vec3(0.26, 0.64, 0.13), vec3(0.32, 0.72, 0.17), n);
		col *= 1.0 + 0.10 * step(0.5, fract(p.x / 1.0));
		rough = 0.85;
	} else {
		// Farmland beyond the playing area
		vec2 cell = floor(p / vec2(70.0, 48.0));
		float t = hash(cell);
		vec3 crop;
		if (t < 0.3) {
			crop = vec3(0.70, 0.55, 0.22);
		} else if (t < 0.55) {
			crop = vec3(0.26, 0.40, 0.12);
		} else if (t < 0.75) {
			crop = vec3(0.33, 0.24, 0.15);
		} else {
			crop = vec3(0.40, 0.46, 0.18);
		}
		float rows = 0.85 + 0.15 * sin(p.x * (2.0 + t * 3.0));
		col = crop * rows * (0.8 + 0.35 * n);
		rough = 0.95;
	}

	vec2 b = baked(p);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = b.g;              // baked ambient occlusion: darkens the sky light only
	AO_LIGHT_AFFECT = 0.0;
}

// Direct sun, scaled by the baked shadow mask (this replaces the real-time shadow).
void light() {
	float vis = baked(wpos.xz).r;
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ndl * vis / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float shin = mix(300.0, 8.0, ROUGHNESS);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * vis * pow(max(dot(NORMAL, h), 0.0), shin) * ndl * SPECULAR_AMOUNT * (1.0 - ROUGHNESS * 0.6) * (shin + 2.0) / (8.0 * PI);
}
