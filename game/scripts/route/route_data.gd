class_name RouteData
extends RefCounted
## The baked road (see tools/bake_route.py): a centerline sampled every `spacing` meters,
## plus the crossroads, bridges and terrain along it.
##
## Distances along the road are "stations" in meters from the first sample.
## World axes: x = east, y = up, z = south (so driving north is -z).

const MILE_M := 1609.344

var title: String
var spacing: float
var length: float
var start_station: float
var finish_station: float
var points := PackedVector3Array()
var crossroads: Array = []  ## Dictionaries: station, name, route, kind, side
var bridges: Array = []  ## [from_station, to_station] pairs
var terrain: TerrainTiles
var horizon: HorizonTerrain
## Real buildings from the lidar (tools/bake_lidar.py): Dictionaries with x, z, length,
## width, yaw, height, kind ("house", "barn", "shed", "bin"). Empty if not baked.
var buildings: Array = []
## Real trees from the lidar: 5 floats each (x, z, height, crown radius, conifer 0/1).
var trees := PackedFloat32Array()
## Named creeks, city limits and the county line (tools/bake_places.py).
var places := {"creeks": [], "cities": [], "counties": []}
## Hand-built landmarks (data/route/landmarks.json, built by Landmarks): Dictionaries with
## id, name, x, z and the `clear` rectangles their own buildings fill.
var landmarks: Array = []
var _no_pass_north := PackedByteArray()  ## per sample: 1 = solid line for northbound
var _no_pass_south := PackedByteArray()


static func load_from(dir: String) -> RouteData:
	var text := FileAccess.get_file_as_string(dir.path_join("route.json"))
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("could not read %s/route.json" % dir)
		return null

	var r := RouteData.new()
	r.title = d.name
	r.spacing = d.spacing_m
	r.start_station = d.start_station
	r.finish_station = d.finish_station
	r.crossroads = d.crossroads
	r.bridges = d.bridges

	var flat: Array = d.points
	r.points.resize(flat.size() / 3)
	for i in r.points.size():
		r.points[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
	r.length = (r.points.size() - 1) * r.spacing

	r._no_pass_north = r._flags(d.no_passing.northbound)
	r._no_pass_south = r._flags(d.no_passing.southbound)
	r.terrain = TerrainTiles.load_from(dir, d.terrain)
	r.horizon = HorizonTerrain.load_from(dir, d.horizon)
	if r.terrain == null or r.horizon == null:
		return null
	var structures = _optional_json(dir.path_join("structures.json"))
	if typeof(structures) == TYPE_DICTIONARY:
		r.buildings = structures.buildings
	if FileAccess.file_exists(dir.path_join("trees.bin")):
		r.trees = FileAccess.get_file_as_bytes(dir.path_join("trees.bin")).to_float32_array()
	var places = _optional_json(dir.path_join("places.json"))
	if typeof(places) == TYPE_DICTIONARY:
		r.places = places
	var landmarks = _optional_json(dir.path_join("landmarks.json"))
	if typeof(landmarks) == TYPE_DICTIONARY:
		r.landmarks = landmarks.landmarks
		r._clear_for_landmarks()
	return r


## Is (x, z) where a landmark stands (inside one of its `clear` rectangles)?
func in_landmark(x: float, z: float) -> bool:
	for l: Dictionary in landmarks:
		for c: Array in l.clear:
			if x >= c[0] and x <= c[2] and z >= c[1] and z <= c[3]:
				return true
	return false


## Leave out the lidar's buildings and trees where a landmark stands: its own model
## replaces them.
func _clear_for_landmarks() -> void:
	buildings = buildings.filter(func(b: Dictionary): return not in_landmark(b.x, b.z))
	var kept := PackedFloat32Array()
	for i in trees.size() / 5:
		if not in_landmark(trees[i * 5], trees[i * 5 + 1]):
			kept.append_array(trees.slice(i * 5, i * 5 + 5))
	trees = kept


## A data file that may not have been baked: its parsed JSON, or null.
static func _optional_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func position_at(station: float) -> Vector3:
	var f := clampf(station / spacing, 0.0, points.size() - 1.0)
	var i := mini(int(f), points.size() - 2)
	return points[i].lerp(points[i + 1], f - i)


## Unit direction of travel (northbound) at a station.
func tangent_at(station: float) -> Vector3:
	return (position_at(station + spacing) - position_at(station - spacing)).normalized()


## Unit vector pointing to the driver's right, kept level.
func right_at(station: float) -> Vector3:
	var t := tangent_at(station)
	return Vector3(-t.z, 0.0, t.x).normalized()


## Station of the centerline point closest to `pos` (ignoring height).
## With a hint, only searches `window` meters either side of it.
func nearest_station(pos: Vector3, hint := -1.0, window := 250.0) -> float:
	var i0 := 0
	var i1 := points.size() - 1
	if hint >= 0.0:
		i0 = clampi(int((hint - window) / spacing), 0, points.size() - 1)
		i1 = clampi(int((hint + window) / spacing), 0, points.size() - 1)
	var best := i0
	var best_d := INF
	for i in range(i0, i1 + 1):
		var p := points[i]
		var d := (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
		if d < best_d:
			best_d = d
			best = i
	return best * spacing


## True where the center line is solid for traffic going `direction` (+1 north, -1 south):
## not enough sight distance to pass, or in town.
func no_passing(station: float, direction: float) -> bool:
	var i := clampi(roundi(station / spacing), 0, points.size() - 1)
	return (_no_pass_north if direction > 0.0 else _no_pass_south)[i] == 1


func _flags(zones: Array) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(points.size())
	for z in zones:
		for i in range(clampi(ceili(z[0] / spacing), 0, points.size()), clampi(floori(z[1] / spacing) + 1, 0, points.size())):
			flags[i] = 1
	return flags


## Miles driven from the Kalona start line.
func mile_at(station: float) -> float:
	return (station - start_station) / MILE_M


## The first named crossroad (not a ramp) ahead of `station`, or {} near the end.
func next_crossroad(station: float) -> Dictionary:
	for c in crossroads:
		if c.station > station and c.kind != "ramp":
			return c
	return {}
