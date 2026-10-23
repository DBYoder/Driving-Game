class_name Roadside
extends Node3D
## Street-name signs at the real crossroads and green mile markers (the start and finish
## intersections have their own: Intersections). From the map data (tools/bake_places.py): the names of the creeks at their
## bridges, the county line and the city limits with their populations. And the usual:
## 55 mph once out of Kalona, route markers (NORTH over IOWA 1, WEST over IOWA 22).

const SIGN_GREEN := Color(0.05, 0.40, 0.18)
const POST_GRAY := Color(0.55, 0.55, 0.57)
const SIGN_RANGE := 1100.0  ## signs further than this are a pixel or two in the haze: not drawn
const WHITE := Color(0.95, 0.95, 0.93)
const BLACK := Color(0.08, 0.08, 0.08)
const SPEED_LIMIT_EVERY := 4.0 * RouteData.MILE_M  ## a 55 sign about this often...
const CLEAR_OF_CROSSROADS := 120.0  ## ...but not crowding a crossroad's own signs

var route: RouteData


func setup(r: RouteData) -> void:
	route = r
	var green := _material(SIGN_GREEN)
	var gray := _material(POST_GRAY)

	for c in route.crossroads:
		if c.kind == "ramp" or Intersections.at_line(route, c):
			continue
		var text: String = c.name
		if c.route != "":
			text = "%s\n%s" % [c.route, c.name]
		_add_sign(c.station - 12.0, 8.5, text, green, gray)

	var mile := 1
	while route.start_station + mile * RouteData.MILE_M < route.finish_station:
		_add_marker(route.start_station + mile * RouteData.MILE_M, mile, green, gray)
		mile += 1


	var white := _material(WHITE)
	for c: Dictionary in route.places.creeks:
		_add_sign(_bridge_start(c.station) - 20.0, 7.6, String(c.name).to_upper(), green, gray)
	for c: Dictionary in route.places.counties:
		_add_sign(c.station, 8.5, "%s\nCOUNTY" % String(c.entering).to_upper(), green, gray)
	var leave_town := route.start_station
	for c: Dictionary in route.places.cities:
		if c.entering:
			_add_sign(c.station, 8.5, "%s\nPOP %s" % [String(c.name).to_upper(), _thousands(int(c.population))], green, gray)
		elif c.station > route.start_station and c.station < route.start_station + RouteData.MILE_M:
			leave_town = c.station
	var s := leave_town + 150.0
	while s < route.finish_station - RouteData.MILE_M:
		s = _clear_spot(s)
		_add_plate(s, 7.6, "SPEED\nLIMIT\n55", Vector2(0.75, 0.95), white, BLACK, gray)
		_add_route_marker(_clear_spot(s + 400.0), white, gray)
		s += SPEED_LIMIT_EVERY


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


## A sign standing on the right shoulder, facing us.
func _add_sign(station: float, offset: float, text: String, face: Material, post: Material) -> void:
	var holder := _place(station, offset)
	var lines := text.count("\n") + 1
	var width := clampf(text.length() * 0.09 / lines + 0.6, 1.2, 3.2)
	_box(holder, Vector3(0.08, 2.6, 0.08), Vector3(0, 1.3, 0), post)
	_box(holder, Vector3(width, 0.38 * lines, 0.04), Vector3(0, 2.5, 0), face)
	var label := _label(text, 40)
	label.position = Vector3(0, 2.5, 0.03)
	label.visibility_range_end = SIGN_RANGE
	holder.add_child(label)


## A regulatory-style sign: `face` colored, dark text, a set size.
func _add_plate(station: float, offset: float, text: String, size: Vector2, face: Material,
		text_color: Color, post: Material) -> void:
	var holder := _place(station, offset)
	_box(holder, Vector3(0.08, 2.4, 0.08), Vector3(0, 1.2, 0), post)
	_box(holder, Vector3(size.x, size.y, 0.04), Vector3(0, 2.1, 0), face)
	_box(holder, Vector3(size.x - 0.06, size.y - 0.06, 0.042), Vector3(0, 2.1, 0), _material(text_color))
	_box(holder, Vector3(size.x - 0.1, size.y - 0.1, 0.044), Vector3(0, 2.1, 0), face)
	var label := _label(text, 44)
	label.modulate = text_color
	label.position = Vector3(0, 2.1, 0.03)
	label.visibility_range_end = SIGN_RANGE
	holder.add_child(label)


## Iowa's route marker (IOWA over the route's number in a black-rimmed white square) under
## its direction (NORTH, WEST).
func _add_route_marker(station: float, white: Material, post: Material) -> void:
	var holder := _place(station, 7.6)
	var black := _material(BLACK)
	_box(holder, Vector3(0.08, 2.9, 0.08), Vector3(0, 1.45, 0), post)
	_box(holder, Vector3(0.62, 0.62, 0.04), Vector3(0, 2.3, 0), black)
	_box(holder, Vector3(0.56, 0.56, 0.042), Vector3(0, 2.3, 0), white)
	_box(holder, Vector3(0.62, 0.24, 0.04), Vector3(0, 2.78, 0), white)
	var number: String = route.info.number
	var rows := [[route.info.heading, 26, 2.78], ["IOWA", 22, 2.47], [number, 80 if number.length() < 2 else 64, 2.24]]
	for row: Array in rows:
		var label := _label(row[0], row[1])
		label.modulate = BLACK
		label.position = Vector3(0, row[2], 0.03)
		label.visibility_range_end = SIGN_RANGE
		holder.add_child(label)


## Where a creek's bridge starts (the bridge nearest the crossing), or the crossing.
func _bridge_start(station: float) -> float:
	for b: Array in route.bridges:
		if station > float(b[0]) - 60.0 and station < float(b[1]) + 60.0:
			return float(b[0])
	return station


## The first station from `s` on that isn't crowding a crossroad's signs.
func _clear_spot(s: float) -> float:
	for c in route.crossroads:
		if absf(float(c.station) - s) < CLEAR_OF_CROSSROADS:
			s = float(c.station) + CLEAR_OF_CROSSROADS
	return s


static func _thousands(n: int) -> String:
	var digits := str(n)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _add_marker(station: float, mile: int, face: Material, post: Material) -> void:
	var holder := _place(station, 7.6)
	_box(holder, Vector3(0.06, 1.3, 0.06), Vector3(0, 0.65, 0), post)
	_box(holder, Vector3(0.45, 0.6, 0.03), Vector3(0, 1.3, 0), face)
	var label := _label(str(mile), 56)
	label.position = Vector3(0, 1.3, 0.02)
	label.visibility_range_end = SIGN_RANGE
	holder.add_child(label)


func _place(station: float, offset: float) -> Node3D:
	var deck := route.deck_at(station)
	if not deck.is_empty():  # not out over the river: past the bridge
		station = float(deck[1]) + RouteData.RAIL_APPROACH_M + 10.0
	var holder := Node3D.new()
	add_child(holder)
	var pos := route.position_at(station) + route.right_at(station) * offset
	pos.y = route.position_at(station).y - 0.1
	holder.position = pos
	# Face the approaching (northbound) driver: +Z of the holder points back down the road.
	holder.basis = Basis.looking_at(route.tangent_at(station), Vector3.UP)
	return holder


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = SIGN_RANGE
	parent.add_child(node)


func _label(text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.005
	label.outline_size = 0
	label.modulate = Color.WHITE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.double_sided = false
	return label
