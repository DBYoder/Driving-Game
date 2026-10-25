extends "res://tests/test_case.gd"

const SAVE := "user://test_records.cfg"


func _tracker() -> RunTracker:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	return RunTracker.new(100.0, 1000.0, "Test car", SAVE)


func test_clock_starts_at_the_line_and_stops_at_the_finish() -> void:
	var t := _tracker()
	t.update(50.0, 1.0)
	check(t.state == RunTracker.State.READY and t.elapsed == 0.0, "clock waits behind the line")
	t.update(100.0, 1.0)
	check(t.state == RunTracker.State.RUNNING, "crossing the line starts the clock")
	for i in 10:
		t.update(500.0, 0.5)
	check_near(t.elapsed, 5.0, 1e-6, "elapsed time adds up")
	t.update(1000.0, 0.5)
	check(t.state == RunTracker.State.FINISHED, "crossing the finish stops the clock")
	check_near(t.elapsed, 5.5, 1e-6, "finish tick counts")
	t.update(1200.0, 3.0)
	check_near(t.elapsed, 5.5, 1e-6, "clock stays stopped after the finish")


func test_best_time_is_kept_and_only_improved() -> void:
	var t := _tracker()
	t.update(100.0, 0.0)
	t.update(1000.0, 60.0)
	check(t.new_best and t.best_time == 60.0, "first finish is a best time")
	t.reset()
	t.update(100.0, 0.0)
	t.update(1000.0, 70.0)
	check(not t.new_best and t.best_time == 60.0, "a slower run doesn't replace it")
	var reloaded := RunTracker.new(100.0, 1000.0, "Test car", SAVE)
	check(reloaded.best_time == 60.0, "best time survives a restart of the game")
	var other := RunTracker.new(100.0, 1000.0, "Other car", SAVE)
	check(other.best_time == 0.0, "best times are per car")


func test_format_time() -> void:
	check(RunTracker.format_time(0.0) == "0:00.0", "zero")
	check(RunTracker.format_time(754.36) == "12:34.4", "minutes and tenths")


func test_the_title_screens_car_and_cars_put_down_up_the_road_save_nothing() -> void:
	# The title screen's car drives a whole run on its own: nothing it does is a record.
	var t := _tracker()
	t.demo = true
	t.update(97.0, 0.0)
	t.update(100.0, 0.0)
	check(t.running() and not t.counts(), "the title screen's car's run is timed but doesn't count")
	t.update(1000.0, 900.0)
	t.record_score(12345)
	check(t.best_time == 0.0 and t.best_score == 0 and not t.new_best and not t.new_best_score, "no records from it")
	check(RunTracker.saved_records(SAVE, "Test car") == [0, 0.0], "not even on disk")
	# A car put down up the road (a run started with --station) starts the clock as it goes:
	# past the finish, that's a 0.02 s "best time".
	t.demo = false
	t.reset()
	t.update(2000.0, 0.0)
	t.update(2000.0, 1.0 / 60.0)
	check(t.state == RunTracker.State.FINISHED and not t.counts(), "a run that starts past the finish finishes at once, and doesn't count")
	t.record_score(17999)
	check(t.best_time == 0.0 and t.best_score == 0, "no 0.02 s record")
	t.reset()
	t.update(600.0, 0.0)
	check(t.running() and not t.counts(), "nor one put down half way")
	# A real run from behind the line still does.
	t.reset()
	t.update(97.0, 0.0)
	t.update(101.0, 0.0)
	check(t.counts(), "a real run counts again after a reset")
	t.update(1000.0, 600.0)
	t.record_score(4321)
	check(RunTracker.saved_records(SAVE, "Test car") == [4321, 600.0], "and is saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
