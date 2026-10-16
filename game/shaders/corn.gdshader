// A clump of corn on two crossed quads (leafy stalks with a jagged top and tassels) and
// a leafy top quad (vertex color white), swaying a little. It sinks into the ground
// between fade_near and fade_far from the car, where the corn canopy has taken over,
// and ducks out of the way right next to the camera so the camera never ends up inside
// a clump. UV.y is 0 at the top of a stalk quad, 1 at the ground.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 leaf : source_color = vec3(0.20, 0.40, 0.12);
uniform vec3 tassel : source_color = vec3(0.62, 0.58, 0.36);
uniform vec3 clear_center;  // the car
uniform float fade_far = 98.0;
uniform float fade_near = 90.0;
uniform float camera_clear = 3.0;  // meters around the camera kept clear of corn

varying float height01;
varying float seed;
varying float is_top;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 base = MODEL_MATRIX[3].xyz;  // the clump's foot, so the whole clump scales together
	seed = fract(sin(dot(base.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float grow = smoothstep(fade_far, fade_near, distance(base.xz, clear_center.xz))
		* smoothstep(camera_clear * 0.5, camera_clear, distance(base, CAMERA_POSITION_WORLD));
	VERTEX.y *= grow;
	is_top = COLOR.r;
	float sway = sin(TIME * 1.4 + world.x * 0.2 + world.z * 0.15) * 0.10;
	VERTEX.xz += vec2(sway) * (is_top > 0.5 ? 1.0 : 1.0 - UV.y) * grow;
	height01 = is_top > 0.5 ? 0.82 : 1.0 - UV.y;
}

void fragment() {
	if (is_top > 0.5) {
		// Leaves seen from above: a ragged round patch with a few tassels.
		vec2 g = floor(UV * 6.0);
		float h = fract(sin(dot(g + seed * 7.0, vec2(12.9898, 78.233))) * 43758.5453);
		if (h < 0.3 || length(UV - 0.5) > 0.5) {
			discard;
		}
		ALBEDO = (h > 0.88 ? tassel : leaf * (0.8 + 0.35 * h)) * 0.95;
	} else {
		// Stalks across the quad, each with a ragged leafy outline that thins out at the top.
		float x = UV.x * 9.0 + seed * 3.0;
		float stalk = abs(fract(x) - 0.5);
		float leafy = 0.18 + 0.22 * sin(height01 * 23.0 + floor(x) * 2.7) * (1.0 - height01 * 0.6);
		float top = 0.9 + 0.08 * sin(floor(x) * 4.1 + seed * 6.0);
		if (stalk > leafy + 0.12 || height01 > top) {
			discard;
		}
		vec3 col = height01 > top - 0.035 ? tassel : leaf * (0.95 + 0.15 * sin(floor(x) * 1.9));
		ALBEDO = col * mix(0.5, 1.05, height01);
	}
}
