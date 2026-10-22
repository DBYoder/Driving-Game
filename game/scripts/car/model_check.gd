class_name ModelCheck
extends RefCounted
## Finds where a car model's tires pass through its own body: every tire edge against
## every nearby body triangle, and every body edge against the tire's triangles. Used by
## the unit tests (sweeping steering, suspension, lean and dents) and by the QA stress
## and drift runs (live, while the car is thrown around).
##
## Everything is in the CarModel's own space. The tire is a 16-sided cylinder, like the
## one drawn (CarModel builds it 12-sided; 16 here errs on the side of finding a clip).

const SIDES := 16


## How many places each tire passes through the body (or a part on it) right now:
## an Array of one int per wheel.
static func tire_clips(model: CarModel) -> Array[int]:
	var body := body_triangles(model)
	var out: Array[int] = []
	for pivot: Node3D in model.wheel_pivots():
		out.append(_clips(_tire(model.wheel_radius(), CarModel.TIRE_WIDTH / 2.0, pivot.transform), body))
	return out


## Every triangle of the body and the parts on it (not the wheels, the boost flame or
## smoke), in the model's space.
static func body_triangles(model: CarModel) -> PackedVector3Array:
	var tris := PackedVector3Array()
	_collect(model.body_node(), Transform3D(model.body_node().transform), tris)
	return tris


static func _collect(node: Node, xf: Transform3D, tris: PackedVector3Array) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible or child.has_meta("no_clip_check"):
			continue
		var cxf: Transform3D = xf * child.transform
		if child is MeshInstance3D and child.mesh:
			var mesh: Mesh = child.mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx = arrays[Mesh.ARRAY_INDEX]
				if idx == null or (idx as PackedInt32Array).is_empty():
					for v in verts:
						tris.append(cxf * v)
				else:
					for i: int in idx:
						tris.append(cxf * verts[i])
		_collect(child, cxf, tris)


class Tire:
	var tris := PackedVector3Array()
	var edges := PackedVector3Array()  ## pairs
	var box: AABB


## The tire's triangles and edges: two rims and the tread, around the axle (local X).
static func _tire(radius: float, half_width: float, xf: Transform3D) -> Tire:
	var t := Tire.new()
	var rims: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	for s in 2:
		var x := -half_width if s == 0 else half_width
		for i in SIDES:
			var a := TAU * i / SIDES
			rims[s].append(xf * Vector3(x, cos(a) * radius, sin(a) * radius))
	var centers := [xf * Vector3(-half_width, 0, 0), xf * Vector3(half_width, 0, 0)]
	for i in SIDES:
		var j := (i + 1) % SIDES
		for s in 2:
			t.edges.append_array([rims[s][i], rims[s][j]])
			t.tris.append_array([centers[s], rims[s][i], rims[s][j]])
		t.edges.append_array([rims[0][i], rims[1][i]])
		t.tris.append_array([rims[0][i], rims[0][j], rims[1][j], rims[0][i], rims[1][j], rims[1][i]])
	t.box = AABB(t.edges[0], Vector3.ZERO)
	for p in t.edges:
		t.box = t.box.expand(p)
	return t


static func _clips(tire: Tire, body: PackedVector3Array) -> int:
	var hits := 0
	var near := tire.box.grow(0.02)
	for b in range(0, body.size(), 3):
		var p0 := body[b]
		var p1 := body[b + 1]
		var p2 := body[b + 2]
		var box := AABB(p0, Vector3.ZERO).expand(p1).expand(p2)
		if not box.intersects(near):
			continue
		var crossed := false
		# A tire edge through the body triangle...
		for e in range(0, tire.edges.size(), 2):
			if Geometry3D.segment_intersects_triangle(tire.edges[e], tire.edges[e + 1], p0, p1, p2) != null:
				crossed = true
				break
		# ...or one of the triangle's edges through the tire.
		if not crossed:
			for edge: Array in [[p0, p1], [p1, p2], [p2, p0]]:
				for t in range(0, tire.tris.size(), 3):
					if Geometry3D.segment_intersects_triangle(edge[0], edge[1], tire.tris[t], tire.tris[t + 1],
							tire.tris[t + 2]) != null:
						crossed = true
						break
				if crossed:
					break
		hits += int(crossed)
	return hits


## Throw a model through every state it can be drawn in and count the clips: steering
## lock to lock, the suspension from fully hanging to fully compressed, leaning hard
## every way, and (with `dents`) beaten in from all round. Returns {"clips": total,
## "states": how many were checked, "worst": a description of the worst state}.
static func sweep(stats: CarStats, dents := false) -> Dictionary:
	var model := CarModel.new()
	var wheels: Array = []
	for z: float in [-stats.wheelbase / 2.0, stats.wheelbase / 2.0]:
		for x: float in [-stats.track / 2.0, stats.track / 2.0]:
			var w := Car.Wheel.new()
			w.mount = Vector3(x, stats.mount_y, z)
			w.front = z < 0.0
			w.left = x < 0.0
			w.spring_length = stats.rest_length
			w.grounded = true
			wheels.append(w)
	model.build(stats, wheels)
	if dents:
		for i in 12:
			var a := TAU * i / 12.0
			model.dent(Vector3(sin(a), 0.0, cos(a)), 1.0)
	var steer_max := deg_to_rad(stats.max_steer_deg)
	var g := 9.8
	var accels := [Vector3.ZERO, Vector3(3.0 * g, 0, 0), Vector3(-3.0 * g, 0, 0), Vector3(0, 0, 3.0 * g),
		Vector3(0, 0, -3.0 * g), Vector3(2.0 * g, 0, 2.0 * g), Vector3(-2.0 * g, 0, -2.0 * g)]
	var total := 0
	var states := 0
	var worst := {"clips": 0}
	for steer: float in [-steer_max, -steer_max * 0.5, 0.0, steer_max * 0.5, steer_max]:
		for k in 6:
			var spring := stats.rest_length * k / 5.0
			for w: Car.Wheel in wheels:
				w.spring_length = spring
			for accel: Vector3 in accels:
				for i in 4:  # long enough for the lean to settle
					model.update(wheels, steer, accel, 20.0, 1.0)
				var clips := tire_clips(model)
				var n := 0
				for c in clips:
					n += c
				total += n
				states += 1
				if n > worst.clips:
					worst = {"clips": n, "steer": rad_to_deg(steer), "spring": spring, "accel_g": accel / g, "per_wheel": clips}
	model.free()
	return {"clips": total, "states": states, "worst": worst}
