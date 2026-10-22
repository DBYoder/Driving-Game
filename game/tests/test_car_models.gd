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
		var beltline := -INF
		for p: Array in CarModel.SHAPES[stats.style].cabin:
			beltline = maxf(beltline, -INF if p[1] > 0.5 else p[1])
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
