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
