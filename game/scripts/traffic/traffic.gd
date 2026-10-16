class_name Traffic
extends Node3D
## Other road users. Slow things in your lane to get around (Amish buggies near Kalona,
## tractors pulling hay wagons, the odd 45-mph sedan) and oncoming cars, pickups and
## semis. They keep their lanes, keep their distance, and brake for the player.
##
## Scores: a near miss with oncoming traffic, and a clean pass of anything in your lane.
## Hitting a vehicle is a real crash (damage, momentum, it tumbles away as a wreck);
## a head-on at speed or touching a buggy ends the run.

const LANE := 1.83
const SHOULDER_LANE := 2.6  ## buggies and tractors hug the edge
const SPAWN_AHEAD_MIN := 900.0
const SPAWN_AHEAD_MAX := 1300.0
const DESPAWN_BEHIND := 400.0
const MAX_SAME_DIRECTION := 3
const MAX_ONCOMING := 4
const WRECK_LIFETIME := 30.0
const HEAD_ON_SPEED := 25.0  ## closing speed (m/s) at which a head-on ends the run
const NEAR_MISS_GAP := 1.2  ## meters between mirrors
const NEAR_MISS_POINTS := 250

## length/width (m), mass (kg), speed range (m/s), footprint center along the vehicle
## (meters toward the back), points for passing it, and the run-over message.
const KINDS := {
	"car": {"length": 4.7, "width": 1.8, "mass": 1500.0, "speed": [24.0, 29.0], "center": 0.0, "pass": 100},
	"pickup": {"length": 5.5, "width": 2.0, "mass": 2300.0, "speed": [24.0, 29.0], "center": 0.0, "pass": 100},
	"semi": {"length": 21.4, "width": 2.6, "mass": 30000.0, "speed": [23.0, 26.0], "center": -0.5, "pass": 300},
	"buggy": {"length": 5.0, "width": 1.6, "mass": 700.0, "speed": [4.0, 5.0], "center": -0.65, "pass": 150},
	"tractor": {"length": 9.2, "width": 2.4, "mass": 6000.0, "speed": [7.0, 9.0], "center": 0.0, "pass": 200},
}


class Vehicle:
	var kind: String
	var node: MeshInstance3D
	var station: float
	var direction: float  ## +1 northbound (with the player), -1 oncoming
	var offset: float  ## meters right of the centerline
	var cruise: float
	var speed: float
	var passed := false  ## scored (passed or near-missed) already
	var touched := false
	var last_gap := INF  ## station ahead of the player last tick (oncoming near-miss check)


var route: RouteData
var car: Car
var run: Run
var enabled := true
var vehicles: Array[Vehicle] = []
var _wrecks: Array = []  ## [RigidBody3D, age]
var _rng := RandomNumberGenerator.new()
var _oncoming_timer := 0.0
var _same_timer := 0.0


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
		w[0].queue_free()
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
	_cleanup(delta)


## The nearest vehicle ahead of `station` going `direction` (within `reach`), or null.
func leader(station: float, direction: float, reach: float) -> Vehicle:
	var best: Vehicle = null
	for v in vehicles:
		var gap := (v.station - station) * direction
		if v.direction == direction and gap > 0.0 and gap < reach and (best == null or gap < (best.station - station) * direction):
			best = v
	return best


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
		var roll := _rng.randf()
		_add("semi" if roll < 0.2 else ("pickup" if roll < 0.5 else "car"), -1.0)
	if _same_timer <= 0.0 and _count(1.0) < MAX_SAME_DIRECTION:
		_same_timer = _rng.randf_range(8.0, 20.0)
		var buggy_odds := 0.5 if mile < 5.0 else 0.15  # Kalona is Amish country
		var roll := _rng.randf()
		_add("buggy" if roll < buggy_odds else ("tractor" if roll < buggy_odds + 0.3 else "car"), 1.0)


func _count(direction: float) -> int:
	return vehicles.filter(func(v): return v.direction == direction).size()


## Put a few vehicles right in view (for screenshots and demos).
func populate_near() -> void:
	_add("buggy", 1.0, car.station + 22.0)
	_add("tractor", 1.0, car.station + 110.0)
	_add("car", -1.0, car.station + 60.0)
	_add("semi", -1.0, car.station + 160.0)
	_oncoming_timer = 20.0
	_same_timer = 30.0


func _add(kind: String, direction: float, station := -1.0) -> void:
	if station < 0.0:
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
	var slow := kind == "buggy" or kind == "tractor"
	v.offset = (SHOULDER_LANE if slow else LANE) * direction
	v.cruise = _rng.randf_range(spec.speed[0], spec.speed[1])
	if direction > 0.0 and kind == "car":
		v.cruise = _rng.randf_range(18.0, 21.0)  # the slowpoke you have to get around
	v.speed = v.cruise
	v.node = MeshInstance3D.new()
	v.node.mesh = TrafficModels.build(kind, _rng)
	v.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(v.node)
	vehicles.append(v)
	_place(v)
	v.node.reset_physics_interpolation()


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
	var car_pos := Vector2(car.global_position.x, car.global_position.z)
	var car_fwd := Vector2(-car.global_transform.basis.z.x, -car.global_transform.basis.z.z).normalized()
	var car_half := Vector2(car.stats.body_size.x, car.stats.body_size.z) / 2.0
	for v: Vehicle in vehicles.duplicate():
		var spec: Dictionary = KINDS[v.kind]
		var fwd3: Vector3 = -v.node.global_transform.basis.z
		var fwd := Vector2(fwd3.x, fwd3.z).normalized()
		var center: Vector2 = Vector2(v.node.global_position.x, v.node.global_position.z) - fwd * spec.center
		var half := Vector2(spec.width, spec.length) / 2.0
		var dy := absf(car.global_position.y - v.node.global_position.y)
		if dy < 4.0 and overlaps(car_pos, car_fwd, car_half, center, fwd, half):
			_collide(v)
			continue
		_score_pass(v, spec)


func _score_pass(v: Vehicle, spec: Dictionary) -> void:
	if v.passed or v.touched or not run.tracker.running():
		return
	var gap := v.station - car.station
	if v.direction > 0.0:
		# Overtook it: the player's whole car is past its front.
		if gap < -(spec.length / 2.0 + car.stats.body_size.z / 2.0 + 2.0):
			v.passed = true
			run.score.add("Passed: %s" % v.kind, spec.pass)
		return
	# Oncoming: when it goes by, how close were the mirrors?
	if v.last_gap > 0.0 and gap <= 0.0:
		v.passed = true
		var mirrors: float = absf(car.lateral - v.offset) - (car.stats.body_size.x + spec.width) / 2.0
		var closing := car.forward_speed() + v.speed
		if mirrors < NEAR_MISS_GAP and closing > 20.0:
			run.score.add("Near miss", NEAR_MISS_POINTS)
	v.last_gap = gap


## A crash with a vehicle: momentum, damage, maybe the end of the run, and the vehicle
## leaves traffic as a physics wreck.
func _collide(v: Vehicle) -> void:
	var spec: Dictionary = KINDS[v.kind]
	v.touched = true
	var v_velocity := -v.node.global_transform.basis.z * v.speed
	var closing := (car.linear_velocity - v_velocity).length()
	var m_car := car.stats.mass
	var m_v: float = spec.mass
	var shared := (car.linear_velocity * m_car + v_velocity * m_v) / (m_car + m_v)

	if v.kind == "buggy":
		run.wreck("You hit an Amish buggy")
		car.bump(0.3, 0.0, false)
		v.speed = 0.0
		v.cruise = 0.0
		return
	var head_on := car.linear_velocity.dot(v_velocity) < 0.0 and closing > HEAD_ON_SPEED
	var damage := closing * 2.2 * clampf(2.0 * m_v / (m_v + m_car), 0.3, 1.5)
	# Both leave at the shared velocity, nudged apart so they don't start out overlapped.
	var away := car.global_position - v.node.global_position
	away.y = 0.0
	away = away.normalized() * 2.5
	car.bump_to(shared + away, damage)
	if head_on:
		run.wreck("Head-on with a %s" % v.kind)
	_make_wreck(v, shared - away * m_car / m_v)


func _make_wreck(v: Vehicle, velocity: Vector3) -> void:
	vehicles.erase(v)
	var spec: Dictionary = KINDS[v.kind]
	var body := RigidBody3D.new()
	body.mass = spec.mass
	body.collision_layer = 1 << (Car.WRECK_LAYER - 1)
	body.collision_mask = 1 << (Car.WORLD_LAYER - 1)  # the car is added once they've separated
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(spec.width, 1.6, spec.length)
	shape.shape = box
	shape.position = Vector3(0, 0.9, spec.center)
	body.add_child(shape)
	add_child(body)
	body.global_transform = v.node.global_transform
	v.node.reparent(body)
	body.linear_velocity = velocity + Vector3.UP * 1.5
	body.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-3, 3), _rng.randf_range(-1, 1))
	_wrecks.append([body, 0.0])


func _cleanup(delta: float) -> void:
	for v: Vehicle in vehicles.duplicate():
		var behind := (car.station - v.station) * v.direction
		if behind > DESPAWN_BEHIND or v.station < 0.0 or v.station > route.length:
			v.node.queue_free()
			vehicles.erase(v)
	for i in range(_wrecks.size() - 1, -1, -1):
		var w: Array = _wrecks[i]
		w[1] += delta
		var body: RigidBody3D = w[0]
		if w[1] > 0.6:
			body.collision_mask |= 1 << (Car.CAR_LAYER - 1)  # now solid to the player too
		if w[1] > WRECK_LIFETIME or body.global_position.distance_to(car.global_position) > 600.0:
			body.queue_free()
			_wrecks.remove_at(i)


## Do two rectangles on the ground overlap? Each is a center, a unit forward direction
## and half extents (half width, half length). Separating-axis test.
static func overlaps(c1: Vector2, f1: Vector2, h1: Vector2, c2: Vector2, f2: Vector2, h2: Vector2) -> bool:
	var r1 := Vector2(-f1.y, f1.x)
	var r2 := Vector2(-f2.y, f2.x)
	var d := c2 - c1
	for axis in [f1, r1, f2, r2]:
		var reach1 := absf(f1.dot(axis)) * h1.y + absf(r1.dot(axis)) * h1.x
		var reach2 := absf(f2.dot(axis)) * h2.y + absf(r2.dot(axis)) * h2.x
		if absf(d.dot(axis)) > reach1 + reach2:
			return false
	return true
