extends "res://tests/test_case.gd"
## The ways back: Highway 1 south from Mormon Trek to Kalona, Highway 22 east from Wellman
## to Kalona. The same road and world as the way out, the other way along it
## (RouteData.reversed_as): its start where the way out finished, its finish at the 4-way.

const Main := preload("res://scripts/main.gd")

var hw1 := RouteData.load_route("highway1")
var south := RouteData.load_route("highway1_south")
var hw22 := RouteData.load_route("highway22")
var east := RouteData.load_route("highway22_east")


func test_the_same_road_the_other_way() -> void:
	for pair: Array in [[hw1, south], [hw22, east]]:
		var out: RouteData = pair[0]
		var back: RouteData = pair[1]
		var L := back.length
		check(back.reversed and back.way_out().id == out.id and back.way_out().length == L and out.way_out() == out,
			"%s is the way back along %s" % [back.id, out.id])
		for s: float in [0.0, 333.0, L / 2.0, L - 40.0, L]:
			check(back.position_at(s).distance_to(out.position_at(L - s)) < 0.01, "%s: the same road at %.0f" % [back.id, s])
			check(back.tangent_at(s).dot(out.tangent_at(L - s)) < -0.99, "going the other way at %.0f" % s)
			check(back.no_passing(s, 1.0) == out.no_passing(L - s, -1.0), "with their passing zones at %.0f" % s)
			check(is_equal_approx(back.lane_offset(s), out.lane_offset(L - s)), "and lanes at %.0f" % s)
		var stations: Array = back.crossroads.map(func(c): return c.station)
		var sorted := stations.duplicate()
		sorted.sort()
		check(stations == sorted, "%s: its crossroads in order along it" % back.id)
		var first: Dictionary = back.crossroads[0]
		var same: Dictionary = out.crossroads[out.crossroads.size() - 1]
		check(first.name == same.name and first.side != same.side if same.side in ["left", "right"] else true,
			"the last crossroad out is the first back, on the other side")
		check(back.bridges.size() == out.bridges.size() and absf(float(back.bridges[0][0]) - (L - float(out.bridges[-1][1]))) < 0.01,
			"and its bridges")
		check(back.terrain == back.way_out().terrain and back.trees == back.way_out().trees and back.streets == back.way_out().streets,
			"the world's the same one")
		var miles := back.mile_at(back.finish_station)
		check(absf(miles - out.mile_at(out.finish_station)) < 0.05, "%s is as long: %.2f mi" % [back.id, miles])
		var spawn := back.start_station - Main.SPAWN_BEHIND_START
		check(back.station_hint(back.position_at(spawn).x, back.position_at(spawn).z) >= 0.0
			and absf(back.nearest_station(back.position_at(spawn), back.station_hint(back.position_at(spawn).x, back.position_at(spawn).z)) - spawn) < 3.0,
			"its station hints point the right way")


func test_highway_1_south_from_mormon_trek_to_the_4_way() -> void:
	var start := _crossroad(south, "Mormon Trek Blvd")
	check(not start.is_empty() and absf(south.start_station - float(start.station)) < 25.0, "it starts at Mormon Trek")
	check(south.tangent_at(south.finish_station - 500.0).z > 0.9, "and comes down into Kalona heading south (%s)" % south.tangent_at(south.finish_station - 500.0))
	var middle := Vector3(south.junction.center[0], south.junction.center[1], south.junction.center[2])
	var finish := south.position_at(south.finish_station)
	check(absf(Vector2(finish.x - middle.x, finish.z - middle.z).length() - 12.0) < 3.0,
		"and finishes at the 4-way's stop line coming down from the north (%.1f m from its middle)" % Vector2(finish.x - middle.x, finish.z - middle.z).length())
	check(finish.z < middle.z, "north of the middle")
	var into: Array = south.places.cities.filter(func(c): return c.entering)
	check(into.size() == 1 and into[0].name == "Kalona" and south.mile_at(into[0].station) > 13.0, "into Kalona near the end: %s" % [into])
	check(south.places.counties.size() == 1 and south.places.counties[0].entering == "Washington", "back into Washington County")
	check(south.road_end < south.length and south.road_end > south.finish_station + 100.0, "the road's closed a way past the 4-way")


func test_highway_22_east_from_wellman_to_the_4_way() -> void:
	var start := _crossroad(east, "8th Ave SW")
	check(not start.is_empty() and east.start_station > float(start.station) and east.start_station - float(start.station) < 20.0,
		"it starts just past the middle of 8th Ave in Wellman")
	check(east.tangent_at(east.start_station + 300.0).x > 0.9, "heading east")
	var spawn := east.start_station - Main.SPAWN_BEHIND_START
	check(not east.next_crossroad(spawn).name.begins_with("8th Ave"), "the next crossroad isn't the one it's in")
	var kalona := _crossroad(east, "1st St")
	check(absf(east.finish_station + 12.0 - float(kalona.station)) < 15.0, "it finishes at the 4-way in Kalona")


func test_the_ends_built_the_other_way_round() -> void:
	var x := Intersections.new()
	x.setup(south)
	check(not x.signal_heads.is_empty(), "the lights at Mormon Trek, at the start now")
	check(x.stop_signs == 4, "the 4-way's four stop signs at the finish (%d)" % x.stop_signs)
	var banners := {}
	for holder in x.get_children():
		for n in holder.get_children():
			if n is Label3D and String(n.text).contains("·"):
				banners[n.text] = south.nearest_station(holder.position, -1.0)
	check(banners.has("IOWA CITY  ·  START") and absf(banners["IOWA CITY  ·  START"] - south.start_station) < 3.0, "IOWA CITY · START over the start: %s" % [banners])
	check(banners.has("KALONA  ·  FINISH") and absf(banners["KALONA  ·  FINISH"] - south.finish_station) < 3.0, "KALONA · FINISH over the finish")
	x.free()
	x = Intersections.new()
	x.setup(east)
	check(x.signal_heads.is_empty() and x.stop_signs == 6, "Wellman's two-way stop and the 4-way: %d stop signs" % x.stop_signs)
	x.free()


func test_the_signs_for_the_way_back() -> void:
	var signs := Roadside.new()
	signs.setup(south)
	var found := {}
	for holder: Node in signs.get_children():
		for child: Node in holder.get_children():
			if child is Label3D:
				var s := south.nearest_station((holder as Node3D).position, -1.0)
				found[(child as Label3D).text] = minf(s, found.get((child as Label3D).text, INF))
	check(found.has("SOUTH") and found.SOUTH > south.start_station and found.SOUTH < south.start_station + 100.0,
		"a SOUTH 1 marker right out of Mormon Trek (%s)" % found.get("SOUTH", "none"))
	check(found.has("KALONA  15"), "and KALONA 15 past it: %s" % [found.keys().filter(func(k): return String(k).begins_with("KALONA"))])
	check(found.has("WASHINGTON\nCOUNTY"), "WASHINGTON COUNTY at the county line")
	check(found.has("KALONA\nPOP 2,630") and south.mile_at(found["KALONA\nPOP 2,630"]) > 13.0, "KALONA POP 2,630 coming into town")
	signs.free()


func test_the_county_line_the_other_way() -> void:
	var car := Car.new()
	car.stats = CarStats.preset("legend")
	car.route = south
	var cops := Cops.new()
	var run := Run.new()
	var traffic := Traffic.new()
	cops.setup(south, car, run, traffic, 3)
	check(cops.county_at(south.start_station) == "Johnson" and cops.county_at(south.finish_station) == "Washington",
		"Johnson County first, then Washington")
	var counties: Array = cops.traps.map(func(t): return t.county)
	check(counties.count("Johnson") == 3 and counties.count("Washington") == 1, "three Johnson deputies and one Washington: %s" % [counties])
	check(cops.traps.all(func(t): return cops.county_at(t.station) == t.county), "each in its own county")
	cops.free()
	run.free()
	traffic.free()
	car.free()


func test_practice_from_the_far_end() -> void:
	var main := Main.new()
	main.route = south
	var starts: Array = main._practice_starts()
	check(starts[0][1] == "Iowa City (Mormon Trek Blvd)", "practice starts at Iowa City first: %s" % starts[0][1])
	check(starts.size() >= 15 and String(starts[1][1]).begins_with("Mile 1"), "then every mile")
	main.route = hw1
	check(main._practice_starts()[0][1] == "Kalona (the 4-way stop)", "(Kalona going north)")
	main.free()


func test_its_own_records() -> void:
	check(Routes.records_key("1993 Acura Legend", "highway1_south") == "highway1_south|1993 Acura Legend", "the way back's records are its own")


func _crossroad(route: RouteData, name: String) -> Dictionary:
	for c: Dictionary in route.crossroads:
		if c.name == name:
			return c
	return {}
