class_name ClipProbe
extends RefCounted
## Measures what the eye calls clipping during a QA drive: the car's body sitting inside
## crashed traffic, flying debris or standing corn, or sunk into the ground; and the
## car's own tires through its bodywork (ModelCheck, sampled less often: it's slower).
## Sampled every physics tick; QaDrive reports the worst of each and fails past the
## limits (any tire clip at all fails).

const VISIBLE_OVERLAP := 0.3  ## meters of overlap you'd notice at a glance
const VISIBLE_SINK := 0.15  ## meters of body below the ground surface

var worst := {"wreck": 0.0, "cop": 0.0, "debris": 0.0, "corn": 0.0, "ground": 0.0, "building": 0.0, "tires": 0.0}
var worst_mile := {"wreck": 0.0, "cop": 0.0, "debris": 0.0, "corn": 0.0, "ground": 0.0, "building": 0.0, "tires": 0.0}
var visible_ticks := {"wreck": 0, "cop": 0, "debris": 0, "corn": 0, "ground": 0, "building": 0, "tires": 0}
var tire_samples := 0


func sample(main: Node, car: Car) -> void:
	var mile := car.route.mile_at(car.station)
	var deepest := 0.0
	for body: RigidBody3D in main.traffic.wreck_bodies():
		deepest = maxf(deepest, _overlap(car, body))
	_record("wreck", deepest, VISIBLE_OVERLAP, mile)
	deepest = 0.0
	for cop: Car in main.cops.cop_cars():
		deepest = maxf(deepest, _overlap(car, cop))
	_record("cop", deepest, VISIBLE_OVERLAP, mile)
	deepest = 0.0
	for body: RigidBody3D in main.props.debris_bodies():
		if not body.has_meta("car_part"):  # the car's own hubcaps can't hit it anyway
			deepest = maxf(deepest, _overlap(car, body))
	_record("debris", deepest, VISIBLE_OVERLAP, mile)
	_record("corn", main.corn.standing_clumps_touching(car), 0.5, mile)
	deepest = 0.0
	var car_xf := car.body_shape.global_transform
	var car_half := (car.body_shape.shape as BoxShape3D).size / 2.0
	for box: Array in main.scenery.building_boxes(car.global_position, 40.0) + main.landmarks.building_boxes(car.global_position, 80.0):
		deepest = maxf(deepest, box_overlap(car_xf, car_half, box[0], box[1]))
	_record("building", deepest, VISIBLE_OVERLAP, mile)
	_record("ground", _sink(car), VISIBLE_SINK, mile)


## The car's tires against its own body, as drawn right now.
func sample_tires(car: Car) -> void:
	var clips := 0
	for c in ModelCheck.tire_clips(car.model):
		clips += c
	tire_samples += 1
	_record("tires", clips, 0.5, car.route.mile_at(car.station))


func report() -> String:
	return "worst overlap with wrecks %.2f m (%d ticks visible), cruisers %.2f m (%d), debris %.2f m (%d), standing corn %d clumps (%d), body below ground %.2f m (%d)" % [
		worst.wreck, visible_ticks.wreck, worst.cop, visible_ticks.cop, worst.debris, visible_ticks.debris,
		worst.corn, visible_ticks.corn, worst.ground, visible_ticks.ground] \
		+ ", buildings %.2f m (%d), tires through the body %d places (%d of %d looks)" % [worst.building, visible_ticks.building,
			worst.tires, visible_ticks.tires, tire_samples]


func _record(what: String, value: float, visible: float, mile: float) -> void:
	if value > worst[what]:
		worst[what] = value
		worst_mile[what] = mile
	if value > visible:
		visible_ticks[what] += 1


## How deep the car's body is into a body's collision shapes (0 if apart): boxes in 3D,
## with a cylinder (a hay bale) treated as the box around it.
func _overlap(car: Car, body: RigidBody3D) -> float:
	var car_xf := car.body_shape.global_transform
	var car_half := (car.body_shape.shape as BoxShape3D).size / 2.0
	var deepest := 0.0
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var half := Vector3.ZERO
		if shape.shape is BoxShape3D:
			half = (shape.shape as BoxShape3D).size / 2.0
		elif shape.shape is CylinderShape3D:
			var cyl := shape.shape as CylinderShape3D
			half = Vector3(cyl.radius, cyl.height / 2.0, cyl.radius)
		else:
			continue
		deepest = maxf(deepest, box_overlap(car_xf, car_half, shape.global_transform, half))
	return deepest


## Penetration depth of two boxes (transform + half extents), 0 if they're apart.
## Separating-axis test over the 15 candidate axes.
static func box_overlap(a: Transform3D, ha: Vector3, b: Transform3D, hb: Vector3) -> float:
	var axes_a := [a.basis.x.normalized(), a.basis.y.normalized(), a.basis.z.normalized()]
	var axes_b := [b.basis.x.normalized(), b.basis.y.normalized(), b.basis.z.normalized()]
	var candidates: Array[Vector3] = []
	for v: Vector3 in axes_a + axes_b:
		candidates.append(v)
	for u: Vector3 in axes_a:
		for v: Vector3 in axes_b:
			var c := u.cross(v)
			if c.length_squared() > 1e-6:
				candidates.append(c.normalized())
	var d := b.origin - a.origin
	var least := INF
	for axis in candidates:
		var ra := ha.x * absf(axes_a[0].dot(axis)) + ha.y * absf(axes_a[1].dot(axis)) + ha.z * absf(axes_a[2].dot(axis))
		var rb := hb.x * absf(axes_b[0].dot(axis)) + hb.y * absf(axes_b[1].dot(axis)) + hb.z * absf(axes_b[2].dot(axis))
		var overlap := ra + rb - absf(d.dot(axis))
		if overlap <= 0.0:
			return 0.0
		least = minf(least, overlap)
	return least


## How far the lowest corner of the car's lower body is below the ground under it.
func _sink(car: Car) -> float:
	var route := car.route
	var deepest := 0.0
	var w := car.stats.body_size.x / 2.0
	var l := car.stats.body_size.z / 2.0
	for corner in [Vector3(-w, -0.37, -l), Vector3(w, -0.37, -l), Vector3(-w, -0.37, l), Vector3(w, -0.37, l)]:
		var p: Vector3 = car.global_transform * corner
		var center := route.position_at(car.station)
		var offset := (p - center).dot(route.right_at(car.station))
		var ground := route.terrain.height_at(p.x, p.z)
		if absf(offset) < RoadMesher.DITCH_EDGE:
			ground = maxf(ground, center.y + RoadMesher.surface_height(offset))
		if not is_nan(ground):
			deepest = maxf(deepest, ground - p.y)
	return deepest
