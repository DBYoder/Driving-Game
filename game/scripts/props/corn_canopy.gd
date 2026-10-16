class_name CornCanopy
extends RefCounted
## The rest of each corn field, past the clumps near the car: a top of leaves and tassels
## HEIGHT above the ground, and walls of stalks where the corn meets the grass strip
## along the road or a field of something else. One mesh per terrain tile, on a grid a
## lot coarser than the tile's; corn_canopy.gdshader trims it exactly to the field and
## verge edges, and sinks it out of the way within CLEAR_INNER of the car, where the
## real clumps are (CornField).
##
## Mesh attributes: UV.x = meters from the road centerline, UV.y = meters along a wall
## (for the stalk pattern), UV2.x = 0 for the top, 1 for a verge wall, 2 for a wall
## between fields, UV2.y = height above the ground. Wall normals point into the corn
## (verge walls) or across the field edge (field walls).

const HEIGHT := 2.5  ## its ragged top comes to about the clumps' height
const CLEAR_INNER := 70.0  ## sunk into the ground this close to the car...
const CLEAR_OUTER := 80.0  ## ...and full height from here
const WALL_FOOT := 0.3  ## walls start this far below the ground, so slopes don't show a gap


## The canopy for terrain tile `tile`, on a grid of `step` meters, or null if there's no
## corn on it.
static func build(route: RouteData, fields: Fields, tile: int, step: float) -> ArrayMesh:
	var t := route.terrain
	var ox := t.coords[tile].x * t.size
	var oz := t.coords[tile].y * t.size
	var n := roundi(t.size / step) + 1
	var points := PackedVector3Array()  ## ground under each grid point
	var dist := PackedFloat32Array()
	var corn := PackedByteArray()
	points.resize(n * n)
	dist.resize(n * n)
	corn.resize(n * n)
	var any_corn := false
	for row in n:
		for col in n:
			var k := row * n + col
			# Points on the far edges belong to the next tile; sample just inside this one.
			var x := ox + minf(col * step, t.size - 0.01)
			var z := oz + minf(row * step, t.size - 0.01)
			points[k] = Vector3(ox + col * step, t.height_at(x, z), oz + row * step)
			dist[k] = t.road_distance_smooth(x, z)
			corn[k] = int(fields.crop_at(x, z) == Fields.CORN)
			any_corn = any_corn or corn[k] == 1
	if not any_corn:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for row in n - 1:
		for col in n - 1:
			var a := row * n + col
			var quad := [a, a + 1, a + n, a + n + 1]
			var touches_corn := false
			var reaches_past_verge := false
			for k: int in quad:
				touches_corn = touches_corn or corn[k] == 1
				reaches_past_verge = reaches_past_verge or dist[k] >= CornField.VERGE
			if not touches_corn or not reaches_past_verge:
				continue
			# The same two triangles as the terrain tile, raised to the top of the corn.
			for tri: Array in [[a, a + 1, a + n + 1], [a, a + n + 1, a + n]]:
				for k: int in tri:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(dist[k], 0.0))
					st.set_uv2(Vector2(0.0, HEIGHT))
					st.add_vertex(points[k] + Vector3.UP * HEIGHT)
				count += 1
				count += _verge_wall(st, points, dist, tri)
	count += _field_walls(st, route, fields, ox, oz, step)
	if count == 0:
		return null
	return st.commit()


## A wall along the verge line where it crosses one triangle of the grid (marching
## triangles on the road distance, so it meets the top's trimmed edge exactly).
static func _verge_wall(st: SurfaceTool, points: PackedVector3Array, dist: PackedFloat32Array, tri: Array) -> int:
	var crossing: Array[Vector3] = []
	var into_corn := Vector3.ZERO
	for i in 3:
		var p: int = tri[i]
		var q: int = tri[(i + 1) % 3]
		var dp := dist[p] - CornField.VERGE
		var dq := dist[q] - CornField.VERGE
		if (dp < 0.0) != (dq < 0.0):
			crossing.append(points[p].lerp(points[q], dp / (dp - dq)))
		if dp >= 0.0:
			into_corn += points[p]
	if crossing.size() != 2:
		return 0
	var along := crossing[1] - crossing[0]
	along.y = 0.0
	if along.length() < 0.01:
		return 0
	var normal := Vector3(-along.z, 0.0, along.x).normalized()
	# Point the normal at the side past the verge (the corn side).
	var mid := (crossing[0] + crossing[1]) / 2.0
	if normal.dot(into_corn / 3.0 - mid) < 0.0:
		normal = -normal
	_wall(st, crossing[0], crossing[1], normal, 1.0, CornField.VERGE, CornField.VERGE)
	return 2


## Walls along the field boundaries crossing this tile, wherever corn meets something
## else (the shader decides per pixel which side is corn).
static func _field_walls(st: SurfaceTool, route: RouteData, fields: Fields, ox: float, oz: float,
		step: float) -> int:
	var t := route.terrain
	var count := 0
	for axis in 2:  # 0: lines of constant x, 1: lines of constant z
		var origin: float = fields.offset[axis]
		var lo := ox if axis == 0 else oz
		var first := ceili((lo - origin) / Fields.FIELD_SIZE)
		var line := origin + first * Fields.FIELD_SIZE
		while line < lo + t.size:
			var along := 0.0
			while along < t.size:
				var a := Vector2(line, (oz if axis == 0 else ox) + along)
				var b := Vector2(line, (oz if axis == 0 else ox) + minf(along + step, t.size - 0.01))
				if axis == 1:
					a = Vector2(a.y, a.x)
					b = Vector2(b.y, b.x)
				var mid := (a + b) / 2.0
				var across := Vector2(1, 0) if axis == 0 else Vector2(0, 1)
				var side_a := fields.crop_at(mid.x + across.x, mid.y + across.y) == Fields.CORN
				var side_b := fields.crop_at(mid.x - across.x, mid.y - across.y) == Fields.CORN
				var da := t.road_distance_smooth(a.x, a.y)
				var db := t.road_distance_smooth(b.x, b.y)
				if side_a != side_b and maxf(da, db) >= CornField.VERGE and da < 255.0:
					var pa := Vector3(a.x, t.height_at(a.x, a.y), a.y)
					var pb := Vector3(b.x, t.height_at(b.x, b.y), b.y)
					if not is_nan(pa.y) and not is_nan(pb.y):
						_wall(st, pa, pb, Vector3(across.x, 0.0, across.y), 2.0, da, db)
						count += 2
				along += step
			line += Fields.FIELD_SIZE
	return count


## A wall of stalks from ground `a` to ground `b`, HEIGHT tall.
static func _wall(st: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3, kind: float,
		dist_a: float, dist_b: float) -> void:
	# Measure along the wall in world space so the stalks line up across segments.
	var u0 := a.x + a.z
	var u1 := u0 + Vector2(b.x - a.x, b.z - a.z).length()
	var corners := [
		[a + Vector3.DOWN * WALL_FOOT, u0, 0.0, dist_a], [b + Vector3.DOWN * WALL_FOOT, u1, 0.0, dist_b],
		[b + Vector3.UP * HEIGHT, u1, HEIGHT, dist_b], [a + Vector3.UP * HEIGHT, u0, HEIGHT, dist_a],
	]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(Vector2(corners[i][3], corners[i][1]))
		st.set_uv2(Vector2(kind, corners[i][2]))
		st.add_vertex(corners[i][0])
