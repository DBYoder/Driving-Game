// The Kalona 4-way's pavement (scripts/world/junction.gd): concrete with its joints, and the
// gravel shoulders and grass slopes round it.
// COLOR.g says which (0 concrete, 0.5 gravel, 1 grass); COLOR.r which highway's joints show
// (0 IA 1's, 1/3 IA 22's, 2/3 both, 1 none); UV is (m east of IA 1's middle, m north along
// it), UV2 (m north of IA 22's middle, m east along it).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/sun.gdshaderinc"
#include "res://shaders/ground.gdshaderinc"

uniform vec3 concrete : source_color = vec3(0.58, 0.58, 0.55);
uniform vec3 gravel : source_color = vec3(0.56, 0.51, 0.42);
uniform vec3 verge : source_color = vec3(0.40, 0.48, 0.24);

varying vec2 ia1;
varying vec2 ia22;
varying vec2 info;
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 on a sawed joint every `period` m (offset by `offset`), antialiased.
float joint(float x, float period, float offset) {
	float d = abs(fract((x - offset) / period + 0.5) - 0.5) * period;
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(0.02 - aa, 0.02 + aa, d);
}

void vertex() {
	ia1 = UV;
	ia22 = UV2;
	info = COLOR.rg;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	sun_dist = length(VERTEX);
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VIEW) < 0.0 ? -n : n;
	float px = g_pixel(world_pos);
	vec2 wp = world_pos.xz;
	vec3 col;
	if (info.y < 0.25) {
		// Each slab a shade of its own, a fine grain in it.
		float slab = g_hash(floor(vec2(ia1.x / 3.66, ia1.y / 4.6)) + 3.0);
		col = concrete * (0.96 + 0.08 * slab) * (1.0 + (g_hash(floor(wp * 9.0)) - 0.5) * 0.08 * g_fine(0.11, px))
			* (1.0 + (g_noise(wp / 3.0) - 0.5) * 0.06);
		// Joints along the lanes and across every 4.6 m, the way the slabs were poured.
		float axis = info.x * 3.0;
		float j1 = max(joint(ia1.x, 3.66, 1.83), joint(ia1.y, 4.6, 0.0));
		float j22 = max(joint(ia22.x, 3.66, 0.0), joint(ia22.y, 4.6, 0.0));
		float j = axis < 0.5 ? j1 : (axis < 1.5 ? j22 : (axis < 2.5 ? max(j1, j22) : 0.0));
		col = mix(col, col * 0.6, j * 0.7);
	} else if (info.y < 0.75) {
		col = g_gravel(gravel * 0.98, wp, px);
	} else {
		col = g_grass(verge * 0.97, wp, px);
	}
	ALBEDO = col;
	// (The sky's reflection, as the sun's fix needs to know it: shaders/sun.gdshaderinc.)
	SPECULAR = 0.0;
	EMISSION = g_emission(ALBEDO, world_pos, 1.0);
}
