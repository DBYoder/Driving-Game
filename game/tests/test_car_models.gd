extends "res://tests/test_case.gd"
## The car models under stress: tires never pass through the bodywork, whatever the
## steering, suspension, lean or dents (ModelCheck), and the wheel arches that make room
## for them stay below the beltline.

const MODELS := ["windstar", "tercel", "legend", "cruiser_washington", "cruiser_johnson"]


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


func test_the_check_finds_a_tire_in_the_body() -> void:
	var model := _model("legend")
	check(ModelCheck.tire_clips(model) == [0, 0, 0, 0], "at rest nothing clips")
	var pivot: Node3D = model.wheel_pivots()[0]
	pivot.position.y += 0.35  # shoved up into the fender
	check(ModelCheck.tire_clips(model)[0] > 0, "a tire shoved up into the fender is caught")
	pivot.position.y -= 0.35
	pivot.position.x += 0.35  # and out through the side
	check(ModelCheck.tire_clips(model)[0] > 0, "and one pushed out through the side")
	model.free()


func test_no_tire_ever_goes_through_the_body() -> void:
	for id: String in MODELS:
		var clean := ModelCheck.sweep(CarStats.preset(id), false)
		check(clean.clips == 0, "%s: %d clips in %d poses (worst %s)" % [id, clean.clips, clean.states, clean.worst])
		var dented := ModelCheck.sweep(CarStats.preset(id), true)
		check(dented.clips == 0, "%s beaten in from all round: %d clips (worst %s)" % [id, dented.clips, dented.worst])


func test_the_arches_stay_below_the_beltline() -> void:
	for id: String in MODELS:
		var stats := CarStats.preset(id)
		var model := _model(id)
		var beltline: float = CarModel.cabin_points(stats).belt
		for arch: Dictionary in model._arches:
			check(arch.top < beltline - 0.03, "%s: arch top %.2f m under the beltline at %.2f m" % [id, arch.top, beltline])
			check(arch.half < stats.wheel_radius + 0.12, "%s: the arch hugs the tire (%.2f m for a %.2f m tire)" % [
				id, arch.half, stats.wheel_radius])
		model.free()


func test_the_wheels_stay_on_the_ground_as_drawn() -> void:
	# The drawn wheels stop VISUAL_BUMP above where they rest, so a hard landing pushes
	# them into the road a little rather than up through the fenders: check that's small
	# in normal driving (the spring a few cm past its resting compression).
	for id: String in ["windstar", "tercel", "legend"]:
		var stats := CarStats.preset(id)
		var static_compression := stats.mass * 9.8 / (4.0 * stats.spring)
		check(CarModel.VISUAL_BUMP > 0.03, "%s: the wheels can still move up %.0f cm over bumps" % [id, CarModel.VISUAL_BUMP * 100.0])
		check(static_compression < stats.rest_length * 0.7, "%s: the car rests on its springs, not the bump stops" % id)


func test_the_glass_sits_flush_in_the_body() -> void:
	# The side windows are part of the greenhouse's sides, not panels stuck on: every bit of
	# side glass lies on its surface.
	for id: String in MODELS:
		var model := _model(id)
		var glass: PackedVector3Array = model._rest.glass
		var mirror_z := -model._stats.body_size.z / 2.0 + float(CarModel.SHAPES[model._stats.style].mirror[0])
		var worst := 0.0
		for t in range(0, glass.size(), 3):
			var n := (glass[t + 1] - glass[t]).cross(glass[t + 2] - glass[t]).normalized()
			if absf(n.x) < 0.9 or absf(glass[t].z - mirror_z) < 0.3:
				continue  # the windshield and back glass (facing along the car), and the mirrors' glass
			for v in [glass[t], glass[t + 1], glass[t + 2]]:
				worst = maxf(worst, absf(absf(v.x) - model._half(model._pieces.cabin, v.y, v.z)))
		check(worst < 0.005, "%s: side glass %.3f m off the greenhouse's side" % [id, worst])
		model.free()


func test_the_windstar_door_lies_on_the_body() -> void:
	var model := _model("windstar")
	var door: Node3D = model._parts.filter(func(p): return not p.node.get_parent() is Node3D or p.node.position.x > 0.5)[0].node
	var worst := 0.0
	var count := 0
	for child in door.get_children():
		if child is MeshInstance3D:
			var verts: PackedVector3Array = (child as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := door.position + v
				var off := INF
				for piece: Dictionary in [model._pieces.body, model._pieces.cabin]:
					off = minf(off, absf(absf(p.x) - model._half(piece, p.y, p.z)))
				worst = maxf(worst, off)
				count += 1
	check(count > 50, "the sliding door is built (%d points)" % count)
	# The panel stands PATCH_OFFSET off the body; its handle twice that.
	check(worst < CarModel.PATCH_OFFSET * 2.0 + 0.003, "and lies on the van's side, %.3f m out at most" % worst)
	model.free()


func test_nothing_stands_out_past_the_sides_but_the_mirrors() -> void:
	for id: String in MODELS:
		var model := _model(id)
		var mirror: Array = CarModel.SHAPES[model._stats.style].mirror
		var mirror_z := -model._stats.body_size.z / 2.0 + float(mirror[0])
		var half := model._stats.body_size.x / 2.0
		var worst := 0.0
		var where := Vector3.ZERO
		var tris := ModelCheck.body_triangles(model)
		for v in tris:
			if absf(v.z - mirror_z) < 0.25:
				continue
			if absf(v.x) - half > worst:
				worst = absf(v.x) - half
				where = v
		check(worst < 0.04, "%s: %.2f m out past the side at %s" % [id, worst, where])
		check(tris.size() / 3 < 8000, "%s: %d triangles (a budget for old laptops)" % [id, tris.size() / 3])
		model.free()
