extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/routes/highway1")


func test_route_is_the_real_length() -> void:
	check(route != null, "route loads")
	var miles := route.mile_at(route.finish_station)
	check(miles > 14.8 and miles < 15.5, "Kalona to US 218 is ~15 mi, got %.2f" % miles)
	check(route.start_station > 100.0, "there is road behind the start line")
	check(route.length - route.finish_station > 100.0, "there is road past the finish line")


func test_position_at_interpolates_between_samples() -> void:
	var a := route.points[100]
	var b := route.points[101]
	var mid := route.position_at(100.5 * route.spacing)
	check(mid.is_equal_approx(a.lerp(b, 0.5)), "halfway between samples")
	check(route.position_at(-50.0).is_equal_approx(route.points[0]), "clamped before the start")
	check(route.position_at(route.length + 50.0).is_equal_approx(route.points[-1]), "clamped past the end")


func test_directions() -> void:
	var s := route.start_station + 1000.0
	var t := route.tangent_at(s)
	check_near(t.length(), 1.0, 1e-4, "tangent is a unit vector")
	check(t.z < -0.95, "first miles run due north (-z), got %s" % t)
	check(route.right_at(s).x > 0.95, "right of northbound is east (+x)")


func test_nearest_station_round_trips() -> void:
	for s in [0.0, 1234.0, 9876.0, route.length]:
		var pos := route.position_at(s) + route.right_at(s) * 3.0
		check_near(route.nearest_station(pos), s, route.spacing, "global search near %d" % s)
		check_near(route.nearest_station(pos, s + 80.0), s, route.spacing, "hinted search near %d" % s)


func test_grades_are_highway_like() -> void:
	var worst := 0.0
	for i in route.points.size() - 1:
		worst = maxf(worst, absf(route.points[i + 1].y - route.points[i].y) / route.spacing)
	check(worst < 0.08, "steepest grade %.1f%% (real highways stay under ~7%%)" % (worst * 100.0))


func test_crossroads_are_in_order_and_named() -> void:
	var last := -1.0
	var names := []
	for c in route.crossroads:
		check(c.station >= last, "crossroads sorted by station")
		last = c.station
		names.append(c.name)
	for expected in ["Johnson-Washington Rd SW", "540th St SW", "Sharon Center Rd SW", "Naples Ave SW"]:
		check(expected in names, "%s is on the route" % expected)
	check(route.next_crossroad(route.start_station + 1.0).name == "E Ave", "the 4-way stop at the start")
	check(route.next_crossroad(route.start_station + 20.0).name == "W H Ave", "then the first crossroad out of it")


func test_passing_zones() -> void:
	check(route.no_passing(route.start_station + 50.0, 1.0), "no passing leaving Kalona")
	check(route.no_passing(route.finish_station - 100.0, 1.0), "no passing at the interchange")
	var solid := 0
	var samples := 0
	var s := route.start_station
	while s < route.finish_station:
		solid += int(route.no_passing(s, 1.0))
		samples += 1
		s += 50.0
	var share := float(solid) / samples
	check(share > 0.1 and share < 0.6, "some but not most of the road is no-passing (%.0f%%)" % (share * 100.0))
