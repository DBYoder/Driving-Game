extends "res://tests/test_case.gd"
## The in-car view: in every car the driver can see the speedometer, the tachometer and
## the radio past the steering wheel and the bodywork, nowhere can they see out through
## the bodywork (between the dash and the hood, under the dash, past the doors), the view
## ahead is clear, and the gauges follow the car.

const CARS := ["windstar", "tercel", "legend"]
var route := RouteData.load_from("res://data/routes/highway1")


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


## Everything in the car (the model's space) as triangles: [a, b, c, drawn (shown, so the
## renderer draws its front), bodywork (the body and its parts, not the cockpit), glass].
func _faces(node: Node, xf: Transform3D, glass: Material, shown: bool, cockpit: bool, out: Array) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var cxf: Transform3D = xf * child.transform
		var drawn: bool = shown and child.visible
		var inside: bool = cockpit or child is Cockpit
		if child is MeshInstance3D and child.mesh and not (child.has_meta("no_clip_check") and not inside):
			var mesh: Mesh = child.mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx = arrays[Mesh.ARRAY_INDEX]
				var order: Array = range(verts.size()) if idx == null or (idx as PackedInt32Array).is_empty() else Array(idx)
				var material: Material = child.material_override if child.material_override else mesh.surface_get_material(s)
				for k in range(0, order.size(), 3):
					out.append([cxf * verts[order[k]], cxf * verts[order[k + 1]], cxf * verts[order[k + 2]], drawn,
						not inside, material == glass])
		_faces(child, cxf, glass, drawn, inside, out)


## Rays from the driver's eyes across the whole view (as wide as a phone held sideways)
## that see out through the bodywork. Each piece of the body is closed, its faces facing
## out, so going through one facing the eyes is going into a piece and through one facing
## away is coming out of it; starting inside the cabin, a ray that's out of the car before
## it gets to anything drawn, and got out through paint and not glass, sees through the
## car. (The top of the body under the cabin is hidden in the in-car view: going through
## it just goes from the cabin into the body.) Each [degrees right, degrees up, where it
## got out].
func _see_through(model: CarModel, eye: Transform3D) -> Array:
	var faces := []
	_faces(model, Transform3D(), model._glass, true, false, faces)
	const ACROSS := 76
	const DOWN := 34
	var tan_v := tan(deg_to_rad(Cockpit.FOV / 2.0))
	var tan_h := tan_v * 2.2
	var inv := eye.affine_inverse()
	# Each face into the cells of the view it covers (all of them, if it reaches behind the eyes).
	var cells := []
	cells.resize(ACROSS * DOWN)
	for i in cells.size():
		cells[i] = []
	var everywhere := []
	for f: Array in faces:
		f.append((f[2] - f[0]).cross(f[1] - f[0]).dot(eye.origin - f[0]) > 0.0)  # [6]: facing the eyes
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := false
		for k in 3:
			var p: Vector3 = inv * (f[k] as Vector3)
			if p.z > -0.02:
				behind = true
				break
			var q := Vector2(p.x / -p.z / tan_h, p.y / -p.z / tan_v)
			lo = lo.min(q)
			hi = hi.max(q)
		if behind:
			everywhere.append(f)
			continue
		if hi.x < -1.0 or lo.x > 1.0 or hi.y < -1.0 or lo.y > 1.0:
			continue
		for cx in range(clampi(floori((lo.x + 1.0) / 2.0 * ACROSS), 0, ACROSS - 1), clampi(floori((hi.x + 1.0) / 2.0 * ACROSS), 0, ACROSS - 1) + 1):
			for cy in range(clampi(floori((lo.y + 1.0) / 2.0 * DOWN), 0, DOWN - 1), clampi(floori((hi.y + 1.0) / 2.0 * DOWN), 0, DOWN - 1) + 1):
				cells[cy * ACROSS + cx].append(f)
	var out := []
	for cy in DOWN:
		for cx in ACROSS:
			var q := Vector2((cx + 0.5) / ACROSS * 2.0 - 1.0, (cy + 0.5) / DOWN * 2.0 - 1.0)
			var dir := (eye.basis * Vector3(q.x * tan_h, q.y * tan_v, -1.0)).normalized()
			var seen := INF
			var crossings := []
			for list: Array in [cells[cy * ACROSS + cx], everywhere]:
				for f: Array in list:
					var hit = Geometry3D.ray_intersects_triangle(eye.origin, dir, f[0], f[1], f[2])
					if hit == null:
						continue
					var t: float = (hit - eye.origin).dot(dir)
					if f[3] and f[6]:
						seen = minf(seen, t)
					if f[4]:
						crossings.append([t, f[6], f[5], hit])
			crossings.sort_custom(func(a, b): return a[0] < b[0])
			var depth := 1  # in the cabin
			for c: Array in crossings:
				if c[0] >= seen - 0.003:
					break
				depth += 1 if c[1] else -1
				if depth <= 0:
					if not c[2]:
						out.append([rad_to_deg(atan(q.x * tan_h)), rad_to_deg(atan(q.y * tan_v)) + Cockpit.EYE_PITCH_DEG, c[3]])
					break
	return out


func test_no_seeing_out_through_the_bodywork() -> void:
	for id: String in CARS:
		var stats := CarStats.preset(id)
		var model := _model(id)
		var body := model.body_node()
		var cockpit := Cockpit.new()
		body.add_child(cockpit)
		cockpit.build(stats)
		cockpit.active = true
		model.show_cabin_floor(false)
		var gaps := _see_through(model, body.transform * cockpit.eye)
		check(gaps.is_empty(), "%s: %d rays from the driver's seat see out through the bodywork%s" % [id, gaps.size(),
			"" if gaps.is_empty() else ", the first %.0f° right, %.0f° up, through %s" % gaps[0]])
		# And the check sees one when there is: with no cockpit, in under the hood.
		var eye := body.transform * cockpit.eye
		cockpit.free()
		check(not _see_through(model, eye).is_empty(), "%s: the check would notice no dash" % id)
		model.free()


func test_the_view_ahead_is_clear() -> void:
	for id: String in CARS:
		var stats := CarStats.preset(id)
		var model := _model(id)
		var body := model.body_node()
		var cockpit := Cockpit.new()
		body.add_child(cockpit)
		cockpit.build(stats)
		cockpit.active = true
		model.show_cabin_floor(false)
		var faces := []
		_faces(model, Transform3D(), model._glass, true, false, faces)
		var eye := body.transform * cockpit.eye
		var blocked := []
		for yaw in range(-20, 21, 5):
			for up in [0.0, 4.0]:  # level and a little up: the road ahead and the sky over it
				var dir := Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(up)).rotated(Vector3.UP, deg_to_rad(-yaw))
				dir = body.transform.basis * dir
				for f: Array in faces:
					var facing: bool = (f[2] - f[0]).cross(f[1] - f[0]).dot(eye.origin - f[0]) > 0.0
					if f[3] and facing and Geometry3D.ray_intersects_triangle(eye.origin, dir, f[0], f[1], f[2]) != null:
						blocked.append("%d° right, %.0f° up" % [yaw, up])
						break
		check(blocked.is_empty(), "%s: something's in the way straight ahead: %s" % [id, blocked])
		model.free()


func test_the_eyes_are_inside_the_cabin() -> void:
	for id: String in CARS:
		var stats := CarStats.preset(id)
		var cockpit := Cockpit.new()
		cockpit.build(stats)
		var cabin := CarModel.cabin_points(stats)
		var eye := cockpit.eye.origin
		check(eye.y > float(cabin.windshield_base.y) + 0.15 and eye.y < float(cabin.roof_front.y) - 0.15,
			"%s: the eyes are %.2f m up, between the beltline (%.2f) and the roof (%.2f)" % [id, eye.y,
				cabin.windshield_base.y, cabin.roof_front.y])
		check(eye.z > float(cabin.roof_front.x), "%s: and behind the windshield" % id)
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
