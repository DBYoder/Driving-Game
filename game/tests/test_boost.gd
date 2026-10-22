extends "res://tests/test_case.gd"


func test_near_misses_fill_the_meter_up_to_full() -> void:
	var b := Boost.new()
	var filled := []
	b.filled.connect(func(amount): filled.append(amount))
	b.fill(Boost.NEAR_MISS)
	check_near(b.meter, Boost.NEAR_MISS, 0.001, "one near miss")
	b.fill(Boost.NEAR_MISS)
	b.fill(Boost.NEAR_MISS)
	check(b.full() and b.meter == 1.0, "three near misses fill it, and it stops at full")
	b.fill(Boost.CLOSE_PASS)
	check(filled.size() == 3, "nothing to show for filling a full meter")


func test_a_full_meter_burns_for_four_seconds() -> void:
	var b := Boost.new()
	check(not b.update(true, 0.1), "nothing to burn")
	b.fill(1.0)
	var burned := 0.0
	while b.update(true, 0.05):
		burned += 0.05
	check_near(burned, Boost.BURN_SECONDS, 0.06, "seconds of boost from a full meter")
	b.fill(0.5)
	check(not b.update(false, 0.05) and b.meter == 0.5, "let go: it keeps what's left")
	b.reset()
	check(b.meter == 0.0 and not b.active, "a new run starts empty")


func test_boosting_raises_the_top_speed() -> void:
	for id: String in ["windstar", "tercel", "legend"]:
		var s := CarStats.preset(id)
		var boosted := Boost.top_speed(s.top_speed)
		check(boosted > s.top_speed + 10.0 and boosted <= Boost.MAX_SPEED, "%s boosts to %.0f m/s" % [id, boosted])
		check(s.drive_force(s.top_speed) == 0.0, "%s: no push at its usual top speed" % id)
		check(s.drive_force(s.top_speed, boosted - s.top_speed) > 0.0, "%s: still pulling there while boosting" % id)


func test_deputies_are_a_little_faster_than_you_unless_you_boost() -> void:
	var cruiser := CarStats.preset("cruiser_johnson")
	for id: String in ["windstar", "tercel"]:
		var s := CarStats.preset(id)
		var chase := Pursuit.chase_speed(cruiser, s)
		check(chase > s.flat_out_speed() + 2.0, "%s: the deputy catches up (%.1f vs %.1f m/s)" % [id, chase, s.flat_out_speed()])
		check(chase < Boost.top_speed(s.top_speed) - 15.0, "%s: boosting leaves them behind" % id)
	var legend := CarStats.preset("legend")
	check(Pursuit.chase_speed(cruiser, legend) == cruiser.top_speed, "the Legend's chased flat out")
	check(cruiser.flat_out_speed() < legend.flat_out_speed(), "and it's still the faster car")


func test_flat_out_speed_is_just_under_the_top_speed() -> void:
	for id: String in ["windstar", "tercel", "legend", "cruiser_johnson"]:
		var s := CarStats.preset(id)
		var v := s.flat_out_speed()
		check(v > s.top_speed - 4.0 and v < s.top_speed, "%s: %.1f of %.1f m/s" % [id, v, s.top_speed])


func test_losing_a_deputy_takes_400_m() -> void:
	var p := Pursuit.new("Johnson")
	var outcome := Pursuit.Outcome.NONE
	for i in 50:
		outcome = p.update(0.1, 380.0, 60.0, "Johnson", false)
	check(outcome == Pursuit.Outcome.NONE, "380 m back, they've still got you")
	for i in 41:
		outcome = p.update(0.1, 420.0, 60.0, "Johnson", false)
	check(outcome == Pursuit.Outcome.LOST, "420 m for 4 s: lost them")


func test_squeezing_past_fills_the_boost() -> void:
	var traffic := _traffic("legend")
	var car := traffic.car
	var wide := _overtake(traffic, car, 1.83 - 1.83 * 2.0)  # the other lane: a normal pass
	check(traffic.run.score.pot > 0 and car.boost.meter == 0.0, "a normal pass scores but doesn't fill the boost")
	check(wide.passed, "the pass counted")
	_free(traffic)
	traffic = _traffic("legend")
	car = traffic.car
	var spec: Dictionary = Traffic.KINDS["car"]
	# Mirrors 0.5 m apart: the two cars' half-widths plus half a meter right of its lane.
	var close_lateral: float = 1.83 - ((car.stats.body_size.x + spec.width) / 2.0 + 0.5)
	_overtake(traffic, car, close_lateral)
	check_near(car.boost.meter, Boost.CLOSE_PASS, 0.001, "a close pass fills some boost")
	check(traffic.run.score._pot_by_label.has("Close pass"), "and scores a close pass")
	_free(traffic)


func _free(traffic: Traffic) -> void:
	traffic.car.free()
	traffic.run.free()
	traffic.free()


func _traffic(car_id: String) -> Traffic:
	var traffic := Traffic.new()
	var car := Car.new()
	car.stats = CarStats.preset(car_id)
	traffic.car = car
	var run := Run.new()
	run.tracker = RunTracker.new(0.0, 10000.0, "Test car", "")
	run.tracker.update(10.0, 0.0)
	traffic.run = run
	return traffic


## Drive the car past a car in the northbound lane, `lateral` m right of the centerline.
func _overtake(traffic: Traffic, car: Car, lateral: float) -> Traffic.Vehicle:
	var v := Traffic.Vehicle.new()
	v.kind = "car"
	v.direction = 1.0
	v.offset = 1.83
	v.station = 500.0
	car.lateral = lateral
	var spec: Dictionary = Traffic.KINDS["car"]
	for i in 40:
		car.station = 490.0 + i * 0.5
		traffic._score_pass(v, spec)
	return v
