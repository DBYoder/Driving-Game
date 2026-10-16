class_name CornField
extends Node3D
## Corn you can plow through. Clumps of corn (crossed quads, one MultiMesh, one draw
## call) fill the real corn fields near the car, from just past the ditch out to
## LATERAL_REACH. Driving into it flattens what you hit, slows you down and scores by
## the meter. Flattened corn stays flat for the rest of the run.

const SPACING := 1.6  ## meters between clumps
const VERGE := 17.0  ## corn starts this far from the road centerline
const LATERAL_REACH := 55.0
const AHEAD := 200.0
const BEHIND := 60.0
const REBUILD_EVERY := 50.0  ## meters of travel
const POINTS_PER_METER := 5
const DRAG := 700.0  ## N per m/s of speed while plowing
const BUILD_BUDGET_USEC := 2000.0

var route: RouteData
var fields: Fields
var car: Car
var score: ScoreKeeper
var plowing := false
var plowed_meters := 0.0
var _multimesh: MultiMesh
var _index := {}  ## Vector2i grid cell -> instance index in the current build
var _flattened := {}  ## Vector2i grid cell -> true, for the run
var _built_at := INF
var _job := {}  ## an in-progress rebuild
var _meter_credit := 0.0
var _fresh_entry := true
var _leaves: CPUParticles3D


func setup(r: RouteData, f: Fields, c: Car, s: ScoreKeeper) -> void:
	route = r
	fields = f
	car = c
	score = s
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = _clump_mesh()
	var node := MultiMeshInstance3D.new()
	node.multimesh = _multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/corn.gdshader")
	node.material_override = material
	add_child(node)
	_leaves = _make_leaves()
	add_child(_leaves)


func reset() -> void:
	_flattened.clear()
	_built_at = INF
	plowed_meters = 0.0
	rebuild()


## Place clumps in corn fields around the car's stretch of road. With `now` false the
## work is spread over physics ticks (a few ms each) and swapped in when it's done, so
## driving never hitches.
func rebuild(now := true) -> void:
	_built_at = car.station
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var s := car.station - BEHIND
	while s <= car.station + AHEAD:
		var p := route.position_at(s)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		s += 20.0
	lo -= Vector2.ONE * LATERAL_REACH
	hi += Vector2.ONE * LATERAL_REACH
	_job = {
		"gx": floori(lo.x / SPACING), "gx_end": ceili(hi.x / SPACING),
		"gz0": floori(lo.y / SPACING), "gz_end": ceili(hi.y / SPACING),
		"cells": [] as Array[Vector2i], "buffer": PackedFloat32Array(),
	}
	_continue_rebuild(INF if now else BUILD_BUDGET_USEC)


func _continue_rebuild(budget_usec: float) -> void:
	var start := Time.get_ticks_usec()
	var cells: Array[Vector2i] = _job.cells
	var buffer: PackedFloat32Array = _job.buffer
	while _job.gx < _job.gx_end:
		var gx: int = _job.gx
		var x := gx * SPACING
		for gz in range(_job.gz0, _job.gz_end):
			var z := gz * SPACING
			var d := route.terrain.road_distance_at(x, z)
			if d < VERGE or d > LATERAL_REACH or fields.crop_at(x, z) != Fields.CORN:
				continue
			var cell := Vector2i(gx, gz)
			cells.append(cell)
			_append_transform(buffer, _clump_transform(cell))
		_job.gx += 1
		if Time.get_ticks_usec() - start > budget_usec:
			_job.buffer = buffer  # packed arrays are values; keep the progress
			return
	_index.clear()
	for i in cells.size():
		_index[cells[i]] = i
	_multimesh.instance_count = cells.size()
	if not cells.is_empty():
		_multimesh.buffer = buffer
	_job = {}


## MultiMesh buffers hold each transform as a 3x4 matrix, row by row.
static func _append_transform(buffer: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	buffer.append_array([b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y,
		b.x.z, b.y.z, b.z.z, t.origin.z])


func _physics_process(delta: float) -> void:
	if car == null:
		return
	if not _job.is_empty():
		_continue_rebuild(BUILD_BUDGET_USEC)
	elif absf(car.station - _built_at) > REBUILD_EVERY:
		rebuild(false)
	var pos := car.global_position
	var d := route.terrain.road_distance_at(pos.x, pos.z)
	var speed := car.linear_velocity.length()
	plowing = d >= VERGE - 1.0 and speed > 2.0 and car.grounded_wheels() > 0 \
		and fields.crop_at(pos.x, pos.z) == Fields.CORN
	_leaves.emitting = plowing
	if not plowing:
		_meter_credit = 0.0
		_fresh_entry = true
		return
	_flatten_around(pos)
	car.apply_central_force(-car.linear_velocity * DRAG)
	var meters := speed * delta
	plowed_meters += meters
	_meter_credit += meters
	if _meter_credit >= 1.0:
		var whole := int(_meter_credit)
		_meter_credit -= whole
		# Plowing into a field counts as a combo event; the rest just keeps the combo alive.
		score.add("Corn", whole * POINTS_PER_METER, _fresh_entry)
		_fresh_entry = false


func _flatten_around(pos: Vector3) -> void:
	var center := Vector2i(roundi(pos.x / SPACING), roundi(pos.z / SPACING))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var cell := center + Vector2i(dx, dz)
			if _flattened.has(cell):
				continue
			if Vector2(cell.x * SPACING - pos.x, cell.y * SPACING - pos.z).length() > 2.2:
				continue
			_flattened[cell] = true
			if _index.has(cell):
				_multimesh.set_instance_transform(_index[cell], _clump_transform(cell))


func _clump_transform(cell: Vector2i) -> Transform3D:
	var x := cell.x * SPACING
	var z := cell.y * SPACING
	var h := Fields.cell_hash(cell.x, cell.y)  # stable per-clump jitter
	var y := route.terrain.height_at(x, z)
	var basis := Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * (0.85 + 0.3 * h))
	if _flattened.has(cell):
		basis = Basis(Vector3.UP, h * TAU) * Basis(Vector3.RIGHT, deg_to_rad(80.0)).scaled(Vector3(1.0, 0.6, 1.0))
	return Transform3D(basis, Vector3(x + (h - 0.5) * 0.6, y, z + (h - 0.5) * 0.6))


## Two crossed quads, 2.4 m wide, 2.5 m tall, standing on y = 0.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [PI / 4.0, -PI / 4.0]:
		var across := Vector3(cos(angle), 0.0, sin(angle)) * 1.2
		var corners := [[-across, 0.0, 1.0], [across, 1.0, 1.0], [across + Vector3.UP * 2.5, 1.0, 0.0],
			[-across + Vector3.UP * 2.5, 0.0, 0.0]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(corners[i][1], corners[i][2]))
			st.add_vertex(corners[i][0])
	return st.commit()


func _make_leaves() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 40
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -6, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.12)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.15)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	return p


func _process(_delta: float) -> void:
	if car and _leaves.emitting:
		_leaves.global_position = car.global_position
