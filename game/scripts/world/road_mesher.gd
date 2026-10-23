class_name RoadMesher
extends RefCounted
## Builds the road surface along the route, one chunk of samples at a time.
## Paint and surface colors come from road.gdshader using UV.x = meters from centerline,
## so stripes stay crisp at any distance with no extra geometry. UV.y is the station
## (for dashes), UV2 says which way passing is allowed, and COLOR.r is 1 on a bridge's
## deck (concrete shoulders, square edges, no foreslope: Bridges adds the rails).

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


const DECK_HALF_WIDTH := 7.2
## A bridge's cross-section: the same road, then the deck's square concrete edges.
const DECK_SECTION := [
	[-DECK_HALF_WIDTH, -1.2],
	[-DECK_HALF_WIDTH, -0.1],
	[-GRAVEL_HALF_WIDTH, -0.08],
	[-PAVED_HALF_WIDTH, 0.0],
	[0.0, 0.04],
	[PAVED_HALF_WIDTH, 0.0],
	[GRAVEL_HALF_WIDTH, -0.08],
	[DECK_HALF_WIDTH, -0.1],
	[DECK_HALF_WIDTH, -1.2],
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


## A chunk's mesh, with a row of vertices every `step` route samples (1 up close, more
## for far away). Every step includes the chunk's end rows, so neighbors always meet.
func build_chunk(c: int, step := 1) -> ArrayMesh:
	var i0 := c * CHUNK_SAMPLES
	var i1 := mini(i0 + CHUNK_SAMPLES, route.points.size() - 1)
	var rows: Array[int] = []
	for i in range(i0, i1, step):
		rows.append(i)
	rows.append(i1)
	var cols := SECTION.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var lines := PackedVector2Array()  ## UV2: solid center line for (northbound, southbound)
	var decks := PackedColorArray()  ## COLOR.r: on a bridge
	var indices := PackedInt32Array()
	for i in rows:
		var station := i * route.spacing
		var center := route.points[i]
		var right := route.right_at(station)
		var solid := Vector2(float(route.no_passing(station, 1.0)), float(route.no_passing(station, -1.0)))
		var on_deck := not route.deck_at(station).is_empty()
		for s in (DECK_SECTION if on_deck else SECTION):
			verts.append(center + right * s[0] + Vector3.UP * s[1])
			uvs.append(Vector2(s[0], station))
			lines.append(solid)
			decks.append(Color(1, 0, 0) if on_deck else Color(0, 0, 0))
	for row in rows.size() - 1:
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
	arrays[Mesh.ARRAY_TEX_UV2] = lines
	arrays[Mesh.ARRAY_COLOR] = decks
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
