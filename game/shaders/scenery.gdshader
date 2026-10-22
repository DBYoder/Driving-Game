// Buildings and trees (Scenery). Vertex colors carry the colors, already multiplied by the
// multimesh instance color that tints each building or tree (instance custom data reads
// back wrong with vertex colors in the Compatibility renderer, so it's not used). Vertex
// alpha says what a face is: 0 plain,
// 1/3 a window (glows warm at night), 2/3 a lamp (a yard light, glows white at night),
// 1 leaves (they take the season's leaf color: green, fall colors, bare branches).
// Snow settles on whatever faces up.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec3 leaf : source_color = vec3(0.25, 0.42, 0.17);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.90, 0.92, 0.96);
uniform float night : hint_range(0.0, 1.0) = 0.0;  // lit windows

varying float up;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float a = COLOR.a;
	float leafy = step(0.83, a);
	float lamp = step(0.5, a) * (1.0 - leafy);
	float window = step(0.17, a) * (1.0 - step(0.5, a));
	vec3 c = mix(base, leaf * base.g * 2.4, leafy);
	float s = snow * smoothstep(0.3, 0.7, up) * (1.0 - lamp - window);
	ALBEDO = mix(c, snow_color, s);
	ROUGHNESS = 0.9;
	EMISSION = (vec3(1.0, 0.78, 0.42) * window * 0.9 + vec3(0.85, 0.92, 1.0) * lamp * 3.0) * night;
}
