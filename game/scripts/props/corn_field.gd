class_name CornField
extends Node3D
## Corn you can plow through. Up close it's real clumps (crossed quads with a leafy top)
## in every corn field around the car, however deep into the field: built BLOCK meters
## square at a time, a few milliseconds per physics tick so driving never hitches, and
## freed once the car is far away. Past them the rest of each field is the corn canopy
## that comes with the terrain (CornCanopy). The canopy sinks out of the way within
## CornCanopy.CLEAR_INNER of the car, and the clumps sink into the ground between
## CLUMP_FULL and CLUMP_GONE, where the canopy is already back up around them, so the
## hand-off can't be seen.
##
## Driving into it flattens everything the car's body touches, slows you down and scores
## by the meter. Flattened corn stays flat for the rest of the run.

const SPACING := 1.6  ## meters between clumps
const VERGE := 26.0  ## corn starts this far from the road centerline, past the fence and a grass strip
const YARD := 24.0  ## and this far from any building: farmyards and lawns
const CELLS_PER_BLOCK := 40
const BLOCK := SPACING * CELLS_PER_BLOCK  ## meters per side of a square of clumps
const BUILD_RADIUS := 120.0  ## blocks with any part this close to the car are built...
const FREE_RADIUS := 150.0  ## ...and freed once every part of them is further than this
const CLUMP_FULL := 90.0  ## clumps are full height out to here from the car...
const CLUMP_GONE := 98.0  ## ...and down in the ground by here
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
## The closest a block's clumps have been to the car when they appeared, outside a
## respawn (checked by the QA drive: past CLUMP_GONE they're still down in the ground).
var nearest_pop_in := INF
var canopy_material: ShaderMaterial  ## the terrain's corn canopy, told where the car is
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _blocks := {}  ## Vector2i block -> MultiMeshInstance3D
var _where := {}  ## Vector2i grid cell -> [block, instance index]
var _flattened := {}  ## Vector2i grid cell -> true, for the run
var _job := {}  ## the block being built
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
	_material.set_shader_parameter("fade_far", CLUMP_GONE)
	_material.set_shader_parameter("fade_near", CLUMP_FULL)
	_leaves = _make_leaves()
	add_child(_leaves)


## The condition's corn colors (green, harvest brown). Which fields are cut is up to
## Fields.harvested; blocks are rebuilt by reset() and warm_up() for that.
func apply_condition(c: Condition) -> void:
	_material.set_shader_parameter("leaf", c.corn_leaf)
	_material.set_shader_parameter("tassel", c.corn_tassel)
	_material.set_shader_parameter("light", c.corn_light())


## Stand all the corn back up for a new run (warm_up() builds it again).
func reset() -> void:
	_flattened.clear()
	plowed_meters = 0.0
	_abandon_job()
	for b in _blocks.keys():
		_free_block(b)


## Build everything in range right now (at the start, or after the car is moved).
func warm_up() -> void:
	_abandon_job()
	_warming_up = true
	var wanted := _wanted_blocks()
	for b in _blocks.keys():
		if _block_distance(b) > FREE_RADIUS:
			_free_block(b)
	for b in wanted:
		if not _blocks.has(b):
			_start_block(b)
			_continue_block(INF)
	_warming_up = false
	_update_materials()


func block_count() -> int:
	return _blocks.size()


func clump_count() -> int:
	return _where.size()


## Standing clumps whose leaves reach into the car's body (for the clipping check).
func standing_clumps_touching(c: Car) -> int:
	var count := 0
	for cell in _cells_near(c, 0.0):
		if not _flattened.has(cell):
			count += 1
	return count


## Meters from the road as far as the corn's concerned: it grows where this is VERGE or
## more. Near a building it's cut short so the corn stops YARD meters from it, which
## gives every farmstead a yard with walls of corn around it (CornCanopy builds its
## walls on this line too).
static func clearance(terrain: TerrainTiles, x: float, z: float) -> float:
	var road := terrain.road_distance_smooth(x, z)
	if road >= 255.0:
		return road
	return minf(road, VERGE + terrain.yard_distance_smooth(x, z) - YARD)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_stream()
	_flatten_touching(delta)
	var pos := car.global_position
	var d := clearance(route.terrain, pos.x, pos.z)
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


## Blocks with any part within BUILD_RADIUS of the car, nearest first.
func _wanted_blocks() -> Array[Vector2i]:
	var here := Vector2i(floori(car.global_position.x / BLOCK), floori(car.global_position.z / BLOCK))
	var reach := ceili(BUILD_RADIUS / BLOCK) + 1
	var out: Array[Vector2i] = []
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var b := here + Vector2i(dx, dz)
			if _block_distance(b) <= BUILD_RADIUS:
				out.append(b)
	out.sort_custom(func(a, b): return _block_distance(a) < _block_distance(b))
	return out


## Distance from the car to the nearest point of a block, on the ground.
func _block_distance(b: Vector2i) -> float:
	var p := Vector2(car.global_position.x, car.global_position.z)
	var lo := Vector2(b) * BLOCK
	var nearest := p.clamp(lo, lo + Vector2.ONE * BLOCK)
	return nearest.distance_to(p)


## Free blocks the car has left behind and keep building the ones it's coming up on.
func _stream() -> void:
	if _job.is_empty():
		for b in _blocks.keys():
			if _block_distance(b) > FREE_RADIUS:
				_free_block(b)
		for b in _wanted_blocks():
			if not _blocks.has(b):
				_start_block(b)
				break
	if not _job.is_empty():
		_continue_block(BUILD_BUDGET_USEC)


func _start_block(b: Vector2i) -> void:
	_job = {"block": b, "col": 0, "cells": [] as Array[Vector2i], "buffer": PackedFloat32Array(), "nearest": INF}
	# Most blocks are nowhere near corn: a block is far smaller than a field, so if no
	# corner is in a corn field, none of it is.
	var lo := Vector2(b) * BLOCK
	var any_corn := false
	for corner: Vector2 in [lo, lo + Vector2(BLOCK, 0), lo + Vector2(0, BLOCK), lo + Vector2.ONE * BLOCK]:
		any_corn = any_corn or fields.crop_at(corner.x, corner.y) == Fields.CORN
	if not any_corn:
		_job.col = CELLS_PER_BLOCK


## Scan the block's grid a column at a time for cells in corn past the verge.
func _continue_block(budget_usec: float) -> void:
	var start := Time.get_ticks_usec()
	var b: Vector2i = _job.block
	var cells: Array[Vector2i] = _job.cells
	var buffer: PackedFloat32Array = _job.buffer
	var car_pos := car.global_position
	while _job.col < CELLS_PER_BLOCK:
		var cx: int = b.x * CELLS_PER_BLOCK + _job.col
		for row in CELLS_PER_BLOCK:
			var cell := Vector2i(cx, b.y * CELLS_PER_BLOCK + row)
			var x := cell.x * SPACING
			var z := cell.y * SPACING
			var d := clearance(route.terrain, x, z)
			if d < VERGE or d >= 255.0 or fields.crop_at(x, z) != Fields.CORN:
				continue
			_where[cell] = [b, cells.size()]
			cells.append(cell)
			var xf := _clump_transform(cell)
			_append_transform(buffer, xf)
			_job.nearest = minf(_job.nearest, Vector2(xf.origin.x - car_pos.x, xf.origin.z - car_pos.z).length())
		_job.col += 1
		if Time.get_ticks_usec() - start > budget_usec:
			_job.buffer = buffer  # packed arrays are values; keep the progress
			return
	_finish_block(b, cells, buffer)


func _finish_block(b: Vector2i, cells: Array[Vector2i], buffer: PackedFloat32Array) -> void:
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
	node.set_meta("cells", cells)
	add_child(node)
	_blocks[b] = node
	if not cells.is_empty() and not _warming_up:
		nearest_pop_in = minf(nearest_pop_in, _job.nearest)
	_job = {}


## Drop a half-built block, releasing the cells it claimed.
func _abandon_job() -> void:
	if _job.is_empty():
		return
	for cell: Vector2i in _job.cells:
		_where.erase(cell)
	_job = {}


func _free_block(b: Vector2i) -> void:
	var node: MultiMeshInstance3D = _blocks[b]
	for cell: Vector2i in node.get_meta("cells"):
		_where.erase(cell)
	node.queue_free()
	_blocks.erase(b)


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
		var node: MultiMeshInstance3D = _blocks[at[0]]
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
			if not _where.has(cell) or not _blocks.has(_where[cell][0]):
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


## Two crossed quads, 2.4 m wide, 2.5 m tall, standing on y = 0, and a leafy top
## (marked by vertex color) so a field of them looks full from above too.
func _clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.BLACK)
	for angle in [PI / 4.0, -PI / 4.0]:
		var across := Vector3(cos(angle), 0.0, sin(angle)) * 1.2
		var corners := [[-across, 0.0, 1.0], [across, 1.0, 1.0], [across + Vector3.UP * 2.5, 1.0, 0.0],
			[-across + Vector3.UP * 2.5, 0.0, 0.0]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(corners[i][1], corners[i][2]))
			st.add_vertex(corners[i][0])
	st.set_color(Color.WHITE)
	var h := 2.05
	var top := [[Vector3(-0.95, h, -0.95), 0.0, 0.0], [Vector3(0.95, h, -0.95), 1.0, 0.0],
		[Vector3(0.95, h, 0.95), 1.0, 1.0], [Vector3(-0.95, h, 0.95), 0.0, 1.0]]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(top[i][1], top[i][2]))
		st.add_vertex(top[i][0])
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
	if car == null:
		return
	_update_materials()
	if _leaves.emitting:
		_leaves.global_position = car.global_position


## Tell the clumps and the canopy where the car is (they make room around it).
func _update_materials() -> void:
	var center := car.get_global_transform_interpolated().origin
	_material.set_shader_parameter("clear_center", center)
	if canopy_material:
		canopy_material.set_shader_parameter("clear_center", center)
