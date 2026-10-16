extends "res://tests/test_case.gd"

var stats := CarStats.new()


func test_drive_force_curve() -> void:
	check_near(stats.drive_force(0.0), stats.max_drive_force, 1e-3, "full traction-limited force off the line")
	check_near(stats.drive_force(30.0), stats.wheel_power / 30.0, 1e-3, "power-limited at highway speed")
	check(stats.drive_force(stats.top_speed) == 0.0, "nothing left at top speed")
	var last := INF
	for v in range(0, 60, 5):
		var f := stats.drive_force(v)
		check(f <= last, "force never rises with speed (at %d m/s)" % v)
		last = f


func test_top_speed_is_reachable_on_flat_ground() -> void:
	# Engine force beats drag + rolling resistance until just under the limiter.
	var v := stats.top_speed - 5.0
	var resist := stats.drag * v * v + stats.rolling_resistance * stats.mass * 9.8
	check(stats.drive_force(v) > resist, "still accelerating at %.0f mph" % (v * Hud.MPH))


func test_steering_tightens_with_speed() -> void:
	check_near(rad_to_deg(stats.steer_limit(0.0)), stats.max_steer_deg, 1e-4, "full lock when parked")
	check_near(rad_to_deg(stats.steer_limit(100.0)), stats.high_speed_steer_deg, 1e-4, "small lock flat out")


func test_autopilot_steers_toward_the_target() -> void:
	var limit := deg_to_rad(20.0)
	check(Autopilot.steer_toward(Vector3(0, 0, -30), limit) == 0.0, "straight ahead: no steering")
	check(Autopilot.steer_toward(Vector3(5, 0, -30), limit) > 0.0, "target to the right: steer right")
	check(Autopilot.steer_toward(Vector3(-5, 0, -30), limit) < 0.0, "target to the left: steer left")
	check(Autopilot.steer_toward(Vector3(50, 0, -1), limit) == 1.0, "clamped to full lock")
