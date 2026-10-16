class_name RoadMesher
extends RefCounted
## Builds the road surface along the route, one chunk of samples at a time.
## Paint and surface colors come from road.gdshader using UV.x = meters from centerline,
## so stripes stay crisp at any distance with no extra geometry.

const CHUNK_SAMPLES := 128
const LANE_WIDTH := 3.66  ## 12 ft
const PAVED_HALF_WIDTH := 4.26  ## lane + 2 ft paved shoulder
const GRAVEL_HALF_WIDTH := 6.5

const DITCH_EDGE := 10.0  ## where the grassy foreslope meets the ditch bottom

## Cross-section, left to right: [meters from centerline, height above the profile].
## Asphalt, gravel shoulder, then a 1:3.5 grass foreslope down into the ditch (gentle
## enough to drive back out of), ending in a short skirt tucked into the ditch bottom
## that the bake carved into the terrain 1.25 m below the road.
const SECTION := [
	[-DITCH_EDGE - 0.3, -1.5],
	[-DITCH_EDGE, -1.1],
	[-GRAVEL_HALF_WIDTH, -0.08],
	[-PAVED_HALF_WIDTH, 0.0],
	[0.0, 0.04],
	[PAVED_HALF_WIDTH, 0.0],
	[GRAVEL_HALF_WIDTH, -0.08],
	[DITCH_EDGE, -1.1],
	[DITCH_EDGE + 0.3, -1.5],
]


## Height of the road surface above the profile at a lateral offset (0 outside the section).
static func surface_height(offset: float) -> float:
	for i in SECTION.size() - 1:
		var a: Array = SECTION[i]
		var b: Array = SECTION[i + 1]
		if offset >= a[0] and offset <= b[0]:
			return lerpf(a[1], b[1], (offset - a[0]) / (b[0] - a[0]))
	return 0.0

var route: RouteData


func _init(r: RouteData) -> void:
	route = r


func chunk_count() -> int:
	return ceili(float(route.points.size() - 1) / CHUNK_SAMPLES)


func chunk_center(c: int) -> Vector3:
	var mid := mini((c * CHUNK_SAMPLES) + CHUNK_SAMPLES / 2, route.points.size() - 1)
	return route.points[mid]


func build_chunk(c: int) -> ArrayMesh:
	var i0 := c * CHUNK_SAMPLES
	var i1 := mini(i0 + CHUNK_SAMPLES, route.points.size() - 1)
	var cols := SECTION.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(i0, i1 + 1):
		var station := i * route.spacing
		var center := route.points[i]
		var right := route.right_at(station)
		for s in SECTION:
			verts.append(center + right * s[0] + Vector3.UP * s[1])
			uvs.append(Vector2(s[0], station))
	for row in i1 - i0:
		for col in cols - 1:
			var a := row * cols + col
			var b := a + 1
			var c2 := a + cols
			var d := c2 + 1
			# Clockwise seen from above while driving north (+row is forward, +col is right).
			indices.append_array([a, c2, d, a, d, b])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
