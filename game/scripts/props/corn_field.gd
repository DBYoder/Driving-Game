class_name CornField
extends Node3D
## Corn you can plow through. Clumps of corn (crossed quads) fill the real corn fields
## along the road, from just past the ditch out to LATERAL_REACH, for RADIUS meters of
## road either way. Each CHUNK_LENGTH stretch of road is one MultiMesh, built once when
## it comes within range (a few milliseconds per physics tick, so driving never hitches)
## and freed when it's left behind. The shader grows corn up out of the ground between
## FADE_FAR and FADE_NEAR from the camera, so it never pops in.
##
## Driving into it flattens everything the car's body touches, slows you down and scores
## by the meter. Flattened corn stays flat for the rest of the run.

const SPACING := 1.6  ## meters between clumps
const VERGE := 17.0  ## corn starts this far from the road centerline
const LATERAL_REACH := 55.0
const CHUNK_LENGTH := 128.0  ## meters of road per chunk
const RADIUS := 640.0  ## meters of road built either way of the car
const FADE_FAR := 560.0  ## corn starts growing in this far from the camera...
const FADE_NEAR := 480.0  ## ...and is full height by here
const WALK := 1.0  ## sampling step when finding a chunk's cells (finer than SPACING)
const POINTS_PER_METER := 5
const DRAG := 700.0  ## N per m/s of speed while plowing
const BUILD_BUDGET_USEC := 2000.0
const CLUMP_REACH := 0.6  ## how far a clump's leaves reach out from its stalks

var route: RouteData
var fields: Fields
var car: Car
var score: ScoreKeeper
var plowing := false
var plowed_meters := 0.0
## The closest a chunk has been to the car when it appeared, after the initial build
## (checked by the QA drive: it has to be past FADE_FAR so it grows in unseen).
var nearest_pop_in := INF
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _chunks := {}  ## chunk -> MultiMeshInstance3D
var _where := {}  ## Vector2i grid cell -> [chunk, instance index]
var _flattened := {}  ## Vector2i grid cell -> true, for the run
var _job := {}  ## the chunk being built
var _warming_up := false
var _meter_credit := 0.0
var _fresh_entry := true
var _leaves: CPUParticles3D


func setup(r: RouteData, f: Fields, c: Car, s: ScoreKeeper) -> void:
	route = r
	fields = f
	car = c
	score = s
	_mesh = _clump_mesh()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/corn.gdshader")
	_material.set_shader_parameter("fade_far", FADE_FAR)
	_material.set_shader_parameter("fade_near", FADE_NEAR)
	_leaves = _make_leaves()
	add_child(_leaves)


## Stand all the corn back up for a new run (warm_up() builds it again).
func reset() -> void:
	_flattened.clear()
	plowed_meters = 0.0
	_abandon_job()
	for c in _chunks.keys():
		_free_chunk(c)


## Build everything in range right now (at the start, or after the car is moved).
func warm_up() -> void:
	_abandon_job()
	_warming_up = true
	var wanted := _wanted_chunks()
	for c in _chunks.keys():
		if not c in wanted:
			_free_chunk(c)
	for c in wanted:
		if not _chunks.has(c):
			_start_chunk(c)
			_continue_chunk(INF)
	_warming_up = false


func chunk_count() -> int:
	return _chunks.size()


func clump_count() -> int:
	return _where.size()


## Standing clumps whose leaves reach into the car's body (for the clipping check).
func standing_clumps_touching(c: Car) -> int:
	var count := 0
	for cell in _cells_near(c, 0.0):
		if not _flattened.has(cell):
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_stream()
	_flatten_touching(delta)
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


## Chunks within RADIUS of the car, nearest first.
func _wanted_chunks() -> Array[int]:
	var first := maxi(0, floori((car.station - RADIUS) / CHUNK_LENGTH))
	var last := floori(minf(car.station + RADIUS, route.length - 1.0) / CHUNK_LENGTH)
	var out: Array[int] = []
	for c in range(first, last + 1):
		out.append(c)
	var here := car.station
	out.sort_custom(func(a, b): return absf((a + 0.5) * CHUNK_LENGTH - here) < absf((b + 0.5) * CHUNK_LENGTH - here))
	return out


## Free chunks that fell out of range and keep building the ones that came into it.
func _stream() -> void:
	if _job.is_empty():
		var wanted := _wanted_chunks()
		for c in _chunks.keys():
			if not c in wanted:
				_free_chunk(c)
		for c in wanted:
			if not _chunks.has(c):
				_start_chunk(c)
				break
	if not _job.is_empty():
		_continue_chunk(BUILD_BUDGET_USEC)


func _start_chunk(c: int) -> void:
	_job = {"chunk": c, "s": c * CHUNK_LENGTH, "end": minf((c + 1) * CHUNK_LENGTH, route.length),
		"cells": [] as Array[Vector2i], "buffer": PackedFloat32Array(), "nearest": INF}


## Walk the chunk's stretch of road in WALK steps, across both verges, and collect the
## corn cells it passes over. A cell already claimed by a neighboring chunk stays there.
func _continue_chunk(budget_usec: float) -> void:
	var start := Time.get_ticks_usec()
	var c: int = _job.chunk
	var cells: Array[Vector2i] = _job.cells
	var buffer: PackedFloat32Array = _job.buffer
	var car_pos := car.global_position
	while _job.s < _job.end:
		var s: float = _job.s
		var center := route.position_at(s)
		var right := route.right_at(s)
		for side: float in [-1.0, 1.0]:
			var offset := VERGE - WALK
			while offset <= LATERAL_REACH + WALK:
				var p := center + right * (side * offset)
				offset += WALK
				var cell := Vector2i(roundi(p.x / SPACING), roundi(p.z / SPACING))
				if _where.has(cell):
					continue
				var x := cell.x * SPACING
				var z := cell.y * SPACING
				var d := route.terrain.road_distance_at(x, z)
				if d < VERGE or d > LATERAL_REACH or fields.crop_at(x, z) != Fields.CORN:
					continue
				_where[cell] = [c, cells.size()]
				cells.append(cell)
				var xf := _clump_transform(cell)
				_append_transform(buffer, xf)
				_job.nearest = minf(_job.nearest, xf.origin.distance_to(car_pos))
		_job.s = s + WALK
		if Time.get_ticks_usec() - start > budget_usec:
			_job.buffer = buffer  # packed arrays are values; keep the progress
			return
	_finish_chunk(c, cells, buffer)


func _finish_chunk(c: int, cells: Array[Vector2i], buffer: PackedFloat32Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh
	multimesh.instance_count = cells.size()
	if not cells.is_empty():
		multimesh.buffer = buffer
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = FADE_FAR + CHUNK_LENGTH  # all of it is below ground by then
	node.set_meta("cells", cells)
	add_child(node)
	_chunks[c] = node
	if not cells.is_empty() and not _warming_up:
		nearest_pop_in = minf(nearest_pop_in, _job.nearest)
	_job = {}


## Drop a half-built chunk, releasing the cells it claimed.
func _abandon_job() -> void:
	if _job.is_empty():
		return
	for cell: Vector2i in _job.cells:
		_where.erase(cell)
	_job = {}


func _free_chunk(c: int) -> void:
	var node: MultiMeshInstance3D = _chunks[c]
	for cell: Vector2i in node.get_meta("cells"):
		_where.erase(cell)
	node.queue_free()
	_chunks.erase(c)


## MultiMesh buffers hold each transform as a 3x4 matrix, row by row.
static func _append_transform(buffer: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	buffer.append_array([b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y,
		b.x.z, b.y.z, b.z.z, t.origin.z])


## Flatten every clump the car's body touches now or will by the next tick, so standing
## corn never shows through the car.
func _flatten_touching(delta: float) -> void:
	for cell in _cells_near(car, car.linear_velocity.length() * delta):
		if _flattened.has(cell):
			continue
		_flattened[cell] = true
		var at: Array = _where[cell]
		var node: MultiMeshInstance3D = _chunks[at[0]]
		node.multimesh.set_instance_transform(at[1], _clump_transform(cell))


## Clumps (in finished chunks) whose leaves reach into the car's body, with the body
## stretched forward by `ahead` meters along its direction of travel.
func _cells_near(c: Car, ahead: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pos := c.global_position
	var inv := c.global_transform.affine_inverse()
	var half := Vector2(c.stats.body_size.x, c.stats.body_size.z) / 2.0 + Vector2.ONE * CLUMP_REACH
	var travel := inv.basis * c.linear_velocity
	var sweep := Vector2(travel.x, travel.z).normalized() * ahead if travel.length() > 0.1 else Vector2.ZERO
	var span := ceili((half.y + ahead) / SPACING) + 1
	var center := Vector2i(roundi(pos.x / SPACING), roundi(pos.z / SPACING))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell := center + Vector2i(dx, dz)
			if not _where.has(cell) or not _chunks.has(_where[cell][0]):
				continue
			var local := inv * _stalk_position(cell)
			if absf(local.y) > 2.5:
				continue
			if in_swept_box(Vector2(local.x, local.z), half, sweep):
				out.append(cell)
	return out


## Is `p` inside a box (centered on the origin, half extents `half`) at any point as it
## moves from where it is to `sweep` away?
static func in_swept_box(p: Vector2, half: Vector2, sweep: Vector2) -> bool:
	var lo := 0.0
	var hi := 1.0
	for axis in 2:
		if absf(sweep[axis]) < 1e-6:
			if absf(p[axis]) >= half[axis]:
				return false
			continue
		var t0: float = (p[axis] - half[axis]) / sweep[axis]
		var t1: float = (p[axis] + half[axis]) / sweep[axis]
		lo = maxf(lo, minf(t0, t1))
		hi = minf(hi, maxf(t0, t1))
	return lo < hi


func _stalk_position(cell: Vector2i) -> Vector3:
	var h := Fields.cell_hash(cell.x, cell.y)
	var x := cell.x * SPACING + (h - 0.5) * 0.6
	var z := cell.y * SPACING + (h - 0.5) * 0.6
	return Vector3(x, route.terrain.height_at(x, z), z)


func _clump_transform(cell: Vector2i) -> Transform3D:
	var h := Fields.cell_hash(cell.x, cell.y)  # stable per-clump jitter
	var basis := Basis(Vector3.UP, h * TAU).scaled(Vector3.ONE * (0.85 + 0.3 * h))
	if _flattened.has(cell):
		basis = Basis(Vector3.UP, h * TAU) * Basis(Vector3.RIGHT, deg_to_rad(80.0)).scaled(Vector3(1.0, 0.6, 1.0))
	return Transform3D(basis, _stalk_position(cell))


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
