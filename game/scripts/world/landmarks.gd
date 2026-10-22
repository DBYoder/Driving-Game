class_name Landmarks
extends Node3D
## The places you'd point at from the passenger seat, built by hand at their real spots
## (data/route/landmarks.json). RouteData leaves out the lidar's own buildings and trees
## where each one stands.
##
## Kalona Cheese, at the corner of 540th St 3.9 miles up from Kalona (the Kalona Creamery
## since 2017): the red brick store right by the road, a story and a half under a steep
## gray roof with KALONA CHEESE across its gable, wrapped in a one-story front with a gray
## shingled mansard and the black KALONA CREAMERY sign over the doors. Behind it, the
## cheese plant: a concrete-block and brick wing, the old plant under its tan roof, the
## brick smokestack, steel silos and the big metal plant buildings. Sizes and heights
## are off the 2019 lidar; the look is off a photo.
##
## Drawn with the scenery's shader, so the roofs take the snow and the windows light up
## at night. Solid, like the rest of the buildings.

# Vertex alpha says what a face is (see scenery.gdshader): 0 plain, 1/3 window, 2/3 lamp.
const BRICK := Color(0.62, 0.25, 0.18, 0.0)
const BRICK_DARK := Color(0.42, 0.17, 0.13, 0.0)
const SHINGLE := Color(0.40, 0.41, 0.43, 0.0)
const TAN_ROOF := Color(0.64, 0.50, 0.34, 0.0)
const FLAT_ROOF := Color(0.30, 0.30, 0.31, 0.0)
const BLOCK := Color(0.66, 0.66, 0.64, 0.0)
const METAL := Color(0.82, 0.83, 0.84, 0.0)
const STEEL := Color(0.88, 0.89, 0.90, 0.0)
const DOOR := Color(0.36, 0.37, 0.38, 0.0)  ## roll-up doors
const SIGN_BLACK := Color(0.05, 0.05, 0.05, 0.0)
const SILL := Color(0.86, 0.85, 0.80, 0.0)
const CONCRETE := Color(0.58, 0.57, 0.55, 0.0)
const POLE := Color(0.42, 0.42, 0.44, 0.0)
const WINDOW := Color(0.07, 0.08, 0.10, 0.33)
const LAMP := Color(0.85, 0.85, 0.80, 0.66)
const LETTERS := Color(0.97, 0.95, 0.88)
const LABEL_RANGE := 1100.0  ## like the road signs: a pixel or two in the haze past this

var route: RouteData
var material: ShaderMaterial
var _boxes: Array = []  ## [Transform3D at the box's center, half extents]: for QA's clip probe
var _body: StaticBody3D


func setup(r: RouteData) -> void:
	route = r
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/scenery.gdshader")
	_body = StaticBody3D.new()
	_body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	_body.collision_mask = 0
	add_child(_body)
	for l: Dictionary in route.landmarks:
		match String(l.id):
			"kalona_cheese":
				_kalona_cheese(Vector3(float(l.x), 0.0, float(l.z)))


## The season and the time of day, like the scenery's.
func set_look(snow: float, night: float) -> void:
	material.set_shader_parameter("snow", snow)
	material.set_shader_parameter("night", night)


## Solid boxes within `radius` of a point (QA's clip probe), as [transform, half extents].
func building_boxes(near: Vector3, radius: float) -> Array:
	return _boxes.filter(func(b: Array): return Vector2(b[0].origin.x - near.x, b[0].origin.z - near.z).length() <= radius)


func box_count() -> int:
	return _boxes.size()


## Local axes: x east, z south (the store's front faces south, onto 540th St), y up from
## the ground at the middle of each group. The origin is the middle of the store's main
## block.
func _kalona_cheese(origin: Vector3) -> void:
	# The store and the buildings joined to it.
	var g := _group(origin, Rect2(-11.5, -14.5, 44.5, 40.0))
	var st: SurfaceTool = g.st
	var base: float = g.base
	# The main block: a story and a half of brick under a steep gray roof, gable to the front.
	var eave := 5.4
	var ridge := 9.8
	_box(st, g, Vector3(-8, base, -14.5), Vector3(8, eave, 14.5), BRICK)
	_gable_z(st, -8.0, 8.0, -14.5, 14.5, eave, ridge, 0.45, 0.35, SHINGLE, BRICK)
	var front := 14.5
	for x: float in [-1.3, 1.3]:
		_window(st, Vector3(x, 7.7, front), Vector2(0.85, 1.05), Vector3.BACK)
	for x: float in [-4.6, -1.6, 1.6, 4.6]:
		_window(st, Vector3(x, 4.75, front), Vector2(0.9, 0.6), Vector3.BACK)
	_label(g, "KALONA CHEESE", 112, 0.0105, Vector3(0, 6.0, front + 0.03), Vector3.BACK, false)
	for z: float in [-11.0, -6.5, -2.0, 2.5, 7.0, 11.0]:
		_window(st, Vector3(-8.0, 4.8, z), Vector2(0.9, 0.9), Vector3.LEFT)
	for z: float in [-11.0, -6.5]:  # the west wall, ahead of the one-story wing
		_window(st, Vector3(-8.0, 1.8, z), Vector2(1.2, 1.3), Vector3.LEFT)
	for z: float in [6.0, 11.0]:  # the east wall, past the old plant
		_window(st, Vector3(8.0, 4.8, z), Vector2(0.9, 0.9), Vector3.RIGHT)
		_window(st, Vector3(8.0, 1.8, z), Vector2(1.2, 1.3), Vector3.RIGHT)
	for x: float in [-4.0, 0.0, 4.0]:
		_window(st, Vector3(x, 4.8, -14.5), Vector2(0.9, 0.9), Vector3.FORWARD)
		_window(st, Vector3(x, 1.8, -14.5), Vector2(1.2, 1.3), Vector3.FORWARD)

	# The one-story front and its wing along the road side, under the gray mansard.
	var wall := 3.0
	var top := 4.2
	_one_story(st, g, Rect2(-11.5, 14.5, 22.5, 11.0), wall, top, [true, false, false, true])
	_one_story(st, g, Rect2(-11.5, -2.5, 3.5, 17.0), wall, top, [true, false, true, false])
	var face := 25.5
	for x: float in [-7.0, 4.6, 8.0]:
		_window(st, Vector3(x, 1.75, face), Vector2(1.9, 1.7), Vector3.BACK)
	for z: float in [0.0, 4.0, 8.0, 12.0, 17.5, 22.0]:
		_window(st, Vector3(-11.5, 1.75, z), Vector2(1.5, 1.7), Vector3.LEFT)
	# Black double doors (glass: lit at night), and the sign over them.
	_box(st, g, Vector3(-1.25, 0.0, face - 0.05), Vector3(1.25, 2.55, face + 0.08), SIGN_BLACK)
	for x: float in [-0.55, 0.55]:
		_window(st, Vector3(x, 1.2, face + 0.08), Vector2(0.85, 2.0), Vector3.BACK)
	_box(st, g, Vector3(-3.2, 2.7, face + 0.2), Vector3(3.2, 4.55, face + 0.5), SIGN_BLACK)
	_label(g, "KALONA\nCREAMERY", 96, 0.0085, Vector3(0, 3.62, face + 0.52), Vector3.BACK, true)
	# A concrete walk along the front.
	_walk(st, g, -11.5, 32.0, face, face + 3.5)

	# Joined on the right: a concrete-block section, then a brick wing with a garage door.
	_box(st, g, Vector3(11, base, 9.5), Vector3(18, 4.7, 25.5), BLOCK)
	_box(st, g, Vector3(11.2, 4.7, 9.7), Vector3(17.8, 4.8, 25.3), FLAT_ROOF)
	_box(st, g, Vector3(18, base, 9.5), Vector3(32, 4.2, 25.5), BRICK)
	_box(st, g, Vector3(18.2, 4.2, 9.7), Vector3(31.8, 4.3, 25.3), FLAT_ROOF)
	_box(st, g, Vector3(23.0, 0.0, 25.5), Vector3(26.4, 3.2, 25.6), DOOR)
	_window(st, Vector3(29.0, 1.8, 25.5), Vector2(1.4, 1.2), Vector3.BACK)
	# The old plant behind, brick under a tan roof, and its smokestack.
	_box(st, g, Vector3(8, base, -11.5), Vector3(26, 5.0, 2.5), BRICK)
	_gable_x(st, 8.0, 26.0, -11.5, 2.5, 5.0, 7.6, 0.4, TAN_ROOF, BRICK)
	_window(st, Vector3(26.0, 2.0, -4.5), Vector2(1.2, 1.2), Vector3.RIGHT)
	_stack(st, g, Vector3(33.0, 0, 3.5), 0.95, 15.0)
	# A light pole out front.
	_light_pole(st, g, Vector3(-13.5, 0, 29.0))
	_finish(g)

	# The plant: steel silos and two big metal buildings.
	var p := _group(origin, Rect2(26.0, -22.5, 49.0, 37.0))
	st = p.st
	base = p.base
	_box(st, p, Vector3(26, base, -18.5), Vector3(36, 7.0, -1.5), METAL)
	_box(st, p, Vector3(26.2, 7.0, -18.3), Vector3(35.8, 7.1, -1.7), FLAT_ROOF)
	for z: float in [-15.0, -10.0, -5.0]:
		_silo(st, p, Vector3(42.0, 0, z), 2.1, 12.5)
	_box(st, p, Vector3(48, base, -22.5), Vector3(75, 10.0, -4.5), METAL)
	_box(st, p, Vector3(48.2, 10.0, -22.3), Vector3(74.8, 10.1, -4.7), FLAT_ROOF)
	_box(st, p, Vector3(48, base, -1.5), Vector3(75, 6.0, 14.5), METAL)
	_box(st, p, Vector3(48.2, 6.0, -1.3), Vector3(74.8, 6.1, 14.3), FLAT_ROOF)
	for x: float in [54.0, 62.0, 70.0]:
		_box(st, p, Vector3(x - 1.6, 0.0, 14.5), Vector3(x + 1.6, 3.4, 14.6), DOOR)
	for z: float in [-17.0, -10.0]:
		_box(st, p, Vector3(47.9, 0.0, z - 1.8), Vector3(48.0, 4.0, z + 1.8), DOOR)
	_finish(p)


## A group of buildings drawn as one mesh, sat on the ground: y = 0 is the ground at the
## middle of `area` (local x/z), and walls start at `base`, below the lowest ground under
## it, so nothing floats on a slope.
func _group(origin: Vector3, area: Rect2) -> Dictionary:
	var t := route.terrain
	var low := INF
	for corner: Vector2 in [area.position, area.position + Vector2(area.size.x, 0), area.end,
			area.position + Vector2(0, area.size.y)]:
		var h := t.height_at(origin.x + corner.x, origin.z + corner.y)
		if not is_nan(h):
			low = minf(low, h)
	var middle := area.get_center()
	var floor_y := t.height_at(origin.x + middle.x, origin.z + middle.y)
	if is_nan(floor_y):
		floor_y = low if not is_inf(low) else route.position_at(route.nearest_station(origin, 0.0, 1e9)).y
	if is_inf(low):
		low = floor_y
	return {"st": MeshKit.begin(), "at": Vector3(origin.x, floor_y, origin.z), "base": low - floor_y - 0.3}


func _finish(g: Dictionary) -> void:
	var st: SurfaceTool = g.st
	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = g.at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## An axis-aligned box from corner `a` to corner `b` (local); solid unless it's trim.
func _box(st: SurfaceTool, g: Dictionary, a: Vector3, b: Vector3, color: Color, solid := true) -> void:
	var size := (b - a).abs()
	var center := (a + b) / 2.0
	MeshKit.box(st, size, center, color)
	if solid and size.x > 0.5 and size.y > 0.5 and size.z > 0.5:
		_solid(g, center, size / 2.0)


func _solid(g: Dictionary, center: Vector3, half: Vector3, shape: Shape3D = null) -> void:
	var at: Vector3 = g.at + center
	var cs := CollisionShape3D.new()
	if shape == null:
		var box := BoxShape3D.new()
		box.size = half * 2.0
		shape = box
		_boxes.append([Transform3D(Basis.IDENTITY, at), half])
	cs.shape = shape
	cs.position = at
	_body.add_child(cs)


## A two-sided roof whose ridge runs north-south, over walls from x0 to x1 and z0 to z1,
## with brick gables at the ends.
func _gable_z(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, eave: float, ridge: float,
		overhang: float, end_overhang: float, roof: Color, wall: Color) -> void:
	var mid := (x0 + x1) / 2.0
	var half := (x1 - x0) / 2.0 + overhang
	var drop := (ridge - eave) * overhang / ((x1 - x0) / 2.0)
	for side: float in [-1.0, 1.0]:
		var e := Vector3(mid + side * half, eave - drop, 0)
		var r := Vector3(mid, ridge, 0)
		var out := Vector3(side * (ridge - eave), (x1 - x0) / 2.0, 0).normalized()
		MeshKit.quad(st, e + Vector3(0, 0, z0 - end_overhang), e + Vector3(0, 0, z1 + end_overhang),
			r + Vector3(0, 0, z1 + end_overhang), r + Vector3(0, 0, z0 - end_overhang), out, roof)
	for z: float in [z0, z1]:
		MeshKit.tri(st, Vector3(x0, eave, z), Vector3(x1, eave, z), Vector3(mid, ridge, z), Vector3(0, 0, signf(z - (z0 + z1) / 2.0)), wall)


## The same with the ridge running east-west.
func _gable_x(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, eave: float, ridge: float,
		overhang: float, roof: Color, wall: Color) -> void:
	var mid := (z0 + z1) / 2.0
	var half := (z1 - z0) / 2.0 + overhang
	var drop := (ridge - eave) * overhang / ((z1 - z0) / 2.0)
	for side: float in [-1.0, 1.0]:
		var e := Vector3(0, eave - drop, mid + side * half)
		var r := Vector3(0, ridge, mid)
		var out := Vector3(0, (z1 - z0) / 2.0, side * (ridge - eave)).normalized()
		MeshKit.quad(st, e + Vector3(x0 - overhang, 0, 0), e + Vector3(x1 + overhang, 0, 0),
			r + Vector3(x1 + overhang, 0, 0), r + Vector3(x0 - overhang, 0, 0), out, roof)
	for x: float in [x0, x1]:
		MeshKit.tri(st, Vector3(x, eave, z0), Vector3(x, eave, z1), Vector3(x, ridge, mid), Vector3(signf(x - (x0 + x1) / 2.0), 0, 0), wall)


## One story of brick, its roof edged with a sloping shingled mansard on the sides in
## `sides` (west, east, north, south), flat behind it.
func _one_story(st: SurfaceTool, g: Dictionary, area: Rect2, wall: float, top: float, sides: Array) -> void:
	var base: float = g.base
	_box(st, g, Vector3(area.position.x, base, area.position.y), Vector3(area.end.x, wall, area.end.y), BRICK)
	var out := 0.3  ## the mansard's foot sticks out past the wall this far...
	var inset := 1.0  ## ...and its top is this far in
	# Where the flat roof's edges are, and where the mansard's foot is, per side.
	var lo := [area.position.x, area.end.x, area.position.y, area.end.y]
	var foot := lo.duplicate()
	var crest := lo.duplicate()
	for i in 4:
		var outward := -1.0 if i % 2 == 0 else 1.0
		if sides[i]:
			foot[i] = lo[i] + outward * out
			crest[i] = lo[i] - outward * inset
	MeshKit.box(st, Vector3(crest[1] - crest[0], top - wall, crest[3] - crest[2]),
		Vector3((crest[0] + crest[1]) / 2.0, (wall + top) / 2.0, (crest[2] + crest[3]) / 2.0), FLAT_ROOF)
	var y0 := wall - 0.1
	# Corners of the foot and the crest, going round: NW, NE, SE, SW.
	var f := [Vector3(foot[0], y0, foot[2]), Vector3(foot[1], y0, foot[2]), Vector3(foot[1], y0, foot[3]), Vector3(foot[0], y0, foot[3])]
	var c := [Vector3(crest[0], top, crest[2]), Vector3(crest[1], top, crest[2]), Vector3(crest[1], top, crest[3]), Vector3(crest[0], top, crest[3])]
	# side index -> the two corners along it, and its outward normal
	var edges := {0: [3, 0, Vector3.LEFT], 1: [1, 2, Vector3.RIGHT], 2: [0, 1, Vector3.FORWARD], 3: [2, 3, Vector3.BACK]}
	for i in 4:
		if not sides[i]:
			continue
		var a: int = edges[i][0]
		var b: int = edges[i][1]
		MeshKit.quad(st, f[a], f[b], c[b], c[a], edges[i][2] + Vector3.UP * 0.8, SHINGLE)
		MeshKit.quad(st, f[a], f[b], f[b] + Vector3(0, -0.12, 0), f[a] + Vector3(0, -0.12, 0), edges[i][2], SHINGLE)


## A flat strip on the ground (a sidewalk), following it.
func _walk(st: SurfaceTool, g: Dictionary, x0: float, x1: float, z0: float, z1: float) -> void:
	var at: Vector3 = g.at
	var step := (x1 - x0) / ceilf((x1 - x0) / 2.0)
	var x := x0
	while x < x1 - 0.01:
		var corners: Array[Vector3] = []
		for c: Vector2 in [Vector2(x, z0), Vector2(x + step, z0), Vector2(x + step, z1), Vector2(x, z1)]:
			var h := route.terrain.height_at(at.x + c.x, at.z + c.y)
			corners.append(Vector3(c.x, (h - at.y if not is_nan(h) else 0.0) + 0.06, c.y))
		MeshKit.quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.UP, CONCRETE)
		x += step


## A window (dark glass that lights up at night) just proud of a wall facing `normal`,
## with a pale sill under it.
func _window(st: SurfaceTool, center: Vector3, size: Vector2, normal: Vector3) -> void:
	var c := center + normal * 0.03
	var across := Vector3.UP.cross(normal).normalized() * size.x / 2.0
	var up := Vector3.UP * size.y / 2.0
	MeshKit.quad(st, c - across - up, c + across - up, c + across + up, c - across + up, normal, WINDOW)
	MeshKit.box(st, Vector3(size.x + 0.15, 0.08, 0.12) if absf(normal.z) > 0.5 else Vector3(0.12, 0.08, size.x + 0.15),
		c - up + normal * 0.03 - Vector3(0, 0.04, 0), SILL)


## A round steel silo with a cone top.
func _silo(st: SurfaceTool, g: Dictionary, at: Vector3, radius: float, height: float) -> void:
	var base: float = g.base
	var length := height - base
	MeshKit.cylinder(st, radius, length, at + Vector3(0, base + length / 2.0, 0), STEEL, STEEL, 12, Vector3.UP)
	var tip := at + Vector3(0, height + 1.3, 0)
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		var p0 := at + Vector3(cos(a0) * radius, height, sin(a0) * radius)
		var p1 := at + Vector3(cos(a1) * radius, height, sin(a1) * radius)
		MeshKit.tri(st, p0, p1, tip, (p0 + p1) / 2.0 - at - Vector3(0, height - 1.0, 0), METAL)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = length
	_solid(g, at + Vector3(0, base + length / 2.0, 0), Vector3(radius, length / 2.0, radius), shape)


## The brick smokestack, darker at the top.
func _stack(st: SurfaceTool, g: Dictionary, at: Vector3, radius: float, height: float) -> void:
	var base: float = g.base
	var length := height - 1.2 - base
	MeshKit.cylinder(st, radius, length, at + Vector3(0, base + length / 2.0, 0), BRICK, BRICK, 10, Vector3.UP)
	MeshKit.cylinder(st, radius * 0.92, 1.2, at + Vector3(0, height - 0.6, 0), BRICK_DARK, SIGN_BLACK, 10, Vector3.UP)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height - base
	_solid(g, at + Vector3(0, (height + base) / 2.0, 0), Vector3(radius, (height - base) / 2.0, radius), shape)


## A parking-lot light: a pole with a lamp that's lit at night.
func _light_pole(st: SurfaceTool, g: Dictionary, at: Vector3) -> void:
	var pole := Vector3(0.22, 8.5 - g.base, 0.22)
	MeshKit.box(st, pole, at + Vector3(0, (8.5 + g.base) / 2.0, 0), POLE)
	_solid(g, at + Vector3(0, (8.5 + g.base) / 2.0, 0), pole / 2.0)
	MeshKit.box(st, Vector3(1.2, 0.1, 0.12), at + Vector3(0.6, 8.4, 0), POLE)
	MeshKit.box(st, Vector3(0.5, 0.18, 0.4), at + Vector3(1.1, 8.25, 0), LAMP)


## Lettering on a wall, facing `normal`. `lit` for a sign that's lit at night.
func _label(g: Dictionary, text: String, font_size: int, pixel: float, pos: Vector3, normal: Vector3, lit: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = LETTERS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.line_spacing = -8.0
	label.double_sided = false
	label.shaded = not lit
	label.visibility_range_end = LABEL_RANGE
	label.position = g.at + pos
	label.rotation.y = atan2(normal.x, normal.z)
	add_child(label)
