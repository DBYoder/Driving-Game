// Buildings and trees (Scenery), and the landmarks' and the junction's models (`fitted`
// off: drawn as they're built, colored by their vertex colors). See SceneryMeshes for how
// the scenery's models are laid out.
//
// Per instance: COLOR tints the walls (it's already multiplied into the vertex colors);
// INSTANCE_CUSTOM is the roof's color (rgb) and the eaves' share of the height (a): a
// model's walls (y 0 to 1) are fitted under the eaves, its roof (1 to 2) between them and
// the ridge. Plus 2 for a roof sloping one way, up to the +z side (a lean-to, or half a
// gable roof the lidar cut along its ridge), 4 up to the -z side: the ridge is moved to
// that side. Trees, bins and the rest have a = 1 and nothing over y = 1.
// UV.x is the part (walls, roof, roof trim, wall trim; +10/+20/+30 for a house's lower
// and upper rows of windows and its door: moved to suit a one-story house), UV.y and UV2
// its color or the roof's slope.
// Vertex alpha says what a face is: 0 plain, 1/3 a window (glows warm at night), 2/3 a
// lamp (a yard light, glows white), 1 leaves (the season's color: green, fall colors,
// bare branches). Snow settles on whatever faces up.
//
// The renderers turn an instance's normals by its transform as it is (not its inverse
// transpose), which tips a stretched model's slopes the wrong way: normals are divided
// by the scale squared first to come out right.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec3 leaf : source_color = vec3(0.25, 0.42, 0.17);
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.90, 0.92, 0.96);
uniform float night : hint_range(0.0, 1.0) = 0.0;  // lit windows
uniform bool fitted = false;  // Scenery's instances: walls and roofs fitted to each building

const float TWO_STORY_M = 4.4;  // eaves this high: a two-story house's windows and door

varying float up;
varying float shade;

void vertex() {
	shade = 1.0;
	if (fitted) {
		vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		float ea = INSTANCE_CUSTOM.a;
		float lean = ea > 3.0 ? -1.0 : (ea > 1.5 ? 1.0 : 0.0);
		float e = clamp(ea - (lean > 0.5 ? 2.0 : (lean < -0.5 ? 4.0 : 0.0)), 0.05, 1.0);
		float ridge = lean * 0.5;  // the ridge's z
		float code = UV.x + 0.01;
		float story = floor(code / 10.0);
		float part = floor(code - story * 10.0);
		if (story > 0.5 && e * scale.y < TWO_STORY_M) {  // a one-story house (see SceneryMeshes)
			if (story == 1.0) {
				VERTEX.y = 0.52 + (VERTEX.y - 0.27) * 1.9;  // the lower row of windows, up the wall
			} else if (story == 2.0) {
				VERTEX = vec3(0.0);  // no upper row
			} else {
				VERTEX.y *= 2.0;  // the door and porch
			}
		}
		float y = VERTEX.y;
		bool roofy = part == 1.0 || part == 2.0 || y > 1.0;
		float side = sign(NORMAL.z);
		VERTEX.y = roofy ? e + (y - 1.0) * (1.0 - e) : y * e;
		if (roofy) {  // each side of the ridge squeezed or stretched to meet it where it is
			if (lean != 0.0 && VERTEX.z * lean > 0.001) {
				VERTEX.y = 1.0;  // (a lean-to has no roof on its high side: nothing left of it)
			}
			VERTEX.z = ridge + VERTEX.z * (1.0 - 2.0 * ridge * sign(VERTEX.z));
		} else if (lean != 0.0 && y > 0.999 && VERTEX.z * lean > 0.45 && abs(NORMAL.z) > 0.5) {
			VERTEX.y = 1.0;  // a lean-to's high wall, up under the ridge (its ends: the gables)
		}
		if (part == 1.0) {
			COLOR.rgb = INSTANCE_CUSTOM.rgb * UV.y;
			NORMAL = vec3(0.0, UV2.x * (1.0 - 2.0 * ridge * side), side * UV2.y * (1.0 - e));
		} else if (part >= 2.0) {
			COLOR.rgb = vec3(UV2.x, UV2.y, UV.y);
		}
		NORMAL = normalize(NORMAL / (scale * scale));
		// A little darker down by the ground (the walls; trees shade themselves).
		if (part == 0.0 && COLOR.a < 0.1) {
			shade = mix(0.8, 1.0, clamp(VERTEX.y / e * 1.5, 0.0, 1.0));
		}
	}
	up = normalize(mat3(MODEL_MATRIX) * NORMAL).y;
}

void fragment() {
	vec3 base = COLOR.rgb * shade;
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
