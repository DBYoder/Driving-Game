extends "res://tests/test_case.gd"


func _run(p: Pursuit, seconds: float, gap: float, speed: float, county := "Johnson", wrecked := false) -> Pursuit.Outcome:
	var outcome := Pursuit.Outcome.NONE
	var t := 0.0
	while t < seconds and outcome == Pursuit.Outcome.NONE:
		outcome = p.update(0.1, gap, speed, county, wrecked)
		t += 0.1
	return outcome


func test_radar_flags_speeders_in_range() -> void:
	check(Pursuit.spotted(100.0, 35.0), "75+ mph right past the deputy")
	check(not Pursuit.spotted(100.0, 30.0), "67 mph slips by")
	check(not Pursuit.spotted(300.0, 45.0), "out of radar range")


func test_stopping_next_to_the_cop_gets_you_busted() -> void:
	var p := Pursuit.new("Johnson")
	check(_run(p, 2.5, 8.0, 1.0) == Pursuit.Outcome.NONE, "not yet after 2.5 s")
	check(_run(p, 1.0, 8.0, 1.0) == Pursuit.Outcome.BUSTED, "busted after 3 s stopped at the cruiser")
	var moving := Pursuit.new("Johnson")
	check(_run(moving, 10.0, 8.0, 20.0) == Pursuit.Outcome.NONE, "tailgated at speed: not busted")
	var far := Pursuit.new("Johnson")
	check(_run(far, 10.0, 40.0, 0.0) == Pursuit.Outcome.NONE, "stopped, but the cop's not on you yet")


func test_getting_away() -> void:
	var p := Pursuit.new("Johnson")
	check(_run(p, 3.0, 700.0, 50.0) == Pursuit.Outcome.NONE, "need to stay gone a few seconds")
	check(_run(p, 2.0, 700.0, 50.0) == Pursuit.Outcome.LOST, "lost the cop")
	check(_run(Pursuit.new("Johnson"), 1.0, 30.0, 30.0, "Johnson", true) == Pursuit.Outcome.LOST, "wrecked the cruiser")
	check(_run(Pursuit.new("Johnson"), 200.0, 30.0, 30.0) == Pursuit.Outcome.GAVE_UP, "the deputy gives up eventually")


func test_deputies_stop_at_the_county_line() -> void:
	var p := Pursuit.new("Washington")
	check(_run(p, 1.0, 30.0, 40.0, "Washington") == Pursuit.Outcome.NONE, "still in Washington County")
	check(_run(p, 1.0, 30.0, 40.0, "Johnson") == Pursuit.Outcome.JURISDICTION, "out of their county")
