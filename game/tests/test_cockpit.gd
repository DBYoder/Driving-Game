extends "res://tests/test_case.gd"
## The in-car view: in every car the driver can see the speedometer, the tachometer and
## the radio past the steering wheel and the bodywork, and the gauges follow the car.

const CARS := ["windstar", "tercel", "legend"]
var route := RouteData.load_from("res://data/route")


func _model(id: String) -> CarModel:
	var stats := CarStats.preset(id)
	var wheels: Array = []
	for z: float in [-stats.wheelbase / 2.0, stats.wheelbase / 2.0]:
		for x: float in [-stats.track / 2.0, stats.track / 2.0]:
			var w := Car.Wheel.new()
			w.mount = Vector3(x, stats.mount_y, z)
			w.front = z < 0.0
			w.spring_length = stats.rest_length
			w.grounded = true
			wheels.append(w)
	var model := CarModel.new()
	model.build(stats, wheels)
	model.update(wheels, 0.0, Vector3.ZERO, 0.0, 1.0)
	return model


## Whether the driver sees `point` (in the model's space): it's in the view, and nothing
## on the way there from their eyes is solid (only faces turned toward the eyes count:
## the renderer culls the others).
func _sees(eye: Transform3D, point: Vector3, blockers: PackedVector3Array) -> String:
	var local := eye.basis.inverse() * (point - eye.origin)
	var up := rad_to_deg(atan2(local.y, -local.z))
	var across := rad_to_deg(atan2(local.x, -local.z))
	var half_across := rad_to_deg(atan(tan(deg_to_rad(Cockpit.FOV / 2.0)) * 16.0 / 9.0))
	if local.z >= 0.0 or absf(up) > Cockpit.FOV / 2.0 * 0.95 or absf(across) > half_across * 0.95:
		return "out of view (%.0f° up, %.0f° across)" % [up, across]
	var short := point.lerp(eye.origin, 0.01 / eye.origin.distance_to(point))
	for t in range(0, blockers.size(), 3):
		var a := blockers[t]
		var facing := (blockers[t + 2] - a).cross(blockers[t + 1] - a).dot(eye.origin - a) > 0.0
		if facing and Geometry3D.segment_intersects_triangle(eye.origin, short, a, blockers[t + 1], blockers[t + 2]) != null:
			return "blocked near %s" % blockers[t]
	return ""


func test_the_driver_sees_the_gauges() -> void:
	for id: String in CARS:
		var stats := CarStats.preset(id)
		var model := _model(id)
		var body := model.body_node()
		var cockpit := Cockpit.new()
		body.add_child(cockpit)
		cockpit.build(stats)
		model.show_cabin_floor(false)
		for screen in cockpit.screens():
			screen.visible = false  # the gauges themselves don't block the view of the gauges
		var blockers := ModelCheck.body_triangles(model)
		ModelCheck._collect(cockpit, body.transform * cockpit.transform, blockers)
		var eye := body.transform * cockpit.eye
		var targets := {"the radio": Gauges.RADIO.get_center()}
		for dial: Dictionary in Gauges.LAYOUTS[id].dials:
			if dial.kind == "speed":
				targets["the speedometer"] = dial.at
				targets["the odometer"] = dial.at + Vector2(0, dial.r * 0.25)
				targets["the speedometer at 60"] = dial.at + Vector2.from_angle(Gauges._angle(60.0 / dial.max)) * dial.r * 0.7
			elif dial.kind == "tach":
				targets["the tachometer"] = dial.at
		check(targets.has("the speedometer"), "%s has a speedometer" % id)
		for what: String in targets:
			var why := _sees(eye, body.transform * cockpit.gauge_point(targets[what]), blockers)
			check(why == "", "%s: the driver can't see %s: %s" % [id, what, why])
		# Without hiding the top of the body under the cabin, it would hide the dash (the
		# minivan's dash stands above its beltline).
		if stats.style != "minivan":
			model.show_cabin_floor(true)
			var with_floor := ModelCheck.body_triangles(model)
			var speedo: Vector2 = targets["the speedometer"]
			check(_sees(eye, body.transform * cockpit.gauge_point(speedo), with_floor) != "",
				"%s: the check would notice the floor in the way" % id)
		model.free()


func test_the_eyes_are_inside_the_cabin() -> void:
	for id: String in CARS:
		var stats := CarStats.preset(id)
		var cockpit := Cockpit.new()
		cockpit.build(stats)
		var cabin: Array = CarModel.SHAPES[stats.style].cabin
		var l := stats.body_size.z
		var eye := cockpit.eye.origin
		check(eye.y > float(cabin[0][1]) + 0.15 and eye.y < float(cabin[1][1]) - 0.15,
			"%s: the eyes are %.2f m up, between the beltline (%.2f) and the roof (%.2f)" % [id, eye.y, cabin[0][1], cabin[1][1]])
		check(eye.z > -l / 2.0 + float(cabin[1][0]) * l, "%s: and behind the windshield" % id)
		check(absf(eye.x) > 0.25 and eye.x < 0.0, "%s: the driver sits on the left" % id)
		cockpit.free()


func test_the_gauges_follow_the_car() -> void:
	var car := Car.new()
	car.stats = CarStats.preset("legend")
	car.route = route
	var cockpit := Cockpit.new()
	cockpit.build(car.stats)
	var g := cockpit.gauges

	car.station = 2000.0
	cockpit._read(car, 30.0, 1.0 / 60.0)
	check_near(g.speed_mph, 30.0 * Hud.MPH, 0.1, "the speedometer reads the car's speed")
	check(g.gear == "D", "in drive")
	var fuel_early := g.fuel
	var temp_cold := g.temp
	check(g.trip > 0.5 and g.trip < 2.0, "the trip meter counts the miles from Kalona (%.1f)" % g.trip)
	check_near(g.odometer, Cockpit.CARS.legend.odometer + g.trip, 0.01, "the odometer too")

	car.station = 20000.0
	for i in 60 * 60:  # a minute's driving warms the engine up
		cockpit._read(car, 30.0, 1.0 / 60.0)
	check(g.fuel < fuel_early - 0.2, "the fuel goes down on the way (%.2f -> %.2f)" % [fuel_early, g.fuel])
	check(g.temp > temp_cold + 0.2, "the engine warms up (%.2f -> %.2f)" % [temp_cold, g.temp])
	var warm := g.temp
	check(not g.lights.check, "no check engine light on a healthy car")

	car.health = car.stats.durability * 0.25
	cockpit._read(car, 30.0, 1.0 / 60.0)
	check(g.temp > warm + 0.2 and g.lights.check, "a beaten-up car runs hot, check engine on (%.2f)" % g.temp)

	car.steer_angle = 0.3
	car.headlights = true
	car.handbrake = true
	cockpit._read(car, -3.0, 1.0 / 60.0)  # backing up
	check_near(cockpit._wheel_spin.rotation.z, 0.3 * Cockpit.WHEEL_RATIO, 0.001, "the steering wheel turns with the wheels")
	check(g.gear == "R", "in reverse")
	check(g.lights.beam and g.lights.brake, "headlights and handbrake show on the dash")

	Cockpit.clock_start = 12 * 60 + 59
	Cockpit.clock_since = Time.get_ticks_msec()
	cockpit._read(car, 0.0, 1.0 / 60.0)
	check(g.clock == "12:59", "the dash clock (%s)" % g.clock)
	Cockpit.clock_since -= 60000
	cockpit._read(car, 0.0, 1.0 / 60.0)
	check(g.clock == "1:00", "a minute later (%s)" % g.clock)

	car.free()
	cockpit.free()
