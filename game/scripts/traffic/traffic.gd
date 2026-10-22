class_name Traffic
extends Node3D
## Other road users. Slow things in your lane to get around (Amish buggies near Kalona,
## tractors pulling hay wagons, the odd 45-mph sedan) and oncoming cars, pickups and
## semis. They keep their lanes, keep their distance, and brake for the player.
##
## Scores: a near miss with oncoming traffic, and a clean pass of anything in your lane
## (a close one counts extra). Near misses and close passes fill the boost meter.
## Hitting a vehicle is a real crash (damage, momentum, it tumbles away as a wreck);
## a head-on at speed or touching a buggy ends the run.
##
## Vehicles appear and disappear far enough away that the haze hides it. They pull
## onto the shoulder and slow down for a cruiser with its lights on, and they can be
## hit by one.

const LANE := 1.83
const SHOULDER_LANE := 2.6  ## buggies and tractors hug the edge
const SPAWN_AHEAD_MIN := 2000.0
const SPAWN_AHEAD_MAX := 2600.0
const DESPAWN_BEHIND := 900.0
const MAX_SAME_DIRECTION := 6  ## ahead of the player
const MAX_ONCOMING := 6  ## ahead of the player
const MAX_WRECKS := 8  ## past this, the farthest goes
const WRECK_RANGE := 900.0  ## wrecks further than this from the car are cleared away
const HEAD_ON_SPEED := 25.0  ## closing speed (m/s) at which a head-on ends the run
const NEAR_MISS_GAP := 1.2  ## meters between mirrors
const YIELD_RANGE := 250.0  ## m: pull over for a siren coming up this close
const YIELD_SHIFT := 2.4  ## m further out, onto the shoulder
const NEAR_MISS_POINTS := 250
const CLOSE_PASS_POINTS := 100  ## on top of the pass, for squeezing by within NEAR_MISS_GAP

## length/width (m), mass (kg), speed range (m/s), footprint center along the vehicle
## (meters toward the back), points for passing it, and the run-over message.
const KINDS := {
	"car": {"length": 4.7, "width": 1.8, "mass": 1500.0, "speed": [24.0, 29.0], "center": 0.0, "pass": 100},
	"pickup": {"length": 5.5, "width": 2.0, "mass": 2300.0, "speed": [24.0, 29.0], "center": 0.0, "pass": 100},
	"semi": {"length": 21.4, "width": 2.6, "mass": 30000.0, "speed": [23.0, 26.0], "center": -0.5, "pass": 300},
	"buggy": {"length": 5.0, "width": 1.6, "mass": 700.0, "speed": [4.0, 5.0], "center": -0.65, "pass": 150},
	"tractor": {"length": 9.2, "width": 2.4, "mass": 6000.0, "speed": [7.0, 9.0], "center": 0.0, "pass": 200},
	"combine": {"length": 10.5, "width": 4.2, "mass": 15000.0, "speed": [6.0, 8.0], "center": -0.3, "pass": 400},
	"grain_truck": {"length": 10.6, "width": 2.5, "mass": 14000.0, "speed": [20.0, 24.0], "center": -0.8, "pass": 150},
	"snowplow": {"length": 10.6, "width": 3.4, "mass": 16000.0, "speed": [12.0, 15.0], "center": -0.5, "pass": 250},
}
## Where the slow ones drive: buggies and tractors hug the edge; a combine's header spills
## onto the shoulder (and still nearly fills the lane).
const LANES := {"buggy": SHOULDER_LANE, "tractor": SHOULDER_LANE, "combine": 2.6}


class Vehicle:
	var kind: String
	var node: MeshInstance3D
	var station: float
	var direction: float  ## +1 northbound (with the player), -1 oncoming
	var offset: float  ## meters right of the centerline, now
	var lane: float  ## meters right of the centerline it normally keeps to
	var yielding := false  ## pulled over for a siren
	var cruise: float
	var speed: float
	var passed := false  ## scored (passed or near-missed) already
	var closest := INF  ## m between mirrors while the player was alongside (overtaking)
	var touched := false
	var last_gap := INF  ## station ahead of the player last tick (oncoming near-miss check)


var route: RouteData
var car: Car
var run: Run
var enabled := true
var vehicles: Array[Vehicle] = []
var other_cars: Array[Car] = []  ## besides the player's: police cruisers, which can hit traffic too
## What turns up after the buggies (absolute shares; the last takes the rest), set by the
## condition: tractors and slowpokes in summer, combines and grain trucks at harvest...
var same_mix := {"tractor": 0.3, "car": 0.7}
var oncoming_mix := {"semi": 0.2, "pickup": 0.3, "car": 0.5}
var night := false  ## head and tail lights on
var sirens: Array[Car] = []  ## cruisers with their lights on
var _wrecks: Array[RigidBody3D] = []
var _rng := RandomNumberGenerator.new()
var _oncoming_timer := 0.0
var _same_timer := 0.0
## The closest a vehicle has been to the car when it appeared or disappeared (checked by
## the QA drive).
var nearest_pop_in := INF
var nearest_pop_out := INF


func setup(r: RouteData, c: Car, game_run: Run, seed_value := 1) -> void:
	route = r
	car = c
	run = game_run
	_rng.seed = seed_value


func reset() -> void:
	for v in vehicles:
		v.node.queue_free()
	vehicles.clear()
	for w in _wrecks:
		w.queue_free()
	_wrecks.clear()
	_oncoming_timer = 0.0
	_same_timer = 0.0


func _physics_process(delta: float) -> void:
	if car == null or not enabled:
		return
	_spawn(delta)
	for v in vehicles:
		_drive(v, delta)
	_check_player()
	_cleanup()


## The nearest vehicle ahead of `station` going `direction` (within `reach`), or null.
## Pulled-over vehicles count unless `include_yielding` is false (they're on the
## shoulder, out of the lane).
func leader(station: float, direction: float, reach: float, include_yielding := true) -> Vehicle:
	var best: Vehicle = null
	for v in vehicles:
		var gap := (v.station - station) * direction
		if v.direction == direction and gap > 0.0 and gap < reach and (best == null or gap < (best.station - station) * direction) \
				and (include_yielding or not v.yielding):
			best = v
	return best


## Crashed vehicles (physics bodies).
func wreck_bodies() -> Array[RigidBody3D]:
	return _wrecks.duplicate()


## True when no oncoming vehicle is within `distance` ahead of `station`.
func oncoming_clear(station: float, distance: float) -> bool:
	for v in vehicles:
		if v.direction < 0.0 and v.station > station - 10.0 and v.station < station + distance:
			return false
	return true


func _spawn(delta: float) -> void:
	_oncoming_timer -= delta
	_same_timer -= delta
	var mile := route.mile_at(car.station)
	if _oncoming_timer <= 0.0 and _count(-1.0) < MAX_ONCOMING:
		_oncoming_timer = _rng.randf_range(5.0, 12.0)
		_add(_pick(oncoming_mix, _rng.randf(), 0.0), -1.0)
	if _same_timer <= 0.0 and _count(1.0) < MAX_SAME_DIRECTION:
		_same_timer = _rng.randf_range(8.0, 20.0)
		var buggy_odds := 0.5 if mile < 5.0 else 0.15  # Kalona is Amish country
		var roll := _rng.randf()
		_add("buggy" if roll < buggy_odds else _pick(same_mix, roll, buggy_odds), 1.0)


## The kind a roll lands on, walking the shares up from `start`.
static func _pick(mix: Dictionary, roll: float, start: float) -> String:
	var acc := start
	var last := ""
	for kind: String in mix:
		if float(mix[kind]) <= 0.0:
			continue
		acc += float(mix[kind])
		last = kind
		if roll < acc:
			return kind
	return last


func apply_condition(c: Condition) -> void:
	same_mix = c.same_direction
	oncoming_mix = c.oncoming
	night = c.night > 0.5


## Vehicles going `direction` that are still ahead of the player.
func _count(direction: float) -> int:
	return vehicles.filter(func(v): return v.direction == direction and v.station > car.station).size()


## Put a few vehicles right in view (for screenshots and demos).
func populate_near() -> void:
	var slow := "tractor"
	for kind in ["combine", "snowplow"]:
		if same_mix.has(kind):
			slow = kind
	_add("buggy", 1.0, car.station + 22.0)
	_add(slow, 1.0, car.station + 110.0)
	_add("car", -1.0, car.station + 60.0)
	_add("grain_truck" if oncoming_mix.has("grain_truck") else "semi", -1.0, car.station + 160.0)
	_oncoming_timer = 20.0
	_same_timer = 30.0


func _add(kind: String, direction: float, station := -1.0) -> void:
	var streaming := station < 0.0
	if streaming:
		station = car.station + _rng.randf_range(SPAWN_AHEAD_MIN, SPAWN_AHEAD_MAX)
	if station > route.length - 50.0:
		return
	for v in vehicles:
		if v.direction == direction and absf(v.station - station) < 80.0:
			return
	var spec: Dictionary = KINDS[kind]
	var v := Vehicle.new()
	v.kind = kind
	v.station = station
	v.direction = direction
	v.lane = float(LANES.get(kind, LANE)) * direction
	v.offset = v.lane
	v.cruise = _rng.randf_range(spec.speed[0], spec.speed[1])
	if direction > 0.0 and kind == "car":
		v.cruise = _rng.randf_range(18.0, 21.0)  # the slowpoke you have to get around
	v.speed = v.cruise
	v.node = MeshInstance3D.new()
	v.node.mesh = TrafficModels.build(kind, _rng)
	v.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if night:
		v.node.add_child(TrafficModels.lamps(kind, spec))
	add_child(v.node)
	vehicles.append(v)
	_place(v)
	v.node.reset_physics_interpolation()
	if streaming:
		nearest_pop_in = minf(nearest_pop_in, v.node.global_position.distance_to(car.global_position))


func _drive(v: Vehicle, delta: float) -> void:
	var spec: Dictionary = KINDS[v.kind]
	var wanted := v.cruise
	# Keep a gap to whoever's ahead in the lane.
	var ahead := leader(v.station, v.direction, 60.0)
	if ahead:
		var gap: float = absf(ahead.station - v.station) - (spec.length + KINDS[ahead.kind].length) / 2.0
		wanted = minf(wanted, maxf(0.0, ahead.speed + (gap - 15.0) * 0.5))
	# Brake for the player when they're in this lane ahead.
	var player_gap: float = (car.station - v.station) * v.direction - spec.length / 2.0
	var in_lane := car.lateral * v.direction > 0.2
	if in_lane and player_gap > 0.0 and player_gap < v.speed * 1.6 + 15.0:
		wanted = 0.0
	# A siren coming up: onto the shoulder and slow down until it's gone by.
	v.yielding = false
	for siren in sirens:
		var behind := v.station - siren.station
		if behind > -20.0 and behind < YIELD_RANGE:
			v.yielding = true
	if v.yielding:
		wanted = minf(wanted, v.cruise * 0.35)
	var lane_target := v.lane + signf(v.lane) * YIELD_SHIFT if v.yielding else v.lane
	v.offset = move_toward(v.offset, lane_target, 1.5 * delta)
	var rate := 2.0 if wanted > v.speed else 6.0
	v.speed = move_toward(v.speed, wanted, rate * delta)
	v.station += v.direction * v.speed * delta
	_place(v)


func _place(v: Vehicle) -> void:
	var center := route.position_at(v.station)
	var pos := center + route.right_at(v.station) * v.offset
	pos.y = center.y + 0.03
	var forward := route.tangent_at(v.station) * v.direction
	forward.y = 0.0
	v.node.global_transform = Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), pos)


func _check_player() -> void:
	for c: Car in [car] + other_cars:
		var car_pos := Vector2(c.global_position.x, c.global_position.z)
		var car_fwd := Vector2(-c.global_transform.basis.z.x, -c.global_transform.basis.z.z).normalized()
		var car_half := Vector2(c.stats.body_size.x, c.stats.body_size.z) / 2.0
		for v: Vehicle in vehicles.duplicate():
			var spec: Dictionary = KINDS[v.kind]
			var fwd3: Vector3 = -v.node.global_transform.basis.z
			var fwd := Vector2(fwd3.x, fwd3.z).normalized()
			var center: Vector2 = Vector2(v.node.global_position.x, v.node.global_position.z) - fwd * spec.center
			var half := Vector2(spec.width, spec.length) / 2.0
			var dy := absf(c.global_position.y - v.node.global_position.y)
			var push := push_apart(car_pos, car_fwd, car_half, center, fwd, half)
			if dy < 4.0 and push != Vector2.ZERO:
				_collide(v, push, c)
				continue
			if c == car:
				_score_pass(v, spec)


func _score_pass(v: Vehicle, spec: Dictionary) -> void:
	if v.passed or v.touched or not run.tracker.running():
		return
	var gap := v.station - car.station
	var mirrors: float = absf(car.lateral - v.offset) - (car.stats.body_size.x + spec.width) / 2.0
	if v.direction > 0.0:
		var overlap: float = spec.length / 2.0 + car.stats.body_size.z / 2.0
		if absf(gap) < overlap:
			v.closest = minf(v.closest, mirrors)
		# Overtook it: the player's whole car is past its front.
		if gap < -(overlap + 2.0):
			v.passed = true
			run.score.add("Passed: %s" % v.kind, spec.pass)
			if v.closest < NEAR_MISS_GAP:
				run.score.add("Close pass", CLOSE_PASS_POINTS)
				car.boost.fill(Boost.CLOSE_PASS)
		return
	# Oncoming: when it goes by, how close were the mirrors?
	if v.last_gap > 0.0 and gap <= 0.0:
		v.passed = true
		var closing := car.forward_speed() + v.speed
		if mirrors < NEAR_MISS_GAP and closing > 20.0:
			run.score.add("Near miss", NEAR_MISS_POINTS)
			car.boost.fill(Boost.NEAR_MISS)
	v.last_gap = gap


## A crash with a vehicle: momentum, damage, maybe the end of the run, and the vehicle
## leaves traffic as a physics wreck. `push` moves the vehicle's footprint off the car's:
## at highway speeds the car is up to a meter into it by the time they're seen to touch.
func _collide(v: Vehicle, push: Vector2, c: Car) -> void:
	var spec: Dictionary = KINDS[v.kind]
	v.touched = true
	var v_velocity := -v.node.global_transform.basis.z * v.speed
	var closing := (c.linear_velocity - v_velocity).length()
	var m_car := c.stats.mass
	var m_v: float = spec.mass
	var shared := (c.linear_velocity * m_car + v_velocity * m_v) / (m_car + m_v)
	var head_on := c.linear_velocity.dot(v_velocity) < 0.0 and closing > HEAD_ON_SPEED
	var damage := closing * 2.2 * clampf(2.0 * m_v / (m_v + m_car), 0.3, 1.5)
	# Start them just touching, then both leave at the shared velocity, nudged apart.
	var apart := Vector3(push.x, 0.0, push.y)
	v.node.global_position += apart + apart.normalized() * 0.05
	var away := -apart.normalized() * 2.5
	c.bump_to(shared + away, damage)
	if c == car:
		if v.kind == "buggy":
			run.wreck("You hit an Amish buggy")
		elif head_on:
			run.wreck("Head-on with a %s" % v.kind)
	_make_wreck(v, shared - away * m_car / m_v)


func _make_wreck(v: Vehicle, velocity: Vector3) -> void:
	vehicles.erase(v)
	var spec: Dictionary = KINDS[v.kind]
	var body := RigidBody3D.new()
	body.mass = spec.mass
	body.collision_layer = 1 << (Car.WRECK_LAYER - 1)
	body.collision_mask = (1 << (Car.WORLD_LAYER - 1)) | (1 << (Car.CAR_LAYER - 1))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(spec.width, 1.6, spec.length)
	shape.shape = box
	shape.position = Vector3(0, 0.9, spec.center)
	body.add_child(shape)
	add_child(body)
	body.global_transform = v.node.global_transform
	body.reset_physics_interpolation()
	v.node.reparent(body)
	body.linear_velocity = velocity + Vector3.UP * 1.5
	body.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-3, 3), _rng.randf_range(-1, 1))
	_wrecks.append(body)


func _cleanup() -> void:
	var here := car.global_position
	for v: Vehicle in vehicles.duplicate():
		var left_behind := car.station - v.station > DESPAWN_BEHIND
		if left_behind or v.station < 0.0 or v.station > route.length:  # or off the end of the map
			if left_behind:
				nearest_pop_out = minf(nearest_pop_out, v.node.global_position.distance_to(here))
			v.node.queue_free()
			vehicles.erase(v)
	# Wrecks stay where they land until the car is far away (or there are too many, when
	# the farthest goes), so nothing vanishes in front of you.
	_wrecks.sort_custom(func(a, b): return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	while not _wrecks.is_empty() and (_wrecks.size() > MAX_WRECKS or _wrecks[-1].global_position.distance_to(here) > WRECK_RANGE):
		_wrecks.pop_back().queue_free()


## Do two rectangles on the ground overlap? Each is a center, a unit forward direction
## and half extents (half width, half length).
static func overlaps(c1: Vector2, f1: Vector2, h1: Vector2, c2: Vector2, f2: Vector2, h2: Vector2) -> bool:
	return push_apart(c1, f1, h1, c2, f2, h2) != Vector2.ZERO


## The shortest move that takes rectangle 2 off rectangle 1 (rectangles as in
## overlaps()), or Vector2.ZERO when they don't overlap. Separating-axis test.
static func push_apart(c1: Vector2, f1: Vector2, h1: Vector2, c2: Vector2, f2: Vector2, h2: Vector2) -> Vector2:
	var r1 := Vector2(-f1.y, f1.x)
	var r2 := Vector2(-f2.y, f2.x)
	var d := c2 - c1
	var push := Vector2.ZERO
	var least := INF
	for axis: Vector2 in [f1, r1, f2, r2]:
		var reach1 := absf(f1.dot(axis)) * h1.y + absf(r1.dot(axis)) * h1.x
		var reach2 := absf(f2.dot(axis)) * h2.y + absf(r2.dot(axis)) * h2.x
		var along := d.dot(axis)
		var depth := reach1 + reach2 - absf(along)
		if depth <= 0.0:
			return Vector2.ZERO
		if depth < least:
			least = depth
			push = axis * (depth if along >= 0.0 else -depth)
	return push
