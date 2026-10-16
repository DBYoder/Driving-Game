// Two-lane rural highway: asphalt, gravel shoulders, double yellow center, white edge lines.
// UV.x is meters from the centerline (negative = left), UV.y is the station.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 gravel : source_color = vec3(0.56, 0.51, 0.42);
uniform vec3 verge : source_color = vec3(0.40, 0.48, 0.24);
uniform vec3 yellow : source_color = vec3(0.95, 0.74, 0.10);
uniform vec3 white : source_color = vec3(0.92, 0.92, 0.92);
uniform float lane_width = 3.66;
uniform float paved_half_width = 4.26;
uniform float gravel_half_width = 6.5;

varying float lateral;

// 1 inside a stripe of half-width `hw` around `center`, antialiased by screen-space width.
float stripe(float x, float center, float hw) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(x - center));
}

void vertex() {
	lateral = UV.x;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VIEW) < 0.0 ? -n : n;

	float a = abs(lateral);
	vec3 col = a <= paved_half_width ? asphalt : (a <= gravel_half_width ? gravel : verge);
	float center_lines = max(stripe(lateral, -0.17, 0.06), stripe(lateral, 0.17, 0.06));
	float edge_line = stripe(a, lane_width + 0.08, 0.075);
	col = mix(col, yellow, center_lines);
	col = mix(col, white, edge_line);
	ALBEDO = col;
}
