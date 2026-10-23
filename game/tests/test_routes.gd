extends "res://tests/test_case.gd"
## The routes: Highway 1 (Kalona north to Iowa City) and Highway 22 (Kalona west to
## Wellman) both load, start at the same 4-way stop (Highway 22 in the middle of it,
## pointed west), finish where they should, and keep their own records; Wellman's finish is
## a stop sign on 8th Ave, not a light.

const Main := preload("res://scripts/main.gd")

var hw1 := RouteData.load_from(Routes.dir("highway1"))
var hw22 := RouteData.load_from(Routes.dir("highway22"))


func _crossroad(route: RouteData, name: String) -> Dictionary:
	for c: Dictionary in route.crossroads:
		if c.name == name:
			return c
	return {}


func test_every_route_loads_with_its_details() -> void:
	for id: String in Routes.IDS:
		var r := RouteData.load_from(Routes.dir(id))
		check(r != null, "%s loads from %s" % [id, Routes.dir(id)])
		if r == null:
			continue
		check(r.id == id and r.info == Routes.INFO[id], "%s knows which route it is" % id)
		for key: String in ["title", "from", "to", "number", "heading", "tagline", "finish", "finish_stop_line",
				"section_corner", "traps", "par_seconds", "min_miles", "min_buildings", "min_trees", "landmark"]:
			check(Routes.INFO[id].has(key), "%s has %s" % [id, key])
		check(not _crossroad(r, Routes.INFO[id].section_corner).is_empty(),
			"%s: the fields line up on %s, a real crossroad" % [id, Routes.INFO[id].section_corner])
		check(r.mile_at(r.finish_station) > float(Routes.INFO[id].min_miles), "%s is %.2f mi" % [id, r.mile_at(r.finish_station)])
		check(r.buildings.size() >= int(Routes.INFO[id].min_buildings) and r.trees.size() / 5 >= int(Routes.INFO[id].min_trees),
			"%s: %d buildings and %d trees from the lidar" % [id, r.buildings.size(), r.trees.size() / 5])


func test_highway_22_runs_from_kalona_to_wellman() -> void:
	var miles := hw22.mile_at(hw22.finish_station)
	check(miles > 6.6 and miles < 6.9, "6.75 mi from the 4-way stop in Kalona to 8th Ave (%.2f)" % miles)
	var start := _crossroad(hw22, "1st St")
	check(not start.is_empty() and start.route == "IA 1" and absf(start.station - hw22.start_station) < 30.0,
		"it starts at IA 1 (1st St in Kalona)")
	var finish := _crossroad(hw22, "8th Ave SW")
	check(not finish.is_empty() and absf(finish.station - hw22.finish_station - 8.0) < 10.0,
		"and finishes 8 m short of 8th Ave in Wellman")
	# West: the road heads toward -x out of Kalona.
	var heading := hw22.tangent_at(hw22.start_station + 500.0)
	check(heading.x < -0.9, "it heads west out of Kalona (%s)" % heading)
	check(hw1.tangent_at(hw1.start_station + 500.0).z < -0.9, "(Highway 1 heads north)")
	var creeks: Array = hw22.places.creeks.map(func(c): return c.name)
	check(creeks == ["Ramsey Creek", "English River", "Lime Creek"], "over Ramsey Creek, the English River and Lime Creek: %s" % [creeks])
	for c: Dictionary in hw22.places.creeks:
		var bridged := hw22.bridges.any(func(b): return c.station > b[0] - 60.0 and c.station < b[1] + 60.0)
		check(bridged, "%s has its bridge" % c.name)
	var into: Array = hw22.places.cities.filter(func(c): return c.entering)
	check(into.size() == 1 and into[0].name == "Wellman" and hw22.mile_at(into[0].station) > 5.5,
		"one WELLMAN city limit sign, a mile short of the finish: %s" % [into])
	check(hw22.places.counties.is_empty(), "all in Washington County: no county line")


func test_both_routes_start_at_the_same_4_way_stop() -> void:
	# Each route has its own origin; compare in real (UTM) meters.
	var at := []
	for id: String in Routes.IDS:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Routes.dir(id).path_join("route.json")))
		var r := RouteData.load_from(Routes.dir(id))
		var p := r.position_at(r.start_station)
		at.append(Vector2(d.origin.easting + p.x, d.origin.northing - p.z))
	# Highway 1's start line is 12 m short of the middle, Highway 22's 12 m past it.
	check(at[0].distance_to(at[1]) < 30.0, "the start lines are %.1f m apart" % at[0].distance_to(at[1]))


func test_highway_22_starts_in_the_4_way_stop_pointed_west() -> void:
	# Coming up from the south, Highway 1 starts at its stop line. Highway 22 starts in the
	# intersection, past the middle, pointed west straight out of it: nothing to cross
	# before Larch Ave, a mile out.
	var e_ave := _crossroad(hw1, "E Ave")
	check(hw1.start_station < float(e_ave.station), "Highway 1 starts short of E Ave")
	var first := _crossroad(hw22, "1st St")
	var past := hw22.start_station - float(first.station)
	check(past > 5.0 and past < 25.0, "Highway 22 starts %.0f m past the middle of 1st St" % past)
	var spawn := hw22.start_station - Main.SPAWN_BEHIND_START
	check(hw22.tangent_at(spawn).x < -0.99, "the car's pointed west (%s)" % hw22.tangent_at(spawn))
	check(hw22.next_crossroad(spawn).name == "Larch Ave", "next up is Larch Ave, not the intersection it's in")
	# Right out of it: WEST over IOWA 22, then how far to Wellman.
	var signs := Roadside.new()
	signs.setup(hw22)
	var found := {}
	for holder: Node in signs.get_children():
		for child: Node in holder.get_children():
			if child is Label3D:  # the first of each
				var s := hw22.nearest_station((holder as Node3D).position, hw22.start_station, 20000.0)
				found[(child as Label3D).text] = minf(s, found.get((child as Label3D).text, INF))
	check(found.has("WEST") and found.WEST > hw22.start_station and found.WEST < hw22.start_station + 100.0,
		"a WEST 22 marker right out of the 4-way stop (%s)" % found.get("WEST", "none"))
	check(found.has("WELLMAN  7") and found["WELLMAN  7"] < hw22.start_station + 300.0, "and WELLMAN 7 past it")
	signs.free()


func test_each_route_keeps_its_own_records() -> void:
	var was := Routes.current
	check(Routes.records_key("1993 Acura Legend", "highway1") == "1993 Acura Legend", "Highway 1's records keep their old keys")
	check(Routes.records_key("1993 Acura Legend", "highway22") == "highway22|1993 Acura Legend", "Highway 22's are its own")
	Routes.current = "highway22"
	check(Condition.preset("night").records_key("1997 Toyota Tercel") == "highway22|1997 Toyota Tercel|night",
		"a run on Highway 22 saves under Highway 22")
	Routes.current = was


func test_wellman_finish_is_a_stop_sign_not_a_light() -> void:
	var x22 := Intersections.new()
	x22.setup(hw22)
	check(x22.signal_heads.is_empty(), "no traffic lights in Wellman")
	check(not x22.finish_crossroad.is_empty() and String(x22.finish_crossroad.name).begins_with("8th Ave"),
		"the finish is at 8th Ave")
	# The 4-way stop's four, and 8th Ave's two, one each way in.
	check(x22.stop_signs >= 6, "stop signs at both ends (%d)" % x22.stop_signs)
	x22.free()
	var x1 := Intersections.new()
	x1.setup(hw1)
	check(not x1.signal_heads.is_empty(), "Highway 1 still finishes at the lights")
	x1.free()


func test_highway_22_has_two_washington_county_traps() -> void:
	var car := Car.new()
	car.stats = CarStats.preset("legend")
	car.route = hw22
	var cops := Cops.new()
	var run := Run.new()
	var traffic := Traffic.new()
	cops.setup(hw22, car, run, traffic, 3)
	check(is_inf(cops.county_line), "no county line to run for")
	check(cops.traps.size() == 2 and cops.traps.all(func(t): return t.county == "Washington"),
		"two Washington County deputies: %s" % [cops.traps.map(func(t): return t.county)])
	check(cops.county_at(hw22.finish_station) == "Washington", "Wellman's in Washington County too")
	cops.free()
	run.free()
	traffic.free()
	car.free()


func test_the_garage_switches_routes() -> void:
	var was := Routes.current
	Routes.current = "highway1"
	for action: String in ["menu_left", "menu_right", "menu_up", "menu_down", "menu_accept", "menu_back"]:
		if not InputMap.has_action(action):  # (the Controls autoload adds them in the game)
			InputMap.add_action(action)
	var garage := CarSelect.new()
	garage.setup("")
	garage.open(false, true)
	check(garage.row == CarSelect.Row.ROUTE, "after a switch the garage opens on the route")
	var asked := []
	garage.route_changed.connect(func(id): asked.append(id))
	var right := InputEventAction.new()
	right.action = "menu_right"
	right.pressed = true
	garage._unhandled_input(right)
	check(asked == ["highway22"], "▶ on the route line asks for Highway 22: %s" % [asked])
	garage._unhandled_input(right)
	check(asked.size() == 1, "and only once while it loads")
	garage.free()
	Routes.current = was


func test_par_is_per_route() -> void:
	var score := ScoreKeeper.new()
	score.par_seconds = Routes.INFO.highway22.par_seconds
	score.finish(300.0)
	check(score.time_bonus == int(Routes.INFO.highway22.par_seconds - 300.0) * ScoreKeeper.BONUS_PER_SECOND,
		"a 5-minute run to Wellman beats its par (%d)" % score.time_bonus)
	var hw1_par := float(Routes.INFO.highway1.par_seconds)
	var hw22_par := float(Routes.INFO.highway22.par_seconds)
	var ratio := (hw22_par / hw22.mile_at(hw22.finish_station)) / (hw1_par / hw1.mile_at(hw1.finish_station))
	check(ratio > 0.95 and ratio < 1.15, "the pars ask about the same pace (%.2f)" % ratio)
