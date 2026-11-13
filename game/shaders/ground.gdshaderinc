// What the ground's made of, close up and from afar: grass in patches, rows in the crops,
// grain in the asphalt, stones in the gravel. For the terrain, the roads, the streets and
// the 4-way (Main sets ground_detail from the graphics preset).
//
// All of it in world space (the same pattern on overlapping pieces, and seamless from
// one mesh to the next), and every pattern finer than a few pixels fades to its average
// before it can shimmer: g_fade(size) is 1 while a `size` m pattern is drawn by plenty of
// pixels, 0 once it'd be down to a couple. `px` is how big a pixel is on the ground there,
// m: g_pixel(world position), once per fragment.

global uniform float ground_detail;  // 0: only the broad patches (Low), 1: all of it
// At night, the lamps and headlights nearest the camera (NightLamps): a column each, rows
// (position, reach), (light, 0 for a lamp / 1 for headlights), (headlights' direction,
// spread, length).
global uniform sampler2D night_lamps : filter_nearest;
global uniform int night_lamp_count;

// An integer hash of a lattice cell to [0, 1): no sin(), so no patterns far from the
// origin (the routes run 15 km from it).
float g_hash(vec2 cell) {
	uvec2 c = uvec2(ivec2(floor(cell)) + ivec2(1 << 20));
	uint h = (c.x * 0x27d4eb2du) ^ (c.y * 0x165667b1u);
	h ^= h >> 15u;
	h *= 0x2c1b3c6du;
	h ^= h >> 12u;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

// Smooth value noise, [0, 1).
float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash(i), g_hash(i + vec2(1.0, 0.0)), f.x),
		mix(g_hash(i + vec2(0.0, 1.0)), g_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float g_pixel(vec3 world) {
	return max(length(fwidth(world.xz)), 0.001);
}

float g_fade(float size, float px) {
	return 1.0 - smoothstep(size * 0.18, size * 0.45, px);
}

// A pattern's share of the picture: its fade, and none of the fine ones on Low.
float g_fine(float size, float px) {
	return g_fade(size, px) * ground_detail;
}

// Rows `spacing` m apart, as a ridge across `x` (1 on a row, 0 between), sharper with
// `sharp` (1, 2 or 3), fading to their average once they're too fine to draw.
float g_rows(float x, float spacing, int sharp, float px) {
	float r = 0.5 + 0.5 * cos(x / spacing * 6.2831853);
	float mean = 0.5;
	if (sharp == 2) {
		r *= r;
		mean = 0.375;
	} else if (sharp >= 3) {
		r *= r * r;
		mean = 0.3125;
	}
	return mix(mean, r, g_fine(spacing, px));
}

// Grass in patches: greener and drier, lighter and darker, broad (seen from far off) to
// fine (up close). Snow, being white, only gets lighter and darker.
vec3 g_grass(vec3 base, vec2 p, float px) {
	float broad = g_noise(p / 31.0);
	float mid = g_noise(p / 6.7 + 11.3);
	float fine = g_noise(p / 1.1 + 4.7);
	float shade = (broad - 0.5) * 0.18 + (mid - 0.5) * 0.14 * g_fine(6.7, px) + (fine - 0.5) * 0.14 * g_fine(1.1, px);
	float sat = (max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b))) / max(max(base.r, max(base.g, base.b)), 0.01);
	vec3 dry = base * vec3(1.14, 1.04, 0.78);
	vec3 c = mix(base, dry, smoothstep(0.5, 0.85, g_noise(p / 17.0 + 3.1)) * 0.7 * sat);
	return c * (1.0 + shade);
}

// Asphalt: a fine grain up close, and broad patches where it's newer or older.
vec3 g_asphalt(vec3 base, vec2 p, float px) {
	float broad = g_noise(p / 9.0 + 2.3);
	float grain = g_hash(floor(p * 9.0)) + g_hash(floor(p * 9.0) + 17.0) - 1.0;
	return base * (1.0 + (broad - 0.5) * 0.14 + grain * 0.10 * g_fine(0.11, px));
}

// Gravel: round stones of their own tones with darker gaps between, a looser and a
// packed-down mottle.
vec3 g_gravel(vec3 base, vec2 p, float px) {
	vec2 q = p * 11.0;
	vec2 cell = floor(q);
	vec2 off = vec2(g_hash(cell + 5.0), g_hash(cell + 9.0)) - 0.5;
	float body = 1.0 - smoothstep(0.30, 0.5, length(fract(q) - 0.5 + off * 0.25));
	float stones = mix(0.84, 0.92 + 0.22 * g_hash(cell), body) / 0.94;  // (0.94: their average)
	float mottle = g_noise(p / 1.7 + 5.5);
	return base * mix(1.0, stones, g_fine(0.1, px)) * (1.0 + (mottle - 0.5) * 0.16 * g_fine(1.7, px) + (g_noise(p / 11.0) - 0.5) * 0.08);
}


// The light (linear) the lamps nearest the camera and the traffic's headlights throw on
// the ground at `world`: a pool under each lamp, as bright as it's high (it falls off with
// the cube of the slant distance, like a real one), and a beam down the road ahead of each
// pair of headlights.
vec3 g_lamps(vec3 world) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < night_lamp_count; i++) {
		vec4 at = texelFetch(night_lamps, ivec2(i, 0), 0);
		vec4 light = texelFetch(night_lamps, ivec2(i, 1), 0);
		vec3 v = world - at.xyz;
		float across = length(v.xz);
		if (across > at.w) {
			continue;
		}
		float f;
		if (light.a < 0.5) {
			float h = max(-v.y, 1.0);
			f = pow(h / max(length(v), h), 3.0);
		} else {
			vec4 beam = texelFetch(night_lamps, ivec2(i, 2), 0);
			float along = dot(v.xz, beam.xy);
			float side = abs(v.x * beam.y - v.z * beam.x);
			float width = along * beam.z + 0.8;
			f = smoothstep(1.5, 7.0, along) * (1.0 - smoothstep(width * 0.5, width, side))
				* 40.0 / (40.0 + along * along * 0.35);
		}
		sum += light.rgb * f * (1.0 - smoothstep(at.w * 0.6, at.w, across));
	}
	return sum;
}

// EMISSION for a lit ground shader: the sky's faint reflection (shaders/sun.gdshaderinc,
// `sheen` of it) and the lamps' light at night on the surface `albedo` (as fragment()
// has it, in sRGB).
vec3 g_emission(vec3 albedo, vec3 world, float sheen) {
	vec3 lamps = night_lamp_count > 0 ? sun_decode(albedo) * g_lamps(world) : vec3(0.0);
	return sun_encode(sky_sheen * sheen + lamps);
}
