class_name QaDrive
extends Node
## Automated test drives, run headless and faster than real time:
##   HighwayOne --headless --fixed-fps 60 -- --qa-drive    the autopilot drives the whole route
##   HighwayOne --headless --fixed-fps 60 -- --qa-stress   random inputs for 4 minutes
##   HighwayOne --headless --fixed-fps 60 -- --qa-drift    a scripted handbrake turn
##   HighwayOne --headless --fixed-fps 60 -- --qa-cops=bust (or =line)  a speed trap
##   HighwayOne --headless --fixed-fps 60 -- --qa-cops=boost  boost away from a deputy
##   HighwayOne --headless --fixed-fps 60 -- --qa-deer     a herd of deer, then a hit
## Watches for the car falling through the world, leaving its lane (autopilot only),
## flipping (autopilot only), or the physics blowing up; for things popping into or out
## of view where the haze doesn't hide it; and for the car's body visibly sitting inside
## wrecks, debris, standing corn or the ground; and for the autopilot hitting a deer
## (holding its speed and line, it never should). Prints a report and exits 0/1.

const ROUTE_TIME_LIMIT := 1500.0
const STRESS_TIME := 240.0
const MAX_LANE_ERROR := 3.0
## A handbrake turn at 50 mph should swing the tail out at least this far...
const DRIFT_MIN_SLIP := 35.0
## ...and the car should gather itself up within this long of straightening the wheel.
const DRIFT_MAX_RECOVERY := 4.0
## The closest each kind of thing may appear (m from the car): past where the haze hides
## it, or (detailed tiles, props) where it's a speck replacing nothing much.
const MIN_POP_IN := {"horizon": 3000.0, "road": 2400.0, "terrain": 1000.0, "streets": 1000.0, "props": 1000.0,
	"corn": CornField.CLUMP_GONE, "traffic": 1800.0, "deer": 170.0, "scenery": 1000.0}
const MIN_TRAFFIC_POP_OUT := 800.0
## Ticks of visible clipping allowed per kind: 10 (contacts can sink in a little for a
## tick), but none for the tires through the car's own body.
const MAX_CLIP_TICKS := {"tires": 0}
const TIRE_CHECK_EVERY := {"drive": 60, "thrown": 3}  ## physics ticks between tire checks: cruising, or stress/drift

var car: Car
var run: Run
var stress := false
var drift: DriftDriver  ## set for the drift test
var cop_scenario := ""  ## "bust" or "line" for the speed-trap test, "boost" to outrun one
var deer_scenario := false
var _sim_time := 0.0
var _wall_start := 0
var _worst_lane_error := 0.0
var _worst_lane_station := 0.0
var _worst_lane_note := ""  ## what was going on then
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
var _peak_lean := 0.0
var _recovery_time := -1.0
var _start_heading := 0.0
var _problems: Array[String] = []
var _clips := ClipProbe.new()
var _ticks := 0
var _chase_seen := false
var _chase_started_at := -1.0
var _chase_county := ""
var _closest_cop := INF
var _stopped_at := -1.0
var _deer_hits := 0
var _deer_station := 0.0
var _deer_stage := 0  ## 0 the herd, 1 the one to hit, 2 after the hit
var _health_before := 0.0
var _hit_at := 0.0
var _hits_before_stand := 0
var _combo_lost := false
var _boost_fills := 0
var _filled_at := -INF
var _chase_outcome := -1
var _boost_top := 0.0


func _ready() -> void:
	_wall_start = Time.get_ticks_msec()
	process_physics_priority = 100  # after the car has moved this tick


func _physics_process(delta: float) -> void:
	if _sim_time == 0.0 and cop_scenario == "boost":
		_set_up_boost_chase()
	elif _sim_time == 0.0 and cop_scenario != "":
		_set_up_trap_run()
	if _sim_time == 0.0 and deer_scenario:
		_set_up_deer_run()
	_sim_time += delta
	var pos := car.global_position
	var speed := car.linear_velocity.length()
	if not pos.is_finite() or not car.linear_velocity.is_finite():
		_fail("physics produced NaN at %.1f s" % _sim_time)
		return
	if speed > Boost.MAX_SPEED + 8.0:
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
	_ticks += 1
	if _ticks % (TIRE_CHECK_EVERY.thrown if stress or drift else TIRE_CHECK_EVERY.drive) == 0:
		_clips.sample_tires(car)
	var deer: Deer = get_parent().deer
	if deer.hits > _deer_hits:
		_deer_hits = deer.hits
		if not stress and not deer_scenario:
			_problems.append("hit a deer near mile %.2f" % car.route.mile_at(car.station))

	if stress:
		_stress_tick(up_y, delta)
		return
	if drift:
		_drift_tick()
		return
	if cop_scenario == "boost":
		_boost_tick()
		return
	if cop_scenario != "":
		_cop_tick()
		return
	if deer_scenario:
		_deer_tick()
		return
	if run.tracker.running():
		var aim: float = car.driver.lane if car.driver is Autopilot else Autopilot.LANE_OFFSET
		var lane_error := absf(car.lateral - aim)
		if lane_error > _worst_lane_error:
			_worst_lane_error = lane_error
			_worst_lane_station = car.station
			var ap := car.driver as Autopilot
			_worst_lane_note = "%.0f mph, %.1f m right of center aiming for %.1f%s%s" % [
				car.forward_speed() * Hud.MPH, car.lateral, aim,
				", passing" if ap and ap.passing else "", ", on ice" if car.on_ice else ""]
	if _lowest_up < 0.3:
		_fail("car rolled over near mile %.2f" % car.route.mile_at(car.station))
	elif run.tracker.state == RunTracker.State.WRECKED:
		var ap := car.driver as Autopilot
		_fail("wrecked (%s) near mile %.2f at %.0f mph, %.1f m right of center%s%s" % [
			run.tracker.wreck_reason, car.route.mile_at(car.station), car.forward_speed() * Hud.MPH, car.lateral,
			" (passing)" if ap and ap.passing else "", " on ice" if car.on_ice else ""])
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
	if drift.phase != DriftDriver.Phase.ACCELERATE and absf(car.lateral) < RoadMesher.PAVED_HALF_WIDTH:
		# Roll on the pavement: how far the car's sides tip relative to its own forward direction.
		var b := car.global_transform.basis
		_peak_lean = maxf(_peak_lean, rad_to_deg(absf(atan2(b.x.y, b.y.y))))
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
			print("QA drift (%s): peak slide %.0f deg, peak yaw rate %.0f deg/s, leaned %.0f deg, turned %.0f deg, %s, %.0f mph after" % [
				car.stats.display_name, _peak_slip, _peak_yaw_rate, _peak_lean, turned,
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


## Put the car a way back from the trap the scenario needs, at 85 mph cruise.
func _set_up_trap_run() -> void:
	var cops: Cops = get_parent().cops
	var county := "Johnson" if cop_scenario == "bust" and cops.traps_per_county.has("Johnson") else "Washington"
	if cop_scenario == "line":
		county = cops.county_at(car.route.start_station)  # (the county before the line: Johnson on the way back)
	var traps := cops.traps.filter(func(t): return t.county == county)
	if traps.is_empty():
		_fail("no %s County speed trap this run" % county)
		return
	get_parent()._spawn(maxf(traps[0].station - 700.0, car.route.start_station - 25.0))
	(car.driver as Autopilot).target_speed = 85.0 / Hud.MPH


## Speed past the trap; then ("bust") pull over and wait, or ("line") keep going
## on across the county line.
func _cop_tick() -> void:
	var cops: Cops = get_parent().cops
	if cops.chasing():
		if not _chase_seen:
			_chase_seen = true
			_chase_started_at = _sim_time
			_chase_county = cops.chase.county
		_closest_cop = minf(_closest_cop, cops.chaser.car.global_position.distance_to(car.global_position))
	if cop_scenario == "bust" and _chase_seen and _stopped_at < 0.0 and _sim_time - _chase_started_at > 8.0:
		_stopped_at = _sim_time
		car.driver = PullOver.new()
	if run.tracker.state == RunTracker.State.WRECKED:
		if cop_scenario == "bust" and run.tracker.wreck_reason == "Busted":
			print("QA cops: busted %.1f s after pulling over; the deputy got within %.0f m during the chase" % [
				_sim_time - _stopped_at, _closest_cop])
			if _closest_cop > 40.0:
				_problems.append("the deputy never caught up (closest %.0f m)" % _closest_cop)
			_finish()
		else:
			_fail("wrecked (%s) during the speed-trap test" % run.tracker.wreck_reason)
	elif cop_scenario == "line" and run.score.totals.has("Jurisdiction"):
		print("QA cops: the %s County deputy gave up at the county line, %.1f s into the chase" % [
			_chase_county, _sim_time - _chase_started_at])
		_finish()
	elif _sim_time > 150.0:
		_fail("speed-trap test: %s" % ("no chase" if not _chase_seen else "the chase never ended the way it should (%s)" % cop_scenario))


## Johnson County (on Highway 1; a mile in on a route with no county line), flat out with
## no speed traps; once the car's at its top speed a deputy turns up on its tail, going
## just as fast.
func _set_up_boost_chase() -> void:
	var cops: Cops = get_parent().cops
	for trap in cops.traps:
		trap.done = true
	cops.chase_ended.connect(func(outcome): _chase_outcome = outcome)
	get_parent()._spawn(cops.county_line + 300.0 if cops.county_line < INF else car.route.start_station + RouteData.MILE_M)
	(car.driver as Autopilot).target_speed = 100.0  # flat out


## With the deputy right behind, fill the meter (as two near misses in a row would) and
## burn it; again 15 s later. That should lose the deputy: they're only a little faster
## than the car without it.
func _boost_tick() -> void:
	var cops: Cops = get_parent().cops
	if not _chase_seen:
		if car.forward_speed() > car.stats.top_speed - 4.0:
			cops.chase_from_behind(25.0)
			cops.chaser.car.linear_velocity = car.linear_velocity
			_chase_seen = true
			_chase_started_at = _sim_time
		elif _sim_time > 60.0:
			_fail("boost test: never got up to top speed (%.0f mph)" % (car.forward_speed() * Hud.MPH))
		return
	if cops.chasing():
		_closest_cop = minf(_closest_cop, cops.chaser.car.global_position.distance_to(car.global_position))
		var gap := cops.chaser.car.global_position.distance_to(car.global_position)
		if car.boost.meter == 0.0 and _sim_time - _filled_at > 15.0 and _boost_fills < 3 and gap < Pursuit.LOST_GAP:
			car.boost.fill(1.0)
			_boost_fills += 1
			_filled_at = _sim_time
		car.boost_held = car.boost.meter > 0.0
	else:
		car.boost_held = false
	_boost_top = maxf(_boost_top, car.forward_speed())
	if run.tracker.state == RunTracker.State.WRECKED:
		_fail("wrecked (%s) during the boost test" % run.tracker.wreck_reason)
	elif _chase_outcome == Pursuit.Outcome.LOST:
		print("QA cops: boosted away from the deputy, lost %.1f s into the chase with %d full boosts, top %.0f mph" % [
			_sim_time - _chase_started_at, _boost_fills, _boost_top * Hud.MPH])
		if _boost_fills > 2:
			_problems.append("took %d full boosts to lose the deputy (2 should do it)" % _boost_fills)
		_finish()
	elif _chase_outcome != -1:
		_fail("boost test: the chase ended the wrong way (%s)" % Pursuit.Outcome.keys()[_chase_outcome])
	elif _sim_time - _chase_started_at > 90.0:
		_fail("boost test: still chased after 90 s and %d full boosts" % _boost_fills)


## Line up a herd of three at the first creek, coming from the right, the first one
## set to freeze in the lane; start 900 m back at the usual 70 mph.
func _set_up_deer_run() -> void:
	var deer: Deer = get_parent().deer
	_deer_station = Bridges.deer_station(car.route, car.route.bridges[0])
	deer.spots.clear()
	deer.add_spot(_deer_station, 1.0, 3, true)
	get_parent()._spawn(_deer_station - 900.0)


## The herd should cross (the first one stopping in the lane), all of them missing the
## car; then a deer that stays put in the lane gets hit: damage, the combo gone, the
## deer sent flying clear of the car.
func _deer_tick() -> void:
	var deer: Deer = get_parent().deer
	if run.tracker.state == RunTracker.State.WRECKED:
		_fail("wrecked (%s) during the deer test" % run.tracker.wreck_reason)
	elif _deer_stage == 0 and car.station > _deer_station + 80.0:
		print("QA deer: %d herd crossed, %d deer froze in the lane, %d dodged, %d hit" % [
			deer.crossings, deer.froze, deer.dodges, deer.hits])
		if deer.crossings != 1:
			_problems.append("the herd never broke cover")
		if deer.froze != 1:
			_problems.append("the first deer didn't freeze in the lane")
		if deer.hits > 0:
			_problems.append("the autopilot hit a deer holding its speed and line")
		if deer.dodges < 1:
			_problems.append("no deer got in the way to be dodged")
		_deer_stage = 1
		_hits_before_stand = deer.hits
		_health_before = car.health
		run.score.add("QA", 100)  # a combo for the hit to break
		run.score.combo_lost.connect(func(_points: int) -> void: _combo_lost = true)
		deer.stand_in_road(80.0)  # reached well inside the combo window
	elif _deer_stage == 1 and deer.hits > _hits_before_stand:
		_deer_stage = 2
		_hit_at = _sim_time
		var damage := _health_before - car.health
		print("QA deer: hit one at %.0f mph, %.0f damage, combo %s" % [
			car.forward_speed() * Hud.MPH, damage, "lost" if _combo_lost else "kept"])
		if damage < 20.0:
			_problems.append("hitting a deer only did %.0f damage" % damage)
		if not _combo_lost:
			_problems.append("hitting a deer didn't break the combo")
	elif _deer_stage == 2 and _sim_time - _hit_at > 5.0:
		_finish()
	elif _sim_time > 120.0:
		_fail("deer test: stuck at stage %d" % _deer_stage)


## Brake to a stop on the shoulder side of the lane and wait.
class PullOver:
	func update(c: Car, _delta: float) -> void:
		c.throttle = 0.0
		c.steer = 0.0
		c.handbrake = false
		c.brake = 1.0 if c.forward_speed() > 0.6 else 0.0


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
	var what := "QA drive (%s): %s run time, score %d" % [get_parent().condition.display_name,
		RunTracker.format_time(run.tracker.elapsed), run.score.banked]
	if stress:
		what = "QA stress: reached mile %.1f, %d flips recovered, %d wrecks %s" % [
			car.route.mile_at(_furthest), _flips, _wrecks, _wreck_reasons]
	elif drift:
		what = "QA drift"
	print("%s, %.1f s simulated in %.1f s wall (%.1fx real time)" % [
		what, _sim_time, wall, _sim_time / maxf(wall, 0.001)])
	var lane := "" if stress else ", worst lane error %.2f m (mile %.2f: %s)" % [
		_worst_lane_error, car.route.mile_at(_worst_lane_station), _worst_lane_note]
	print("  0-60 mph %.1f s, top speed %.0f mph%s, min uprightness %.2f, airborne %.1f s" % [
		_zero_to_sixty, _top_speed * Hud.MPH, lane, _lowest_up, _airborne_ticks * get_physics_process_delta_time()])
	print("  biggest one-tick jolt %.2f m/s, car health %.0f%%, props smashed %d%s" % [
		car.peak_jolt, car.health / car.stats.durability * 100.0, get_parent().props.smashed_count(),
		", backed out of a jam %d times" % car.driver.unstuck_count if car.driver is Autopilot and car.driver.unstuck_count > 0 else ""])
	var labels := run.score.totals.keys()
	labels.sort()
	print("  clipping: %s" % _clips.report())
	for kind in _clips.visible_ticks:
		if _clips.visible_ticks[kind] > MAX_CLIP_TICKS.get(kind, 10):
			_problems.append("car visibly inside %s for %d ticks (worst %.2f near mile %.2f)" % [
				kind, _clips.visible_ticks[kind], _clips.worst[kind], _clips.worst_mile[kind]])
	var main := get_parent()
	var pop_in := {"horizon": main.streamer.nearest_pop_in.far, "road": main.streamer.nearest_pop_in.road,
		"terrain": main.streamer.nearest_pop_in.tile, "streets": main.streamer.nearest_pop_in.street,
		"props": main.props.nearest_pop_in,
		"corn": main.corn.nearest_pop_in, "traffic": main.traffic.nearest_pop_in,
		"deer": main.deer.nearest_pop_in, "scenery": main.scenery.nearest_pop_in}
	print("  nearest pop-in: %s; traffic gone at %s" % [
		", ".join(pop_in.keys().map(func(k): return "%s %s" % [k, _meters(pop_in[k])])),
		_meters(main.traffic.nearest_pop_out)])
	for kind in pop_in:
		if pop_in[kind] < MIN_POP_IN[kind]:
			_problems.append("%s popped in %.0f m away (want %.0f+)" % [kind, pop_in[kind], MIN_POP_IN[kind]])
	if main.traffic.nearest_pop_out < MIN_TRAFFIC_POP_OUT:
		_problems.append("traffic vanished %.0f m away" % main.traffic.nearest_pop_out)
	print("  deer: %d herds crossed, %d froze in the lane, %d dodged, %d hit" % [
		main.deer.crossings, main.deer.froze, main.deer.dodges, main.deer.hits])
	print("  scored: %s" % ", ".join(labels.map(func(l): return "%s %d" % [l, run.score.totals[l]])))
	if _problems.is_empty():
		print("QA OK")
		get_tree().quit(0)
	else:
		for p in _problems:
			printerr("QA FAIL: ", p)
		get_tree().quit(1)
