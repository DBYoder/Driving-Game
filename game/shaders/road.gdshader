// Two-lane rural highway: asphalt, gravel shoulders, white edge lines, and a yellow
// center line that's solid where you can't pass and dashed where you can.
// UV.x is meters from the centerline (negative = left), UV.y is the station, and
// UV2 is 1 where the line is solid for (northbound, southbound) traffic, COLOR.r is
// 1 on a bridge's deck (concrete shoulders and edges), and COLOR.g is 1 on a town's main
// street (a parking lane and a concrete gutter where the gravel would be).
// Close up (shaders/ground.gdshaderinc) the asphalt has its grain, lighter worn wheel paths
// and a darker strip down the middle of each lane, tar-sealed cracks and the odd patch; the
// shoulders are loose stones, the grass in patches.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/sun.gdshaderinc"
#include "res://shaders/ground.gdshaderinc"

uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 gravel : source_color = vec3(0.56, 0.51, 0.42);
uniform vec3 verge : source_color = vec3(0.40, 0.48, 0.24);
uniform vec3 concrete : source_color = vec3(0.58, 0.58, 0.55);
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
varying float deck;
varying float town;
varying vec3 world_pos;

// 1 inside a stripe of half-width `hw` around `center`, antialiased by screen-space width.
float stripe(float x, float center, float hw) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(x - center));
}

void vertex() {
	lateral = UV.x;
	station = UV.y;
	solid = UV2;
	deck = COLOR.r;
	town = COLOR.g;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// Tar-sealed cracks across the lanes, now and then, wandering a little, and along the
// paving seam by the centerline for a stretch. `s` is the station, `x` m from the
// centerline: 1 on one.
float tar(float s, float x, float px) {
	float cell = floor(s / 13.0);
	float h = g_hash(vec2(cell, 7.0));
	float line = 0.0;
	if (h < 0.5) {
		float at = (cell + 0.2 + 0.6 * g_hash(vec2(cell, 9.0))) * 13.0
			+ sin(x * 1.3 + h * 40.0) * 0.35 + sin(x * 4.1 + h * 17.0) * 0.08;
		float from = -4.3 + 3.0 * g_hash(vec2(cell, 11.0));
		float to = 4.3 - 3.0 * g_hash(vec2(cell, 13.0));
		float aa = fwidth(s) + 0.01;
		line = (1.0 - smoothstep(0.035, 0.035 + aa, abs(s - at))) * step(from, x) * step(x, to);
	}
	float run = floor(s / 41.0);
	if (g_hash(vec2(run, 21.0)) < 0.45) {
		float seam = 0.42 * sign(g_hash(vec2(run, 23.0)) - 0.5) + sin(s * 0.35 + run) * 0.12 + sin(s * 1.7) * 0.03;
		line = max(line, 1.0 - smoothstep(0.03, 0.03 + fwidth(x) + 0.01, abs(x - seam)));
	}
	return line * g_fine(0.6, px);
}

// 1 on a patch of newer (darker) asphalt, every so often in one lane.
float patch(float s, float x) {
	float cell = floor(s / 47.0);
	if (g_hash(vec2(cell, 31.0)) > 0.2) {
		return 0.0;
	}
	float s0 = (cell + 0.1 + 0.5 * g_hash(vec2(cell, 33.0))) * 47.0;
	float len = 2.5 + 6.0 * g_hash(vec2(cell, 35.0));
	float xs = x * (g_hash(vec2(cell, 37.0)) < 0.5 ? -1.0 : 1.0);
	float x0 = 0.4 + 1.2 * g_hash(vec2(cell, 39.0));
	float x1 = x0 + 1.0 + 1.5 * g_hash(vec2(cell, 41.0));
	return step(s0, s) * step(s, s0 + len) * step(x0, xs) * step(xs, x1);
}

void fragment() {
	sun_dist = length(VERTEX);
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VIEW) < 0.0 ? -n : n;

	float a = abs(lateral);
	float px = g_pixel(world_pos);
	vec2 wp = world_pos.xz;
	vec3 col;
	if (a <= paved_half_width) {
		col = g_asphalt(asphalt, wp, px);
		float lane = a - lane_width * 0.5;  // m from the middle of the lane (either way)
		float in_lane = step(a, lane_width);
		float tracks = exp(-pow((abs(lane) - 0.86) / 0.34, 2.0)) * in_lane;
		float oil = exp(-pow(lane / 0.3, 2.0)) * in_lane;
		col *= 1.0 + 0.11 * tracks - 0.10 * oil * g_fade(0.6, px);
		col = mix(col, col * 0.84, patch(station, lateral));
		col = mix(col, asphalt * 0.62, tar(station, lateral, px) * 0.85);
	} else if (a <= gravel_half_width) {
		col = g_gravel(gravel, wp, px);
	} else {
		col = g_grass(verge, wp, px);
	}
	col = mix(col, concrete * (1.0 + (g_noise(wp / 2.3) - 0.5) * 0.08), step(0.5, deck) * step(paved_half_width, a));
	float curbed = step(0.5, town) * step(paved_half_width, a) * step(a, gravel_half_width);
	col = mix(col, asphalt, curbed * step(a, gravel_half_width - 0.6));
	col = mix(col, concrete * 1.15, curbed * step(gravel_half_width - 0.6, a));
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
	// (The sky's reflection, as the sun's fix needs to know it: shaders/sun.gdshaderinc. Ice
	// keeps the renderer's own: it's a mirror.)
	ROUGHNESS = mix(1.0, 0.12, ice);
	SPECULAR = 0.9 * ice;
	EMISSION = sun_sheen() * (1.0 - ice);
}
