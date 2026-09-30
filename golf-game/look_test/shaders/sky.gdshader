shader_type sky;
// Stylized sky: layered gradient, warm horizon glow toward the sun, soft sun halo,
// HDR sun disk (feeds bloom + window reflections) and static painted-looking clouds.
// No TIME use, so the radiance map only re-renders when the time of day changes.

uniform vec3 zenith_color : source_color = vec3(0.20, 0.30, 0.58);
uniform vec3 mid_color : source_color = vec3(0.62, 0.58, 0.72);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.55, 0.28);
uniform vec3 ground_color : source_color = vec3(0.30, 0.22, 0.20);
uniform vec3 cloud_color : source_color = vec3(1.0, 0.72, 0.55);
uniform vec3 cloud_shadow : source_color = vec3(0.45, 0.35, 0.45);
uniform float cloud_coverage = 0.45;
uniform float sun_disk_energy = 14.0;
uniform float sun_halo = 1.0;
uniform float sky_energy = 1.0;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 0.2, -1.0);
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0, 0.7, 0.4);
	float h = max(d.y, 0.0);
	float toward = max(dot(d, sun), 0.0);

	// Base gradient
	vec3 col = mix(horizon_color, mid_color, smoothstep(0.0, 0.22, pow(h, 0.8)));
	col = mix(col, zenith_color, smoothstep(0.12, 0.85, h));

	// Horizon band is hottest on the sun's side of the sky
	float band = exp(-h * 9.0);
	col += horizon_color * band * pow(toward, 2.5) * 0.9;

	// Sun halo layers (these push into HDR so the glow pass blooms them)
	col += sun_col * pow(toward, 12.0) * 0.55 * sun_halo;
	col += sun_col * pow(toward, 90.0) * 1.2 * sun_halo;
	col += sun_col * pow(toward, 900.0) * 3.0 * sun_halo;

	// Clouds projected on a high plane
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.6;
		float c = fbm(uv * 1.3 + vec2(3.0, 1.0));
		float wisp = fbm(uv * vec2(0.6, 3.5) + 11.0);
		float amount = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.3, c * 0.7 + wisp * 0.45);
		amount *= smoothstep(0.02, 0.18, d.y);
		// clouds near the sun are rim-lit gold, away from it they go lilac/grey
		vec3 lit = mix(cloud_shadow, cloud_color, 0.35 + 0.65 * pow(toward, 3.0));
		lit += sun_col * pow(toward, 20.0) * 1.5 * (1.0 - amount);
		col = mix(col, lit, amount * 0.85);
	}

	// Sun disk
	float disk = smoothstep(0.99955, 0.99975, dot(d, sun));
	col += sun_col * disk * sun_disk_energy;

	// Below the horizon: fade into a hazy ground colour
	if (d.y < 0.0) {
		col = mix(horizon_color * 0.8, ground_color, smoothstep(0.0, -0.25, d.y));
	}

	COLOR = col * sky_energy;
}
