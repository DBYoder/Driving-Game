// A clump of corn on two crossed quads: leafy stalks with a jagged top and tassels,
// swaying a little, growing up out of the ground at the edge of the drawn area so
// there's no pop-in. UV.y is 0 at the top, 1 at the ground.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 leaf : source_color = vec3(0.20, 0.40, 0.12);
uniform vec3 tassel : source_color = vec3(0.62, 0.58, 0.36);
uniform float fade_far = 200.0;
uniform float fade_near = 160.0;

varying float height01;
varying float seed;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = fract(sin(dot(world.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float grow = smoothstep(fade_far, fade_near, distance(world.xz, CAMERA_POSITION_WORLD.xz));
	VERTEX.y *= grow;
	float sway = sin(TIME * 1.4 + world.x * 0.2 + world.z * 0.15) * 0.10;
	VERTEX.xz += vec2(sway) * (1.0 - UV.y) * grow;
	height01 = 1.0 - UV.y;
}

void fragment() {
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
