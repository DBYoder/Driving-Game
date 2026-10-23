class_name Cops
extends Node3D
## County sheriff's deputies running speed traps, parked on the shoulder just past a
## crossroad. Each run on Highway 1, one deputy waits in Washington County (Kalona, up to
## the county line at Johnson-Washington Rd) and three in Johnson County; on Highway 22,
## all in Washington County, two (Routes.INFO traps). Blow past one well
## over the limit (or hit it) and the chase is on: lights, siren, and traffic pulling
## over. The rules are in Pursuit; the driving in CopDriver.
##
## A cruiser is a real physics car like yours, but only near you: further than
## PHYSICS_RANGE away there's no ground collision built, so it's frozen, and a chasing
## cruiser that far back rides along the road on rails until it's close again.

signal chase_started(county: String)
signal chase_ended(outcome: Pursuit.Outcome)

const COUNTY_LINE_ROAD := "Johnson-Washington Rd SW"
const PARK_OFFSET := 6.0  ## out on the shoulder, clear of a combine's header
const PARK_PAST := 15.0  ## m past the crossroad
const TRAP_SPACING := 900.0  ## m at least between traps
const SPAWN_AHEAD := 1300.0  ## parked cruisers exist this far up the road...
const SPAWN_BEHIND := 500.0  ## ...and this far back
const PHYSICS_RANGE := 200.0  ## real physics within this of the player
const RAILS_MARGIN := 25.0
const RIDE_HEIGHT := 0.75  ## body origin above the road
const LOST_POINTS := 1000
const JURISDICTION_POINTS := 2000


class Trap:
	var station: float
	var county: String
	var car: Car
	var driver: CopDriver
	var done := false  ## this deputy has had their chase


var route: RouteData
var player: Car
var run: Run
var traffic: Traffic
var enabled := true
var night := false  ## cruisers drive with their headlights on
var county_line := INF  ## station: Washington County before here, Johnson County after (none: INF)
var traps_per_county := {"Washington": 1, "Johnson": 3}
var traps: Array[Trap] = []
var chase: Pursuit  ## the chase on now, or null
var chaser: Trap
var siren: Siren
var _rails := false  ## the chaser is far back, frozen and moving along the road
var _rail_station := 0.0
var _cop_rolled := 0.0
var _rng := RandomNumberGenerator.new()


func setup(r: RouteData, p: Car, game_run: Run, t: Traffic, seed_value: int) -> void:
	for county: String in ["washington", "johnson"]:  # (their bodies take a while to work out)
		CarModel.prepare(CarStats.preset("cruiser_" + county))
	route = r
	player = p
	run = game_run
	traffic = t
	traps_per_county = route.info.get("traps", traps_per_county)
	for c in route.crossroads:
		if c.name == COUNTY_LINE_ROAD:
			county_line = c.station
	siren = Siren.new()
	add_child(siren)
	reset(seed_value)


## Clear the road of cruisers and set new traps.
func reset(seed_value: int) -> void:
	_end_chase_quietly()
	for trap in traps:
		_free_car(trap)
	traps.clear()
	_rng.seed = seed_value
	for county: String in traps_per_county:
		var spots: Array[float] = []
		for c in route.crossroads:
			var s: float = c.station + PARK_PAST
			var in_county: bool = county_at(s) == county and absf(s - county_line) > 150.0
			var by_bridge := not route.deck_at(s, RouteData.RAIL_APPROACH_M + 15.0).is_empty()
			if c.kind == "road" and in_county and not by_bridge and s > route.start_station + 150.0 \
					and s < route.finish_station - 400.0:
				spots.append(s)
		var count: int = traps_per_county[county]
		for i in count:
			spots = spots.filter(func(s): return traps.all(func(t): return absf(t.station - s) > TRAP_SPACING))
			if spots.is_empty():
				break
			var trap := Trap.new()
			trap.station = spots[_rng.randi() % spots.size()]
			trap.county = county
			traps.append(trap)
	traps.sort_custom(func(a, b): return a.station < b.station)


func county_at(station: float) -> String:
	return "Washington" if station < county_line else "Johnson"


func chasing() -> bool:
	return chase != null


## For the HUD: who's after you and how close, or "" when nobody is.
func status() -> String:
	if chase == null:
		return ""
	var gap := chaser.car.global_position.distance_to(player.global_position)
	var line := "%s County deputy  ·  %d m" % [chaser.county, roundi(gap)]
	if chase.bust_timer > 0.0:
		line = "PULL OVER!  Busted in %.1f" % maxf(Pursuit.BUST_SECONDS - chase.bust_timer, 0.0)
	return line


## Start a chase with a deputy right behind the player (for screenshots and testing).
func chase_from_behind(distance := 25.0) -> void:
	var trap := Trap.new()
	trap.station = player.station - distance
	trap.county = county_at(player.station)
	traps.append(trap)
	_spawn_car(trap)
	trap.car.place_at(trap.station, 1.83)
	trap.car.freeze = false
	_start(trap)


## End the chase with the player caught (the tow truck isn't getting you out of this).
func bust() -> void:
	if chase:
		_end(Pursuit.Outcome.BUSTED)


func cop_cars() -> Array[Car]:
	var out: Array[Car] = []
	for trap in traps:
		if trap.car:
			out.append(trap.car)
	return out


func _physics_process(delta: float) -> void:
	if player == null or not enabled:
		return
	for trap in traps:
		var ahead := trap.station - player.station
		var near := ahead < SPAWN_AHEAD and ahead > -SPAWN_BEHIND
		if trap.car == null and near and not trap.done:
			_spawn_car(trap)
		elif trap.car and trap != chaser and not near:
			_free_car(trap)
		elif trap.car and trap != chaser:
			# Parked (or pulled over after its chase): real physics only near the player.
			trap.car.freeze = trap.car.global_position.distance_to(player.global_position) > PHYSICS_RANGE
	if chase == null:
		_watch_radar()
	else:
		_run_chase(delta)


func _watch_radar() -> void:
	if player.driver == null or run.tracker.over():
		return
	for trap in traps:
		if trap.car and not trap.done:
			var distance := trap.car.global_position.distance_to(player.global_position)
			if Pursuit.spotted(distance, player.linear_velocity.length()):
				_start(trap)
				return


func _start(trap: Trap) -> void:
	chaser = trap
	chase = Pursuit.new(trap.county)
	_rails = false
	_cop_rolled = 0.0
	trap.car.freeze = false
	trap.driver.mode = CopDriver.Mode.CHASING
	trap.driver.target = player
	trap.driver.chase_speed = Pursuit.chase_speed(trap.car.stats, player.stats)
	trap.car.model.set_beacons(true)
	siren.reparent(trap.car, false)
	siren.position = Vector3.ZERO
	siren.on = true
	traffic.sirens.append(trap.car)
	chase_started.emit(trap.county)


func _run_chase(delta: float) -> void:
	var car := chaser.car
	var gap := car.global_position.distance_to(player.global_position)
	_update_rails(gap, delta)
	_cop_rolled = _cop_rolled + delta if car.global_transform.basis.y.y < 0.3 and not _rails else 0.0
	var wrecked := car.health <= 0.0 or _cop_rolled > 2.0
	var outcome := chase.update(delta, gap, player.linear_velocity.length(), county_at(player.station), wrecked)
	if outcome != Pursuit.Outcome.NONE:
		_end(outcome)


## Far back, there's no ground under the cruiser: freeze it and move it along the road
## toward the player at its chase speed, then hand it back to the physics when it's close.
func _update_rails(gap: float, delta: float) -> void:
	var car := chaser.car
	if not _rails and gap > PHYSICS_RANGE + RAILS_MARGIN:
		_rails = true
		car.freeze = true
		_rail_station = car.station
	elif _rails and gap < PHYSICS_RANGE:
		_rails = false
		car.freeze = false
		var dir := 1.0 if player.station >= _rail_station else -1.0
		car.linear_velocity = route.tangent_at(_rail_station) * dir * chaser.driver.chase_speed * 0.9
		car.reset_physics_interpolation()
	if not _rails:
		return
	var to_go := player.station - _rail_station
	var dir := signf(to_go) if absf(to_go) > 5.0 else 0.0
	_rail_station += dir * minf(chaser.driver.chase_speed * 0.95 * delta, absf(to_go))
	var heading := route.tangent_at(_rail_station) * (dir if dir != 0.0 else 1.0)
	var pos := route.position_at(_rail_station) + route.right_at(_rail_station) * (1.83 * (dir if dir != 0.0 else 1.0))
	pos.y += RIDE_HEIGHT
	car.global_transform = Transform3D(Basis.looking_at(Vector3(heading.x, 0.0, heading.z).normalized(), Vector3.UP), pos)
	car.station = _rail_station


func _end(outcome: Pursuit.Outcome) -> void:
	var trap := chaser
	trap.done = true
	var scoring := run.tracker.running()
	match outcome:
		Pursuit.Outcome.BUSTED:
			trap.driver.mode = CopDriver.Mode.PARKED
			run.wreck("Busted")
		Pursuit.Outcome.JURISDICTION:
			if scoring:
				run.score.add("Jurisdiction", JURISDICTION_POINTS)
		Pursuit.Outcome.LOST:
			if scoring:
				run.score.add("Lost the cop", LOST_POINTS)
		Pursuit.Outcome.GAVE_UP:
			if scoring:
				run.score.add("Outlasted the cop", LOST_POINTS)
	if outcome != Pursuit.Outcome.BUSTED:
		trap.driver.mode = CopDriver.Mode.GIVING_UP
		trap.car.model.set_beacons(false)
	_end_chase_quietly()
	chase_ended.emit(outcome)


func _end_chase_quietly() -> void:
	if chaser:
		traffic.sirens.erase(chaser.car)
	siren.on = false
	if siren.get_parent() != self:
		siren.reparent(self, false)
	chase = null
	chaser = null
	_rails = false


func _spawn_car(trap: Trap) -> void:
	var car := Car.new()
	add_child(car)
	car.setup(CarStats.preset("cruiser_" + trap.county.to_lower()), route)
	car.headlights = night
	trap.driver = CopDriver.new()
	car.driver = trap.driver
	car.place_at(trap.station, PARK_OFFSET)
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Ramming a parked cruiser gets its attention too.
	car.hit.connect(func(_damage, _smash):
		if chase == null and not trap.done and player.global_position.distance_to(car.global_position) < 15.0:
			_start(trap))
	trap.car = car
	traffic.other_cars.append(car)


func _free_car(trap: Trap) -> void:
	if trap.car == null:
		return
	traffic.other_cars.erase(trap.car)
	traffic.sirens.erase(trap.car)
	if siren.get_parent() == trap.car:
		siren.reparent(self, false)
	trap.car.queue_free()
	trap.car = null
