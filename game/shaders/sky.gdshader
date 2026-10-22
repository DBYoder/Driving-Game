// The sky: a gradient from the horizon up, a sun (or moon) disk, flat-bottomed clouds
// drifting nowhere (still, so the sky's lighting never has to be redrawn) and, at night,
// stars. Each condition sets the colors and how much of the sky the clouds cover.
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sky_top_color : source_color = vec3(0.36, 0.55, 0.82);
uniform vec3 sky_horizon_color : source_color = vec3(0.78, 0.83, 0.86);
uniform vec3 ground_horizon_color : source_color = vec3(0.76, 0.81, 0.85);
uniform vec3 ground_bottom_color : source_color = vec3(0.76, 0.81, 0.85);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0);  // sunlit tops
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.76, 0.82);  // undersides
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float sun_size = 0.025;  // radians across

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col = up >= 0.0
		? mix(sky_horizon_color, sky_top_color, pow(clamp(up, 0.0, 1.0), 0.6))
		: mix(ground_horizon_color, ground_bottom_color, clamp(-up * 6.0, 0.0, 1.0));

	// The sun (or the moon at night): a disk and a soft glow around it.
	if (LIGHT0_ENABLED) {
		float a = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		vec3 light = LIGHT0_COLOR * min(LIGHT0_ENERGY, 1.2);
		col += light * (1.0 - smoothstep(sun_size * 0.45, sun_size * 0.5, a)) * 2.0;
		col += light * exp(-a * 9.0) * 0.18 * step(0.0, up);
	}

	if (up > 0.0 && !AT_CUBEMAP_PASS) {
		// Stars, a few thousand of them, twinkle-free.
		if (stars > 0.0) {
			vec2 cell = vec2(atan(d.x, d.z) * 180.0, acos(d.y) * 220.0);
			float h = hash(floor(cell));
			vec2 f = fract(cell) - 0.5;
			float star = step(0.9965, h) * (1.0 - smoothstep(0.05, 0.25, length(f)));
			col += vec3(0.9, 0.92, 1.0) * star * stars * (0.4 + 0.6 * hash(floor(cell) + 3.1)) * smoothstep(0.02, 0.2, up);
		}
		// Clouds on a flat layer overhead, thinning out toward the horizon.
		vec2 p = d.xz / (up + 0.12) * 1.6;
		float n = fbm(p);
		float cover = smoothstep(1.0 - cloud_cover - 0.08, 1.0 - cloud_cover + 0.22, n + 0.32 * cloud_cover);
		// Lit on the side toward the sun, darker underneath and in the thick middles.
		vec2 toward_sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) * 0.08 : vec2(0.0);
		float lit = clamp(0.55 + (n - fbm(p + toward_sun)) * 6.0, 0.0, 1.0);
		vec3 cloud = mix(cloud_shade, cloud_color, lit * (1.0 - 0.35 * cover));
		col = mix(col, cloud, cover * smoothstep(0.0, 0.18, up) * 0.97);
	}
	COLOR = col;
}
