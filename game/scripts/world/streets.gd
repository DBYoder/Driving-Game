class_name Streets
extends RefCounted
## The side roads and town streets (tools/bake_streets.py): ribbons laid just above the
## ground, built in square cells so the WorldStreamer can load the ones near the car.
##
## Each street point comes with the surface height at its left edge, middle and right
## edge (left/right as you go along the points). Past each edge a grass skirt slopes down
## under the ground, so where a street crosses IA 1's ditch on a fill, or the ground falls
## away, the fill shows instead of a gap. Where a street meets IA 1 its end is cut along
## the edge of IA 1's pavement.
##
## Mesh attributes: UV.x = meters from the street's middle (negative = left), UV.y =
## meters along it, UV2.x = kind (0 paved, 1 gravel, 2 lane), UV2.y = its half width.

const CELL := 256.0
const CELL_HALF_DIAGONAL := 181.0
const KINDS := ["paved", "gravel", "lane"]
const SKIRT_OUT := 3.0  ## the skirt reaches this far past the edge...
const SKIRT_DROP := 1.4  ## ...and this far down
const IA1_EDGE := 4.3  ## where a street meeting IA 1 starts (IA 1's pavement is 4.26 m)

var route: RouteData
var streets: Array = []  ## Dictionaries: name, kind, half_width, joins, points (5 floats each)
var cells: Array[Vector2i] = []
var _runs := {}  ## cell -> [[street index, first point, last point], ...]
var _along: Array[PackedFloat32Array] = []  ## per street: meters along it at each point


func _init(r: RouteData) -> void:
	route = r
	streets = r.streets
	for s in streets.size():
		var flat: PackedFloat32Array = streets[s].points
		var n := flat.size() / 5
		var along := PackedFloat32Array([0.0])
		for i in range(1, n):
			along.append(along[i - 1] + _point(flat, i).distance_to(_point(flat, i - 1)))
		_along.append(along)
		var start := 0
		var cell := _cell_of(flat, 0)
		for i in range(1, n):
			var c := _cell_of(flat, i)
			if c != cell or i == n - 1:
				_add_run(cell, [s, start, i])  # shares point i with the next run, so they meet
				start = i
				cell = c
	for c: Vector2i in _runs:
		cells.append(c)


func cell_count() -> int:
	return cells.size()


func cell_center(i: int) -> Vector3:
	return Vector3((cells[i].x + 0.5) * CELL, 0.0, (cells[i].y + 0.5) * CELL)


## A cell's mesh: a surface for the paved streets and one for the gravel roads and lanes
## (named "asphalt" and "gravel"; a cell without one kind has only the other).
func build_cell(i: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for group: Array in [["paved"], ["gravel", "lane"]]:
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var indices := PackedInt32Array()
		for run: Array in _runs[cells[i]]:
			var street: Dictionary = streets[run[0]]
			if street.kind in group:
				_add_ribbon(run[0], run[1], run[2], verts, uvs, uv2s, indices)
		if indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, "asphalt" if group[0] == "paved" else "gravel")
	return mesh


## The street (if any) whose surface is under (x, z): {"name", "kind"} or {}.
func street_at(x: float, z: float) -> Dictionary:
	var c := Vector2i(floori(x / CELL), floori(z / CELL))
	if not _runs.has(c):
		return {}
	for run: Array in _runs[c]:
		var street: Dictionary = streets[run[0]]
		var flat: PackedFloat32Array = street.points
		for i in range(run[1], run[2]):
			var a := Vector2(flat[i * 5], flat[i * 5 + 4])
			var b := Vector2(flat[i * 5 + 5], flat[i * 5 + 9])
			var p := Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b)
			if p.distance_to(Vector2(x, z)) <= float(street.half_width):
				return {"name": street.name, "kind": street.kind}
	return {}


func _cell_of(flat: PackedFloat32Array, i: int) -> Vector2i:
	return Vector2i(floori(flat[i * 5] / CELL), floori(flat[i * 5 + 4] / CELL))


func _add_run(cell: Vector2i, run: Array) -> void:
	if not _runs.has(cell):
		_runs[cell] = []
	_runs[cell].append(run)


func _add_ribbon(index: int, i0: int, i1: int, verts: PackedVector3Array, uvs: PackedVector2Array,
		uv2s: PackedVector2Array, indices: PackedInt32Array) -> void:
	var street: Dictionary = streets[index]
	var flat: PackedFloat32Array = street.points
	var n := flat.size() / 5
	var hw: float = street.half_width
	var kind := float(KINDS.find(street.kind))
	var offsets := PackedFloat32Array([-hw - SKIRT_OUT, -hw, 0.0, hw, hw + SKIRT_OUT])
	var cols := offsets.size()
	var first := verts.size()
	for i in range(i0, i1 + 1):
		var p := _point(flat, i)
		var fwd := (_point(flat, mini(i + 1, n - 1)) - _point(flat, maxi(i - 1, 0)))
		fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var left_y := flat[i * 5 + 1]
		var mid_y := flat[i * 5 + 2]
		var right_y := flat[i * 5 + 3]
		var heights := PackedFloat32Array([left_y - SKIRT_DROP, left_y, mid_y, right_y, right_y - SKIRT_DROP])
		var joined: bool = (i == 0 and street.joins[0]) or (i == n - 1 and street.joins[1])
		for k in cols:
			var v := Vector3(p.x, heights[k], p.z) + right * offsets[k]
			if joined:
				v = _onto_ia1_edge(v, fwd)
			verts.append(v)
			uvs.append(Vector2(offsets[k], _along[index][i]))
			uv2s.append(Vector2(kind, hw))
	for row in i1 - i0:
		for k in cols - 1:
			var a := first + row * cols + k
			var b := a + cols
			indices.append_array([a, b + 1, a + 1, a, b, b + 1])


func _point(flat: PackedFloat32Array, i: int) -> Vector3:
	return Vector3(flat[i * 5], flat[i * 5 + 2], flat[i * 5 + 4])


## Slide an end-row vertex along the street until it's on the edge of IA 1's pavement
## (on its own side), so the end follows IA 1 instead of cutting square across it.
func _onto_ia1_edge(v: Vector3, fwd: Vector3) -> Vector3:
	var s := route.nearest_station(v, route.terrain.station_hint(v.x, v.z))
	var c := route.position_at(s)
	var right := route.right_at(s)
	var lateral := (v - c).dot(right)
	var rate := fwd.dot(right)  ## how fast the lateral offset changes along the street
	if absf(rate) < 0.2:
		return v  # running alongside: leave it be
	var t := (signf(lateral) * IA1_EDGE - lateral) / rate
	return v + fwd * clampf(t, -6.0, 6.0)
