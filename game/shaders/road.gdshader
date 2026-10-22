// Two-lane rural highway: asphalt, gravel shoulders, white edge lines, and a yellow
// center line that's solid where you can't pass and dashed where you can.
// UV.x is meters from the centerline (negative = left), UV.y is the station, and
// UV2 is 1 where the line is solid for (northbound, southbound) traffic.
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
// Black ice (winter): 1 along the stations where it is, a texel per ICE_STEP meters.
uniform sampler2D ice_mask : filter_linear, repeat_disable;
uniform float ice_length = 1.0;  // meters the mask covers; 0 = no ice

varying float lateral;
varying float station;
varying vec2 solid;

// 1 inside a stripe of half-width `hw` around `center`, antialiased by screen-space width.
float stripe(float x, float center, float hw) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(x - center));
}

void vertex() {
	lateral = UV.x;
	station = UV.y;
	solid = UV2;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VIEW) < 0.0 ? -n : n;

	float a = abs(lateral);
	vec3 col = a <= paved_half_width ? asphalt : (a <= gravel_half_width ? gravel : verge);
	// US marking: 10 ft dashes every 40 ft. Each driver obeys the line nearer their lane
	// (northbound drive on the +x side); if both may pass, it's one dashed line.
	float dash = step(fract(station / 12.19), 0.25);
	float north_line = stripe(lateral, 0.17, 0.06) * max(solid.x, dash);
	float south_line = stripe(lateral, -0.17, 0.06) * max(solid.y, dash);
	float both_may_pass = (1.0 - solid.x) * (1.0 - solid.y);
	float center_lines = mix(max(north_line, south_line), stripe(lateral, 0.0, 0.06) * dash, both_may_pass);
	float edge_line = stripe(a, lane_width + 0.08, 0.075);
	col = mix(col, yellow, center_lines);
	col = mix(col, white, edge_line);
	// Ice: a dark, glassy glaze over the pavement, easy to see if you're looking.
	float ice = ice_length > 0.0 ? texture(ice_mask, vec2(station / ice_length, 0.5)).r : 0.0;
	ice *= 1.0 - smoothstep(paved_half_width - 0.3, paved_half_width + 0.3, a);
	col = mix(col, vec3(0.10, 0.12, 0.15), ice * 0.65);
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.12, ice);
	SPECULAR = mix(0.5, 0.9, ice);
}
