class_name RouteData
extends RefCounted
## A baked route (see tools/bake_route.py): a centerline sampled every `spacing` meters,
## plus the crossroads, bridges and terrain along it. Each route has its own folder,
## data/routes/<id>/ (Routes lists them).
##
## Distances along the road are "stations" in meters from the first sample.
## World axes: x = east, y = up, z = south (so driving north is -z).

const MILE_M := 1609.344
const RAILED_BRIDGE_M := 3.0  ## a bridge standing this high has a deck and guardrails (tools/config.py)
const RAIL_APPROACH_M := 25.0  ## the guardrails run on this far past each end of the deck
const LANE := 1.83  ## the middle of a lane, off the centerline, on a two-lane road
const JUNCTION_CLEAR := 3.0  ## nothing roadside stands this close to the 4-way's pavement

var id := Routes.DEFAULT  ## the route's folder name (one of Routes.IDS)
var info: Dictionary  ## what the game knows about it besides the data (Routes.INFO)
var title: String
var spacing: float
var length: float
var start_station: float
var finish_station: float
var points := PackedVector3Array()
var crossroads: Array = []  ## Dictionaries: station, name, route, kind, side
## Where the road crosses a dip on a fill: [from, to, height, open]. `height` is the deck
## over the ground at the deepest; from RAILED_BRIDGE_M up it's a real bridge (decks),
## lower a culvert. `open` (1): a creek runs under it and the ground there is the real
## ground; 0: a road does (US 218 under IA 1), and the fill's left in.
var bridges: Array = []
var decks: Array = []  ## the real bridges (bridges at least RAILED_BRIDGE_M up)
var terrain: TerrainTiles
var horizon: HorizonTerrain
## Real buildings from the lidar (tools/bake_lidar.py): Dictionaries with x, z, length,
## width, yaw, height, kind ("house", "barn", "shed", "bin"). Empty if not baked.
var buildings: Array = []
## Real trees from the lidar: 5 floats each (x, z, height, crown radius, conifer 0/1).
var trees := PackedFloat32Array()
## Named creeks, city limits and the county line (tools/bake_places.py).
var places := {"creeks": [], "cities": [], "counties": []}
## Side roads and town streets (tools/bake_streets.py): Dictionaries with name, kind
## ("paved", "gravel", "lane"), half_width, joins ([start, end] meet the highway) and points
## (PackedFloat32Array, 5 per point: x, left edge y, middle y, right edge y, z).
var streets: Array = []
## Hand-built landmarks (the route's landmarks.json, built by Landmarks): Dictionaries with
## id, name, x, z and the `clear` rectangles their own buildings fill.
var landmarks: Array = []
## Their `clear` rectangles, each [center: Vector2, half extents: Vector2, yaw]: written
## [x0, z0, x1, z1] square to the compass, or [x, z, half_x, half_z, yaw] turned with the
## building (yaw like rotation.y).
var landmark_boxes: Array = []
## The Kalona 4-way stop where both runs start, laid out like the real one (the route's
## junction.json, from tools/junction.py; Junction builds it). Its pavement replaces the
## road between junction_gap's stations. Empty if not baked.
var junction := {}
var junction_gap := Vector2(-1.0, -1.0)
var _junction_outline := PackedVector2Array()  ## the edge of its pavement
var _junction_near := PackedVector2Array()  ## ...and JUNCTION_CLEAR m out from it
var _junction_box := Rect2()  ## round the second
var _no_pass_north := PackedByteArray()  ## per sample: 1 = solid line for northbound
var _no_pass_south := PackedByteArray()


static func load_from(dir: String) -> RouteData:
	var text := FileAccess.get_file_as_string(dir.path_join("route.json"))
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("could not read %s/route.json" % dir)
		return null

	var r := RouteData.new()
	r.id = dir.trim_suffix("/").get_file()
	r.info = Routes.info(r.id)
	r.title = d.name
	r.spacing = d.spacing_m
	r.start_station = d.start_station
	r.finish_station = d.finish_station
	r.crossroads = d.crossroads
	r.bridges = d.bridges
	r.decks = r.bridges.filter(func(b: Array) -> bool: return b.size() >= 4 and float(b[2]) >= RAILED_BRIDGE_M)

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
	var streets = _optional_json(dir.path_join("streets.json"))
	if typeof(streets) == TYPE_DICTIONARY:
		for st: Dictionary in streets.streets:
			st.points = PackedFloat32Array(st.points)
			r.streets.append(st)
	var landmarks = _optional_json(dir.path_join("landmarks.json"))
	if typeof(landmarks) == TYPE_DICTIONARY:
		r.landmarks = landmarks.landmarks
		for l: Dictionary in r.landmarks:
			for c: Array in l.clear:
				if c.size() == 5:
					r.landmark_boxes.append([Vector2(c[0], c[1]), Vector2(c[2], c[3]), float(c[4])])
				else:
					r.landmark_boxes.append([Vector2(c[0] + c[2], c[1] + c[3]) / 2.0, Vector2(c[2] - c[0], c[3] - c[1]) / 2.0, 0.0])
		r._clear_for_landmarks()
	var junction = _optional_json(dir.path_join("junction.json"))
	if typeof(junction) == TYPE_DICTIONARY:
		r._set_junction(junction)
	return r


func _set_junction(j: Dictionary) -> void:
	junction = j
	junction_gap = Vector2(j.gap[0], j.gap[1])
	var flat: Array = j.outline
	for i in flat.size() / 2:
		_junction_outline.append(Vector2(flat[i * 2], flat[i * 2 + 1]))
	var grown := Geometry2D.offset_polygon(_junction_outline, JUNCTION_CLEAR)
	_junction_near = grown[0] if not grown.is_empty() else _junction_outline
	_junction_box = Rect2(_junction_near[0], Vector2.ZERO)
	for v in _junction_near:
		_junction_box = _junction_box.expand(v)
	# The ground under its pavement, pulled down so it can't poke through.
	var per_tile := terrain.grid * terrain.grid
	for c: Array in j.terrain:
		terrain.heights[int(c[0]) * per_tile + int(c[1])] = float(c[2])
	# The lidar's buildings and trees out on it (a light pole or a tree in a turning lane).
	buildings = buildings.filter(func(b: Dictionary): return not near_junction(b.x, b.z))
	var kept := PackedFloat32Array()
	for i in trees.size() / 5:
		if not near_junction(trees[i * 5], trees[i * 5 + 1]):
			kept.append_array(trees.slice(i * 5, i * 5 + 5))
	trees = kept


## Is (x, z) on the 4-way's pavement?
func on_junction(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	return _junction_box.has_point(p) and Geometry2D.is_point_in_polygon(p, _junction_outline)


## Is (x, z) on the 4-way's pavement or within JUNCTION_CLEAR m of it?
func near_junction(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	return _junction_box.has_point(p) and Geometry2D.is_point_in_polygon(p, _junction_near)


## Is the road at `station` the 4-way's (left out of the road mesh)?
func in_junction(station: float) -> bool:
	return station > junction_gap.x and station < junction_gap.y


## The middle of the right-hand lane at a station, off the centerline: LANE, but through
## the 4-way IA 1's lanes shift out for its left-turn lanes.
func lane_offset(station: float) -> float:
	if not in_junction(station):
		return LANE
	var lanes: Array = junction.lanes
	var f := clampf((station - junction_gap.x) / float(junction.lane_step), 0.0, lanes.size() - 1.0)
	var i := mini(int(f), lanes.size() - 2)
	return lerpf(float(lanes[i]), float(lanes[i + 1]), f - i)


## The real bridge whose deck `station` is on (with `margin` m more at each end), or [].
func deck_at(station: float, margin := 0.0) -> Array:
	for b: Array in decks:
		if station >= float(b[0]) - margin and station <= float(b[1]) + margin:
			return b
	return []


## Is (x, z) where a landmark stands (inside one of its `clear` rectangles)?
func in_landmark(x: float, z: float) -> bool:
	for box: Array in landmark_boxes:
		var d := Vector2(x, z) - (box[0] as Vector2)
		var yaw: float = box[2]
		var half: Vector2 = box[1]
		# The box's own axes: x turned by yaw is (cos, -sin), z is (sin, cos).
		if absf(d.dot(Vector2(cos(yaw), -sin(yaw)))) <= half.x and absf(d.dot(Vector2(sin(yaw), cos(yaw)))) <= half.y:
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
