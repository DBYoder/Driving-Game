// The sun's light on a surface, for every lit shader here: plain Lambert, and the fix for
// how the Compatibility renderer draws a sun that casts shadows.
//
// Without shadows a surface is drawn once: the sky's light and the sun's are added, then
// run through the tonemapper and into sRGB. With shadows the sun is drawn in a second
// pass and *that* pass's tonemapped, sRGB picture is added to the first's: the sum of two
// curves rather than the curve of the sum, which comes out brighter, and unevenly so
// (pale surfaces a lot, dark ones a little). The fog's worked into each pass too.
//
// So here the second pass is given exactly what it takes to land where one pass would
// have: what the surface should look like fully lit, less what the first pass has already
// put there, taken back through the sRGB curve and the tonemapper. (Measured against the
// renderer on a test plane, dark to pale, near and far into the fog: within 2 parts in
// 255 of the picture without shadows.)
// Materials without this (Godot's own: the cars, the signs) get by with the sun turned
// down instead (Condition.shadow_sun), which is close, not exact: their brightness holds,
// but strong colors come out a little stronger (a stop sign's red, the car's paint).
//
// A shader that includes this sets `sun_dist = length(VERTEX)`, `SPECULAR = 0.0` and
// `EMISSION = sun_sheen()` in fragment(): the sky's faint reflection on the surface, which
// the fix has to know, so it's drawn here (a measured constant: Condition.sky_sheen) and
// the renderer's own is switched off.
//
// (This renderer keeps colors in sRGB through fragment() and makes them linear afterwards:
// ALBEDO and EMISSION are written in sRGB there, and read back linear in light().)

global uniform float sun_shadow_scale;  // 0: no shadows, one pass; else what the sun's energy is turned down by
global uniform vec3 sky_light_drawn;  // the sky's light the first pass is drawn with (linear)...
global uniform vec3 sky_light_full;  // ...and what it is without shadows
global uniform vec3 haze_color;  // the fog's (linear)
global uniform vec2 haze_range;  // m: where the fog begins, where it's total
global uniform vec3 sky_sheen;  // the sky's faint reflection on every surface (linear): sun_sheen()

varying float sun_dist;

// Godot's filmic tonemapper with white at 1 (Environment.TONE_MAPPER_FILMIC), and back.
const float SUN_A = 0.88;  // 0.22 * 2 * 2
const float SUN_B = 0.6;  // 0.30 * 2
const float SUN_C = 0.10;
const float SUN_D = 0.20;
const float SUN_E = 0.01;
const float SUN_F = 0.30;
const float SUN_WHITE = 0.5783983;  // the curve at 1, before it's scaled to 1

vec3 sun_tonemap(vec3 c) {
	return (((c * (SUN_A * c + SUN_C * SUN_B) + SUN_D * SUN_E) / (c * (SUN_A * c + SUN_B) + SUN_D * SUN_F)) - SUN_E / SUN_F) / SUN_WHITE;
}

vec3 sun_tonemap_inverse(vec3 y) {
	vec3 t = min(y, vec3(0.999)) * SUN_WHITE + SUN_E / SUN_F;
	vec3 a = SUN_A * (t - 1.0);
	vec3 b = SUN_B * (t - SUN_C);
	vec3 c = SUN_D * (t * SUN_F - SUN_E);
	return max((-b - sqrt(max(b * b - 4.0 * a * c, vec3(0.0)))) / (2.0 * a), vec3(0.0));
}

vec3 sun_encode(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, 12.92 * c, lessThan(c, vec3(0.0031308)));
}

vec3 sun_decode(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// The sky's reflection, for EMISSION (in sRGB, as fragment() writes colors).
vec3 sun_sheen() {
	return sun_encode(sky_sheen);
}

void light() {
	vec3 lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL && sun_shadow_scale > 0.0) {
		float fog = smoothstep(haze_range.x, haze_range.y, sun_dist);
		vec3 first = mix(ALBEDO * sky_light_drawn + sky_sheen, haze_color, fog);
		vec3 whole = mix(ALBEDO * (sky_light_full + lit / sun_shadow_scale) + sky_sheen, haze_color, fog);
		vec3 more = max(sun_encode(sun_tonemap(whole)) - sun_encode(sun_tonemap(first)), vec3(0.0));
		DIFFUSE_LIGHT += sun_tonemap_inverse(sun_decode(more)) / (max(1.0 - fog, 0.002) * max(ALBEDO, vec3(0.0005)));
	} else {
		DIFFUSE_LIGHT += lit;
	}
}
