extends "res://tests/test_case.gd"


func test_combo_multiplies_and_banks_when_it_runs_out() -> void:
	var s := ScoreKeeper.new()
	s.add("Mailbox", 50)
	s.add("Mailbox", 50)
	s.add("Fence", 25)
	check(s.multiplier == 3 and s.pot == 125 and s.banked == 0, "three events: x3 on a 125 pot, nothing banked yet")
	s.update(ScoreKeeper.COMBO_WINDOW - 0.1)
	check(s.banked == 0, "still running just inside the window")
	s.update(0.2)
	check(s.banked == 375 and s.multiplier == 0, "banked at x3 when the window lapses")
	check(s.totals.Mailbox == 300 and s.totals.Fence == 75, "breakdown keeps the multiplier")


func test_multiplier_caps_at_five() -> void:
	var s := ScoreKeeper.new()
	for i in 8:
		s.add("Mailbox", 50)
	check(s.multiplier == ScoreKeeper.MAX_MULTIPLIER, "capped at x5")
	check(s.pot_value() == 400 * 5, "pot value")


func test_continuous_points_keep_the_combo_alive_without_raising_it() -> void:
	var s := ScoreKeeper.new()
	s.add("Corn", 5, true)
	for i in 10:
		s.update(1.0)
		s.add("Corn", 5, false)
	check(s.multiplier == 1, "plowing doesn't climb the multiplier")
	check(s.banked == 0 and s.pot == 55, "...but it keeps the combo from lapsing")


func test_breaking_the_combo_loses_only_the_pot() -> void:
	var s := ScoreKeeper.new()
	s.add("Mailbox", 50)
	s.update(10.0)
	s.add("Hay bale", 100)
	s.add("Hay bale", 100)
	s.break_combo()
	check(s.banked == 50 and s.pot == 0 and s.multiplier == 0, "banked points survive, the pot doesn't")


func test_finish_bonus() -> void:
	var s := ScoreKeeper.new()
	s.add("Mailbox", 100)
	s.finish(ScoreKeeper.PAR_SECONDS - 10.0)
	check(s.finish_bonus == 50, "x1.5 on everything")
	check(s.time_bonus == 10 * ScoreKeeper.BONUS_PER_SECOND, "time bonus per second under par")
	check(s.banked == 100 + 50 + 200, "total")
	var slow := ScoreKeeper.new()
	slow.finish(ScoreKeeper.PAR_SECONDS + 60.0)
	check(slow.time_bonus == 0, "no negative time bonus")


func test_wreck_only_counts_once_the_clock_runs() -> void:
	var t := RunTracker.new(100.0, 1000.0, "Test car", "")
	t.wreck("Totaled")
	check(t.state == RunTracker.State.READY, "messing around before the start line is free")
	t.update(150.0, 0.0)
	t.wreck("Totaled")
	check(t.state == RunTracker.State.WRECKED and t.wreck_reason == "Totaled", "wrecked during the run")
	t.update(2000.0, 1.0)
	check(t.state == RunTracker.State.WRECKED, "a wrecked car doesn't finish")


func test_rectangles_overlap() -> void:
	var north := Vector2(0, -1)
	var east := Vector2(1, 0)
	var car := Vector2(0.9, 2.4)
	check(Traffic.overlaps(Vector2.ZERO, north, car, Vector2(0, -4), north, car), "nose to tail, overlapping")
	check(not Traffic.overlaps(Vector2.ZERO, north, car, Vector2(0, -6), north, car), "nose to tail, apart")
	check(not Traffic.overlaps(Vector2.ZERO, north, car, Vector2(2.0, 0), north, car), "side by side in two lanes")
	check(Traffic.overlaps(Vector2.ZERO, north, car, Vector2(2.5, 0), east, car), "T-bone")
	var diag := Vector2(1, -1).normalized()
	check(Traffic.overlaps(Vector2.ZERO, north, car, Vector2(2.6, -2.9), diag, car), "diagonal, clipping a corner")
	check(not Traffic.overlaps(Vector2.ZERO, north, car, Vector2(3.5, -4.5), diag, car), "diagonal, corners close but clear")
