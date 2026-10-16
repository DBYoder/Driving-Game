class_name PropField
extends Node3D
## Things to smash: mailboxes at the edge of the shoulder, pasture fence lines, and round
## hay bales out in hay and pasture fields. Placement comes from a seed per stretch of
## road, so props are in the same places every run, and only stretches near the car
## exist. Hitting one scores, slows the car by the prop's weight, and launches it as
## physics debris.

const CHUNK_LENGTH := 256.0
const VISIBLE_RADIUS := 1200.0  ## meters of road ahead/behind with props built (specks in the haze by then)
const MAX_DEBRIS := 40  ## past this, the farthest piece goes
const DEBRIS_RANGE := 600.0  ## debris further than this from the car is cleared away
const MAILBOX_OFFSET := 7.3  ## just past the gravel shoulder
const FENCE_OFFSET := 19.0  ## the right-of-way line, past the ditch
const BALE_RADIUS := 0.85
const BALE_WIDTH := 1.5
const CROSSROAD_CLEARANCE := 20.0

## label, points, mass (kg), collision radius (m), damage per m/s of impact speed
const KINDS := {
	"mailbox": {"label": "Mailbox", "points": 50, "mass": 15.0, "radius": 0.3, "damage": 0.02},
	"fence": {"label": "Fence", "points": 25, "mass": 40.0, "radius": 0.25, "damage": 0.05},
	"bale": {"label": "Hay bale", "points": 100, "mass": 450.0, "radius": BALE_RADIUS, "damage": 0.9},
}


class Prop:
	var id: int
	var kind: String
	var position: Vector3
	var yaw: float
	var index: int  ## instance in its chunk's MultiMesh
	var smashed := false


var route: RouteData
var fields: Fields
var car: Car
var score: ScoreKeeper
var _meshes := {}
var _chunks := {}  ## chunk -> {"props": Array, "nodes": {kind: MultiMeshInstance3D}}
var _smashed := {}  ## prop id -> true, for the current run
var _debris: Array[RigidBody3D] = []
var _refresh_timer := 0.0
## The closest a prop has been to the car when it appeared, outside of a respawn
## (checked by the QA drive).
var nearest_pop_in := INF


func setup(r: RouteData, f: Fields, c: Car, s: ScoreKeeper) -> void:
	route = r
	fields = f
	car = c
	score = s
	_meshes = {
		"mailbox": PropMeshes.mailbox(),
		"fence": PropMeshes.fence_span(),
		"bale": PropMeshes.hay_bale(BALE_RADIUS, BALE_WIDTH),
	}


## Put everything back for a new run (refresh() builds it again).
func reset() -> void:
	_smashed.clear()
	for d in _debris:
		d.queue_free()
	_debris.clear()
	for c in _chunks.keys():
		_free_chunk(c)


## Build the stretches near the car and drop far ones. `streaming` is false when the
## car has just been put somewhere new, and everything near it appears at once.
func refresh(streaming := false) -> void:
	var first := maxi(0, floori((car.station - VISIBLE_RADIUS) / CHUNK_LENGTH))
	var last := floori(minf(car.station + VISIBLE_RADIUS, route.length) / CHUNK_LENGTH)
	for c in _chunks.keys():
		if c < first or c > last:
			_free_chunk(c)
	for c in range(first, last + 1):
		if not _chunks.has(c):
			_build_chunk(c)
			if streaming:
				for p in _chunks[c].props:
					nearest_pop_in = minf(nearest_pop_in, p.position.distance_to(car.global_position))


func smashed_count() -> int:
	return _smashed.size()


## Smashed props flying or lying around (physics bodies).
func debris_bodies() -> Array[RigidBody3D]:
	return _debris.duplicate()


## Something else to clear away with the debris once it's far behind (parts that fell
## off the car).
func add_debris(body: RigidBody3D) -> void:
	_debris.append(body)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		refresh(true)
	_check_hits()
	_clear_far_debris()


## Generate a stretch's props from its seed (the same every run).
func generate(chunk: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk * 7919 + 13)
	var s0 := chunk * CHUNK_LENGTH
	var s1 := minf(s0 + CHUNK_LENGTH, route.length - 1.0)
	var props: Array = []
	var next_id := chunk * 1000

	for i in _weighted(rng, [0.4, 0.4, 0.2]):  # 0-2 mailboxes per stretch
		var s := rng.randf_range(s0, s1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		if _near_crossroad(s):
			continue
		props.append(_prop(next_id, "mailbox", _roadside(s, side * MAILBOX_OFFSET), _yaw_at(s) + (0.0 if side > 0 else PI)))
		next_id += 1

	for side: float in [-1.0, 1.0]:
		# Pastures and hay ground get fenced; corn and beans usually don't.
		if rng.randf() < 0.8:
			var s := s0 + 2.0
			while s < s1 - 2.0:
				if not _near_crossroad(s) and _hay_ground(_roadside(s, side * (FENCE_OFFSET + 8.0))):
					props.append(_prop(next_id, "fence", _roadside(s, side * FENCE_OFFSET), _yaw_at(s)))
					next_id += 1
				s += 4.0
		for attempt in 3:
			var s := rng.randf_range(s0, s1)
			var offset := side * rng.randf_range(24.0, 45.0)
			var center := _roadside(s, offset)
			if not _hay_ground(center):
				continue
			for b in rng.randi_range(2, 6):
				var p := _roadside(s + rng.randf_range(-30.0, 30.0), offset + rng.randf_range(-8.0, 8.0))
				if not _hay_ground(p):
					continue
				p.y += BALE_RADIUS
				props.append(_prop(next_id, "bale", p, rng.randf_range(0.0, TAU)))
				next_id += 1
			break
	return props


func _hay_ground(p: Vector3) -> bool:
	var crop := fields.crop_at(p.x, p.z)
	return crop == Fields.HAY or crop == Fields.PASTURE


func _weighted(rng: RandomNumberGenerator, weights: Array) -> int:
	var r := rng.randf()
	for i in weights.size():
		r -= weights[i]
		if r < 0.0:
			return i
	return weights.size() - 1


func _prop(id: int, kind: String, pos: Vector3, yaw: float) -> Prop:
	var p := Prop.new()
	p.id = id
	p.kind = kind
	p.position = pos
	p.yaw = yaw
	return p


## A point beside the road: on the road's own cross-section near it, on the terrain beyond.
func _roadside(station: float, offset: float) -> Vector3:
	var p := route.position_at(station) + route.right_at(station) * offset
	if absf(offset) <= RoadMesher.DITCH_EDGE:
		p.y = route.position_at(station).y + RoadMesher.surface_height(offset)
	else:
		var ground := route.terrain.height_at(p.x, p.z)
		if not is_nan(ground):
			p.y = ground
	return p


## Rotation about Y that lines a prop's local Z up with the road.
func _yaw_at(station: float) -> float:
	var t := route.tangent_at(station)
	return atan2(-t.x, -t.z)


func _near_crossroad(station: float) -> bool:
	for c in route.crossroads:
		if absf(c.station - station) < CROSSROAD_CLEARANCE:
			return true
	return false


func _build_chunk(chunk: int) -> void:
	var props := generate(chunk)
	var by_kind := {}
	for p in props:
		if not by_kind.has(p.kind):
			by_kind[p.kind] = []
		p.index = by_kind[p.kind].size()
		p.smashed = _smashed.has(p.id)
		by_kind[p.kind].append(p)
	var nodes := {}
	for kind in by_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[kind]
		mm.instance_count = by_kind[kind].size()
		for p in by_kind[kind]:
			mm.set_instance_transform(p.index, _instance_transform(p))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		nodes[kind] = node
	_chunks[chunk] = {"props": props, "nodes": nodes}


func _free_chunk(chunk: int) -> void:
	for node in _chunks[chunk].nodes.values():
		node.queue_free()
	_chunks.erase(chunk)


func _instance_transform(p: Prop) -> Transform3D:
	var basis := Basis(Vector3.UP, p.yaw)
	if p.smashed:
		basis = basis.scaled(Vector3.ZERO)
	return Transform3D(basis, p.position)


func _check_hits() -> void:
	var here := floori(car.station / CHUNK_LENGTH)
	var inv := car.global_transform.affine_inverse()
	var half_w := car.stats.body_size.x / 2.0
	var half_l := car.stats.body_size.z / 2.0
	for c in [here - 1, here, here + 1]:
		if not _chunks.has(c):
			continue
		for p in _chunks[c].props:
			if p.smashed:
				continue
			var point: Vector3 = p.position
			if p.kind == "fence":
				point = _closest_on_span(p, car.global_position)
			if Vector2(point.x - car.global_position.x, point.z - car.global_position.z).length() > 6.0:
				continue
			var local := inv * point
			var r: float = KINDS[p.kind].radius
			if absf(local.x) < half_w + r and absf(local.z) < half_l + r and local.y > -1.8 and local.y < 1.6 + r:
				_smash(c, p)


func _closest_on_span(p: Prop, to: Vector3) -> Vector3:
	var along := Basis(Vector3.UP, p.yaw).z
	var t := clampf((to - p.position).dot(along), -2.0, 2.0)
	return p.position + along * t


func _smash(chunk: int, p: Prop) -> void:
	p.smashed = true
	_smashed[p.id] = true
	var node: MultiMeshInstance3D = _chunks[chunk].nodes[p.kind]
	node.multimesh.set_instance_transform(p.index, _instance_transform(p))

	var kind: Dictionary = KINDS[p.kind]
	var velocity := car.linear_velocity
	var speed := velocity.length()
	score.add(kind.label, kind.points)
	# Momentum: the heavier the thing, the more it slows you (a glancing share of it).
	car.bump(car.stats.mass / (car.stats.mass + kind.mass * 0.7), kind.damage * speed)
	_launch_debris(p, velocity, kind.mass)


## The smashed prop becomes a physics body, solid to the car too: it starts just clear
## of the car's body and moving at least as fast, and if the car catches it again it
## shoves it rather than driving through it.
func _launch_debris(p: Prop, velocity: Vector3, mass: float) -> void:
	var body := RigidBody3D.new()
	body.mass = mass
	body.collision_layer = 1 << (Car.DEBRIS_LAYER - 1)
	body.collision_mask = (1 << (Car.WORLD_LAYER - 1)) | (1 << (Car.CAR_LAYER - 1))
	var mesh := MeshInstance3D.new()
	mesh.mesh = _meshes[p.kind]
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	if p.kind == "bale":
		var cyl := CylinderShape3D.new()
		cyl.radius = BALE_RADIUS
		cyl.height = BALE_WIDTH
		shape.shape = cyl
		shape.rotation_degrees = Vector3(90, 0, 0)
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 1.2, 4.0) if p.kind == "fence" else Vector3(0.5, 1.2, 0.3)
		shape.shape = box
		shape.position = Vector3(0, 0.6, 0)
	body.add_child(shape)
	add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, p.yaw), p.position + _clearance(p))
	var light := mass < 100.0
	var rng := RandomNumberGenerator.new()
	rng.seed = p.id
	body.linear_velocity = velocity * (rng.randf_range(1.05, 1.35) if light else 0.85) \
		+ Vector3.UP * (rng.randf_range(2.0, 5.0) if light else 1.5) \
		+ car.global_transform.basis.x * rng.randf_range(-3.0, 3.0)
	body.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8)) \
		* (1.0 if light else 0.2)
	_debris.append(body)


## How far to move a prop so its footprint is off the car's (it was hit because they overlap).
func _clearance(p: Prop) -> Vector3:
	var half := Vector2(BALE_RADIUS, BALE_WIDTH / 2.0) if p.kind == "bale" \
		else (Vector2(0.15, 2.0) if p.kind == "fence" else Vector2(0.25, 0.15))
	var car_fwd := -car.global_transform.basis.z
	var prop_fwd := -Basis(Vector3.UP, p.yaw).z
	var push := Traffic.push_apart(Vector2(car.global_position.x, car.global_position.z),
		Vector2(car_fwd.x, car_fwd.z).normalized(), Vector2(car.stats.body_size.x, car.stats.body_size.z) / 2.0,
		Vector2(p.position.x, p.position.z), Vector2(prop_fwd.x, prop_fwd.z), half)
	if push == Vector2.ZERO:
		return Vector3.ZERO
	push += push.normalized() * 0.05
	return Vector3(push.x, 0.0, push.y)


## Debris stays where it lands until the car is far away (or there's too much of it, when
## the farthest piece goes), so nothing vanishes in front of you.
func _clear_far_debris() -> void:
	var here := car.global_position
	_debris.sort_custom(func(a, b): return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	while not _debris.is_empty() and (_debris.size() > MAX_DEBRIS or _debris[-1].global_position.distance_to(here) > DEBRIS_RANGE):
		_debris.pop_back().queue_free()
