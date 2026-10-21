class_name Scenery
extends Node3D
## The real buildings and trees along the road, found in the USGS lidar by
## tools/bake_lidar.py: farmhouses, barns, machine sheds and grain bins at their real
## spots and sizes, the tree lines, windbreaks and creek woods.
##
## Drawn as GPU instances of a few low-poly models (SceneryMeshes), in BLOCK-sized
## squares that load and unload around the car at the same distances as the detailed
## terrain under them, with plainer models past NEAR_LOD. A block's instances are worked
## out on a worker thread the first time it's needed (a wooded one has thousands of
## trees) and kept. Near the car they're solid: buildings as boxes (and cylinders for
## bins), trees as their trunks.

const BLOCK := 512.0
const LOAD_RADIUS := 1250.0  ## the detailed terrain's (WorldStreamer.RADII.tile)
const UNLOAD_RADIUS := 1550.0
const NEAR_LOD := 450.0
const LOD_HYSTERESIS := 50.0
const COLLIDE_RADIUS := 250.0
const COLLIDE_UNLOAD := 400.0
const KINDS := ["house", "barn", "shed", "bin", "tree", "conifer", "yard_light"]
const YARD_LIGHT_HEIGHT := 8.0
const TRUNK_RADIUS := 0.35
const TRUNK_HEIGHT := 5.0
const REFRESH_SECONDS := 0.2
const BUILD_BUDGET_USEC := 3000
## Wall colors: mostly white farmhouses; barns mostly red; sheds steel.
const HOUSE_COLORS: Array[Color] = [Color(0.95, 0.95, 0.93), Color(0.95, 0.95, 0.93), Color(0.93, 0.89, 0.78),
	Color(0.80, 0.85, 0.88), Color(0.86, 0.82, 0.70), Color(0.70, 0.70, 0.68), Color(0.62, 0.42, 0.32)]
const BARN_COLORS: Array[Color] = [Color(0.62, 0.13, 0.10), Color(0.62, 0.13, 0.10), Color(0.55, 0.12, 0.10),
	Color(0.92, 0.92, 0.90), Color(0.60, 0.58, 0.55)]
const SHED_COLORS: Array[Color] = [Color(0.88, 0.89, 0.90), Color(0.80, 0.81, 0.82), Color(0.93, 0.93, 0.91),
	Color(0.62, 0.15, 0.12), Color(0.72, 0.66, 0.55), Color(0.55, 0.62, 0.66)]


class Block:
	var key: Vector2i
	var buildings := PackedInt32Array()
	var trees := PackedInt32Array()
	var node: Node3D
	var lod := -1
	var multimeshes := {}  ## kind -> MultiMeshInstance3D
	var body := RID()
	var shapes: Array[RID] = []
	var buffers := {}  ## kind -> PackedFloat32Array of instances, once worked out
	var task := -1  ## the worker working them out


var route: RouteData
var focus := Vector3.ZERO
var material: ShaderMaterial
## How much to draw, for slow machines (F2 cycles it): 1 everything, 0.5 half the trees
## (an even thinning), 0 no buildings or trees at all.
var density := 1.0:
	set(value):
		density = value
		for block: Block in _blocks.values():
			if block.node:
				_apply_density(block)
				_drop_body(block)  # rebuilt with only what's drawn
## The closest a block appeared to the focus while driving (QA checks it).
var nearest_pop_in := INF
var _blocks := {}  ## Vector2i -> Block
var _meshes := {}  ## "kind:lod" -> Mesh
var _trunk_shape := RID()
var _refresh := 0.0
var _queue: Array[Block] = []
var _warming_up := false


func setup(r: RouteData) -> void:
	route = r
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/scenery.gdshader")
	for kind: String in KINDS:
		for lod in 2:
			_meshes["%s:%d" % [kind, lod]] = SceneryMeshes.build(kind, lod)
	for i in route.buildings.size():
		var b: Dictionary = route.buildings[i]
		_block_at(float(b.x), float(b.z)).buildings.append(i)
	for i in route.trees.size() / 5:
		_block_at(route.trees[i * 5], route.trees[i * 5 + 1]).trees.append(i)
	_trunk_shape = PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(_trunk_shape, {"radius": TRUNK_RADIUS, "height": TRUNK_HEIGHT})


func _exit_tree() -> void:
	for block: Block in _blocks.values():
		if block.task != -1:
			WorkerThreadPool.wait_for_task_completion(block.task)
		_drop_body(block)
	if _trunk_shape.is_valid():
		PhysicsServer3D.free_rid(_trunk_shape)
		_trunk_shape = RID()


## Build everything around `pos` right away (spawning, the tow truck).
func warm_up(pos: Vector3) -> void:
	focus = pos
	_warming_up = true
	_refresh_all()
	while not _queue.is_empty():
		_build(_queue.pop_front())
	_warming_up = false


func loaded_count() -> int:
	return _blocks.values().filter(func(b: Block) -> bool: return b.node != null).size()


func instance_count() -> int:
	var n := 0
	for block: Block in _blocks.values():
		if block.node:
			n += block.buildings.size() + block.trees.size()
	return n


## The season's look: leaf color (green, fall colors, bare gray), snow on top, lit windows.
func set_look(leaf: Color, snow: float, night: float) -> void:
	material.set_shader_parameter("leaf", leaf)
	material.set_shader_parameter("snow", snow)
	material.set_shader_parameter("night", night)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		_refresh_all()
	var start := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - start < BUILD_BUDGET_USEC:
		_build(_queue.pop_front())


func _block_at(x: float, z: float) -> Block:
	var key := Vector2i(floori(x / BLOCK), floori(z / BLOCK))
	if not _blocks.has(key):
		var block := Block.new()
		block.key = key
		_blocks[key] = block
	return _blocks[key]


## Flat distance from the focus to the nearest point of a block.
func _distance(block: Block) -> float:
	var lo := Vector2(block.key) * BLOCK
	var p := Vector2(focus.x, focus.z)
	var q := p.clamp(lo, lo + Vector2.ONE * BLOCK)
	return p.distance_to(q)


func _refresh_all() -> void:
	_queue.clear()
	var wanted: Array = []
	for block: Block in _blocks.values():
		var d := _distance(block)
		if block.node and d > UNLOAD_RADIUS:
			_free(block)
			continue
		if block.body.is_valid() and d > COLLIDE_UNLOAD:
			_drop_body(block)
		if d > LOAD_RADIUS:
			continue
		var lod := 0 if d < NEAR_LOD - (LOD_HYSTERESIS if block.lod == 1 else 0.0) else 1
		if block.node == null or block.lod != lod or (d < COLLIDE_RADIUS and not block.body.is_valid()):
			wanted.append([d, block])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for w in wanted:
		_queue.append(w[1])


func _build(block: Block) -> void:
	var d := _distance(block)
	if d > LOAD_RADIUS:
		return
	var lod := 0 if d < NEAR_LOD - (LOD_HYSTERESIS if block.lod == 1 else 0.0) else 1
	if block.node == null:
		if block.task == -1 and block.buffers.is_empty():
			if _warming_up:
				_compute(block)
			else:
				block.task = WorkerThreadPool.add_task(_compute.bind(block), false, "scenery block")
				return
		if block.task != -1:
			if not WorkerThreadPool.is_task_completed(block.task) and not _warming_up:
				return  # still working; the next refresh asks again
			WorkerThreadPool.wait_for_task_completion(block.task)
			block.task = -1
		if not _warming_up:
			nearest_pop_in = minf(nearest_pop_in, d)
		block.node = Node3D.new()
		add_child(block.node)
		block.lod = lod
		_instantiate(block)
	if block.lod != lod:
		block.lod = lod
		for kind: String in block.multimeshes:
			block.multimeshes[kind].multimesh.mesh = _meshes["%s:%d" % [kind, lod]]
	if d < COLLIDE_RADIUS and not block.body.is_valid():
		_make_body(block)


## Every instance of the block placed on the terrain (runs on a worker thread: it only
## reads the route data and writes the block's buffers).
func _compute(block: Block) -> void:
	var by_kind := {}
	for kind: String in KINDS:
		by_kind[kind] = PackedFloat32Array()
	var t := route.terrain
	for i in block.buildings:
		var b: Dictionary = route.buildings[i]
		var x := float(b.x)
		var z := float(b.z)
		var yaw := float(b.yaw)
		var length := float(b.length)
		var width := float(b.width)
		var basis := Basis(Vector3.UP, yaw)
		# Sit on the lowest corner so nothing floats on a slope; the walls run down into the hill.
		var ground := INF
		for corner: Vector3 in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
			var c := basis * (corner * Vector3(length, 0, width))
			var h := t.height_at(x + c.x, z + c.z)
			if not is_nan(h):
				ground = minf(ground, h)
		if is_inf(ground):
			continue
		var center_h := t.height_at(x, z)
		var height := float(b.height) + (center_h - ground if not is_nan(center_h) else 0.0) + 0.2
		var kind: String = b.kind
		if kind == "bin":
			length = (length + width) / 2.0
			width = length
		var xf := Transform3D(basis * Basis.from_scale(Vector3(length, height, width)), Vector3(x, ground - 0.2, z))
		_append(by_kind[kind], xf, _building_color(kind, i))
		if kind == "house":
			# Every farmhouse has its pole light out in the yard.
			var spot := Vector3(x, 0, z) + basis * Vector3(length * 0.5 + 6.0, 0, width * 0.5 + 4.0)
			var h := t.height_at(spot.x, spot.z)
			if not is_nan(h):
				var pole := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5) * Basis.from_scale(Vector3(1.0, YARD_LIGHT_HEIGHT, 1.0)),
					Vector3(spot.x, h - 0.2, spot.z))
				_append(by_kind["yard_light"], pole, Color.WHITE)
	# Trees in a shuffled (but fixed) order, so drawing the first half thins them evenly.
	var order := Array(block.trees)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(block.key)
	for j in range(order.size() - 1, 0, -1):
		var r := rng.randi_range(0, j)
		var swap: int = order[j]
		order[j] = order[r]
		order[r] = swap
	for i: int in order:
		var k := i * 5
		var x := route.trees[k]
		var z := route.trees[k + 1]
		var ground := t.height_at(x, z)
		if is_nan(ground):
			continue
		var height := route.trees[k + 2]
		var crown := route.trees[k + 3] * 2.0
		var kind := "conifer" if route.trees[k + 4] > 0.5 else "tree"
		var spin := _hash(i * 3 + 1) * TAU
		var xf := Transform3D(Basis(Vector3.UP, spin) * Basis.from_scale(Vector3(crown, height, crown)), Vector3(x, ground - 0.3, z))
		var shade := 0.85 + 0.3 * _hash(i * 7 + 2)
		_append(by_kind[kind], xf, Color(shade, shade * (0.95 + 0.1 * _hash(i * 11)), shade * 0.9))
	block.buffers = by_kind


## One multimesh per kind present in the block.
func _instantiate(block: Block) -> void:
	for kind: String in KINDS:
		var buffer: PackedFloat32Array = block.buffers.get(kind, PackedFloat32Array())
		if buffer.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes["%s:%d" % [kind, maxi(block.lod, 0)]]
		mm.instance_count = buffer.size() / 16
		mm.buffer = buffer
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = material
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		block.node.add_child(inst)
		block.multimeshes[kind] = inst
	_apply_density(block)


func _apply_density(block: Block) -> void:
	block.node.visible = density > 0.0
	for kind: String in block.multimeshes:
		var mm: MultiMesh = block.multimeshes[kind].multimesh
		var trees := kind == "tree" or kind == "conifer"
		mm.visible_instance_count = ceili(mm.instance_count * density) if trees and density < 1.0 else -1


## MultiMesh buffer layout (3D transform + color): the basis rows with the origin at the
## end of each, then the instance color (the tint).
static func _append(buffer: PackedFloat32Array, xf: Transform3D, tint: Color) -> void:
	var b := xf.basis
	buffer.append_array([b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y,
		b.x.z, b.y.z, b.z.z, xf.origin.z, tint.r, tint.g, tint.b, 1.0])


func _building_color(kind: String, i: int) -> Color:
	var h := _hash(i * 13 + 5)
	match kind:
		"house":
			return HOUSE_COLORS[int(h * HOUSE_COLORS.size()) % HOUSE_COLORS.size()]
		"barn":
			return BARN_COLORS[int(h * BARN_COLORS.size()) % BARN_COLORS.size()]
		"bin":
			return Color.WHITE
	return SHED_COLORS[int(h * SHED_COLORS.size()) % SHED_COLORS.size()]


## Solid near the car: a box per building (cylinder for a bin), a trunk per tree; only
## what's drawn.
func _make_body(block: Block) -> void:
	if density <= 0.0:
		return
	var space := get_world_3d().space
	block.body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(block.body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(block.body, space)
	PhysicsServer3D.body_set_collision_layer(block.body, 1 << (Car.WORLD_LAYER - 1))
	PhysicsServer3D.body_set_collision_mask(block.body, 0)
	PhysicsServer3D.body_set_state(block.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	for kind: String in block.multimeshes:
		var mm: MultiMesh = block.multimeshes[kind].multimesh
		var shown := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		for j in shown:
			var xf := mm.get_instance_transform(j)
			var scale := xf.basis.get_scale()
			var shape: RID
			var at: Transform3D
			if kind == "yard_light":
				continue
			if kind == "tree" or kind == "conifer":
				shape = _trunk_shape
				at = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * TRUNK_HEIGHT / 2.0)
			elif kind == "bin":
				shape = PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(shape, {"radius": scale.x / 2.0, "height": scale.y})
				block.shapes.append(shape)
				at = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * scale.y / 2.0)
			else:
				shape = PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape, scale / 2.0)
				block.shapes.append(shape)
				at = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * scale.y / 2.0)
			PhysicsServer3D.body_add_shape(block.body, shape, at)


func _drop_body(block: Block) -> void:
	if block.body.is_valid():
		PhysicsServer3D.free_rid(block.body)
		block.body = RID()
	for shape in block.shapes:
		PhysicsServer3D.free_rid(shape)
	block.shapes.clear()


func _free(block: Block) -> void:
	_drop_body(block)
	block.node.queue_free()
	block.node = null
	block.multimeshes.clear()
	block.lod = -1


## Solid boxes of the buildings within `radius` of a point (QA's clip probe), as
## [transform, half extents] with the transform at the box's center.
func building_boxes(near: Vector3, radius: float) -> Array:
	var out := []
	for block: Block in _blocks.values():
		if block.node == null or _distance(block) > radius + BLOCK:
			continue
		for kind: String in ["house", "barn", "shed", "bin"]:
			if not block.multimeshes.has(kind):
				continue
			var mm: MultiMesh = block.multimeshes[kind].multimesh
			for j in mm.instance_count:
				var xf := mm.get_instance_transform(j)
				if Vector2(xf.origin.x - near.x, xf.origin.z - near.z).length() > radius:
					continue
				var scale := xf.basis.get_scale()
				out.append([Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * scale.y / 2.0), scale / 2.0])
	return out


static func _hash(n: int) -> float:
	var h := (n * 374761393) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / 16777216.0
