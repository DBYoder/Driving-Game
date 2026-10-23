class_name Junction
extends Node3D
## The Kalona 4-way stop, where both runs start, laid out like the real one (tools/junction.py
## worked it out into the route's junction.json; the road mesh leaves its stretch out):
##   - concrete all through: IA 1 opening a left-turn lane each side, IA 22 two lanes, a
##     free right turn round every corner with its gore painted, the lane lines, stop
##     lines, arrows, and IA-1 / IA-22 across the lanes left-turners turn into;
##   - gravel shoulders and grass slopes round it, solid like the road;
##   - a light pole leaning a davit arm over each turning lane, lit at night;
##   - the KALONA welcome sign in its flower bed by the flagpole on the southwest corner.
## Intersections puts up its stop and yield signs and the buggy.
##
## The props are drawn with the scenery's shader, so they take the snow and the lamps light
## up at night.

const PAINT := {"white": Color(0.92, 0.92, 0.92), "yellow": Color(0.95, 0.74, 0.10), "black": Color(0.07, 0.07, 0.07)}
const SURFACES := {"concrete": "asphalt", "gravel": "gravel", "grass": "grass"}  ## what the car feels (Car.SURFACES)
const POLE := Color(0.60, 0.61, 0.63, 0.0)  ## galvanized steel
const LAMP := Color(0.85, 0.85, 0.80, 0.66)
const HEAD := Color(0.30, 0.31, 0.33, 0.0)
const WHITE := Color(0.93, 0.93, 0.91, 0.0)
const LATTICE := Color(0.84, 0.85, 0.83, 0.0)
const TRIM := Color(0.24, 0.25, 0.26, 0.0)
const SUN := Color(0.96, 0.70, 0.42, 0.0)  ## the peach sun behind the buggy
const INK := Color(0.06, 0.06, 0.06, 0.0)
const MULCH := Color(0.27, 0.19, 0.13, 0.0)
const SHRUB := Color(0.16, 0.30, 0.15, 0.0)
const GRASSES := Color(0.70, 0.60, 0.40, 0.0)  ## ornamental grass plumes
const FLAGPOLE := Color(0.86, 0.87, 0.89, 0.0)
const GOLD := Color(0.85, 0.70, 0.25, 0.0)
const POLE_HEIGHT := 12.6
const ARM_REACH := 4.6
const LABEL_RANGE := 600.0

var route: RouteData
var pavement: ShaderMaterial
var props: ShaderMaterial
var lamps: Array[SpotLight3D] = []
var bodies := {}  ## "concrete" / "gravel" / "grass" / "props" -> StaticBody3D
var paint_triangles := 0


func setup(r: RouteData) -> void:
	route = r
	if r.junction.is_empty():
		return
	pavement = ShaderMaterial.new()
	pavement.shader = load("res://shaders/junction.gdshader")
	props = ShaderMaterial.new()
	props.shader = load("res://shaders/scenery.gdshader")
	_build_pavement()
	_build_paint()
	var st := MeshKit.begin()
	for l: Dictionary in r.junction.lights:
		_light_pole(st, l)
	_welcome_sign(st, r.junction.welcome_sign)
	_flagpole(st, r.junction.flagpole)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = props
	add_child(node)


## Grass and gravel in the weather's colors, snow on the props, the lamps lit at night.
func apply_condition(c: Condition) -> void:
	if pavement == null:
		return
	pavement.set_shader_parameter("gravel", c.gravel)
	pavement.set_shader_parameter("verge", c.road_verge)
	props.set_shader_parameter("snow", c.snow)
	props.set_shader_parameter("night", c.night)
	for lamp in lamps:
		lamp.visible = c.night > 0.5


# --- The pavement ---------------------------------------------------------------------

func _build_pavement() -> void:
	var j: Dictionary = route.junction
	var mesh := ArrayMesh.new()
	var concrete: Dictionary = j.concrete
	var verts := _vectors(concrete.vertices)
	var joints: Array = concrete.joints
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	for i in verts.size():
		uv.append(Vector2(joints[i * 5], joints[i * 5 + 1]))
		uv2.append(Vector2(joints[i * 5 + 2], joints[i * 5 + 3]))
		colors.append(Color(float(joints[i * 5 + 4]) / 3.0, 0.0, 0.0))
	_add_surface(mesh, "concrete", verts, PackedInt32Array(concrete.indices), uv, uv2, colors)
	var shoulder: Dictionary = j.shoulder
	var sverts := _vectors(shoulder.vertices)
	var blank := PackedVector2Array()
	blank.resize(sverts.size())
	for kind: String in ["gravel", "grass"]:
		var c := PackedColorArray()
		c.resize(sverts.size())
		c.fill(Color(1.0, 0.5 if kind == "gravel" else 1.0, 0.0))
		_add_surface(mesh, kind, sverts, PackedInt32Array(shoulder[kind]), blank, blank, c)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = pavement
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _add_surface(mesh: ArrayMesh, kind: String, verts: PackedVector3Array, indices: PackedInt32Array,
		uv: PackedVector2Array, uv2: PackedVector2Array, colors: PackedColorArray) -> void:
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(mesh.get_surface_count() - 1, kind)
	# Solid, and the car feels concrete as pavement, the shoulders as gravel and grass.
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	body.collision_mask = 0
	body.set_meta("surface", SURFACES[kind])
	var holder := CollisionShape3D.new()
	holder.shape = shape
	body.add_child(holder)
	add_child(body)
	bodies[kind] = body


## The lines, the gores, the arrows and the words, a hair over the concrete.
func _build_paint() -> void:
	for color: String in route.junction.paint:
		var p: Dictionary = route.junction.paint[color]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var verts := _vectors(p.vertices)
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(p.indices)
		if p.indices.is_empty():
			continue
		paint_triangles += p.indices.size() / 3
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := StandardMaterial3D.new()
		m.albedo_color = PAINT[color]
		m.roughness = 1.0
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = m
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("paint", true)
		add_child(node)


# --- Things standing on it ----------------------------------------------------------------

## A light pole: galvanized steel, a davit arm reaching out over the turning lane, and a
## lamp head that lights the lane at night.
func _light_pole(st: SurfaceTool, l: Dictionary) -> void:
	var y := float(l.y)
	var ground := _ground(float(l.x), float(l.z), y)
	var foot := Vector3(l.x, minf(ground, y) - 0.4, l.z)
	var top := Vector3(l.x, y + POLE_HEIGHT, l.z)
	var arm := Vector3(l.arm[0], 0.0, l.arm[1]).normalized()
	_rod(st, foot, top, 0.14, POLE)
	var elbow := top + arm * 1.4 + Vector3.UP * 0.55
	var tip := top + arm * ARM_REACH + Vector3.UP * 0.7
	_rod(st, top - Vector3.UP * 0.3, elbow, 0.07, POLE)
	_rod(st, elbow, tip, 0.06, POLE)
	var yaw := atan2(-arm.z, arm.x)
	var head := tip + arm * 0.25 - Vector3.UP * 0.1
	MeshKit.box(st, Vector3(0.8, 0.16, 0.36), head, HEAD, yaw)
	MeshKit.box(st, Vector3(0.6, 0.03, 0.26), head - Vector3.UP * 0.09, LAMP, yaw)
	_solid(Vector3(l.x, (foot.y + top.y) / 2.0, l.z), _cylinder(0.16, top.y - foot.y))
	var lamp := SpotLight3D.new()
	lamp.position = head - Vector3.UP * 0.2
	lamp.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	lamp.spot_range = 24.0
	lamp.spot_angle = 62.0
	lamp.spot_attenuation = 0.8
	lamp.light_energy = 2.2
	lamp.light_color = Color(1.0, 0.93, 0.82)
	lamp.shadow_enabled = false
	lamp.visible = false
	add_child(lamp)
	lamps.append(lamp)


## The welcome sign: two panels meeting in a point toward the junction (one reads from
## each way along IA 1), each "Welcome to KALONA" over a horse and buggy on a peach sun,
## standing on a white lattice skirt, in a mulched bed of shrubs and ornamental grass.
func _welcome_sign(st: SurfaceTool, w: Dictionary) -> void:
	var center := Vector3(w.x, _ground(float(w.x), float(w.z), float(w.y)), w.z)
	var toward := Vector3(w.toward[0], 0.0, w.toward[1]).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	# The bed.
	_disc(st, center + Vector3.UP * 0.04, Vector2(3.4, 2.4), toward, MULCH)
	for p: Vector2 in [Vector2(1.7, -1.6), Vector2(2.3, -0.5), Vector2(2.2, 0.7), Vector2(1.6, 1.7), Vector2(-0.6, 2.2),
			Vector2(-0.8, -2.1)]:
		var at := center + toward * p.x + side * p.y
		MeshKit.cylinder(st, 0.5, 0.55, at + Vector3.UP * 0.28, SHRUB, SHRUB, 7, Vector3.UP)
		MeshKit.cylinder(st, 0.33, 0.25, at + Vector3.UP * 0.66, SHRUB, SHRUB, 7, Vector3.UP)
	for p: Vector2 in [Vector2(-1.4, -1.0), Vector2(-1.6, 0.4), Vector2(-1.2, 1.5), Vector2(0.4, -2.6)]:
		var at := center + toward * p.x + side * p.y
		for k in 3:
			var lean := Vector3(cos(k * 2.1), 3.0, sin(k * 2.1)).normalized()
			MeshKit.cylinder(st, 0.11, 1.3, at + lean * 0.6, GRASSES, GRASSES, 5, lean)
	# The panels.
	var apex := center + toward * 0.6
	for s: float in [-1.0, 1.0]:
		var along := (-toward + side * s).normalized()  # from the point back along the panel
		var face := (toward + side * s).normalized()  # the way it reads
		var mid := apex + along * 1.0
		var yaw := atan2(-along.z, along.x)
		MeshKit.box(st, Vector3(1.95, 0.95, 0.08), mid + Vector3.UP * 0.5, LATTICE, yaw)
		MeshKit.box(st, Vector3(1.95, 1.45, 0.1), mid + Vector3.UP * 1.72, WHITE, yaw)
		MeshKit.box(st, Vector3(2.05, 0.08, 0.14), mid + Vector3.UP * 2.48, TRIM, yaw)
		for end: float in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0.1, 2.5, 0.12), mid + along * end * 0.98 + Vector3.UP * 1.25, WHITE, yaw)
		var on := mid + face * 0.056
		_disc_on(st, on + Vector3.UP * 1.62, 0.44, face, SUN)
		# The horse and buggy, in silhouette.
		var f := on + face * 0.004
		var a := Vector3(face.z, 0.0, -face.x)  # across the face, left to right as you read it
		for part: Array in [[Vector2(0.1, 1.42), Vector2(0.42, 0.13)], [Vector2(0.33, 1.52), Vector2(0.08, 0.2)],
				[Vector2(0.38, 1.6), Vector2(0.14, 0.07)], [Vector2(0.26, 1.27), Vector2(0.04, 0.2)],
				[Vector2(-0.06, 1.27), Vector2(0.04, 0.2)], [Vector2(-0.28, 1.5), Vector2(0.24, 0.24)],
				[Vector2(-0.12, 1.42), Vector2(0.3, 0.025)]]:
			_flat(st, f, a, part[0], part[1], face, INK)
		_disc_on(st, f - a * 0.3 + Vector3.UP * 1.3, 0.12, face, INK)
		_label("Welcome to", 26, 0.0072, on + a * -0.45 + Vector3.UP * 2.27, face)
		_label("KALONA", 52, 0.0092, on + Vector3.UP * 1.98, face)
	var body := BoxShape3D.new()
	body.size = Vector3(1.6, 2.5, 1.6)
	_solid(apex - toward * 0.7 + Vector3.UP * 1.25, body)


## The flagpole by the welcome sign, the Stars and Stripes standing out in the breeze.
func _flagpole(st: SurfaceTool, f: Dictionary) -> void:
	var foot := Vector3(f.x, _ground(float(f.x), float(f.z), float(f.y)) - 0.2, f.z)
	MeshKit.cylinder(st, 0.07, 9.6, foot + Vector3.UP * 4.8, FLAGPOLE, FLAGPOLE, 8, Vector3.UP)
	MeshKit.box(st, Vector3(0.18, 0.18, 0.18), foot + Vector3.UP * 9.65, GOLD)
	_solid(foot + Vector3.UP * 4.8, _cylinder(0.1, 9.6))
	var flag := MeshInstance3D.new()
	flag.mesh = Landmarks._flag_mesh(Vector2(2.0, 1.1))
	flag.material_override = Landmarks._flag_material("us")
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flag.transform = Transform3D(Basis(Vector3.UP, PI * 0.8), foot + Vector3(0.0, 9.4, 0.0))
	add_child(flag)


# --- Bits -------------------------------------------------------------------------------------

## The ground's height at (x, z), or `fallback` off the terrain.
func _ground(x: float, z: float, fallback: float) -> float:
	var h := route.terrain.height_at(x, z)
	return fallback if is_nan(h) else h


func _rod(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	MeshKit.cylinder(st, radius, a.distance_to(b), (a + b) / 2.0, color, color, 8, b - a)


## A flat oval on the ground (radii along `toward` and across it).
func _disc(st: SurfaceTool, center: Vector3, radii: Vector2, toward: Vector3, color: Color) -> void:
	var side := Vector3(-toward.z, 0.0, toward.x)
	const N := 14
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var p0 := center + toward * cos(a0) * radii.x + side * sin(a0) * radii.y
		var p1 := center + toward * cos(a1) * radii.x + side * sin(a1) * radii.y
		MeshKit.tri(st, center, p0, p1, Vector3.UP, color)


## A round patch standing on a face that looks `normal`.
func _disc_on(st: SurfaceTool, center: Vector3, radius: float, normal: Vector3, color: Color) -> void:
	var across := Vector3.UP.cross(normal).normalized()
	const N := 16
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var p0 := center + (across * cos(a0) + Vector3.UP * sin(a0)) * radius
		var p1 := center + (across * cos(a1) + Vector3.UP * sin(a1)) * radius
		MeshKit.tri(st, center, p0, p1, normal, color)


## A rectangle on a face: `at` (across, up) from `origin`, `size` (across, up).
func _flat(st: SurfaceTool, origin: Vector3, across: Vector3, at: Vector2, size: Vector2, normal: Vector3, color: Color) -> void:
	var c := origin + across * at.x + Vector3(0.0, at.y, 0.0)
	var a := across * size.x / 2.0
	var u := Vector3.UP * size.y / 2.0
	MeshKit.quad(st, c - a - u, c + a - u, c + a + u, c - a + u, normal, color)


func _label(text: String, font_size: int, pixel: float, pos: Vector3, normal: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = Color(0.05, 0.05, 0.05)
	label.double_sided = false
	label.shaded = true
	label.visibility_range_end = LABEL_RANGE
	label.position = pos
	label.rotation.y = atan2(normal.x, normal.z)
	add_child(label)


func _cylinder(radius: float, height: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	return c


func _solid(at: Vector3, shape: Shape3D) -> void:
	if not bodies.has("props"):
		var body := StaticBody3D.new()
		body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
		body.collision_mask = 0
		add_child(body)
		bodies["props"] = body
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	bodies["props"].add_child(cs)


static func _vectors(flat: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(flat.size() / 3)
	for i in out.size():
		out[i] = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
	return out
