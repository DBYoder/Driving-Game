extends "res://tests/test_case.gd"
## The Kalona 4-way stop, where both runs start, laid out like the real one
## (tools/junction.py into each route's junction.json; Junction and Intersections build it).

var hw1 := RouteData.load_from(Routes.dir("highway1"))
var hw22 := RouteData.load_from(Routes.dir("highway22"))


func test_both_runs_start_on_it() -> void:
	for r: RouteData in [hw1, hw22]:
		check(not r.junction.is_empty(), "%s has the 4-way" % r.id)
		check(r.in_junction(r.start_station), "%s starts on it" % r.id)
		var start := r.position_at(r.start_station) + r.right_at(r.start_station) * r.lane_offset(r.start_station)
		check(r.on_junction(start.x, start.z), "%s's start is on its concrete" % r.id)
	check_near(hw1.lane_offset(hw1.start_station), 3.66, 0.01, "Highway 1 starts in the through lane, right of the turn lane")
	check_near(hw22.lane_offset(hw22.start_station), 1.83, 0.01, "IA 22's lanes don't shift")
	check_near(hw1.lane_offset(hw1.junction_gap.y + 10.0), 1.83, 0.01, "back in the usual lane past it")


func test_the_road_leaves_its_stretch_out() -> void:
	for r: RouteData in [hw1, hw22]:
		var mesher := RoadMesher.new(r)
		var inside := 0
		var ends := 0
		for c in mesher.chunk_count():
			for step: int in [1, 4]:
				var arrays := mesher.build_chunk(c, step).surface_get_arrays(0)
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for t in index.size() / 3:
					var s := (uv[index[t * 3]].y + uv[index[t * 3 + 1]].y + uv[index[t * 3 + 2]].y) / 3.0
					inside += int(r.in_junction(s))
				for v in uv:
					ends += int(is_equal_approx(v.y, r.junction_gap.x) or is_equal_approx(v.y, r.junction_gap.y))
		check(inside == 0, "%s: no road triangles on the 4-way's stretch (%d)" % [r.id, inside])
		check(ends > 0, "%s: the road has rows right at its ends" % r.id)


func test_it_meets_the_road_exactly() -> void:
	for r: RouteData in [hw1, hw22]:
		for part: String in ["concrete", "shoulder"]:
			var verts := Junction._vectors(r.junction[part].vertices)
			for s: float in [r.junction_gap.x, r.junction_gap.y]:
				var c := r.position_at(s)
				var right := r.right_at(s)
				var along := Vector3(right.z, 0.0, -right.x)
				var on := 0
				var worst := 0.0
				for v in verts:
					if absf((v - c).dot(along)) < 0.02:
						on += 1
						worst = maxf(worst, absf(v.y - c.y - RoadMesher.surface_height(clampf((v - c).dot(right), -10.3, 10.3))))
				check(on >= 7, "%s %s: vertices on the line at %.0f (%d)" % [r.id, part, s, on])
				check(worst < 0.005, "%s %s at %.0f: on the road's cross-section (%.1f mm off)" % [r.id, part, s, worst * 1000.0])


func test_highway_22_has_one_highway_1() -> void:
	# The NTD draws IA 1 as two roads through the junction; the junction's own IA 1 replaces both.
	var shrunk := Geometry2D.offset_polygon(hw22._junction_outline, -0.5)[0] as PackedVector2Array
	var on := 0
	var ends: Array[float] = []
	for st: Dictionary in hw22.streets:
		var flat: PackedFloat32Array = st.points
		var n := flat.size() / 5
		for i in n:
			on += int(Geometry2D.is_point_in_polygon(Vector2(flat[i * 5], flat[i * 5 + 4]), shrunk))
		if st.name == "1st St":
			for i: int in [0, n - 1]:
				var p := Vector2(flat[i * 5], flat[i * 5 + 4])
				if p.distance_to(Vector2(hw22.junction.center[0], hw22.junction.center[2])) < 250.0:
					ends.append(p.y - float(hw22.junction.center[2]))
	check(on == 0, "no street runs out onto the junction (%d points)" % on)
	check(ends.size() == 2, "IA 1 carries on from both ends of it, once each (%d)" % ends.size())
	if ends.size() == 2:
		ends.sort()
		check(ends[0] < -150.0 and ends[1] > 100.0, "north and south (%.0f, %.0f m)" % [ends[0], ends[1]])


func test_its_signs_and_the_buggy() -> void:
	for r: RouteData in [hw1, hw22]:
		var x := Intersections.new()
		x.setup(r)
		var all_way := 0
		for n in x.get_children():
			for label in n.get_children().filter(func(c): return c is Label3D and c.text == "ALL WAY"):
				all_way += 1
		check(all_way == 4, "%s: an ALL WAY stop sign each way in (%d)" % [r.id, all_way])
		check(x.yield_signs == 4, "%s: a YIELD where each free right turn joins (%d)" % [r.id, x.yield_signs])
		check(x.buggy != null and r.on_junction(x.buggy.position.x, x.buggy.position.z), "%s: the buggy waits on it" % r.id)
		if x.buggy:
			var c := r.position_at(r.start_station)
			var side := (x.buggy.position - c).dot(r.right_at(r.start_station))
			check(side > 4.0, "%s: on your right as you start (%.1f m)" % [r.id, side])
		x.free()


func test_it_is_built() -> void:
	var j := Junction.new()
	j.setup(hw1)
	for kind: String in ["concrete", "gravel", "grass", "props"]:
		check(j.bodies.has(kind), "solid: %s" % kind)
	check(j.bodies.concrete.get_meta("surface") == "asphalt", "the car feels the concrete as pavement")
	check(j.paint_triangles > 2000, "lines, gores, arrows and words painted (%d triangles)" % j.paint_triangles)
	check(j.lamps.size() == 7, "seven light poles (%d)" % j.lamps.size())
	j.apply_condition(Condition.preset("summer"))
	check(j.lamps.all(func(l): return not l.visible), "lamps off by day")
	j.apply_condition(Condition.preset("night"))
	check(j.lamps.all(func(l): return l.visible), "and on at night")
	var words := j.get_children().filter(func(c): return c is Label3D).map(func(c): return c.text)
	check(words.count("KALONA") == 2, "the welcome sign reads KALONA both ways (%s)" % [words])
	j.free()


func test_nothing_stands_out_on_it() -> void:
	for r: RouteData in [hw1, hw22]:
		var poles := PowerLines.new()
		poles.setup(r, Streets.new(r))
		var in_way := poles.poles.filter(func(p: Transform3D): return r.near_junction(p.origin.x, p.origin.z))
		check(in_way.is_empty(), "%s: no power pole on it (%d)" % [r.id, in_way.size()])
		poles.free()
		var signs := Roadside.new()
		signs.setup(r)
		var on := signs.get_children().filter(func(n): return n is Node3D and r.on_junction(n.position.x, n.position.z))
		check(on.is_empty(), "%s: no roadside sign out on it (%d)" % [r.id, on.size()])
		signs.free()
		var trees := 0
		for i in r.trees.size() / 5:
			trees += int(r.near_junction(r.trees[i * 5], r.trees[i * 5 + 1]))
		var buildings := r.buildings.filter(func(b): return r.near_junction(b.x, b.z))
		check(trees == 0 and buildings.is_empty(), "%s: no lidar tree or building on it (%d, %d)" % [r.id, trees, buildings.size()])


func test_the_ground_and_the_corn_keep_off_it() -> void:
	for r: RouteData in [hw1, hw22]:
		var verts := Junction._vectors(r.junction.concrete.vertices)
		var poking := 0
		var corn := 0
		for i in range(0, verts.size(), 5):
			var v := verts[i]
			var ground := r.terrain.height_at(v.x, v.z)
			poking += int(not is_nan(ground) and ground > v.y - 0.05)
			corn += int(r.terrain.road_distance_smooth(v.x, v.z) >= CornField.VERGE)
		check(poking == 0, "%s: the ground stays under the concrete (%d spots poke through)" % [r.id, poking])
		check(corn == 0, "%s: no corn on it (%d spots)" % [r.id, corn])
