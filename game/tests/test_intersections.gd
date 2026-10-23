extends "res://tests/test_case.gd"
## Phase 7: the run goes from the 4-way stop in Kalona to the first stop light in Iowa
## City; skid marks and dust; clouds.

const Main := preload("res://scripts/main.gd")

var route := RouteData.load_from("res://data/routes/highway1")


func _crossroad(street_name: String) -> Dictionary:
	for c: Dictionary in route.crossroads:
		if c.name == street_name:
			return c
	return {}


func test_the_run_is_stop_line_to_stop_line() -> void:
	var e_ave := _crossroad("E Ave")
	var mormon := _crossroad("Mormon Trek Blvd")
	check(e_ave.route == "IA 22" and e_ave.side == "both", "E Ave is IA 22, crossing both ways")
	check_near(e_ave.station - route.start_station, Intersections.STOP_LINE, 2.0, "the start is the stop line before E Ave")
	check(absf(mormon.station - (route.finish_station + Intersections.STOP_LINE)) < 15.0,
		"the finish is the stop line before Mormon Trek (%.0f m short)" % (mormon.station - route.finish_station))
	check_near(route.mile_at(route.finish_station), 15.37, 0.05, "15.4 miles")
	check(route.length - route.finish_station > 250.0, "road on past the finish")


func test_you_start_stopped_at_the_stop_sign() -> void:
	for id: String in CarStats.CARS:
		var stats := CarStats.preset(id)
		var bumper: float = Main.SPAWN_BEHIND_START - stats.body_size.z / 2.0
		check(bumper > 0.0 and bumper < 1.2, "%s: the front bumper %.2f m short of the line" % [id, bumper])


func test_the_four_way_stop() -> void:
	# (Laid out like the real one: tests/test_junction.gd.)
	var x := Intersections.new()
	x.setup(route)
	check(x.start_crossroad.name == "E Ave", "the start intersection is E Ave")
	check(x.stop_signs == 4, "a stop sign each way in (%d)" % x.stop_signs)
	check(x.approaches(route.start_station + Intersections.STOP_LINE).is_empty(), "E Ave's own ends are gone: the junction paves it")
	check(x.buggy != null, "a buggy waits its turn")
	if x.buggy:
		var center := route.start_station + Intersections.STOP_LINE
		var c := route.position_at(center)
		var lateral := (x.buggy.position - c).dot(route.right_at(center))
		check(lateral > 6.0 and lateral < 16.0, "on the right, at E Ave's stop line (%.1f m out)" % lateral)
	var paint := x.get_children().filter(func(n): return n.has_meta("paint")).size()
	check(paint >= 4, "stop lines across every lane at the lights (%d)" % paint)
	x.free()


func test_the_stop_light_cycles() -> void:
	var x := Intersections.new()
	x.setup(route)
	check(x.finish_crossroad.name == "Mormon Trek Blvd", "the finish intersection is Mormon Trek")
	check(x.signal_heads.size() >= 6, "signal heads over IA 1 and Mormon Trek (%d)" % x.signal_heads.size())
	check(x.ia1_light() == "green", "IA 1 starts green")
	var seen := {}
	var both_red := false
	for i in 120:
		x._process(0.5)
		var colors := Intersections._lights_for(x._phase())
		seen[colors[0]] = true
		both_red = both_red or colors == ["red", "red"]
		check(not (colors[0] == "green" and colors[1] == "green"), "never green both ways")
	check(seen.size() == 3, "IA 1 goes green, yellow and red (%s)" % [seen.keys()])
	check(both_red, "with a moment of all red between")
	var lit := 0
	for head: Dictionary in x.signal_heads:
		for lamp: MeshInstance3D in head.lamps:
			var m: StandardMaterial3D = lamp.material_override
			lit += int(m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	check(lit == x.signal_heads.size(), "one lamp lit per head (%d of %d)" % [lit, x.signal_heads.size()])
	x.free()


func test_the_start_and_finish_get_their_own_signs() -> void:
	check(Intersections.at_line(route, _crossroad("E Ave")), "Roadside leaves E Ave to the 4-way stop")
	check(Intersections.at_line(route, _crossroad("Mormon Trek Blvd")), "and Mormon Trek to the light")
	check(not Intersections.at_line(route, _crossroad("W H Ave")), "but signs the rest")


func test_sliding_tires_leave_marks() -> void:
	var car := Car.new()
	car.stats = CarStats.preset("legend")
	var w := Car.Wheel.new()
	car.wheels.append(w)
	car.linear_velocity = Vector3(0, 0, -20)
	var marks := TireMarks.new()
	marks.setup(car)
	w.grounded = true
	w.surface = "asphalt"
	w.normal = Vector3.UP
	w.slide = 1.0  # gripping
	for i in 10:
		w.contact = Vector3(0, 0, -i * 0.5)
		marks._physics_process(1.0 / 60.0)
	check(marks.count == 0, "no marks while the tire grips")
	w.slide = 6.0  # sliding
	for i in 10:
		w.contact = Vector3(0, 0, -i * 0.5)
		marks._physics_process(1.0 / 60.0)
	check(marks.count == 9, "a mark every half meter of a slide (%d)" % marks.count)
	w.surface = "grass"
	w.slide = 2.0  # enough to rut the grass
	for i in 10:
		w.contact = Vector3(0, 0, -5.0 - i * 0.5)
		marks._physics_process(1.0 / 60.0)
	check(marks.count >= 18, "ruts in the grass at a smaller slide (%d)" % marks.count)
	for i in TireMarks.MAX_MARKS:
		marks._add_mark(Vector3.ZERO, Vector3(0, 0, 1), Vector3.UP, Color.BLACK, 1.0)
	check(marks._marks.multimesh.visible_instance_count == TireMarks.MAX_MARKS, "old marks are reused past the limit")
	marks.clear()
	check(marks.count == 0 and marks._marks.multimesh.visible_instance_count == 0, "a new run starts clean")
	marks.free()
	car.free()


func test_every_sky_has_its_clouds() -> void:
	var summer := Condition.preset("summer")
	var storm := Condition.preset("storm")
	var night := Condition.preset("night")
	check(summer.cloud_cover > 0.2 and summer.cloud_cover < 0.5, "summer: fair-weather clouds")
	check(storm.cloud_cover > 0.85, "a storm: overcast")
	check(night.stars == 1.0 and summer.stars == 0.0, "stars only at night")
	for id: String in Condition.IDS:
		var c := Condition.preset(id)
		check(c.cloud_color.get_luminance() >= c.cloud_shade.get_luminance(), "%s: clouds lit on top" % id)
