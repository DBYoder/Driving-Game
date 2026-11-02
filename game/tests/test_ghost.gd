extends "res://tests/test_case.gd"
## Your best run's ghost: recorded, kept on a new best, played back beside you.


func _run(ghost: Ghost, seconds: float, speed: float) -> void:
	# A straight drive north (-z) at `speed`, sampled every physics tick.
	ghost.start_recording()
	var t := 0.0
	while t < seconds:
		var xf := Transform3D(Basis(Vector3.UP, 0.1 * t), Vector3(0, 0, -speed * t))
		ghost.record(t, speed * t, xf)
		t += 1.0 / 60.0
	ghost.keep(seconds, speed * seconds, Transform3D(Basis(), Vector3(0, 0, -speed * seconds)))


func test_a_new_best_becomes_the_ghost_and_is_kept() -> void:
	var dir := "user://test_ghosts"
	var ghost := Ghost.new()
	ghost.dir = dir
	ghost.key = "highway22|Test car|night"
	_run(ghost, 30.0, 20.0)
	check(ghost.has_run() and absf(ghost.duration() - 30.0) < 0.01, "the run's the ghost (%.1f s)" % ghost.duration())
	check(ghost.samples.size() / Ghost.FIELDS <= 30 * Ghost.RATE + 2, "%d samples a second at most" % Ghost.RATE)
	var again := Ghost.new()
	again.dir = dir
	again.key = ghost.key
	check(again._load() == ghost.samples, "and it's there next time")
	DirAccess.remove_absolute(again._path())
	DirAccess.remove_absolute(dir)
	ghost.free()
	again.free()


func test_the_ghost_drives_its_run_again() -> void:
	var ghost := Ghost.new()
	ghost.dir = ""
	_run(ghost, 10.0, 20.0)
	var at := ghost.transform_at(5.05)
	check(absf(at.origin.z + 101.0) < 0.5, "where it was 5.05 s in (%s)" % at.origin)
	check(absf(at.basis.get_euler().y - 0.505) < 0.02, "facing as it was")
	check(ghost.transform_at(-1.0).origin.z == 0.0 and absf(ghost.transform_at(99.0).origin.z + 200.0) < 0.01,
		"waiting at the line before, parked at the finish after")
	# 100 m along: the ghost got there 5 s in. At 6 s you're a second behind; at 4.5, half a second ahead.
	check(absf(ghost.gap_at(100.0, 6.0) - 1.0) < 0.05, "a second behind (%.2f)" % ghost.gap_at(100.0, 6.0))
	check(absf(ghost.gap_at(100.0, 4.5) + 0.5) < 0.05, "half a second ahead")
	check(is_nan(ghost.gap_at(500.0, 10.0)), "no gap past where the ghost got")
	ghost.free()


func test_the_ghost_is_your_car_see_through() -> void:
	var ghost := Ghost.new()
	ghost.dir = ""
	(Engine.get_main_loop() as SceneTree).root.add_child(ghost)
	ghost.prepare("Test", CarStats.preset("tercel"))
	var meshes := ghost.find_children("*", "GeometryInstance3D", true, false)
	check(meshes.size() > 5, "the car's model (%d pieces)" % meshes.size())
	check(meshes.all(func(m): return m.material_override != null and m.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED),
		"every piece see-through")
	ghost.show_at(1.0, true)
	check(not ghost.visible, "nothing to show without a best run")
	_run(ghost, 10.0, 20.0)
	ghost.show_at(1.0, true)
	check(ghost.visible, "shown once there's one")
	ghost.show_at(1.0, false)
	check(not ghost.visible, "and not when it's switched off (or practice, or the title screen)")
	ghost.free()
