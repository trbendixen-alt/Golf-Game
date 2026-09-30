shader_type spatial;
// World-space ground materials. One shader, `kind` picks the surface:
// 0 asphalt road, 1 concrete sidewalk, 2 park grass, 3 putting green, 4 farmland.

uniform int kind = 0;
uniform float town_end_z = -112.0;
uniform float main_half = 5.0;
uniform float country_half = 3.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = fbm(p * 0.35);
	float fine = vnoise(p * 9.0);
	vec3 col;
	float rough = 0.85;

	if (kind == 0) {
		col = vec3(0.12, 0.12, 0.13) * (0.75 + 0.35 * n + 0.2 * fine);
		float patch = smoothstep(0.66, 0.7, vnoise(p * 0.07 + 3.0));
		col = mix(col, vec3(0.075, 0.075, 0.085), patch * 0.7);
		// tar-sealed cracks
		float crack = smoothstep(0.02, 0.0, abs(vnoise(p * 0.5) - 0.5)) * step(0.55, vnoise(p * 0.11));
		col = mix(col, vec3(0.05), crack * 0.6);
		rough = 0.72 - 0.12 * n + patch * 0.1;

		bool town = p.y > town_end_z;
		float half_w = town ? main_half : country_half;
		float ax = abs(p.x);
		float wear = 0.75 + 0.25 * vnoise(p * 3.0);
		float yl = step(0.08, ax) * step(ax, 0.19);
		if (!town) {
			yl = step(ax, 0.07) * step(0.45, fract(p.y / 9.0));
		}
		col = mix(col, vec3(0.85, 0.62, 0.08) * wear, yl);
		float wl = step(half_w - 0.42, ax) * step(ax, half_w - 0.3);
		// parking stall ticks along the curb in town
		float tick = town ? step(half_w - 2.2, ax) * step(ax, half_w - 0.3) * step(fract(p.y / 6.5), 0.02) : 0.0;
		// crosswalks
		float cw = 0.0;
		if ((p.y < -17.0 && p.y > -21.0) || (p.y < -104.0 && p.y > -108.0)) {
			cw = step(0.5, fract(p.x / 1.1)) * step(ax, half_w - 0.3);
		}
		col = mix(col, vec3(0.82) * wear, max(max(wl, tick), cw) * 0.9);
	} else if (kind == 1) {
		col = vec3(0.60, 0.58, 0.54) * (0.82 + 0.25 * n + 0.1 * fine);
		float jz = smoothstep(0.015, 0.0, abs(fract(p.y / 1.6) - 0.5) - 0.485);
		float jx = smoothstep(0.015, 0.0, abs(fract((abs(p.x) - 5.0) / 1.75) - 0.5) - 0.485);
		col *= 1.0 - max(jz, jx) * 0.35;
		float stain = smoothstep(0.6, 0.75, vnoise(p * 0.6 + 7.0));
		col *= 1.0 - stain * 0.15;
		// curb edge
		float curb = step(abs(p.x), 5.18);
		col = mix(col, vec3(0.72, 0.70, 0.66), curb);
		rough = 0.88;
	} else if (kind == 2) {
		col = mix(vec3(0.13, 0.26, 0.06), vec3(0.28, 0.42, 0.10), n);
		col *= 0.85 + 0.3 * fine;
		rough = 0.92;
	} else if (kind == 3) {
		col = mix(vec3(0.16, 0.40, 0.10), vec3(0.22, 0.50, 0.13), n);
		col *= 1.0 + 0.12 * step(0.5, fract(p.y / 2.2));
		col *= 0.92 + 0.12 * fine;
		rough = 0.85;
	} else {
		vec2 cell = floor(p / vec2(70.0, 48.0));
		float t = hash(cell);
		vec3 crop;
		if (t < 0.3) {
			crop = vec3(0.70, 0.55, 0.22);   // wheat
		} else if (t < 0.55) {
			crop = vec3(0.26, 0.40, 0.12);   // green crop
		} else if (t < 0.75) {
			crop = vec3(0.33, 0.24, 0.15);   // ploughed
		} else {
			crop = vec3(0.40, 0.46, 0.18);   // pasture
		}
		float rows = 0.85 + 0.15 * sin(p.x * (2.0 + t * 3.0));
		col = crop * rows * (0.8 + 0.35 * n);
		// the edge of town is mown grass
		float near = smoothstep(90.0, 60.0, abs(p.x)) * smoothstep(-200.0, -165.0, p.y);
		col = mix(col, vec3(0.18, 0.30, 0.08) * (0.85 + 0.3 * n), near);
		rough = 0.95;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	// grass and crops scatter light instead of shining at grazing sun angles
	SPECULAR = kind >= 2 ? 0.15 : 0.5;
}
