// Side roads and town streets (scripts/world/streets.gd): asphalt or gravel, with grass
// skirts past the edges. Two-lane highways get a dashed yellow center line, four-lane
// roads a double yellow and white lane lines. Gravel roads have two paler wheel tracks and a looser middle.
// UV.x = meters from the middle, UV.y = meters along, UV2 = (kind, half width).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 gravel : source_color = vec3(0.56, 0.51, 0.42);
uniform vec3 verge : source_color = vec3(0.40, 0.48, 0.24);
uniform vec3 yellow : source_color = vec3(0.95, 0.74, 0.10);
uniform vec3 white : source_color = vec3(0.92, 0.92, 0.92);

varying float lateral;
varying float along;
varying vec2 info;
varying vec3 world_pos;

float stripe(float x, float center, float hw) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(x - center));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lateral = UV.x;
	along = UV.y;
	info = UV2;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = abs(lateral);
	float hw = info.y;
	bool on_road = a <= hw + 0.01;
	// Streets overlap where they cross: an up normal on the road itself shades every
	// overlapping piece the same, so the overlap can't flicker. The skirts are faceted.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	n = dot(n, VIEW) < 0.0 ? -n : n;
	NORMAL = on_road ? normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) : n;

	// Speckle in world space, the same on overlapping pieces.
	float grain = hash(floor(world_pos.xz * 3.0)) - 0.5;
	vec3 col;
	if (info.x < 0.5) {
		col = asphalt * (1.06 + 0.10 * grain);
		// Edge wear: a little lighter at the very edge.
		col = mix(col, gravel * 0.8, smoothstep(hw - 0.25, hw, a) * 0.5);
		if (hw >= 3.8) {
			float dash = step(fract(along / 12.19), 0.25);
			float center = hw >= 5.0
				? max(stripe(lateral, 0.17, 0.06), stripe(lateral, -0.17, 0.06))
				: stripe(lateral, 0.0, 0.06) * dash;
			col = mix(col, yellow, center);
			if (hw >= 5.0) {
				col = mix(col, white, max(stripe(a, hw * 0.5, 0.06) * dash, stripe(a, hw - 0.3, 0.07)));
			}
		}
	} else {
		// Two wheel tracks packed paler, loose stone in the middle and at the edges.
		float tracks = info.x < 1.5 ? stripe(a, 1.0, 0.45) : stripe(a, 0.75, 0.3);
		col = gravel * (0.96 + 0.16 * grain) * mix(0.93, 1.07, tracks);
	}
	col = on_road ? col : verge * (0.95 + 0.06 * grain);
	ALBEDO = col;
}
