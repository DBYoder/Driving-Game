class_name QaDrive
extends Node
## Automated test drives, run headless and faster than real time:
##   HighwayOne --headless --fixed-fps 60 -- --qa-drive    the autopilot drives the whole route
##   HighwayOne --headless --fixed-fps 60 -- --qa-stress   random inputs for 4 minutes
##   HighwayOne --headless --fixed-fps 60 -- --qa-drift    a scripted handbrake turn
## Watches for the car falling through the world, leaving its lane (autopilot only),
## flipping (autopilot only), or the physics blowing up; for things popping into or out
## of view where the haze doesn't hide it; and for the car's body visibly sitting inside
## wrecks, debris, standing corn or the ground. Prints a report and exits 0/1.

const ROUTE_TIME_LIMIT := 1500.0
const STRESS_TIME := 240.0
const MAX_LANE_ERROR := 3.0
## A handbrake turn at 50 mph should swing the tail out at least this far...
const DRIFT_MIN_SLIP := 35.0
## ...and the car should gather itself up within this long of straightening the wheel.
const DRIFT_MAX_RECOVERY := 4.0
## The closest each kind of thing may appear (m from the car): past where the haze hides
## it, or (detailed tiles, props) where it's a speck replacing nothing much.
const MIN_POP_IN := {"horizon": 3000.0, "road": 2400.0, "terrain": 1000.0, "props": 1000.0,
	"corn": CornField.FADE_FAR, "traffic": 1800.0}
const MIN_TRAFFIC_POP_OUT := 800.0
## Ticks of visible clipping allowed per kind (contacts can sink in a little for a tick).
const MAX_CLIP_TICKS := 10

var car: Car
var run: Run
var stress := false
var drift: DriftDriver  ## set for the drift test
var _sim_time := 0.0
var _wall_start := 0
var _worst_lane_error := 0.0
var _worst_lane_station := 0.0
var _lowest_up := 1.0
var _top_speed := 0.0
var _airborne_ticks := 0
var _zero_to_sixty := 0.0
var _upside_down_time := 0.0
var _flips := 0
var _wrecks := 0
var _wreck_reasons: Array[String] = []
var _furthest := 0.0
var _peak_slip := 0.0
var _peak_yaw_rate := 0.0
var _recovery_time := -1.0
var _start_heading := 0.0
var _problems: Array[String] = []
var _clips := ClipProbe.new()


func _ready() -> void:
	_wall_start = Time.get_ticks_msec()
	process_physics_priority = 100  # after the car has moved this tick


func _physics_process(delta: float) -> void:
	_sim_time += delta
	var pos := car.global_position
	var speed := car.linear_velocity.length()
	if not pos.is_finite() or not car.linear_velocity.is_finite():
		_fail("physics produced NaN at %.1f s" % _sim_time)
		return
	if speed > 80.0:
		_fail("car reached an impossible %.0f mph near mile %.2f" % [speed * Hud.MPH, car.route.mile_at(car.station)])
	var road_y := car.route.position_at(car.station).y
	var ground := car.route.terrain.height_at(pos.x, pos.z)
	var floor_y := maxf(road_y, ground) if not is_nan(ground) and absf(car.lateral) < RoadMesher.GRAVEL_HALF_WIDTH else ground
	if not is_nan(floor_y):
		if pos.y < floor_y - 1.0:
			_fail("fell through the world near mile %.2f" % car.route.mile_at(car.station))
		if pos.y > floor_y + 30.0:
			_fail("launched %.0f m into the sky near mile %.2f" % [pos.y - floor_y, car.route.mile_at(car.station)])

	if _zero_to_sixty == 0.0 and car.forward_speed() >= 60.0 / Hud.MPH:
		_zero_to_sixty = _sim_time
	_top_speed = maxf(_top_speed, car.forward_speed())
	_furthest = maxf(_furthest, car.station)
	if car.grounded_wheels() == 0:
		_airborne_ticks += 1
	var up_y := car.global_transform.basis.y.y
	_lowest_up = minf(_lowest_up, up_y)
	_clips.sample(get_parent(), car)

	if stress:
		_stress_tick(up_y, delta)
		return
	if drift:
		_drift_tick()
		return
	if run.tracker.running():
		var aim: float = car.driver.lane if car.driver is Autopilot else Autopilot.LANE_OFFSET
		var lane_error := absf(car.lateral - aim)
		if lane_error > _worst_lane_error:
			_worst_lane_error = lane_error
			_worst_lane_station = car.station
	if _lowest_up < 0.3:
		_fail("car rolled over near mile %.2f" % car.route.mile_at(car.station))
	elif run.tracker.state == RunTracker.State.WRECKED:
		_fail("wrecked (%s) near mile %.2f" % [run.tracker.wreck_reason, car.route.mile_at(car.station)])
	elif run.tracker.state == RunTracker.State.FINISHED:
		_finish()
	elif _sim_time > ROUTE_TIME_LIMIT:
		_fail("did not finish within %d s of simulated time" % ROUTE_TIME_LIMIT)


## Flips and wrecks are expected when mashing buttons; carry on like a player would.
func _stress_tick(up_y: float, delta: float) -> void:
	if run.tracker.state == RunTracker.State.WRECKED:
		_wrecks += 1
		_wreck_reasons.append(run.tracker.wreck_reason)
		get_parent().restart()
		return
	_upside_down_time = _upside_down_time + delta if up_y < 0.3 else 0.0
	if _upside_down_time > 3.0:
		_flips += 1
		_upside_down_time = 0.0
		car.place_at(car.station)
	if _sim_time >= STRESS_TIME:
		_finish()


func _drift_tick() -> void:
	var slip := DriftDriver.slip_angle(car)
	var yaw_rate := absf(rad_to_deg(car.angular_velocity.y))
	match drift.phase:
		DriftDriver.Phase.ACCELERATE:
			_start_heading = car.global_rotation.y
		DriftDriver.Phase.PULL, DriftDriver.Phase.HOLD:
			_peak_slip = maxf(_peak_slip, slip)
			_peak_yaw_rate = maxf(_peak_yaw_rate, yaw_rate)
		DriftDriver.Phase.STRAIGHTEN:
			_peak_slip = maxf(_peak_slip, slip)
			if _recovery_time < 0.0 and slip < 5.0 and yaw_rate < 10.0:
				_recovery_time = drift.phase_time
		DriftDriver.Phase.DONE:
			var turned := rad_to_deg(absf(angle_difference(_start_heading, car.global_rotation.y)))
			print("QA drift: peak slide %.0f deg, peak yaw rate %.0f deg/s, turned %.0f deg, %s, %.0f mph after" % [
				_peak_slip, _peak_yaw_rate, turned,
				"recovered %.1f s after straightening" % _recovery_time if _recovery_time >= 0.0 else "never recovered",
				car.forward_speed() * Hud.MPH])
			if _peak_slip < DRIFT_MIN_SLIP:
				_problems.append("handbrake turn only slid %.0f deg (want %.0f+)" % [_peak_slip, DRIFT_MIN_SLIP])
			if _recovery_time < 0.0 or _recovery_time > DRIFT_MAX_RECOVERY:
				_problems.append("car didn't recover within %.0f s of straightening" % DRIFT_MAX_RECOVERY)
			if _lowest_up < 0.5:
				_problems.append("car tipped over in the handbrake turn")
			_finish()


static func _meters(d: float) -> String:
	return "-" if is_inf(d) else "%.0f m" % d


func _fail(problem: String) -> void:
	if not problem in _problems:
		_problems.append(problem)
	_finish()


func _finish() -> void:
	set_physics_process(false)
	if _worst_lane_error > MAX_LANE_ERROR:
		_problems.append("drifted %.1f m out of the lane near mile %.2f" % [
			_worst_lane_error, car.route.mile_at(_worst_lane_station)])
	var wall := (Time.get_ticks_msec() - _wall_start) / 1000.0
	var what := "QA drive: %s run time, score %d" % [RunTracker.format_time(run.tracker.elapsed), run.score.banked]
	if stress:
		what = "QA stress: reached mile %.1f, %d flips recovered, %d wrecks %s" % [
			car.route.mile_at(_furthest), _flips, _wrecks, _wreck_reasons]
	elif drift:
		what = "QA drift"
	print("%s, %.1f s simulated in %.1f s wall (%.1fx real time)" % [
		what, _sim_time, wall, _sim_time / maxf(wall, 0.001)])
	var lane := "" if stress else ", worst lane error %.2f m (mile %.2f)" % [
		_worst_lane_error, car.route.mile_at(_worst_lane_station)]
	print("  0-60 mph %.1f s, top speed %.0f mph%s, min uprightness %.2f, airborne %.1f s" % [
		_zero_to_sixty, _top_speed * Hud.MPH, lane, _lowest_up, _airborne_ticks * get_physics_process_delta_time()])
	print("  biggest one-tick jolt %.2f m/s, car health %.0f%%, props smashed %d" % [
		car.peak_jolt, car.health / car.stats.durability * 100.0, get_parent().props.smashed_count()])
	var labels := run.score.totals.keys()
	labels.sort()
	print("  clipping: %s" % _clips.report())
	for kind in _clips.visible_ticks:
		if _clips.visible_ticks[kind] > MAX_CLIP_TICKS:
			_problems.append("car visibly inside %s for %d ticks (worst %.2f near mile %.2f)" % [
				kind, _clips.visible_ticks[kind], _clips.worst[kind], _clips.worst_mile[kind]])
	var main := get_parent()
	var pop_in := {"horizon": main.streamer.nearest_pop_in.far, "road": main.streamer.nearest_pop_in.road,
		"terrain": main.streamer.nearest_pop_in.tile, "props": main.props.nearest_pop_in,
		"corn": main.corn.nearest_pop_in, "traffic": main.traffic.nearest_pop_in}
	print("  nearest pop-in: %s; traffic gone at %s" % [
		", ".join(pop_in.keys().map(func(k): return "%s %s" % [k, _meters(pop_in[k])])),
		_meters(main.traffic.nearest_pop_out)])
	for kind in pop_in:
		if pop_in[kind] < MIN_POP_IN[kind]:
			_problems.append("%s popped in %.0f m away (want %.0f+)" % [kind, pop_in[kind], MIN_POP_IN[kind]])
	if main.traffic.nearest_pop_out < MIN_TRAFFIC_POP_OUT:
		_problems.append("traffic vanished %.0f m away" % main.traffic.nearest_pop_out)
	print("  scored: %s" % ", ".join(labels.map(func(l): return "%s %d" % [l, run.score.totals[l]])))
	if _problems.is_empty():
		print("QA OK")
		get_tree().quit(0)
	else:
		for p in _problems:
			printerr("QA FAIL: ", p)
		get_tree().quit(1)
