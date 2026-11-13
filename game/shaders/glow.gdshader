// A lamp's halo at night: a soft round glow that always faces the camera, added over the
// picture, never too small to see from afar, fading out into the fog (Glow).
// Per instance (a MultiMesh's, or the node's own transform): where the lamp's fixture is;
// `offset` is the lamp's own spot in that transform's space (a yard light's head, up its
// pole), `size` its glow's radius (m).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float lamp_glow;  // 0 by day, 1 at night (Main)
global uniform vec2 haze_range;  // m: where the fog begins, where it's total
uniform vec3 color : source_color = vec3(1.0, 0.85, 0.6);
uniform float size = 0.9;
uniform vec3 offset = vec3(0.0);
uniform float strength = 1.0;
uniform float min_angle = 0.0035;  // radians: no smaller than this on screen
uniform bool instance_color = false;  // each instance's color times `color` (a MultiMesh's)

varying float fade;
varying vec3 tint;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(offset, 1.0)).xyz;
	vec3 view_center = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
	float dist = length(view_center);
	float r = max(size, dist * min_angle);
	// A quad (QuadMesh, 1 x 1) turned to the camera in view space, a little toward it so
	// it isn't cut by the fixture it's on.
	view_center += normalize(-view_center) * min(r * 0.8, 1.5);
	POSITION = PROJECTION_MATRIX * vec4(view_center + vec3(VERTEX.xy * 2.0 * r, 0.0), 1.0);
	fade = lamp_glow * strength * (1.0 - smoothstep(haze_range.x, haze_range.y * 1.1, dist));
	tint = instance_color ? COLOR.rgb : vec3(1.0);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float glow = exp(-d * d * 7.0) * 0.8 + exp(-d * d * 60.0) * 0.6;
	ALBEDO = color * tint * glow * fade;
}
