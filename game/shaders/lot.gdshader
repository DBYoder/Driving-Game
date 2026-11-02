// Parking lots and paved yards (scripts/world/lots.gd): each its color off the aerial
// photos (the vertex color), shaded a little toward the condition's asphalt (wet, frosted)
// and white under snow.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.88, 0.90, 0.94);

void fragment() {
	vec3 c = mix(COLOR.rgb, asphalt * 1.6, 0.3);
	ALBEDO = mix(c, snow_color, snow * 0.85);
	ROUGHNESS = 0.95;
}
