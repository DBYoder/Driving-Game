// A car's lamps (CarModel's "lights" surface, colored by vertex): unshaded, the tail lights
// brighter when the brakes are on and at night, the headlights white at night, the
// reversing lights lit going backward. Which lamp a face is comes from its color (red:
// tail, white: head or reverse, by which end of the car it's on; amber stays as it is).
shader_type spatial;
render_mode unshaded;

uniform float brake = 0.0;  // 0..1
uniform float night = 0.0;  // headlights on
uniform float reversing = 0.0;

varying float along;  // m along the car, the front's -z

void vertex() {
	along = VERTEX.z;
}

void fragment() {
	vec3 c = COLOR.rgb;
	bool red = c.r > 0.4 && c.g < 0.2 && c.b < 0.2;
	bool white = c.g > 0.7 && c.b > 0.7;
	if (red) {
		c = mix(c, vec3(0.82, 0.07, 0.06), night * 0.8);
		c = mix(c, vec3(1.0, 0.16, 0.10), brake);
	} else if (white) {
		c = along < 0.0 ? mix(c, vec3(1.0, 0.98, 0.92), night) : mix(c, vec3(1.0), reversing);
	}
	ALBEDO = c;
}
