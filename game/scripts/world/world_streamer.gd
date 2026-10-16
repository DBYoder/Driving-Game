class_name WorldStreamer
extends Node3D
## Keeps the terrain tiles and road chunks near a focus point built, and frees far ones.
## Building is spread over frames (`builds_per_frame`) so driving doesn't hitch.

@export var load_radius := 1300.0
@export var unload_radius := 1600.0
@export var builds_per_frame := 2  # at 65 mph only ~1 new tile is needed per second

var route: RouteData
var focus := Vector3.ZERO

var _road: RoadMesher
var _terrain_material: ShaderMaterial
var _road_material: ShaderMaterial
var _tiles := {}  ## tile index -> MeshInstance3D
var _chunks := {}  ## road chunk index -> MeshInstance3D
var _queue: Array = []  ## [kind, index, distance] waiting to be built


func setup(r: RouteData) -> void:
	route = r
	_road = RoadMesher.new(r)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = preload("res://shaders/terrain.gdshader")
	_terrain_material.set_shader_parameter("field_offset", _field_grid_offset())
	_road_material = ShaderMaterial.new()
	_road_material.shader = preload("res://shaders/road.gdshader")


## Build everything around `pos` right now (used before the first frame is shown).
func warm_up(pos: Vector3) -> void:
	focus = pos
	_refresh_queue()
	while not _queue.is_empty():
		_build_next()


func loaded_tile_count() -> int:
	return _tiles.size()


func loaded_chunk_count() -> int:
	return _chunks.size()


func _process(_delta: float) -> void:
	if route == null:
		return
	if Engine.get_process_frames() % 10 == 0:
		_refresh_queue()
	for i in builds_per_frame:
		if _queue.is_empty():
			break
		_build_next()


func _refresh_queue() -> void:
	_queue.clear()
	var flat_focus := Vector3(focus.x, 0.0, focus.z)
	var terrain := route.terrain
	for i in terrain.count():
		var d := terrain.tile_center(i).distance_to(flat_focus)
		if d <= load_radius and not _tiles.has(i):
			_queue.append(["tile", i, d])
		elif d > unload_radius and _tiles.has(i):
			_tiles[i].queue_free()
			_tiles.erase(i)
	for c in _road.chunk_count():
		var center := _road.chunk_center(c)
		var d := Vector3(center.x, 0.0, center.z).distance_to(flat_focus)
		if d <= load_radius and not _chunks.has(c):
			_queue.append(["road", c, d - 1000.0])  # road first: it's what you look at
		elif d > unload_radius and _chunks.has(c):
			_chunks[c].queue_free()
			_chunks.erase(c)
	_queue.sort_custom(func(a, b): return a[2] < b[2])


func _build_next() -> void:
	var job: Array = _queue.pop_front()
	var node := MeshInstance3D.new()
	if job[0] == "tile":
		if _tiles.has(job[1]):
			return
		node.mesh = route.terrain.build_mesh(job[1])
		node.material_override = _terrain_material
		_tiles[job[1]] = node
	else:
		if _chunks.has(job[1]):
			return
		node.mesh = _road.build_chunk(job[1])
		node.material_override = _road_material
		_chunks[job[1]] = node
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Section-line roads run every mile on a north-south grid. Snapping the field patchwork
## to one east-west road and IA 1's north-south run makes field edges meet the real roads.
func _field_grid_offset() -> Vector2:
	var offset := Vector2.ZERO
	for c in route.crossroads:
		if c.name == "540th St SW":
			offset.y = route.position_at(c.station).z
			offset.x = route.position_at(c.station).x
	return offset
