extends "res://tests/test_case.gd"


func test_push_apart_moves_one_rectangle_off_the_other() -> void:
	var north := Vector2(0, -1)
	var car := Vector2(0.9, 2.4)
	var push := Traffic.push_apart(Vector2.ZERO, north, car, Vector2(0, -4), north, car)
	check_near(push.length(), 0.8, 1e-4, "nose to tail 0.8 m deep: pushed 0.8 m")
	check(push.y < 0.0, "pushed further ahead, the way it already sticks out")
	check(not Traffic.overlaps(Vector2.ZERO, north, car, Vector2(0, -4) + push * 1.001, north, car), "apart after the push")
	var side := Traffic.push_apart(Vector2.ZERO, north, car, Vector2(1.5, 0.5), north, car)
	check_near(side.x, 0.3, 1e-4, "side by side: pushed sideways, the short way out")
	check(Traffic.push_apart(Vector2.ZERO, north, car, Vector2(0, -6), north, car) == Vector2.ZERO, "apart: no push")


func test_box_overlap_depth() -> void:
	var unit := Vector3.ONE * 0.5
	var at := func(p: Vector3, yaw := 0.0) -> Transform3D: return Transform3D(Basis(Vector3.UP, yaw), p)
	check_near(ClipProbe.box_overlap(at.call(Vector3.ZERO), unit, at.call(Vector3(0.7, 0, 0)), unit), 0.3, 1e-4, "side by side")
	check_near(ClipProbe.box_overlap(at.call(Vector3.ZERO), unit, at.call(Vector3(0, 0.9, 0)), unit), 0.1, 1e-4, "one resting into the other")
	check(ClipProbe.box_overlap(at.call(Vector3.ZERO), unit, at.call(Vector3(0, 1.2, 0)), unit) == 0.0, "one above the other")
	check(ClipProbe.box_overlap(at.call(Vector3.ZERO), unit, at.call(Vector3(1.25, 0, 0), PI / 4.0), unit) == 0.0,
		"a turned box whose corner just misses")
	check(ClipProbe.box_overlap(at.call(Vector3.ZERO), unit, at.call(Vector3(1.0, 0, 0), PI / 4.0), unit) > 0.1,
		"a turned box whose corner pokes in")


func test_corn_in_the_cars_path() -> void:
	var half := Vector2(1.5, 3.0)
	check(CornField.in_swept_box(Vector2(1.4, -2.9), half, Vector2.ZERO), "inside a parked car")
	check(not CornField.in_swept_box(Vector2(0.0, -3.5), half, Vector2.ZERO), "just ahead of a parked car")
	check(CornField.in_swept_box(Vector2(0.0, -3.5), half, Vector2(0.0, -0.8)), "just ahead of a moving car")
	check(CornField.in_swept_box(Vector2(1.4, -2.0), half, Vector2(-0.6, -0.6)),
		"in the corner while drifting the other way")
	check(not CornField.in_swept_box(Vector2(2.0, 0.0), half, Vector2(0.0, -0.8)), "beside a moving car")
