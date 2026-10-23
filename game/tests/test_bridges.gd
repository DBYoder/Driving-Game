extends "res://tests/test_case.gd"
## The real bridges: a deck and guardrails where the road crosses a creek or river 3 m or
## more up (the English River on Highway 22, 92 m long, 7.8 m up), open underneath with
## the creek's water in it; culverts stay plain fills. Nothing roadside stands on a deck,
## and deer cross short of the rails, not over them.

var hw1 := RouteData.load_from(Routes.dir("highway1"))
var hw22 := RouteData.load_from(Routes.dir("highway22"))


func _english_river() -> Array:
	for b: Array in hw22.decks:
		if float(b[1]) - float(b[0]) > 80.0:
			return b
	return []


func test_the_english_river_has_a_real_bridge() -> void:
	var b := _english_river()
	check(not b.is_empty(), "a long bridge on Highway 22: %s" % [hw22.decks])
	if b.is_empty():
		return
	var creek: Dictionary = hw22.places.creeks.filter(func(c): return c.name == "English River")[0]
	check(float(creek.station) > float(b[0]) and float(creek.station) < float(b[1]), "it's where the English River crosses")
	check(float(b[2]) > 6.0 and int(b[3]) == 1, "7.8 m up, open underneath: %s" % [b])
	# Under the middle of the deck the ground is the real valley, well below the road.
	var mid := (float(b[0]) + float(b[1])) / 2.0
	var p := hw22.position_at(mid) + hw22.right_at(mid) * 3.0
	var ground := hw22.terrain.height_at(p.x, p.z)
	check(p.y - ground > 4.0, "the ground's %.1f m under the deck (not filled up to it)" % (p.y - ground))


func test_culverts_stay_fills() -> void:
	for r: RouteData in [hw1, hw22]:
		for b: Array in r.bridges:
			var real := float(b[2]) >= RouteData.RAILED_BRIDGE_M
			check(real == r.decks.has(b), "%s at %.0f: %.1f m up is %s" % [r.id, b[0], b[2], "a bridge" if real else "a culvert"])
	var over_218 := hw1.decks.filter(func(b): return int(b[3]) == 0)
	check(over_218.size() == 1, "on Highway 1 the bridge over US 218 keeps its fill (%d)" % over_218.size())


func test_every_bridge_draws_its_own_rails() -> void:
	# A mesh fades out by the distance to its middle: one mesh for all of a route's rails
	# had its middle miles from any bridge, and none of them showed.
	for r: RouteData in [hw1, hw22]:
		var bridges := Bridges.new()
		bridges.setup(r)
		for child in bridges.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).visibility_range_end > 0.0:
				var box: AABB = (child as MeshInstance3D).mesh.get_aabb()
				var middle := box.get_center()
				var s := r.nearest_station(middle)
				var near := not r.deck_at(s, 200.0).is_empty()
				check(near and box.size.length() < 600.0, "%s: a bridge mesh centered on its bridge (at %.0f, %.0f m across)" % [
					r.id, s, box.size.length()])
		bridges.free()


func test_the_bridge_is_built() -> void:
	var bridges := Bridges.new()
	bridges.setup(hw22)
	check(bridges.rail_runs == hw22.decks.size() * 2, "guardrails on both sides of every bridge (%d)" % bridges.rail_runs)
	check(bridges.markers == hw22.decks.size() * 4, "end markers at every corner (%d)" % bridges.markers)
	var names := bridges.waters.map(func(w): return w.get_meta("creek"))
	check("English River" in names and "Ramsey Creek" in names and "Lime Creek" in names,
		"water under the bridges over named creeks: %s" % [names])
	var solid := 0
	for child in bridges.get_children():
		if child is StaticBody3D:
			solid += 1
	check(solid == bridges.rail_runs, "every guardrail is solid (%d)" % solid)
	bridges.free()
	# The water's surface is under the deck and over the creek bed.
	var course := Bridges.water_course(hw22, _english_river())
	var deck := hw22.position_at((float(_english_river()[0]) + float(_english_river()[1])) / 2.0).y
	var under_deck := 0
	for q: Vector3 in course.points:
		if q.y < deck - Bridges.WATER_CLEARANCE + 0.01:
			under_deck += 1
	check(under_deck == course.points.size(), "the river's surface stays under the deck")


func test_the_deck_is_part_of_the_road() -> void:
	var b := _english_river()
	var mesher := RoadMesher.new(hw22)
	var chunk := int(((float(b[0]) + float(b[1])) / 2.0) / hw22.spacing) / RoadMesher.CHUNK_SAMPLES
	var arrays := mesher.build_chunk(chunk).surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var on_deck := 0
	var widest := 0.0
	for i in colors.size():
		if colors[i].r > 0.5:
			on_deck += 1
			widest = maxf(widest, absf(uvs[i].x))
	check(on_deck > 0, "the road mesh has deck rows over the river (%d vertices)" % on_deck)
	check(absf(widest - RoadMesher.DECK_HALF_WIDTH) < 0.01, "the deck's edges, not a grass foreslope (%.1f m)" % widest)


func test_nothing_roadside_stands_on_a_deck() -> void:
	for r: RouteData in [hw1, hw22]:
		for s in range(0, int(r.length), 50):
			var b := r.deck_at(float(s))
			if b.is_empty():
				continue
			check(not Bridges.deer_station(r, b) > float(b[0]) - RouteData.RAIL_APPROACH_M,
				"%s: deer cross short of the rails at %.0f" % [r.id, b[0]])
	var signs := Roadside.new()
	signs.setup(hw22)
	for holder in signs.get_children():
		var s := hw22.nearest_station((holder as Node3D).position)
		check(hw22.deck_at(s).is_empty(), "no sign out over the river at %.0f" % s)
	signs.free()
