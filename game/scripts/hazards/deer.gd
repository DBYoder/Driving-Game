class_name Deer
extends Node3D
## White-tailed deer bolting across the road. Each run picks crossing spots, most of them
## at the creeks (where the road bridges them) and a few anywhere. Come up on one above
## 30 mph and a herd of one to three breaks from the field, pacing itself to cross ahead
## of you: the first well ahead, the ones behind it closer and closer. Sometimes the
## first one stops dead in your lane and stares, then bolts at the last moment (and
## sometimes back the way it came).
##
## It's fair: hold your speed and your line and they all miss you, if only just. One that
## can't get across ahead of you in time (you sped up) stops at the roadside and crosses
## behind you instead. Speed up after they've committed, or swerve the wrong way, and
## you'll hit one: big damage, the combo's gone, and the deer goes tumbling off (no gore).
## A deer in your path that you don't hit scores "Deer dodged".
##
## They break cover FIELD_START from the road with the car hundreds of meters back, out
## in the corn where you can't see them anyway.

const FIELD_START := 140.0  ## m from the centerline where they break cover
const RUN_SPEED := 12.0  ## m/s across the road
const BOLT_SPEED := 14.0
const MAX_PACE := 16.0
const LEADS := [1.8, 1.45, 1.1]  ## s each deer of a herd reaches the road ahead of the car
const FREEZE_LEAD := 3.0  ## s: one that's going to freeze gets there early, to stand and stare
const SAFE_LEAD := 1.1  ## s: can't reach the road this far ahead of the car? Wait for it to pass
const WAIT_LINE := 14.0  ## m from the centerline: where a deer waits for the car to go by
const MIN_CAR_SPEED := 13.4  ## m/s (30 mph): slower than this and they stay put
const COMMITTED := 20.0  ## m from the centerline: closer than this and it's going for it
const CREEK_CHANCE := 0.8
const RANDOM_SPOTS := 4
const SPOT_SPACING := 600.0
const FREEZE_CHANCE := 0.3  ## the first deer stops dead in your lane
const FREEZE_MAX := 2.5  ## s
const BOLT_TIMES := Vector2(0.6, 1.0)  ## s before the car gets there, a frozen deer bolts
const TURN_BACK_CHANCE := 0.3
const THREAT_TIME := 1.0  ## s: a deer in your path this close counts as dodged if you miss it
const HALF := Vector2(0.25, 0.8)  ## half width, half length
const MASS := 70.0
const DAMAGE_PER_MS := 1.1  ## car health per m/s of closing speed
const DODGE_POINTS := 100
const GONE_RANGE := 450.0


class Animal:
	var node: Node3D
	var legs: Array[Node3D] = []
	var pos: Vector3  ## on the ground
	var dir: Vector3  ## running direction (flat)
	var station: float  ## where it crosses the road
	var lead: float  ## s ahead of the car it means to reach the road
	var delay := 0.0  ## s before it starts running (a herd goes one after another)
	var speed := RUN_SPEED
	var phase := 0.0
	var will_freeze := false
	var frozen := false
	var froze_for := 0.0
	var bolt_time := 0.8
	var stays := false  ## never moves (QA: something to hit)
	var on_road_once := false
	var threat := false  ## was in the car's path, close
	var judged := false


class Spot:
	var station: float
	var side: float  ## the side of the road they come from: +1 right, -1 left
	var herd: int
	var freeze := false
	var used := false


var route: RouteData
var car: Car
var run: Run
var props: PropField
var traffic: Traffic
var enabled := true
## More deer: harvest dusk 1.6, night 3 (Condition.deer_rate). More crossings, closer together.
var rate := 1.0
var spots: Array[Spot] = []
var animals: Array[Animal] = []
var crossings := 0  ## herds that broke cover this run
var hits := 0  ## deer the player hit
var dodges := 0
var froze := 0
## The closest a deer has been to the car when it appeared (checked by the QA drive).
var nearest_pop_in := INF
var _mesh: ArrayMesh
var _leg_mesh: ArrayMesh
var _rng := RandomNumberGenerator.new()


func setup(r: RouteData, c: Car, game_run: Run, p: PropField, t: Traffic, seed_value: int) -> void:
	route = r
	car = c
	run = game_run
	props = p
	traffic = t
	_mesh = _body_mesh()
	_leg_mesh = _leg()
	reset(seed_value)


## Clear the deer away and pick this run's crossing spots.
func reset(seed_value: int) -> void:
	for a in animals:
		a.node.queue_free()
	animals.clear()
	spots.clear()
	crossings = 0
	hits = 0
	dodges = 0
	froze = 0
	_rng.seed = seed_value * 7919 + 3
	var candidates: Array[float] = []
	for b: Array in route.bridges:
		if _rng.randf() < minf(CREEK_CHANCE * rate, 1.0):
			candidates.append((float(b[0]) + float(b[1])) / 2.0)
	for i in roundi(RANDOM_SPOTS * rate * rate):
		candidates.append(_rng.randf_range(route.start_station + 600.0, route.finish_station - 400.0))
	for s in candidates:
		if s < route.start_station + 400.0 or s > route.finish_station - 200.0:
			continue
		var spacing := maxf(SPOT_SPACING / rate, 250.0)
		if spots.any(func(o: Spot) -> bool: return absf(o.station - s) < spacing):
			continue
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var herd := 1 + _rng.randi() % 3
		var freeze := _rng.randf() < FREEZE_CHANCE
		if _path_blocked(s, side):
			continue  # they'd have to run through a farmyard
		add_spot(s, side, herd, freeze)
	spots.sort_custom(func(a: Spot, b: Spot) -> bool: return a.station < b.station)


## Is there a building in the way of a herd running in from `side` and across at `station`?
func _path_blocked(station: float, side: float) -> bool:
	var start := route.position_at(station)
	var across := route.right_at(station) * side
	var a := Vector2(start.x, start.z) + Vector2(across.x, across.z) * (FIELD_START + 6.0)
	var b := Vector2(start.x, start.z) - Vector2(across.x, across.z) * 60.0
	for bl: Dictionary in route.buildings:
		var p := Vector2(float(bl.x), float(bl.z))
		var reach := maxf(float(bl.length), float(bl.width)) / 2.0 + 8.0
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < reach:
			return true
	for l: Dictionary in route.landmarks:
		for c: Array in l.clear:
			var p := Vector2((c[0] + c[2]) / 2.0, (c[1] + c[3]) / 2.0)
			var reach := maxf(c[2] - c[0], c[3] - c[1]) / 2.0 + 8.0
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < reach:
				return true
	return false


func add_spot(station: float, side: float, herd: int, freeze: bool) -> Spot:
	var spot := Spot.new()
	spot.station = station
	spot.side = side
	spot.herd = herd
	spot.freeze = freeze
	spots.append(spot)
	return spot


## Distance up the road to the nearest deer that's on the road or about to be, within
## `ahead` meters of `station`, or INF. For drivers: hold your speed.
func danger_ahead(station: float, ahead: float) -> float:
	var nearest := INF
	for a in animals:
		if a.delay > 0.0 or a.judged:
			continue
		var gap := a.station - station
		if gap > -5.0 and gap < ahead and absf(_lateral(a)) < COMMITTED:
			nearest = minf(nearest, maxf(gap, 0.0))
	return nearest


## A deer standing in the road `distance` ahead of the car, in its lane, that won't
## move (QA: something to hit).
func stand_in_road(distance: float) -> void:
	var spot := add_spot(car.station + distance, 1.0, 1, false)
	spot.used = true
	var a := _add_animal(spot, 0, car.lateral)
	a.stays = true
	a.on_road_once = true


## Send a herd across the road just ahead of the car: in 1.5 s (when a screenshot is
## taken) the first is in the lane, the others coming up behind it.
func cross_now(distance := 45.0) -> void:
	var spot := add_spot(car.station + distance, 1.0, 3, false)
	spot.used = true
	for i in spot.herd:
		var a := _add_animal(spot, i, 20.0 + i * 4.0)
		a.on_road_once = true


func _physics_process(delta: float) -> void:
	if car == null or not enabled:
		return
	var speed := car.linear_velocity.length()
	if speed >= MIN_CAR_SPEED:
		var run_time := (FIELD_START - RoadMesher.GRAVEL_HALF_WIDTH) / RUN_SPEED
		for spot in spots:
			var to_go := spot.station - car.station
			var lead: float = FREEZE_LEAD if spot.freeze else LEADS[0]
			if spot.used or to_go < 0.0 or to_go > speed * (run_time + lead):
				continue
			spot.used = true
			if to_go > speed * run_time * 0.75:  # still time to make it look natural
				_release(spot)
	for a in animals.duplicate():
		_move(a, delta)
		if animals.has(a):
			_check_hits(a)
		if animals.has(a) and a.pos.distance_to(car.global_position) > GONE_RANGE \
				and (a.on_road_once or a.station < car.station):
			a.node.queue_free()
			animals.erase(a)


func _release(spot: Spot) -> void:
	crossings += 1
	for i in spot.herd:
		var a := _add_animal(spot, i, FIELD_START + i * 2.0)
		a.delay = 0.0 if i == 0 else i * _rng.randf_range(0.4, 0.9)
		if i == 0 and spot.freeze:
			a.will_freeze = true
			a.lead = FREEZE_LEAD
		nearest_pop_in = minf(nearest_pop_in, a.pos.distance_to(car.global_position))


## Deer `i` of a spot's herd, `from` meters out on the spot's side, headed across.
func _add_animal(spot: Spot, i: int, from: float) -> Animal:
	var a := Animal.new()
	a.station = spot.station + i * _rng.randf_range(3.0, 6.0)
	a.lead = LEADS[mini(i, LEADS.size() - 1)]
	a.bolt_time = _rng.randf_range(BOLT_TIMES.x, BOLT_TIMES.y)
	var right := route.right_at(a.station)
	# Straight across, give or take: it passes through the crossing point either way.
	a.dir = (-right * spot.side).rotated(Vector3.UP, _rng.randf_range(-0.12, 0.12))
	var start := route.position_at(a.station) - a.dir * from
	a.pos = Vector3(start.x, _ground(start, a.station), start.z)
	a.phase = _rng.randf() * TAU
	a.node = _make_animal(a)
	add_child(a.node)
	_place(a)
	animals.append(a)
	return a


## Meters right of the centerline at the deer's crossing.
func _lateral(a: Animal) -> float:
	return (a.pos - route.position_at(a.station)).dot(route.right_at(a.station))


## Seconds until the car reaches the deer's crossing at the speed it's going now.
func _car_eta(a: Animal) -> float:
	var speed := maxf(car.linear_velocity.dot(route.tangent_at(car.station)), 1.0)
	return (a.station - car.station) / speed


func _move(a: Animal, delta: float) -> void:
	if a.delay > 0.0:
		a.delay -= delta
		return
	if a.stays:
		_place(a)
		return
	var lateral := _lateral(a)
	var heading_in := a.dir.dot(route.right_at(a.station)) * lateral < 0.0
	if absf(lateral) < RoadMesher.GRAVEL_HALF_WIDTH:
		a.on_road_once = true
	if not a.on_road_once and heading_in:
		var to_road := absf(lateral) - RoadMesher.GRAVEL_HALF_WIDTH
		var eta := _car_eta(a)
		if car.station > a.station + car.stats.body_size.z:
			a.speed = RUN_SPEED  # the car's gone by: cross behind it
		elif (eta - SAFE_LEAD) * MAX_PACE < to_road:
			# Too late to get across ahead of the car: stop at the roadside and let it pass.
			a.speed = minf(RUN_SPEED, maxf(absf(lateral) - WAIT_LINE, 0.0) / delta)
		else:
			# Pace it to reach the road `lead` seconds before the car does.
			var time_left := eta - a.lead
			a.speed = MAX_PACE if time_left < 0.05 else clampf(to_road / time_left, 3.0, MAX_PACE)
	else:
		a.speed = BOLT_SPEED if a.froze_for > 0.0 else RUN_SPEED
	if a.will_freeze and a.froze_for == 0.0 and not a.frozen and absf(lateral - car.lateral) < 0.6 \
			and absf(lateral) < RoadMesher.PAVED_HALF_WIDTH and _car_eta(a) > a.bolt_time + 0.4:
		a.frozen = true  # deer in the headlights
		froze += 1
	if a.frozen:
		a.froze_for += delta
		if _car_eta(a) < a.bolt_time or a.froze_for > FREEZE_MAX:
			a.frozen = false
			if _rng.randf() < TURN_BACK_CHANCE:
				a.dir = -a.dir
		else:
			_watch_car(a)
			_place(a)
			return
	a.pos += a.dir * a.speed * delta
	a.pos.y = _ground(a.pos, a.station)
	a.phase += a.speed * delta * 1.3
	_watch_car(a)
	_place(a)


## Did it get in the car's way (and did the car miss it)?
func _watch_car(a: Animal) -> void:
	if a.judged:
		return
	var eta := _car_eta(a)
	var in_path := absf(_lateral(a) - car.lateral) < car.stats.body_size.x / 2.0 + HALF.y + 0.3
	if in_path and eta > 0.0 and eta < THREAT_TIME:
		a.threat = true
	if car.station > a.station + car.stats.body_size.z:
		a.judged = true
		if a.threat and run.tracker.running():
			dodges += 1
			run.score.add("Deer dodged", DODGE_POINTS)


## Hit by the player, a cruiser or traffic?
func _check_hits(a: Animal) -> void:
	var deer_pos := Vector2(a.pos.x, a.pos.z)
	var deer_fwd := Vector2(a.dir.x, a.dir.z).normalized()
	for c: Car in [car] + traffic.other_cars:
		if absf(a.pos.y - c.global_position.y) > 2.5:
			continue
		var pos := Vector2(c.global_position.x, c.global_position.z)
		var fwd := Vector2(-c.global_transform.basis.z.x, -c.global_transform.basis.z.z).normalized()
		var half := Vector2(c.stats.body_size.x, c.stats.body_size.z) / 2.0
		var push := Traffic.push_apart(pos, fwd, half, deer_pos, deer_fwd, HALF)
		if push != Vector2.ZERO:
			var running := 0.0 if a.frozen or a.stays or a.delay > 0.0 else a.speed
			var closing := (c.linear_velocity - a.dir * running).length()
			c.bump(c.stats.mass / (c.stats.mass + MASS * 0.6), closing * DAMAGE_PER_MS, false)
			if c == car:
				hits += 1
				a.judged = true
			_send_flying(a, push, c.linear_velocity)
			return
	for v: Traffic.Vehicle in traffic.vehicles:
		var spec: Dictionary = Traffic.KINDS[v.kind]
		var fwd3: Vector3 = -v.node.global_transform.basis.z
		var fwd := Vector2(fwd3.x, fwd3.z).normalized()
		var center: Vector2 = Vector2(v.node.global_position.x, v.node.global_position.z) - fwd * float(spec.center)
		var half := Vector2(float(spec.width), float(spec.length)) / 2.0
		var push := Traffic.push_apart(center, fwd, half, deer_pos, deer_fwd, HALF)
		if push != Vector2.ZERO and absf(a.pos.y - v.node.global_position.y) < 2.5:
			_send_flying(a, push, fwd3 * v.speed)
			return


## Hit: the deer becomes a tumbling body, starting just clear of whatever hit it.
func _send_flying(a: Animal, push: Vector2, hit_velocity: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = MASS
	body.collision_layer = 1 << (Car.DEBRIS_LAYER - 1)
	body.collision_mask = (1 << (Car.WORLD_LAYER - 1)) | (1 << (Car.CAR_LAYER - 1))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 1.8, 1.6)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	body.add_child(shape)
	add_child(body)
	var away := Vector3(push.x, 0.0, push.y)
	var xf := a.node.global_transform
	body.global_transform = Transform3D(xf.basis, xf.origin + away * 1.05 + away.normalized() * 0.1)
	body.reset_physics_interpolation()
	a.node.reparent(body, false)
	a.node.transform = Transform3D.IDENTITY
	body.linear_velocity = hit_velocity * 1.15 + away.normalized() * 5.0 + Vector3.UP * 4.0
	body.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4), _rng.randf_range(-6, 6))
	props.add_debris(body)
	animals.erase(a)


## The ground under a deer (the road surface on the road).
func _ground(p: Vector3, station: float) -> float:
	var s := route.nearest_station(p, station, 60.0)
	var center := route.position_at(s)
	var offset := (p - center).dot(route.right_at(s))
	var ground := route.terrain.height_at(p.x, p.z)
	if absf(offset) < RoadMesher.DITCH_EDGE:
		var road := center.y + RoadMesher.surface_height(offset)
		ground = road if is_nan(ground) else maxf(ground, road)
	return ground if not is_nan(ground) else p.y


func _place(a: Animal) -> void:
	var moving := a.delay <= 0.0 and not a.frozen and not a.stays and a.speed > 0.5
	var bound := absf(sin(a.phase)) * 0.25 if moving else 0.0
	a.node.global_transform = Transform3D(Basis.looking_at(a.dir, Vector3.UP), a.pos + Vector3.UP * bound)
	var swing := sin(a.phase) * 0.7 if moving else 0.0
	for i in a.legs.size():
		a.legs[i].rotation.x = swing if i < 2 else -swing


func _make_animal(a: Animal) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	for z: float in [-0.5, 0.5]:
		for x: float in [-0.14, 0.14]:
			var hip := Node3D.new()
			hip.position = Vector3(x, 0.92, z)
			var leg := MeshInstance3D.new()
			leg.mesh = _leg_mesh
			leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hip.add_child(leg)
			root.add_child(hip)
			a.legs.append(hip)
	return root


## A low-poly white-tailed deer facing -Z: body, neck, head, ears, the white flag.
func _body_mesh() -> ArrayMesh:
	var tan := Color(0.55, 0.40, 0.25)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.42, 0.5, 1.25), Vector3(0, 1.15, 0), tan)
	MeshKit.box(st, Vector3(0.36, 0.12, 1.0), Vector3(0, 0.88, 0), Color(0.85, 0.82, 0.75))  # belly
	MeshKit.box(st, Vector3(0.18, 0.55, 0.22), Vector3(0, 1.55, -0.62), tan)  # neck
	MeshKit.box(st, Vector3(0.2, 0.22, 0.42), Vector3(0, 1.82, -0.78), tan)  # head
	MeshKit.box(st, Vector3(0.06, 0.16, 0.05), Vector3(-0.1, 1.98, -0.68), tan)  # ears
	MeshKit.box(st, Vector3(0.06, 0.16, 0.05), Vector3(0.1, 1.98, -0.68), tan)
	MeshKit.box(st, Vector3(0.1, 0.08, 0.08), Vector3(0, 1.78, -1.0), Color(0.1, 0.08, 0.07))  # nose
	MeshKit.box(st, Vector3(0.14, 0.2, 0.06), Vector3(0, 1.3, 0.64), Color(0.95, 0.95, 0.92))  # tail
	return MeshKit.finish(st)


func _leg() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.08, 0.92, 0.08), Vector3(0, -0.46, 0), Color(0.45, 0.33, 0.21))
	return MeshKit.finish(st)
