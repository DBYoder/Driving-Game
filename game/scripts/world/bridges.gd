class_name Bridges
extends Node3D
## The real bridges (RouteData.decks: a road crossing a dip at least 3 m up). Their decks
## are part of the road (RoadMesher builds a concrete deck with square edges in place of
## the grass foreslope); here: galvanized guardrails on posts along both edges, carrying
## on past each end, black-and-yellow end markers at the four corners, and where a named
## creek or river runs underneath (an open bridge, where the ground under it is the real
## ground) its water, along its real course (places.json "streams") for a way either
## side. The rails are solid: you bounce off them, you don't go in the river.

const RAIL_OFFSET := 6.9  ## m from the centerline to the rail's face
const RAIL_HEIGHT := 0.6  ## the middle of the W-beam above the road
const RAIL_TALL := 0.32
const RAIL_THICK := 0.09
const WALL_TOP := 0.95  ## the rail's collision reaches this high
const POST_EVERY := 1.9
const STEP := 2.0  ## m between the rail's mesh rows
const MARKER_OFFSET := 7.45  ## the end markers stand just outside the rail
const WATER_ABOVE_BED := 0.3  ## the water's surface over the creek bed (the map's lowest ground)
const WATER_CLEARANCE := 2.0  ## at least this far under the deck
const WATER_REACH := 320.0  ## m of the creek drawn each way from the bridge
const WATER_STEP := 6.0
const RIVER_WIDTH := 24.0  ## (a River)
const CREEK_WIDTH := 8.0
const STEEL := Color(0.66, 0.68, 0.70)
const POST := Color(0.52, 0.53, 0.55)
const WATER := Color(0.27, 0.31, 0.26)  ## muddy, like the English River
const ICE := Color(0.80, 0.84, 0.88)

var route: RouteData
var rail_runs := 0  ## both sides of each bridge (for tests)
var markers := 0
var waters: Array[MeshInstance3D] = []  ## the water under each open bridge with a named creek
var _water_material: StandardMaterial3D


func setup(r: RouteData) -> void:
	route = r
	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = WATER
	_water_material.roughness = 0.12
	_water_material.metallic_specular = 0.8
	_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var marker_material := _marker_material()
	# Each bridge its own meshes, so each fades out with its own distance.
	for b: Array in r.decks:
		var st := MeshKit.begin()
		for side: float in [-1.0, 1.0]:
			_rail(st, b, side)
		var rails := MeshInstance3D.new()
		rails.mesh = MeshKit.finish(st)
		(rails.mesh as ArrayMesh).surface_get_material(0).metallic = 0.5
		rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rails.visibility_range_end = 1500.0
		add_child(rails)
		var marker_st := SurfaceTool.new()
		marker_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_end_markers(marker_st, b)
		marker_st.generate_normals()
		var marker_mesh := MeshInstance3D.new()
		marker_mesh.mesh = marker_st.commit()
		marker_mesh.material_override = marker_material
		marker_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker_mesh.visibility_range_end = 900.0
		add_child(marker_mesh)
		if int(b[3]) == 1:
			_water(b)


## Frozen over in winter.
func set_look(snow: float) -> void:
	if _water_material:
		_water_material.albedo_color = ICE if snow > 0.5 else WATER
		_water_material.roughness = 0.35 if snow > 0.5 else 0.12


## Where deer cross the road near a bridge's creek: at a culvert, over it; at a real
## bridge, just short of the guardrails (they come up the bank, not over the rail).
static func deer_station(r: RouteData, b: Array) -> float:
	var mid := (float(b[0]) + float(b[1])) / 2.0
	if r.deck_at(mid).is_empty():
		return mid
	return float(b[0]) - RouteData.RAIL_APPROACH_M - 15.0


## The named creek or river under an open bridge, as its course for WATER_REACH m each
## way: {name, points (Vector3 on the water's surface)}, or {} if none runs under it.
static func water_course(r: RouteData, b: Array) -> Dictionary:
	var mid := r.position_at((float(b[0]) + float(b[1])) / 2.0)
	var best := {}
	var best_d := 80.0
	for stream: Dictionary in r.places.get("streams", []):
		var flat: Array = stream.points
		for i in flat.size() / 2:
			var d := Vector2(flat[i * 2] - mid.x, flat[i * 2 + 1] - mid.z).length()
			if d < best_d:
				best_d = d
				best = {"stream": stream, "at": i}
	if best.is_empty():
		return {}
	var flat: Array = best.stream.points
	var course: Array[Vector2] = []
	for i in flat.size() / 2:
		course.append(Vector2(flat[i * 2], flat[i * 2 + 1]))
	# Walk out each way from the point nearest the bridge, then resample evenly.
	var line: Array[Vector2] = [course[best.at]]
	for direction: int in [-1, 1]:
		var walked := 0.0
		var i: int = best.at
		var piece: Array[Vector2] = []
		while i + direction >= 0 and i + direction < course.size() and walked < WATER_REACH:
			walked += course[i].distance_to(course[i + direction])
			i += direction
			piece.append(course[i])
		if direction < 0:
			piece.reverse()
			line = piece + line
		else:
			line = line + piece
	var even := PackedVector2Array([line[0]])
	var carry := 0.0
	for k in line.size() - 1:
		var seg := line[k].distance_to(line[k + 1])
		if seg < 0.01:
			continue
		var t := WATER_STEP - carry
		while t <= seg:
			even.append(line[k].lerp(line[k + 1], t / seg))
			t += WATER_STEP
		carry = seg - (t - WATER_STEP)
	# The water's surface: just over the lowest ground near each point (the map's creek
	# bed), and well under the deck.
	var deck := mid.y - WATER_CLEARANCE
	var points: Array[Vector3] = []
	for p in even:
		var low := INF
		for o: Vector2 in [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			var h := r.terrain.height_at(p.x + o.x, p.y + o.y)
			if not is_nan(h):
				low = minf(low, h)
		if is_inf(low):
			continue
		points.append(Vector3(p.x, minf(low + WATER_ABOVE_BED, deck), p.y))
	if points.size() < 3:
		return {}
	return {"name": String(best.stream.name), "points": points}


## Height of the road's surface `offset` m from the centerline at `station`: the deck's
## edge on a bridge, the shoulder and foreslope elsewhere.
func _surface_y(station: float, offset: float) -> float:
	var y := route.position_at(station).y
	if not route.deck_at(station).is_empty():
		return y - 0.09
	return y + RoadMesher.surface_height(offset)


## One side's guardrail: a W-beam from RAIL_APPROACH_M before the deck to as far past
## it, on posts, its ends turned down into the ground; and a wall to bounce off.
func _rail(st: SurfaceTool, b: Array, side: float) -> void:
	rail_runs += 1
	var s0 := float(b[0]) - RouteData.RAIL_APPROACH_M
	var s1 := float(b[1]) + RouteData.RAIL_APPROACH_M
	var steel := STEEL
	var tops: Array[Vector3] = []  ## the rail's centerline, row by row
	var outs: Array[Vector3] = []  ## away from the road
	var s := s0
	while s <= s1 + 0.01:
		var right := route.right_at(s)
		var ease := clampf(minf(s - s0, s1 - s) / 4.0, 0.0, 1.0)  # the ends turn down and out
		var offset := RAIL_OFFSET + (1.0 - ease) * 0.6
		var base := route.position_at(s) + right * offset * side
		base.y = _surface_y(s, offset) + lerpf(0.15, RAIL_HEIGHT, ease)
		tops.append(base)
		outs.append(right * side)
		s += STEP
	for i in tops.size() - 1:
		var up := Vector3.UP * RAIL_TALL / 2.0
		var a := tops[i]
		var c := tops[i + 1]
		var ta := outs[i] * RAIL_THICK / 2.0
		var tc := outs[i + 1] * RAIL_THICK / 2.0
		MeshKit.quad(st, a - ta - up, c - tc - up, c - tc + up, a - ta + up, -outs[i], steel)  # the face
		MeshKit.quad(st, a + ta - up, c + tc - up, c + tc + up, a + ta + up, outs[i], steel)  # the back
		MeshKit.quad(st, a - ta + up, c - tc + up, c + tc + up, a + ta + up, Vector3.UP, steel)
	# Posts, just behind the rail.
	s = s0 + 1.0
	while s < s1 - 0.5:
		var right := route.right_at(s)
		var p := route.position_at(s) + right * (RAIL_OFFSET + 0.14) * side
		var ground := _surface_y(s, RAIL_OFFSET + 0.14)
		var top := ground + RAIL_HEIGHT + 0.12
		MeshKit.box(st, Vector3(0.15, top - ground + 0.4, 0.15), Vector3(p.x, (top + ground - 0.4) / 2.0, p.z), POST)
		s += POST_EVERY
	# The wall: from below the road to over the rail, both faces solid.
	var faces := PackedVector3Array()
	for i in tops.size() - 1:
		var a := tops[i]
		var c := tops[i + 1]
		var lo := Vector3.DOWN * (a.y - _surface_y(s0 + i * STEP, RAIL_OFFSET) + 0.4)
		var hi := Vector3.UP * (WALL_TOP - RAIL_HEIGHT)
		faces.append_array([a + lo, c + lo, c + hi, a + lo, c + hi, a + hi])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	body.collision_mask = 0
	body.set_meta("surface", "gravel")
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	add_child(body)


## Striped markers where each end of the deck starts, on both sides, facing the traffic
## coming onto the bridge.
func _end_markers(st: SurfaceTool, b: Array) -> void:
	for end: Array in [[float(b[0]) - 1.5, 1.0], [float(b[1]) + 1.5, -1.0]]:
		var s: float = end[0]
		var toward: Vector3 = -route.tangent_at(s) * end[1]  # back at the drivers coming on
		for side: float in [-1.0, 1.0]:
			markers += 1
			var right := route.right_at(s)
			var p := route.position_at(s) + right * MARKER_OFFSET * side
			var ground := _surface_y(s, MARKER_OFFSET)
			var across := toward.cross(Vector3.UP).normalized() * 0.16
			var face := p + toward * 0.03
			var lo := Vector3.UP * (ground + 0.75 - p.y)
			var hi := Vector3.UP * (ground + 1.85 - p.y)
			# The striped panel (UVs 0..1 across and up), then its post.
			var corners := [face - across + lo, face + across + lo, face + across + hi, face - across + hi]
			var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_uv(uv[k])
				st.add_vertex(corners[k])
			for k: int in [0, 1, 2, 0, 2, 3]:  # the back, plain
				st.set_uv(Vector2(0.02, 0.98))
				st.add_vertex(corners[k] - toward * 0.04)
			var post_lo := p - toward * 0.05 + Vector3.UP * (ground - 0.3 - p.y)
			var post_hi := p - toward * 0.05 + Vector3.UP * (ground + 1.8 - p.y)
			var w := across * 0.25
			for k: Array in [[post_lo - w, post_lo + w, post_hi + w, post_hi - w]]:
				for idx: int in [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3]:
					st.set_uv(Vector2(0.02, 0.98))
					st.add_vertex(k[idx])


## The creek's water: a ribbon along its course at its surface, but not where it runs
## under the road anywhere but this bridge (the road's on a fill there).
func _water(b: Array) -> void:
	var course := water_course(route, b)
	if course.is_empty():
		return
	var points: Array[Vector3] = course.points
	var half := (RIVER_WIDTH if String(course.name).ends_with("River") else CREEK_WIDTH) / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in points.size() - 1:
		var a := points[k]
		var c := points[k + 1]
		if _crosses_road(a, b) or _crosses_road(c, b):
			continue
		var along := Vector3(c.x - a.x, 0.0, c.z - a.z).normalized()
		var across := Vector3(-along.z, 0.0, along.x) * half
		# Clockwise seen from above (Godot's front faces).
		for v: Vector3 in [a - across, c - across, c + across, a - across, c + across, a + across]:
			st.add_vertex(v)
	var water := MeshInstance3D.new()
	water.mesh = st.commit()
	water.material_override = _water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.set_meta("creek", course.name)
	add_child(water)
	waters.append(water)


## Is this point of a creek under the road somewhere other than the open bridge `b`?
func _crosses_road(p: Vector3, b: Array) -> bool:
	var s := route.nearest_station(p, (float(b[0]) + float(b[1])) / 2.0, WATER_REACH + 200.0)
	var on_road := route.position_at(s)
	if Vector2(p.x - on_road.x, p.z - on_road.z).length() > 18.0:
		return false
	return s < float(b[0]) or s > float(b[1])


## Yellow and black diagonal stripes (an object marker); the bottom-left corner is
## plain gray, for the backs and posts.
func _marker_material() -> StandardMaterial3D:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var stripe := int(floor((x + y) / 6.4)) % 2 == 0
			image.set_pixel(x, y, Color(0.98, 0.78, 0.05) if stripe else Color(0.06, 0.06, 0.06))
	for y in range(size - 3, size):
		for x in 3:
			image.set_pixel(x, y, POST)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(image)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
