// Farmland: a patchwork of quarter-quarter-section fields with grass along the roads, and
// mown lawns around the farmsteads and all through town. Close up (shaders/ground.gdshaderinc)
// the crops are in rows (soybeans and cut corn, each field its own way), hay lies in mown
// swaths, the combine's passes show on a cut field, the grass is in patches, and a fence row
// of rougher grass runs between fields. The ground's faceted, softened by the mesh's own
// normals so the big triangles don't show from up high.
// UV.x = meters from the road, UV.y = meters from the nearest building (0 in town).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/sun.gdshaderinc"
#include "res://shaders/ground.gdshaderinc"

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
uniform float yard_width = 24.0;
uniform float facets = 0.45;  // how much of the faceted look stays (1: all, 0: smooth)
const float ROW_M = 0.76;  // 30-inch rows
const float COMBINE_M = 9.14;  // a 30-foot head's passes
const float SWATH_M = 4.2;  // a mower-conditioner's
const float FENCE_ROW_M = 2.6;  // the rough grass between fields

varying vec3 world_pos;
varying float road_dist;
varying float yard_dist;

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
	yard_dist = UV.y;
}

void fragment() {
	sun_dist = length(VERTEX);
	// Face normal from screen-space derivatives for the low-poly look, eased toward the
	// mesh's smooth one.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	n = dot(n, VIEW) < 0.0 ? -n : n;
	vec3 smooth_n = length(NORMAL) > 0.5 ? normalize(NORMAL) : n;
	NORMAL = normalize(mix(smooth_n, n, facets));

	float px = g_pixel(world_pos);
	vec2 wp = world_pos.xz;
	vec2 local = (wp - field_offset) / field_size;
	vec2 cell = floor(local);
	float h = cell_hash(cell);
	// Each field's rows run one way or the other.
	float along = cell_hash(cell + vec2(5.0, 91.0)) < 0.5 ? wp.x : wp.y;
	float across = cell_hash(cell + vec2(5.0, 91.0)) < 0.5 ? wp.y : wp.x;
	// A cut field (see Fields.crop_at) is stubble in rows.
	bool cut = cell_hash(cell + vec2(57.0, 13.0)) < harvested;
	vec3 crop;
	if (h < 0.45) {
		if (cut) {
			float rows = g_rows(across, ROW_M, 2, px);
			float passes = step(0.5, fract(across / (2.0 * COMBINE_M)));
			crop = stubble * (0.95 + 0.10 * rows) * (0.97 + 0.06 * passes * g_fade(COMBINE_M, px))
				* (1.0 + (g_noise(wp / 7.0) - 0.5) * 0.10);
		} else {
			crop = corn * (1.0 + (g_noise(wp / 13.0) - 0.5) * 0.10) * (0.96 + 0.08 * g_rows(across, ROW_M, 1, px));
		}
	} else if (h < 0.85) {
		// Soybeans: the soil shows between the rows up close.
		float rows = g_rows(across, ROW_M, 2, px);
		crop = soybeans * (0.84 + 0.26 * rows) * (1.0 + (g_noise(wp / 11.0) - 0.5) * 0.12);
	} else if (h < 0.93) {
		// Hay, mown: lighter and darker swaths the mower laid down, there and back.
		float swaths = 0.5 + 0.5 * sin(across / SWATH_M * 3.14159);
		crop = hay * (0.94 + 0.12 * mix(0.5, swaths, g_fade(SWATH_M, px))) * (1.0 + (g_noise(wp / 9.0) - 0.5) * 0.10);
	} else {
		crop = g_grass(pasture, wp, px) * (1.0 + (g_noise(wp / 3.5) - 0.5) * 0.12 * g_fine(3.5, px));
	}
	crop *= 0.94 + 0.12 * cell_hash(cell + vec2(17.0, 31.0));
	// The fence row between fields: rougher grass, a couple of meters either side.
	vec2 edge = min(fract(local), 1.0 - fract(local)) * field_size;
	float fence = 1.0 - smoothstep(FENCE_ROW_M - 0.8, FENCE_ROW_M + 0.8 + px, min(edge.x, edge.y));
	crop = mix(crop, g_grass(verge * vec3(0.92, 0.95, 0.88), wp, px), fence * 0.85);
	vec3 lawn = g_grass(verge * vec3(0.92, 1.08, 0.86), wp, px);
	crop = mix(lawn, crop, smoothstep(yard_width - 8.0, yard_width, yard_dist));
	ALBEDO = mix(g_grass(verge, wp, px), crop, smoothstep(verge_width - 3.0, verge_width + 3.0, road_dist));
	// (The sky's reflection, as the sun's fix needs to know it: shaders/sun.gdshaderinc.)
	SPECULAR = 0.0;
	EMISSION = sun_sheen();
}
