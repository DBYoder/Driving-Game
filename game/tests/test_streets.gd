extends "res://tests/test_case.gd"
## Phase 7: the side roads and town streets, lawns in town, and the power lines.

var route := RouteData.load_from("res://data/route")


func _pieces(street_name: String) -> Array:
	return route.streets.filter(func(s: Dictionary): return s.name == street_name)


func test_streets_are_baked() -> void:
	var kinds := {}
	for s: Dictionary in route.streets:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
		check(s.points.size() % 5 == 0 and s.points.size() >= 15, "%s: x, 3 heights, z per point" % s.name)
	check(route.streets.size() > 50, "%d street pieces" % route.streets.size())
	check(kinds.has("paved") and kinds.has("gravel"), "paved and gravel roads: %s" % kinds)
	check(not _pieces("E Ave").is_empty() and not _pieces("Mormon Trek Blvd").is_empty(), "E Ave and Mormon Trek are there")
	for name: String in ["540th St SW", "500th St SW"]:
		var p := _pieces(name)
		check(not p.is_empty() and p.all(func(s: Dictionary): return s.kind == "gravel"), "%s is a gravel road" % name)


func test_streets_meet_ia1_at_its_edge_and_height() -> void:
	var joined := 0
	for s: Dictionary in route.streets:
		var flat: PackedFloat32Array = s.points
		for e in 2:
			if not s.joins[e]:
				continue
			joined += 1
			var i := 0 if e == 0 else flat.size() / 5 - 1
			var p := Vector3(flat[i * 5], flat[i * 5 + 2], flat[i * 5 + 4])
			var st := route.nearest_station(p, route.terrain.station_hint(p.x, p.z))
			var c := route.position_at(st)
			var lateral := Vector2(p.x - c.x, p.z - c.z).length()
			check(lateral > 3.5 and lateral < 5.5, "%s starts at IA 1's edge (%.1f m out)" % [s.name, lateral])
			check(absf(p.y - c.y) < 0.15, "%s meets IA 1 level (%.2f m)" % [s.name, p.y - c.y])
	check(joined > 20, "%d street ends meet IA 1" % joined)


func test_streets_sit_on_the_ground() -> void:
	var lowest := INF
	var where := ""
	for s: Dictionary in route.streets:
		var flat: PackedFloat32Array = s.points
		for i in flat.size() / 5:
			var ground := route.terrain.height_at(flat[i * 5], flat[i * 5 + 4])
			if is_nan(ground):
				continue
			var above := flat[i * 5 + 2] - ground
			if above < lowest:
				lowest = above
				where = s.name
	check(lowest > 0.05, "the middle of every street is above the ground (lowest %.2f m, %s)" % [lowest, where])


func test_street_meshes_and_lookup() -> void:
	var streets := Streets.new(route)
	check(streets.cell_count() > 20, "%d cells" % streets.cell_count())
	var e_ave: Dictionary = _pieces("E Ave")[0]
	var flat: PackedFloat32Array = e_ave.points
	var mid := flat.size() / 10
	var x := flat[mid * 5]
	var z := flat[mid * 5 + 4]
	check(streets.street_at(x, z).get("name", "") == "E Ave", "E Ave is under one of its own points")
	check(streets.street_at(x + 30.0, z + 30.0).is_empty() or streets.street_at(x + 30.0, z + 30.0).name != "E Ave",
		"and not 40 m off it")
	var cell := Vector2i(floori(x / Streets.CELL), floori(z / Streets.CELL))
	var mesh := streets.build_cell(streets.cells.find(cell))
	var names := []
	for k in mesh.get_surface_count():
		names.append(mesh.surface_get_name(k))
	check("asphalt" in names, "its cell has an asphalt surface (%s)" % [names])


func test_streets_are_driveable() -> void:
	# A street collider tells the tires what they're on.
	var car := Car.new()
	for surface: String in ["asphalt", "gravel"]:
		var body := StaticBody3D.new()
		body.set_meta("surface", surface)
		check(car._surface_at({"collider": body, "position": Vector3.ZERO}) == surface, "a %s street grips like %s" % [surface, surface])
		body.free()
	car.free()


func test_no_crops_in_town() -> void:
	# A block east of IA 1 in Kalona, and one in Iowa City near the finish.
	for at: Array in [[route.start_station + 150.0, 200.0], [route.finish_station - 200.0, 150.0]]:
		var station: float = at[0]
		var p := route.position_at(station) + route.right_at(station) * float(at[1])
		check(route.terrain.yard_distance_smooth(p.x, p.z) < 1.0, "in town is all lawn (station %.0f)" % at[0])
		check(CornField.clearance(route.terrain, p.x, p.z) < CornField.VERGE, "so no corn grows there")


func test_power_lines_follow_the_road() -> void:
	var lines := PowerLines.new()
	lines.setup(route, Streets.new(route))
	var n := lines.poles.size()
	check(n > 400, "%d poles" % n)
	var sides := {}
	var switches := 0
	var last_side := 0.0
	var worst_offset := 0.0
	var near_crossroad := 0
	for t: Transform3D in lines.poles:
		var s := route.nearest_station(t.origin, route.terrain.station_hint(t.origin.x, t.origin.z))
		var lateral := (t.origin - route.position_at(s)).dot(route.right_at(s))
		worst_offset = maxf(worst_offset, absf(absf(lateral) - PowerLines.OFFSET))
		var side := signf(lateral)
		if last_side != 0.0 and side != last_side:
			switches += 1
		last_side = side
		sides[side] = true
		for c: Dictionary in route.crossroads:
			if absf(float(c.station) - s) < PowerLines.CLEAR_OF_CROSSROADS - 1.0:
				near_crossroad += 1
	check(worst_offset < 0.6, "every pole %.1f m off the centerline (worst miss %.2f m)" % [PowerLines.OFFSET, worst_offset])
	check(sides.size() == 2 and switches >= 2, "it crosses the road now and then (%d times)" % switches)
	check(near_crossroad == 0, "no pole in a crossroad (%d)" % near_crossroad)
	for i in range(1, n):
		var gap := lines.poles[i].origin.distance_to(lines.poles[i - 1].origin)
		if gap < PowerLines.SPACING * 0.75:
			check(false, "poles %d and %d only %.1f m apart" % [i - 1, i, gap])
			break
	lines.free()
