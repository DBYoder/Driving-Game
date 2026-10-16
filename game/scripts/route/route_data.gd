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

	r.terrain = TerrainTiles.load_from(dir, d.terrain)
	if r.terrain == null:
		return null
	return r


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


## Miles driven from the Kalona start line.
func mile_at(station: float) -> float:
	return (station - start_station) / MILE_M


## The first named crossroad (not a ramp) ahead of `station`, or {} near the end.
func next_crossroad(station: float) -> Dictionary:
	for c in crossroads:
		if c.station > station and c.kind != "ramp":
			return c
	return {}
