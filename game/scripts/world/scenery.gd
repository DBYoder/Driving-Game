class_name Scenery
extends Node3D
## The real buildings and trees along the road, found in the USGS lidar by
## tools/bake_lidar.py: farmhouses, barns, machine sheds and grain bins at their real
## spots and sizes, the tree lines, windbreaks and creek woods.
##
## Drawn as GPU instances of a few low-poly models (SceneryMeshes), each building's
## fitted to its own eaves and ridge and given its roof's color from the 2015 aerial
## photos (tools/bake_aerial.py) where it has one, in BLOCK-sized
## squares that load and unload around the car at the same distances as the detailed
## terrain under them, with plainer models past `near_lod`. A block's instances are worked
## out the first time it's needed (a wooded one has thousands of trees) and kept: on a
## worker thread, or without one (a single-threaded web build) a slice a frame. Near the
## car they're solid: buildings as boxes (and cylinders for bins), trees as their trunks.

const BLOCK := 512.0
const LOAD_RADIUS := 1250.0  ## the detailed terrain's (WorldStreamer.RADII.tile)
const UNLOAD_RADIUS := 1550.0
const NEAR_LOD := 450.0  ## the usual `near_lod` (the High preset pushes it out)
const LOD_HYSTERESIS := 50.0
const COLLIDE_RADIUS := 250.0
const COLLIDE_UNLOAD := 400.0
const KINDS := ["house", "barn", "shed", "bin", "elevator", "tree", "conifer", "yard_light"]
const YARD_LIGHT_HEIGHT := 8.0
const TRUNK_RADIUS := 0.35
const TRUNK_HEIGHT := 5.0
const REFRESH_SECONDS := 0.2
const BUILD_BUDGET_USEC := 3000
const SLICE := 64  ## buildings and trees placed between looks at the clock, working a block out here
const STRIDE := 20  ## floats an instance takes in a MultiMesh buffer: transform, color, custom data
## Where a building has no eaves in its data: their share of the height.
const EAVES := {"house": 0.6, "barn": 0.45, "shed": 0.75}
const MIN_WALL_M := 2.2
## Roofs a building has no photo of: dark shingles on houses; steel, mostly, on the rest.
const HOUSE_ROOFS: Array[Color] = [Color(0.27, 0.26, 0.26), Color(0.22, 0.21, 0.22), Color(0.33, 0.27, 0.22),
	Color(0.30, 0.31, 0.33), Color(0.24, 0.30, 0.26)]
const BARN_ROOFS: Array[Color] = [Color(0.74, 0.75, 0.76), Color(0.74, 0.75, 0.76), Color(0.30, 0.29, 0.29),
	Color(0.50, 0.15, 0.12)]
const SHED_ROOFS: Array[Color] = [Color(0.80, 0.81, 0.82), Color(0.74, 0.75, 0.77), Color(0.86, 0.86, 0.85),
	Color(0.45, 0.46, 0.47), Color(0.50, 0.15, 0.12), Color(0.30, 0.38, 0.45)]
## A photo's color to the roof's own: the photos are hazy and bright from up there.
const PHOTO_GAMMA := 1.3
const PHOTO_GAIN := 0.95
## Wall colors: mostly white farmhouses; barns mostly red; sheds steel.
const HOUSE_COLORS: Array[Color] = [Color(0.95, 0.95, 0.93), Color(0.95, 0.95, 0.93), Color(0.93, 0.89, 0.78),
	Color(0.80, 0.85, 0.88), Color(0.86, 0.82, 0.70), Color(0.70, 0.70, 0.68), Color(0.62, 0.42, 0.32)]
const BARN_COLORS: Array[Color] = [Color(0.62, 0.13, 0.10), Color(0.62, 0.13, 0.10), Color(0.55, 0.12, 0.10),
	Color(0.92, 0.92, 0.90), Color(0.60, 0.58, 0.55)]
## Grain elevators: galvanized steel, or concrete.
const ELEVATOR_COLORS: Array[Color] = [Color(0.86, 0.87, 0.88), Color(0.80, 0.80, 0.78), Color(0.74, 0.73, 0.70)]
const SHED_COLORS: Array[Color] = [Color(0.88, 0.89, 0.90), Color(0.80, 0.81, 0.82), Color(0.93, 0.93, 0.91),
	Color(0.62, 0.15, 0.12), Color(0.72, 0.66, 0.55), Color(0.55, 0.62, 0.66)]


## A block being worked out a slice at a time: its instances so far, and how far through
## its buildings, then its trees, it's got.
class Work:
	var by_kind := {}
	var trees := []  ## in a shuffled (but fixed) order, so drawing the first half thins them evenly
	var next := 0


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
	var work: Work  ## or how far they've got here, without one


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
## Detailed models within this of the car, plainer ones past it.
var near_lod := NEAR_LOD
## Work blocks out on worker threads. A single-threaded web build has none (a task added
## runs there and then, the whole block in one frame): a slice a frame on this one instead.
var threads := OS.has_feature("threads")
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
	material.set_shader_parameter("fitted", true)
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
	var deadline := Time.get_ticks_usec() + BUILD_BUDGET_USEC
	while not _queue.is_empty() and Time.get_ticks_usec() < deadline:
		var block: Block = _queue.pop_front()
		if not _build(block, deadline):
			_queue.push_front(block)  # more of it next frame
			return


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
		var lod := 0 if d < near_lod - (LOD_HYSTERESIS if block.lod == 1 else 0.0) else 1
		if block.node == null or block.lod != lod or (d < COLLIDE_RADIUS and not block.body.is_valid()):
			wanted.append([d, block])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for w in wanted:
		_queue.append(w[1])


## Build what a block needs now. False if it ran out of time (`deadline`, usec) working
## the block out: there's more to do next frame.
func _build(block: Block, deadline := 0) -> bool:
	var d := _distance(block)
	if d > LOAD_RADIUS:
		return true
	var lod := 0 if d < near_lod - (LOD_HYSTERESIS if block.lod == 1 else 0.0) else 1
	if block.node == null:
		if block.task == -1 and block.buffers.is_empty():
			if _warming_up:
				_compute(block)
				block.work = null
			elif not threads:
				if not _compute_until(block, deadline):
					return false
			else:
				block.task = WorkerThreadPool.add_task(_compute.bind(block), false, "scenery block")
				return true
		if block.task != -1:
			if not WorkerThreadPool.is_task_completed(block.task) and not _warming_up:
				return true  # still working; the next refresh asks again
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
	return true


## Every instance of the block placed on the terrain, all at once (on a worker thread: it
## only reads the route data and writes the block's buffers; or warming up).
func _compute(block: Block) -> void:
	var work := _start_work(block)
	_work_on(block, work, block.buildings.size() + work.trees.size())
	block.buffers = work.by_kind


## The same a slice at a time on this thread, until `deadline` (usec): true once it's done.
func _compute_until(block: Block, deadline: int) -> bool:
	if block.work == null:
		block.work = _start_work(block)
	while not _work_on(block, block.work, SLICE):
		if Time.get_ticks_usec() >= deadline:
			return false
	block.buffers = block.work.by_kind
	block.work = null
	return true


func _start_work(block: Block) -> Work:
	var work := Work.new()
	for kind: String in KINDS:
		work.by_kind[kind] = PackedFloat32Array()
	work.trees = Array(block.trees)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(block.key)
	for j in range(work.trees.size() - 1, 0, -1):
		var r := rng.randi_range(0, j)
		var swap: int = work.trees[j]
		work.trees[j] = work.trees[r]
		work.trees[r] = swap
	return work


## Place up to `count` more of the block's buildings, then its trees: true once they're
## all placed.
func _work_on(block: Block, work: Work, count: int) -> bool:
	var buildings := block.buildings.size()
	var stop := mini(work.next + count, buildings + work.trees.size())
	while work.next < stop:
		if work.next < buildings:
			_place_building(work.by_kind, block.buildings[work.next])
		else:
			_place_tree(work.by_kind, work.trees[work.next - buildings])
		work.next += 1
	return work.next >= buildings + work.trees.size()


func _place_building(by_kind: Dictionary, i: int) -> void:
	var t := route.terrain
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
		return
	var center_h := t.height_at(x, z)
	var below := (center_h - ground if not is_nan(center_h) else 0.0) + 0.2  # down into the hill
	var height := float(b.height) + below
	var kind: String = b.kind
	if kind == "bin":
		length = (length + width) / 2.0
		width = length
	var xf := Transform3D(basis * Basis.from_scale(Vector3(length, height, width)), Vector3(x, ground - 0.2, z))
	_append(by_kind[kind], xf, _building_color(kind, i), _roof(b, kind, i, below, height))
	if kind == "house":
		_place_yard_light(by_kind, b, basis, yaw)


## A house's pole light: where the bake found room for it in the yard ("light"; null if
## there's none), or (older data) off a corner.
func _place_yard_light(by_kind: Dictionary, b: Dictionary, basis: Basis, yaw: float) -> void:
	var spot: Vector3
	if b.has("light"):
		if b.light == null:
			return
		spot = Vector3(float(b.light[0]), 0.0, float(b.light[1]))
	else:
		spot = Vector3(float(b.x), 0, float(b.z)) + basis * Vector3(float(b.length) * 0.5 + 6.0, 0, float(b.width) * 0.5 + 4.0)
	var h := route.terrain.height_at(spot.x, spot.z)
	if is_nan(h):
		return
	var pole := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5) * Basis.from_scale(Vector3(1.0, YARD_LIGHT_HEIGHT, 1.0)),
		Vector3(spot.x, h - 0.2, spot.z))
	_append(by_kind["yard_light"], pole, Color.WHITE)


## A building's roof for the shader: its color (from the photos, or picked), and the
## eaves' share of the model's `height` (walls `below` ground included; 1 for a flat roof;
## plus 2 or 4 for a lean-to: see shaders/scenery.gdshader).
func _roof(b: Dictionary, kind: String, i: int, below: float, height: float) -> Color:
	if not EAVES.has(kind):
		return Color(1, 1, 1, 1)
	var color: Color
	if b.has("roof_color"):
		var c: Array = b.roof_color
		color = Color(pow(float(c[0]) / 255.0, PHOTO_GAMMA), pow(float(c[1]) / 255.0, PHOTO_GAMMA),
			pow(float(c[2]) / 255.0, PHOTO_GAMMA)) * PHOTO_GAIN
	else:
		var choices: Array[Color] = HOUSE_ROOFS if kind == "house" else BARN_ROOFS if kind == "barn" else SHED_ROOFS
		color = choices[int(_hash(i * 17 + 3) * choices.size()) % choices.size()]
	var top := float(b.height)
	var eave := float(b.get("eave", top * EAVES[kind]))
	var shape := str(b.get("roof", "gable"))
	if shape == "flat":
		eave = top
	eave = clampf(eave, minf(MIN_WALL_M, top), top)
	color.a = clampf((eave + below) / height, 0.05, 1.0)
	if shape == "lean":  # one slope, up to its high side (+z or -z)
		color.a += 2.0 if float(b.get("high", 1)) > 0.0 else 4.0
	return color


func _place_tree(by_kind: Dictionary, i: int) -> void:
	var k := i * 5
	var x := route.trees[k]
	var z := route.trees[k + 1]
	var ground := route.terrain.height_at(x, z)
	if is_nan(ground):
		return
	var height := route.trees[k + 2]
	var crown := route.trees[k + 3] * 2.0
	var kind := "conifer" if route.trees[k + 4] > 0.5 else "tree"
	var spin := _hash(i * 3 + 1) * TAU
	var xf := Transform3D(Basis(Vector3.UP, spin) * Basis.from_scale(Vector3(crown, height, crown)), Vector3(x, ground - 0.3, z))
	var shade := 0.85 + 0.3 * _hash(i * 7 + 2)
	_append(by_kind[kind], xf, Color(shade, shade * (0.95 + 0.1 * _hash(i * 11)), shade * 0.9), Color(1, 1, 1, 1))


## One multimesh per kind present in the block.
func _instantiate(block: Block) -> void:
	for kind: String in KINDS:
		var buffer: PackedFloat32Array = block.buffers.get(kind, PackedFloat32Array())
		if buffer.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _meshes["%s:%d" % [kind, maxi(block.lod, 0)]]
		mm.instance_count = buffer.size() / STRIDE
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


## MultiMesh buffer layout (3D transform + color + custom data): the basis rows with the
## origin at the end of each, then the instance color (the tint), then the custom data
## (a roof's color and the eaves' share of the height; see shaders/scenery.gdshader).
static func _append(buffer: PackedFloat32Array, xf: Transform3D, tint: Color, custom := Color(1, 1, 1, 1)) -> void:
	var b := xf.basis
	buffer.append_array([b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y,
		b.x.z, b.y.z, b.z.z, xf.origin.z, tint.r, tint.g, tint.b, 1.0, custom.r, custom.g, custom.b, custom.a])


## Instance `j`'s transform, from a block's buffer. (Not from the MultiMesh: that reads it
## back from the renderer, a GPU read in a browser, and a headless run has nothing there.)
static func _instance(buffer: PackedFloat32Array, j: int) -> Transform3D:
	var k := j * STRIDE
	return Transform3D(Vector3(buffer[k], buffer[k + 4], buffer[k + 8]), Vector3(buffer[k + 1], buffer[k + 5], buffer[k + 9]),
		Vector3(buffer[k + 2], buffer[k + 6], buffer[k + 10]), Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))


func _building_color(kind: String, i: int) -> Color:
	var h := _hash(i * 13 + 5)
	match kind:
		"house":
			return HOUSE_COLORS[int(h * HOUSE_COLORS.size()) % HOUSE_COLORS.size()]
		"barn":
			return BARN_COLORS[int(h * BARN_COLORS.size()) % BARN_COLORS.size()]
		"bin":
			return Color.WHITE
		"elevator":
			return ELEVATOR_COLORS[int(h * ELEVATOR_COLORS.size()) % ELEVATOR_COLORS.size()]
	return SHED_COLORS[int(h * SHED_COLORS.size()) % SHED_COLORS.size()]


## Solid near the car: a box per building (cylinder for a bin), a trunk per tree; only
## what's drawn. The shapes all go on before the body joins the physics space: with Jolt,
## each one added after rebuilds the whole body (seconds, for a wood of thousands of trees).
func _make_body(block: Block) -> void:
	if density <= 0.0:
		return
	block.body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(block.body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(block.body, 1 << (Car.WORLD_LAYER - 1))
	PhysicsServer3D.body_set_collision_mask(block.body, 0)
	PhysicsServer3D.body_set_state(block.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
	for kind: String in block.multimeshes:
		if kind == "yard_light":
			continue
		var mm: MultiMesh = block.multimeshes[kind].multimesh
		var shown := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		var buffer: PackedFloat32Array = block.buffers[kind]
		for j in shown:
			var xf := _instance(buffer, j)
			var shape: RID
			var at: Transform3D
			if kind == "tree" or kind == "conifer":
				shape = _trunk_shape
				at = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * TRUNK_HEIGHT / 2.0)
			else:
				var scale := xf.basis.get_scale()
				if kind == "bin":
					shape = PhysicsServer3D.cylinder_shape_create()
					PhysicsServer3D.shape_set_data(shape, {"radius": scale.x / 2.0, "height": scale.y})
					at = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * scale.y / 2.0)
				else:
					shape = PhysicsServer3D.box_shape_create()
					PhysicsServer3D.shape_set_data(shape, scale / 2.0)
					at = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * scale.y / 2.0)
				block.shapes.append(shape)
			PhysicsServer3D.body_add_shape(block.body, shape, at)
	PhysicsServer3D.body_set_space(block.body, get_world_3d().space)


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
		for kind: String in ["house", "barn", "shed", "bin", "elevator"]:
			if not block.multimeshes.has(kind):
				continue
			var buffer: PackedFloat32Array = block.buffers[kind]
			for j in buffer.size() / STRIDE:
				var xf := _instance(buffer, j)
				if Vector2(xf.origin.x - near.x, xf.origin.z - near.z).length() > radius:
					continue
				var scale := xf.basis.get_scale()
				out.append([Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3.UP * scale.y / 2.0), scale / 2.0])
	return out


static func _hash(n: int) -> float:
	var h := (n * 374761393) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / 16777216.0
