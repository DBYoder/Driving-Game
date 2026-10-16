class_name WorldStreamer
extends Node3D
## Keeps terrain tiles and road chunks near a focus point built and frees far ones.
## Pieces close to the focus also get collision, built from the same triangles that are
## drawn, so what the tires touch is exactly what you see. Building is spread over
## frames (`builds_per_frame`) so driving doesn't hitch.

@export var load_radius := 1300.0
@export var unload_radius := 1600.0
@export var collision_radius := 350.0
@export var collision_unload_radius := 500.0
@export var builds_per_frame := 2  # at 65 mph only ~1 new tile is needed per second

var route: RouteData
var focus := Vector3.ZERO

var _road: RoadMesher
var _terrain_material: ShaderMaterial
var _road_material: ShaderMaterial
var _meshes := {}  ## "tile:12" / "road:3" -> MeshInstance3D
var _bodies := {}  ## same keys -> StaticBody3D
var _queue: Array = []  ## [key, priority, distance], most urgent first


func setup(r: RouteData) -> void:
	route = r
	_road = RoadMesher.new(r)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = preload("res://shaders/terrain.gdshader")
	_terrain_material.set_shader_parameter("field_offset", _field_grid_offset())
	_road_material = ShaderMaterial.new()
	_road_material.shader = preload("res://shaders/road.gdshader")


## Build everything around `pos` right now (before the first frame, or after a teleport).
func warm_up(pos: Vector3) -> void:
	focus = pos
	_refresh_queue()
	while not _queue.is_empty():
		_build_next()


func loaded_tile_count() -> int:
	return _meshes.keys().filter(func(k): return k.begins_with("tile")).size()


func loaded_chunk_count() -> int:
	return _meshes.keys().filter(func(k): return k.begins_with("road")).size()


func collider_count() -> int:
	return _bodies.size()


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
	for i in route.terrain.count():
		_consider("tile:%d" % i, route.terrain.tile_center(i).distance_to(flat_focus))
	for c in _road.chunk_count():
		var center := _road.chunk_center(c)
		# Road chunks are long and thin; measure to the nearer of their two ends too.
		var d := Vector3(center.x, 0.0, center.z).distance_to(flat_focus)
		_consider("road:%d" % c, maxf(d - 128.0, 0.0))
	_queue.sort_custom(func(a, b): return a[1] < b[1])


func _consider(key: String, d: float) -> void:
	if d > unload_radius and _meshes.has(key):
		_meshes[key].queue_free()
		_meshes.erase(key)
	if d > collision_unload_radius and _bodies.has(key):
		_bodies[key].queue_free()
		_bodies.erase(key)
	var needs_mesh := d <= load_radius and not _meshes.has(key)
	var needs_body := d <= collision_radius and not _bodies.has(key)
	if needs_mesh or needs_body:
		# Collision first (the car falls through without it), then road, then scenery.
		var priority := d - 5000.0 if needs_body else (d - 1000.0 if key.begins_with("road") else d)
		_queue.append([key, priority, d])


func _build_next() -> void:
	var job: Array = _queue.pop_front()
	var key: String = job[0]
	var parts := key.split(":")
	var index := int(parts[1])
	var is_road := parts[0] == "road"
	if not _meshes.has(key):
		var node := MeshInstance3D.new()
		node.mesh = _road.build_chunk(index) if is_road else route.terrain.build_mesh(index)
		node.material_override = _road_material if is_road else _terrain_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_meshes[key] = node
	if job[2] <= collision_radius and not _bodies.has(key):
		var body := StaticBody3D.new()
		body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
		body.collision_mask = 0
		body.set_meta("surface", "road" if is_road else "grass")
		var shape := CollisionShape3D.new()
		shape.shape = _meshes[key].mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
		_bodies[key] = body


## Section-line roads run every mile on a north-south grid. Snapping the field patchwork
## to one east-west road and IA 1's north-south run makes field edges meet the real roads.
func _field_grid_offset() -> Vector2:
	var offset := Vector2.ZERO
	for c in route.crossroads:
		if c.name == "540th St SW":
			offset.y = route.position_at(c.station).z
			offset.x = route.position_at(c.station).x
	return offset
