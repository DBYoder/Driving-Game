class_name PowerLines
extends Node3D
## A line of wooden utility poles along the highway, just inside the right-of-way, with
## three wires sagging between them. It runs down one side and every so often swings
## across the road (at a crossroad) to carry on along the other. Poles step aside for
## crossroads, streets, bridges, buildings and the landmarks. They're solid: hit one and it's like
## hitting a tree.
##
## Built once, in chunks of CHUNK poles (a MultiMesh of poles and a mesh of wire lines
## each, drawn out to DRAW_RANGE).

const SPACING := 46.0  ## m between poles
const OFFSET := 15.5  ## m from the centerline: past the ditch, inside the fence (19 m)
const HEIGHT := 10.5
const ARM := 1.0  ## the crossarm reaches this far each side
const SAG := 0.7  ## m the wires droop in the middle of a span
const WIRE_POINTS := 8  ## per span
const CHUNK := 16
const DRAW_RANGE := 1600.0
const CLEAR_OF_CROSSROADS := 18.0
const CLEAR_OF_BRIDGES := 12.0
const CLEAR_OF_BUILDINGS := 2.0  ## a pole (and its crossarm) this far from any wall
const SWITCH_EVERY := 3.0 * RouteData.MILE_M  ## roughly how often it crosses the road
const POLE_RADIUS := 0.16

var route: RouteData
var poles: Array[Transform3D] = []  ## base of each pole; basis x = along the crossarm
var _body: StaticBody3D


func setup(r: RouteData, streets: Streets) -> void:
	route = r
	_place(streets)
	_build()


func _place(streets: Streets) -> void:
	var side := -1.0  # starts down the west side
	var last_switch := 0.0
	var s := SPACING * 0.5
	while s < route.length - SPACING * 0.5:
		var crossroad := _crossroad_near(s, CLEAR_OF_CROSSROADS)
		if not crossroad.is_empty():
			# Cross the road here now and then (the wires swing over the crossroad).
			if s - last_switch > SWITCH_EVERY and crossroad.kind != "ramp":
				side = -side
				last_switch = s
			s = float(crossroad.station) + CLEAR_OF_CROSSROADS + 1.0
			continue
		if _on_bridge(s):
			s += CLEAR_OF_BRIDGES
			continue
		var right := route.right_at(s)
		var base := route.position_at(s) + right * OFFSET * side
		var ground := route.terrain.height_at(base.x, base.z)
		if is_nan(ground) or route.in_landmark(base.x, base.z) or route.near_junction(base.x, base.z) \
				or _on_street(streets, base) or route.near_building(base.x, base.z, CLEAR_OF_BUILDINGS):
			s += 6.0
			continue
		base.y = ground - 0.2
		poles.append(Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), base))
		s += SPACING


func _crossroad_near(s: float, reach: float) -> Dictionary:
	for c: Dictionary in route.crossroads:
		if absf(float(c.station) - s) < reach:
			return c
	return {}


func _on_bridge(s: float) -> bool:
	for b: Array in route.bridges:
		if s > float(b[0]) - CLEAR_OF_BRIDGES and s < float(b[1]) + CLEAR_OF_BRIDGES:
			return true
	return false


func _on_street(streets: Streets, p: Vector3) -> bool:
	for d: Vector3 in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		if not streets.street_at(p.x + d.x, p.z + d.z).is_empty():
			return true
	return false


func _build() -> void:
	var pole_mesh := _pole_mesh()
	var wire_material := StandardMaterial3D.new()
	wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_material.albedo_color = Color(0.12, 0.12, 0.13)
	_body = StaticBody3D.new()
	_body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	_body.collision_mask = 0
	_body.set_meta("surface", "grass")
	add_child(_body)
	var shape := CylinderShape3D.new()
	shape.radius = POLE_RADIUS
	shape.height = HEIGHT
	for first in range(0, poles.size(), CHUNK):
		var last := mini(first + CHUNK, poles.size())
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = pole_mesh
		multimesh.instance_count = last - first
		for i in range(first, last):
			multimesh.set_instance_transform(i - first, poles[i])
			var holder := CollisionShape3D.new()
			holder.shape = shape
			holder.position = poles[i].origin + Vector3.UP * HEIGHT * 0.5
			_body.add_child(holder)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = DRAW_RANGE
		add_child(node)
		# Wires from each pole to the next (this chunk's last runs on to the next chunk's first).
		var lines := PackedVector3Array()
		for i in range(first, mini(last, poles.size() - 1)):
			for attach: Vector3 in _attach_points():
				var a := poles[i] * attach
				var b := poles[i + 1] * attach
				if a.distance_to(b) > SPACING * 3.0:
					continue  # a gap (stepping round something big): no wire
				var prev := a
				for k in range(1, WIRE_POINTS + 1):
					var t := float(k) / WIRE_POINTS
					var p := a.lerp(b, t) + Vector3.DOWN * SAG * 4.0 * t * (1.0 - t)
					lines.append(prev)
					lines.append(p)
					prev = p
		if lines.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = lines
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var wires := MeshInstance3D.new()
		wires.mesh = mesh
		wires.material_override = wire_material
		wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wires.visibility_range_end = DRAW_RANGE
		add_child(wires)


## Where the wires hang, in a pole's own space: each end of the crossarm and the top.
static func _attach_points() -> Array[Vector3]:
	return [Vector3(-ARM + 0.1, HEIGHT - 0.75, 0.0), Vector3(ARM - 0.1, HEIGHT - 0.75, 0.0),
		Vector3(0.0, HEIGHT + 0.05, 0.0)]


## A weathered pole, its crossarm (along x) and three glass insulators. (No faces where
## nobody looks: the pole's foot is in the ground, the insulators' undersides are tiny.)
static func _pole_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var wood := Color(0.36, 0.30, 0.24)
	_post(st, POLE_RADIUS, 0.0, HEIGHT, 6, wood, wood.darkened(0.2))
	MeshKit.box(st, Vector3(ARM * 2.0, 0.11, 0.11), Vector3(0, HEIGHT - 0.85, 0), wood.darkened(0.1))
	var glass := Color(0.45, 0.62, 0.55)
	for p: Vector3 in _attach_points():
		_post(st, 0.06, p.y - 0.13, p.y + 0.03, 3, glass, glass, Vector3(p.x, 0, p.z))
	return MeshKit.finish(st)


## An upright prism from y0 to y1 with a top (no bottom).
static func _post(st: SurfaceTool, radius: float, y0: float, y1: float, sides: int, color: Color, top: Color,
		at := Vector3.ZERO) -> void:
	for i in sides:
		var a0 := TAU * (i + 0.5) / sides
		var a1 := TAU * (i + 1.5) / sides
		var p0 := at + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := at + Vector3(cos(a1), 0, sin(a1)) * radius
		MeshKit.quad(st, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1,
			(p0 + p1) / 2.0 - at, color)
		MeshKit.tri(st, p0 + Vector3.UP * y1, p1 + Vector3.UP * y1, at + Vector3.UP * y1, Vector3.UP, top)
