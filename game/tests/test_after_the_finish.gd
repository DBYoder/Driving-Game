extends "res://tests/test_case.gd"
## Over the finish line (and on into town): the score's final, a chase ends, and the road
## that runs on past the finish ends in a barricade traffic stops for.

const DT := 1.0 / 60.0


class World:
	var root: Node3D
	var route: RouteData
	var car: Car
	var tracker: RunTracker
	var run: Run
	var traffic: Traffic
	var cops: Cops

	func _init(route_id := "highway1") -> void:
		route = RouteData.load_from(Routes.dir(route_id))
		root = Node3D.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(root)
		car = Car.new()
		root.add_child(car)
		car.setup(CarStats.preset("legend"), route)
		tracker = RunTracker.new(route.start_station, route.finish_station, "Test car", "")
		run = Run.new()
		root.add_child(run)
		run.setup(car, tracker)
		traffic = Traffic.new()
		root.add_child(traffic)
		traffic.setup(route, car, run)
		cops = Cops.new()
		root.add_child(cops)
		cops.setup(route, car, run, traffic, 1)

	## Put the car at `station` and tick the run once.
	func at(station: float) -> void:
		car.place_at(station)
		car.station = station
		run._physics_process(DT)

	func destroy() -> void:
		root.free()


func test_points_only_count_on_the_clock() -> void:
	var w := World.new()
	w.at(w.route.start_station - 3.0)
	check(not w.run.score.open, "behind the line: no points yet")
	w.at(w.route.start_station + 1.0)
	check(w.tracker.running() and w.run.score.open, "over the line: scoring")
	w.run.score.add("Mailbox", 50)
	check(w.run.score.pot == 50, "a mailbox scores")
	w.at(w.route.finish_station + 1.0)
	check(w.tracker.state == RunTracker.State.FINISHED and not w.run.score.open, "over the finish: the score's final")
	var final := w.run.score.banked
	w.run.score.add("Mailbox", 50)
	w.run.score.add("Corn", 5, false)
	check(w.run.score.banked == final and w.run.score.pot == 0 and w.run.score.multiplier == 0,
		"flattening mailboxes in town after the finish scores nothing (no combo stuck on the screen)")
	w.destroy()


func test_a_chase_ends_at_the_finish() -> void:
	var w := World.new()
	w.at(w.route.finish_station - 200.0)
	w.cops.chase_from_behind()
	check(w.cops.chasing() and w.cops.siren.on, "a deputy on your tail")
	w.cops._physics_process(DT)
	check(w.cops.chasing(), "still on your tail short of the finish")
	w.tracker.state = RunTracker.State.FINISHED
	w.cops._physics_process(DT)
	check(not w.cops.chasing() and not w.cops.siren.on, "made it: the deputy lets you go, siren off")
	check(w.cops.status() == "", "nothing on the HUD about them")
	w.destroy()


func test_the_road_ends_at_a_barricade() -> void:
	for id: String in ["highway1", "highway22"]:
		var r := RouteData.load_from(Routes.dir(id))
		check(r.road_end > r.finish_station + 1900.0 and r.road_end < r.length,
			"%s: the road's closed %.0f m past the finish, short of its end" % [id, r.road_end - r.finish_station])
		var landmarks := Landmarks.new()
		landmarks.setup(r)
		var end := r.position_at(r.road_end)
		var wall := landmarks.building_boxes(end, 5.0).filter(func(b): return (b[1] as Vector3).x > 10.0)
		check(wall.size() == 1, "%s: a solid barricade there, from ditch to ditch" % id)
		if wall.size() == 1:
			var across: Vector3 = (wall[0][0] as Transform3D).basis.x
			check(absf(across.dot(r.right_at(r.road_end))) > 0.99, "%s: square across the road" % id)
		var signs := landmarks.get_children().filter(func(n): return n is Label3D and n.text == "ROAD\nCLOSED")
		check(signs.size() == 2, "%s: ROAD CLOSED, both ways" % id)
		landmarks.free()


func test_traffic_stops_short_of_the_end_of_the_road() -> void:
	var w := World.new()
	w.at(w.route.finish_station + 100.0)
	w.traffic._add("car", 1.0, w.route.road_end - 200.0)
	w.traffic._add("semi", 1.0, w.route.road_end - 100.0)
	check(w.traffic.vehicles.size() == 2, "two vehicles heading for the end of the road")
	for i in 60 * 40:
		for v: Traffic.Vehicle in w.traffic.vehicles:
			w.traffic._drive(v, DT)
	for v: Traffic.Vehicle in w.traffic.vehicles:
		var front: float = v.station + float(Traffic.KINDS[v.kind].length) / 2.0
		check(front <= w.route.road_end - Traffic.END_GAP + 0.01 and v.speed < 0.05,
			"the %s stops short of the barricade (%.1f m short)" % [v.kind, w.route.road_end - front])
		var forward := -v.node.global_transform.basis.z
		check(forward.is_finite() and forward.length() > 0.9, "still facing up the road")
	w.traffic._add("car", 1.0, w.route.road_end - 20.0)
	check(w.traffic.vehicles.size() == 2, "and none turns up past it")
	w.destroy()


func test_driving_on_tucks_the_results_away() -> void:
	var w := World.new()
	var camera := ChaseCamera.new()
	w.root.add_child(camera)
	var hud := Hud.new()
	w.root.add_child(hud)
	hud.setup(w.route, w.car, w.run, camera)
	w.at(w.route.start_station + 1.0)
	w.at(w.route.finish_station + 1.0)
	var tick := func(seconds: float, gas: float) -> void:
		w.car.throttle = gas
		for i in int(seconds * 60.0):
			hud._process(DT)
	tick.call(0.5, 1.0)
	check(hud._results.visible and not hud.results_tucked, "over the finish: the results come up, gas or not")
	tick.call(Hud.RESULTS_HOLD + 1.0, 1.0)
	check(hud.results_tucked and not hud._results.visible, "still on the gas a few seconds on: they tuck away (driving on into town)")
	check(hud._message.text.begins_with("IOWA CITY!"), "to a line at the top (%s)" % hud._message.text)
	tick.call(0.5, 0.0)
	check(hud.results_tucked, "a moment off the gas doesn't bring them back")
	tick.call(Hud.OFF_GAS_TO_SHOW + 0.2, 0.0)
	check(not hud.results_tucked and hud._results.visible and hud._message.text == "", "off the gas: back they come")
	w.run.restart()
	tick.call(0.2, 1.0)
	check(not hud.results_tucked and not hud._results.visible, "a new run: nothing left over")
	w.destroy()


func test_distances_like_a_road_sign() -> void:
	check(Hud.distance_text(2253.0) == "1.4 mi", "1.4 mi")
	check(Hud.distance_text(0.1 * RouteData.MILE_M) == "0.1 mi", "a tenth of a mile")
	check(Hud.distance_text(91.0) == "300 ft", "close: in feet, to the nearest 50 (%s)" % Hud.distance_text(91.0))
	check(Hud.distance_text(4.0) == "50 ft", "never 0 ft")


func test_typing_a_name_doesnt_drive_the_car() -> void:
	var w := World.new()
	var driver := PlayerDriver.new()
	Input.action_press("accelerate")
	Input.action_press("steer_right")
	driver.update(w.car, DT)
	check(w.car.throttle == 1.0 and w.car.steer == 1.0, "W and D drive")
	var box := LineEdit.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(box)
	box.grab_focus()
	driver.update(w.car, DT)
	check(w.car.throttle == 0.0 and w.car.steer == 0.0, "but not while typing a name for the leaderboard")
	box.release_focus()
	driver.update(w.car, DT)
	check(w.car.throttle == 1.0, "done typing: they drive again")
	Input.action_release("accelerate")
	Input.action_release("steer_right")
	box.free()
	w.destroy()
