// Flat-shaded farmland: a patchwork of quarter-quarter-section fields with grass along the road.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 corn : source_color = vec3(0.32, 0.43, 0.18);  // about corn_canopy's top from afar
uniform vec3 stubble : source_color = vec3(0.62, 0.55, 0.38);  // a corn field after harvest
uniform float harvested = 0.0;  // share of corn fields cut (Fields.harvested)
uniform vec3 soybeans : source_color = vec3(0.34, 0.50, 0.17);
uniform vec3 hay : source_color = vec3(0.58, 0.60, 0.30);
uniform vec3 pasture : source_color = vec3(0.42, 0.50, 0.24);
uniform vec3 verge : source_color = vec3(0.47, 0.57, 0.29);
// A quarter of a quarter section (1/4 mile), the classic Iowa field. Offset lines the
// field edges up with the real section-line roads.
uniform float field_size = 402.336;
uniform vec2 field_offset = vec2(0.0);
uniform float verge_width = 16.0;

varying vec3 world_pos;
varying float road_dist;

// 32-bit integer hash of a field cell to [0, 1). Must match Fields.cell_hash() in
// scripts/world/fields.gd so game logic (corn to plow) agrees with what's drawn.
float cell_hash(vec2 cell) {
	uvec2 c = uvec2(ivec2(cell));
	uint h = (c.x * 73856093u) ^ (c.y * 19349663u);
	h = (h ^ (h >> 13u)) * 0x5bd1e995u;
	h ^= h >> 15u;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	road_dist = UV.x;
}

void fragment() {
	// Face normal from screen-space derivatives gives the low-poly look for free.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VIEW) < 0.0 ? -n : n;

	vec2 cell = floor((world_pos.xz - field_offset) / field_size);
	float h = cell_hash(cell);
	// A cut field (see Fields.crop_at) is stubble in rows.
	bool cut = cell_hash(cell + vec2(57.0, 13.0)) < harvested;
	vec3 crop = h < 0.45 ? (cut ? stubble * (0.93 + 0.07 * step(0.5, fract(world_pos.x / 0.76))) : corn)
		: (h < 0.85 ? soybeans : (h < 0.93 ? hay : pasture));
	crop *= 0.94 + 0.12 * cell_hash(cell + vec2(17.0, 31.0));
	ALBEDO = mix(verge, crop, smoothstep(verge_width - 3.0, verge_width + 3.0, road_dist));
}
