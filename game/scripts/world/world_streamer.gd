class_name WorldStreamer
extends Node3D
## Keeps the world around a focus point built and frees what's far away: the detailed
## terrain tiles of the corridor, the road, and the coarse horizon ground under and
## beyond them. Pieces close to the focus also get collision, built from the same
## triangles that are drawn, so what the tires touch is exactly what you see. Building
## is spread over frames (`builds_per_frame`) so driving doesn't hitch.
##
## Each kind of piece appears far enough out that the haze hides it arriving: the
## horizon past where the fog is total, the road deep in the haze, and the detailed
## tiles where they only replace slightly lower coarse ground. Far-off tiles and road
## use lighter meshes. Distances are to the nearest point of a piece.

## Load and unload distances (m) per kind of piece.
const RADII := {
	"tile": [1250.0, 1550.0],
	"road": [2700.0, 3000.0],
	"far": [3600.0, 4000.0],
}
const COLLISION_RADII := [250.0, 400.0]
## Past these distances tiles and road use their far-away meshes (lod 1), and switch
## back LOD_HYSTERESIS closer than that, so pieces don't flip back and forth.
const FAR_LOD := {"tile": 600.0, "road": 700.0}
const LOD_HYSTERESIS := 50.0
const ROAD_FAR_STEP := 4  ## route samples per row in far-off road
const TILE_HALF_DIAGONAL := 181.0
const ROAD_HALF_LENGTH := 128.0

@export var builds_per_frame := 2  # at 110 mph about 3 new pieces are needed per second

var route: RouteData
var focus := Vector3.ZERO
## The closest each kind of piece has been to the focus when it appeared, after the
## initial build: how close to the camera things pop in (checked by the QA drive).
var nearest_pop_in := {"tile": INF, "road": INF, "far": INF}

var _road: RoadMesher
var _terrain_material: ShaderMaterial
var _road_material: ShaderMaterial
var _meshes := {}  ## "tile:12" / "road:3" / "far:40" -> MeshInstance3D
var _bodies := {}  ## "tile:12" / "road:3" -> StaticBody3D
var _queue: Array = []  ## [key, priority, lod], most urgent first
var _warming_up := false


func setup(r: RouteData) -> void:
	route = r
	_road = RoadMesher.new(r)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = preload("res://shaders/terrain.gdshader")
	_terrain_material.set_shader_parameter("field_offset", Fields.new(r).offset)
	_road_material = ShaderMaterial.new()
	_road_material.shader = preload("res://shaders/road.gdshader")


## Build everything around `pos` right now (before the first frame, or after a teleport).
func warm_up(pos: Vector3) -> void:
	focus = pos
	_warming_up = true
	_refresh_queue()
	while not _queue.is_empty():
		_build_next()
	_warming_up = false


func loaded_count(kind: String) -> int:
	return _meshes.keys().filter(func(k): return k.begins_with(kind + ":")).size()


func loaded_tile_count() -> int:
	return loaded_count("tile")


func loaded_chunk_count() -> int:
	return loaded_count("road")


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


## Distance from the focus to the nearest point of a piece (roughly).
func _distance(kind: String, index: int) -> float:
	var flat_focus := Vector3(focus.x, 0.0, focus.z)
	match kind:
		"tile":
			return maxf(route.terrain.tile_center(index).distance_to(flat_focus) - TILE_HALF_DIAGONAL, 0.0)
		"road":
			var c := _road.chunk_center(index)
			return maxf(Vector3(c.x, 0.0, c.z).distance_to(flat_focus) - ROAD_HALF_LENGTH, 0.0)
		_:
			var half := route.horizon.chunk_size() * sqrt(0.5)
			return maxf(route.horizon.chunk_center(index).distance_to(flat_focus) - half, 0.0)


func _refresh_queue() -> void:
	_queue.clear()
	for i in route.terrain.count():
		_consider("tile", i)
	for c in _road.chunk_count():
		_consider("road", c)
	for c in route.horizon.chunk_count():
		_consider("far", c)
	_queue.sort_custom(func(a, b): return a[1] < b[1])


func _consider(kind: String, index: int) -> void:
	var key := "%s:%d" % [kind, index]
	var d := _distance(kind, index)
	var radii: Array = RADII[kind]
	var load_at: float = radii[0]
	var unload_at: float = radii[1]
	var body_at: float = COLLISION_RADII[0]
	var body_unload_at: float = COLLISION_RADII[1]
	if d > unload_at and _meshes.has(key):
		_meshes[key].queue_free()
		_meshes.erase(key)
	if d > body_unload_at and _bodies.has(key):
		_bodies[key].queue_free()
		_bodies.erase(key)
	var lod := _wanted_lod(kind, key, d)
	var needs_mesh: bool = d <= load_at and (not _meshes.has(key) or _meshes[key].get_meta("lod") != lod)
	var needs_body := kind != "far" and d <= body_at and not _bodies.has(key)
	if needs_mesh or needs_body:
		# Collision first (the car falls through without it), then the nearest scenery.
		_queue.append([key, d - 5000.0 if needs_body else d, lod])


func _wanted_lod(kind: String, key: String, d: float) -> int:
	if not FAR_LOD.has(kind):
		return 0
	var switch_at: float = FAR_LOD[kind]
	if _meshes.has(key):
		switch_at += -LOD_HYSTERESIS if _meshes[key].get_meta("lod") == 1 else LOD_HYSTERESIS
	return 1 if d > switch_at else 0


func _build_next() -> void:
	var job: Array = _queue.pop_front()
	var key: String = job[0]
	var parts := key.split(":")
	var kind := parts[0]
	var index := int(parts[1])
	var lod: int = job[2]
	var d := _distance(kind, index)
	if not _meshes.has(key) or _meshes[key].get_meta("lod") != lod:
		var mesh: ArrayMesh
		match kind:
			"road":
				mesh = _road.build_chunk(index, ROAD_FAR_STEP if lod == 1 else 1)
			"tile":
				mesh = route.terrain.build_mesh(index, lod)
			_:
				mesh = route.horizon.build_mesh(index)
		if _meshes.has(key):
			_meshes[key].mesh = mesh
		else:
			var node := MeshInstance3D.new()
			node.material_override = _road_material if kind == "road" else _terrain_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.mesh = mesh
			add_child(node)
			_meshes[key] = node
			if not _warming_up:
				nearest_pop_in[kind] = minf(nearest_pop_in[kind], d)
		_meshes[key].set_meta("lod", lod)
	if kind != "far" and d <= COLLISION_RADII[0] and not _bodies.has(key):
		var body := StaticBody3D.new()
		body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
		body.collision_mask = 0
		body.set_meta("surface", "road" if kind == "road" else "grass")
		var shape := CollisionShape3D.new()
		shape.shape = _meshes[key].mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
		_bodies[key] = body
