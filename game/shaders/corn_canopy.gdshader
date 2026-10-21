// The corn canopy (CornCanopy): the top of a corn field seen from a distance, and its
// walls of stalks where it meets the grass strip along the road or another crop. Trimmed
// per pixel to the real field and verge edges, and sunk into the ground near the car,
// where the real clumps stand instead. Looks like corn.gdshader's clumps from the side.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 leaf : source_color = vec3(0.20, 0.40, 0.12);
uniform vec3 tassel : source_color = vec3(0.62, 0.58, 0.36);
uniform vec3 light = vec3(1.0);  // unshaded, so the condition says how lit it is (Condition.corn_light)
uniform vec2 field_offset = vec2(0.0);
uniform float field_size = 402.336;
uniform float verge = 26.0;
uniform float height = 2.5;
uniform vec3 clear_center;  // the car
uniform float clear_inner = 70.0;
uniform float clear_outer = 80.0;
uniform float sink = 0.6;

varying vec3 world_pos;
varying vec2 wall_normal;
varying float road_dist;
varying float along;
varying float kind;
varying float height01;

// Must match Fields.cell_hash() (and terrain.gdshader): corn is a hash under 0.45, unless
// the field's been cut (a second hash under `harvested`).
float cell_hash(vec2 cell) {
	uvec2 c = uvec2(ivec2(cell));
	uint h = (c.x * 73856093u) ^ (c.y * 19349663u);
	h = (h ^ (h >> 13u)) * 0x5bd1e995u;
	h ^= h >> 15u;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

uniform float harvested = 0.0;

bool corn_at(vec2 xz) {
	vec2 cell = floor((xz - field_offset) / field_size);
	return cell_hash(cell) < 0.45 && cell_hash(cell + vec2(57.0, 13.0)) >= harvested;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float up = smoothstep(clear_inner, clear_outer, distance(w.xz, clear_center.xz));
	VERTEX.y -= (UV2.y + sink) * (1.0 - up);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = NORMAL.xz;
	road_dist = UV.x;
	along = UV.y;
	kind = UV2.x;
	height01 = UV2.y / height;
}

void fragment() {
	vec2 xz = world_pos.xz;
	if (kind < 0.5) {
		// The top: leaves with tassels poking up, evening out to their average color where
		// they're too small to see, so it doesn't shimmer in the distance.
		if (road_dist < verge || !corn_at(xz)) {
			discard;
		}
		vec2 cell = floor(xz / 0.8);
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 near_col = h > 0.8 ? tassel : leaf * (0.8 + 0.45 * h);
		vec3 far_col = mix(leaf * 1.05, tassel, 0.25);
		float far = clamp(length(fwidth(xz)) * 1.2 - 0.2, 0.0, 1.0);
		// Patches a few meters across keep it looking like a crop, not paint, further out.
		float patch = fract(sin(dot(floor(xz / 5.0), vec2(39.3468, 11.135))) * 43758.5453);
		float patchy = 1.0 - clamp(length(fwidth(xz)) * 0.15 - 0.3, 0.0, 1.0);
		ALBEDO = mix(near_col, far_col, far) * (1.0 + (patch - 0.5) * 0.25 * patchy) * light;
	} else {
		vec2 n = normalize(wall_normal);
		bool show = kind < 1.5 ? corn_at(xz + n * 0.8)
			: corn_at(xz + n * 0.8) != corn_at(xz - n * 0.8) && road_dist >= verge;
		// Stalks, like the clumps: a ragged leafy outline that thins out at the top. Far
		// away they blur into a solid wall instead of shimmering.
		float x = along * 3.75;
		float blur = clamp(fwidth(x) * 1.5 - 0.3, 0.0, 1.0);
		float stalk = abs(fract(x) - 0.5);
		float leafy = 0.18 + 0.22 * sin(height01 * 23.0 + floor(x) * 2.7) * (1.0 - height01 * 0.6);
		float top = 0.9 + 0.08 * sin(floor(x) * 4.1);
		if (!show || stalk > leafy + 0.2 + blur || height01 > top + blur * 0.08) {
			discard;
		}
		vec3 col = height01 > top - 0.035 ? tassel : leaf * (0.95 + 0.15 * sin(floor(x) * 1.9));
		ALBEDO = col * mix(0.5, 1.05, clamp(height01, 0.0, 1.0)) * light;
	}
}
