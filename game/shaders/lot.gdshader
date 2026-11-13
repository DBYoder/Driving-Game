// Parking lots and paved yards (scripts/world/lots.gd): each its color off the aerial
// photos (the vertex color), shaded a little toward the condition's asphalt (wet, frosted)
// and white under snow.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/sun.gdshaderinc"
#include "res://shaders/ground.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

uniform vec3 asphalt : source_color = vec3(0.17, 0.17, 0.18);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.88, 0.90, 0.94);

void fragment() {
	sun_dist = length(VERTEX);
	vec3 c = g_asphalt(mix(COLOR.rgb, asphalt * 1.6, 0.3), world_pos.xz, g_pixel(world_pos));
	ALBEDO = mix(c, snow_color, snow * 0.85);
	ROUGHNESS = 0.95;
	// (The sky's reflection, as the sun's fix needs to know it: shaders/sun.gdshaderinc.)
	SPECULAR = 0.0;
	EMISSION = g_emission(ALBEDO, world_pos, 1.0);
}
