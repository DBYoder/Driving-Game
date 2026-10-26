class_name TrafficModels
extends RefCounted
## Low-poly traffic. Every model faces -Z, sits on y = 0 and is centered on its footprint.

const TIRE := Color(0.06, 0.06, 0.06)
const GLASS := Color(0.12, 0.15, 0.18)
const PAINT := [
	Color(0.55, 0.08, 0.10), Color(0.12, 0.22, 0.45), Color(0.85, 0.85, 0.82), Color(0.15, 0.35, 0.22),
	Color(0.62, 0.55, 0.42), Color(0.35, 0.35, 0.37), Color(0.08, 0.08, 0.09), Color(0.58, 0.47, 0.18),
]


static func build(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := MeshKit.begin()
	st.set_smooth_group(-1)  # flat faces: crisp edges (smoothed, boxes and wheels go soft and blobby)
	match kind:
		"car":
			_sedan(st, PAINT[rng.randi() % PAINT.size()])
		"pickup":
			_pickup(st, PAINT[rng.randi() % PAINT.size()])
		"semi":
			_semi(st, PAINT[rng.randi() % PAINT.size()])
		"buggy":
			_buggy(st)
		"tractor":
			_tractor(st)
		"combine":
			_combine(st, rng)
		"grain_truck":
			_grain_truck(st, PAINT[rng.randi() % PAINT.size()])
		"snowplow":
			_snowplow(st)
	return MeshKit.finish(st)


## Head and tail lights for night: white at the front, red at the back (a buggy's lantern
## and red flashers instead), unshaded so they shine in the dark. `length`/`width` are
## the vehicle's footprint; `center` where it sits along the model (Traffic.KINDS).
static func lamps(kind: String, spec: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l: float = spec.length
	var w: float = spec.width
	var c: float = spec.center
	var front := -l / 2.0 + c
	var back := l / 2.0 + c
	var white := Color(1.0, 0.97, 0.85)
	var red := Color(0.95, 0.08, 0.05)
	var amber := Color(1.0, 0.65, 0.15)
	match kind:
		"buggy":
			MeshKit.box(st, Vector3(0.14, 0.14, 0.14), Vector3(0.82, 1.6, back - 1.8), amber)
			MeshKit.box(st, Vector3(0.14, 0.14, 0.14), Vector3(-0.82, 1.6, back - 1.8), amber)
			MeshKit.box(st, Vector3(0.12, 0.12, 0.05), Vector3(0.55, 1.2, back + 0.02), red)
			MeshKit.box(st, Vector3(0.12, 0.12, 0.05), Vector3(-0.55, 1.2, back + 0.02), red)
		_:
			var y := 0.7 if kind == "car" else 1.0
			for side: float in [-1.0, 1.0]:
				MeshKit.box(st, Vector3(0.28, 0.14, 0.05), Vector3(side * (w / 2.0 - 0.3), y, front - 0.03), white)
				MeshKit.box(st, Vector3(0.22, 0.14, 0.05), Vector3(side * (w / 2.0 - 0.25), y, back + 0.03), red)
			if kind in ["combine", "snowplow", "tractor"]:
				MeshKit.box(st, Vector3(0.5, 0.15, 0.25), Vector3(0, 3.6 if kind == "combine" else 3.2, front + 2.0), amber)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, m)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _wheels(st: SurfaceTool, half_track: float, zs: Array, radius: float, width := 0.22,
		hub := Color(0.55, 0.55, 0.56)) -> void:
	for z in zs:
		for x: float in [-half_track, half_track]:
			MeshKit.cylinder(st, radius, width, Vector3(x, radius, z), TIRE, TIRE, 8)
			# The wheel inside the tire, just proud of its sidewall.
			MeshKit.cylinder(st, radius * 0.58, 0.02, Vector3(x + signf(x) * (width / 2.0 + 0.005), radius, z), hub, hub, 8)


static func _sedan(st: SurfaceTool, paint: Color) -> void:
	MeshKit.box(st, Vector3(1.78, 0.56, 4.7), Vector3(0, 0.62, 0), paint)
	# The greenhouse: raked windshield and back glass, the roof painted.
	_cabin(st, 0.9, 1.4, Vector2(-0.95, 1.35), Vector2(-0.35, 0.85), 1.66, 1.4, paint)
	_ends(st, 1.78, 4.7, 0.62, 0.7)
	_wheels(st, 0.78, [-1.4, 1.4], 0.33)


static func _pickup(st: SurfaceTool, paint: Color) -> void:
	MeshKit.box(st, Vector3(1.95, 0.66, 5.5), Vector3(0, 0.77, 0), paint)
	_cabin(st, 1.1, 1.8, Vector2(-1.75, -0.1), Vector2(-1.35, -0.15), 1.84, 1.7, paint)
	MeshKit.box(st, Vector3(1.85, 0.35, 2.3), Vector3(0, 1.27, 1.45), paint.darkened(0.25))  # bed sides
	MeshKit.box(st, Vector3(1.6, 0.05, 2.2), Vector3(0, 1.11, 1.45), Color(0.12, 0.12, 0.12))  # bed liner
	_ends(st, 1.95, 5.5, 0.72, 0.95)
	_wheels(st, 0.85, [-1.75, 1.6], 0.38, 0.26)


## A car's cabin from y0 to y1: glass all round, narrower and shorter at the top
## (`top` z span over `bottom`'s: the windshield and back glass raked), a painted roof.
static func _cabin(st: SurfaceTool, y0: float, y1: float, bottom: Vector2, top: Vector2, w0: float, w1: float,
		roof: Color) -> void:
	var b: Array[Vector3] = [Vector3(-w0 / 2, y0, bottom.x), Vector3(w0 / 2, y0, bottom.x), Vector3(w0 / 2, y0, bottom.y), Vector3(-w0 / 2, y0, bottom.y)]
	var t: Array[Vector3] = [Vector3(-w1 / 2, y1, top.x), Vector3(w1 / 2, y1, top.x), Vector3(w1 / 2, y1, top.y), Vector3(-w1 / 2, y1, top.y)]
	MeshKit.quad(st, b[0], b[1], t[1], t[0], Vector3(0, 0.5, -1), GLASS)  # windshield
	MeshKit.quad(st, b[2], b[3], t[3], t[2], Vector3(0, 0.5, 1), GLASS)  # back glass
	MeshKit.quad(st, b[1], b[2], t[2], t[1], Vector3(1, 0.2, 0), GLASS)
	MeshKit.quad(st, b[3], b[0], t[0], t[3], Vector3(-1, 0.2, 0), GLASS)
	MeshKit.quad(st, t[0], t[1], t[2], t[3], Vector3.UP, roof)
	# The pillars between the side windows.
	for x: float in [-1.0, 1.0]:
		var mid := (b[1].z + b[2].z) / 2.0
		var top_mid := (t[1].z + t[2].z) / 2.0
		var p0 := Vector3(x * (w0 / 2 + 0.005), y0, mid)
		var p1 := Vector3(x * (w1 / 2 + 0.005), y1, top_mid)
		MeshKit.quad(st, p0 - Vector3(0, 0, 0.07), p0 + Vector3(0, 0, 0.07), p1 + Vector3(0, 0, 0.07), p1 - Vector3(0, 0, 0.07),
			Vector3(x, 0, 0), roof)


## Bumpers, head lamps and tail lamps on a body `width` x `length`, lamps at `lamp_y`
## (what they look like by day: TrafficModels.lamps() lights them at night).
static func _ends(st: SurfaceTool, width: float, length: float, bumper_y: float, lamp_y: float) -> void:
	var trim := Color(0.16, 0.16, 0.17)
	for end: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(width + 0.04, 0.16, 0.12), Vector3(0, bumper_y - 0.2, end * length / 2.0), trim)
		for side: float in [-1.0, 1.0]:
			var lamp := Color(0.92, 0.9, 0.82) if end < 0.0 else Color(0.6, 0.06, 0.05)
			MeshKit.box(st, Vector3(0.3, 0.12, 0.04), Vector3(side * (width / 2.0 - 0.28), lamp_y, end * (length / 2.0 + 0.01)), lamp)


static func _semi(st: SurfaceTool, paint: Color) -> void:
	# Cab at the front (-Z), long trailer behind.
	MeshKit.box(st, Vector3(2.5, 1.6, 2.4), Vector3(0, 1.6, -9.0), paint)
	MeshKit.box(st, Vector3(2.4, 1.1, 1.8), Vector3(0, 2.9, -8.6), GLASS)
	MeshKit.box(st, Vector3(2.5, 0.8, 1.2), Vector3(0, 1.1, -10.6), paint.darkened(0.2))  # hood
	MeshKit.box(st, Vector3(2.6, 2.9, 15.5), Vector3(0, 2.65, 2.4), Color(0.88, 0.88, 0.86))
	_wheels(st, 1.0, [-10.0, -7.5, 7.0, 8.4], 0.5, 0.35)


static func _buggy(st: SurfaceTool) -> void:
	# Horse in front (-Z), black box buggy behind, orange slow-moving-vehicle triangle on the back.
	var horse := Color(0.33, 0.20, 0.11)
	MeshKit.box(st, Vector3(0.55, 0.65, 1.5), Vector3(0, 1.3, -1.85), horse)  # body
	MeshKit.box(st, Vector3(0.3, 0.7, 0.35), Vector3(0, 1.75, -2.6), horse)  # neck
	MeshKit.box(st, Vector3(0.25, 0.3, 0.6), Vector3(0, 2.05, -2.85), horse)  # head
	for x in [-0.18, 0.18]:
		for z in [-2.4, -1.3]:
			MeshKit.box(st, Vector3(0.12, 1.0, 0.12), Vector3(x, 0.5, z), horse)  # legs
	for x in [-0.55, 0.55]:
		MeshKit.box(st, Vector3(0.05, 0.05, 1.8), Vector3(x, 1.15, -1.3), Color(0.15, 0.12, 0.1))  # shafts
	var black := Color(0.07, 0.07, 0.08)
	MeshKit.box(st, Vector3(1.35, 1.4, 1.9), Vector3(0, 1.55, 0.9), black)
	MeshKit.box(st, Vector3(1.0, 0.4, 0.02), Vector3(0, 1.75, -0.06), Color(0.2, 0.22, 0.25))  # windshield
	_wheels(st, 0.72, [0.2, 1.6], 0.6, 0.06, Color(0.2, 0.2, 0.2))
	# SMV emblem: an orange triangle with a red border, facing backward (+Z).
	var back := Vector3(0, 1.45, 1.86)
	MeshKit.tri(st, back + Vector3(-0.4, -0.3, 0), back + Vector3(0.4, -0.3, 0), back + Vector3(0, 0.38, 0),
		Vector3.BACK, Color(0.85, 0.08, 0.05))
	back.z += 0.01
	MeshKit.tri(st, back + Vector3(-0.28, -0.22, 0), back + Vector3(0.28, -0.22, 0), back + Vector3(0, 0.26, 0),
		Vector3.BACK, Color(1.0, 0.45, 0.05))


static func _combine(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	# A combine on the road: the header out front is wider than the lane.
	var body := Color(0.13, 0.42, 0.14) if rng.randf() < 0.6 else Color(0.62, 0.08, 0.06)
	var yellow := Color(0.85, 0.72, 0.12)
	MeshKit.box(st, Vector3(4.2, 1.0, 1.6), Vector3(0, 1.0, -4.3), yellow)  # header
	MeshKit.box(st, Vector3(1.2, 0.8, 1.6), Vector3(0, 1.3, -3.0), body)  # feeder
	MeshKit.box(st, Vector3(3.0, 2.2, 5.6), Vector3(0, 2.1, 0.6), body)  # body
	MeshKit.box(st, Vector3(1.9, 1.3, 1.6), Vector3(0, 3.6, -1.6), GLASS)  # cab
	MeshKit.box(st, Vector3(2.0, 0.1, 1.7), Vector3(0, 4.3, -1.6), Color(0.9, 0.9, 0.88))
	MeshKit.box(st, Vector3(2.8, 1.0, 2.4), Vector3(0, 3.7, 1.2), body)  # grain tank
	MeshKit.cylinder(st, 0.18, 4.0, Vector3(-1.8, 3.8, 1.6), body, body, 6, Vector3(1, 0, -0.3).normalized())  # auger
	MeshKit.cylinder(st, 0.9, 0.6, Vector3(-1.45, 0.9, -1.4), TIRE, yellow, 10)
	MeshKit.cylinder(st, 0.9, 0.6, Vector3(1.45, 0.9, -1.4), TIRE, yellow, 10)
	MeshKit.cylinder(st, 0.55, 0.4, Vector3(-1.3, 0.55, 2.8), TIRE, yellow, 8)
	MeshKit.cylinder(st, 0.55, 0.4, Vector3(1.3, 0.55, 2.8), TIRE, yellow, 8)


static func _grain_truck(st: SurfaceTool, paint: Color) -> void:
	# A straight truck with a grain box and a rolled tarp.
	MeshKit.box(st, Vector3(2.4, 1.4, 2.2), Vector3(0, 1.5, -3.6), paint)  # cab
	MeshKit.box(st, Vector3(2.3, 0.9, 1.6), Vector3(0, 2.6, -3.4), GLASS)
	MeshKit.box(st, Vector3(2.4, 0.8, 1.2), Vector3(0, 1.0, -4.9), paint.darkened(0.2))  # hood
	MeshKit.box(st, Vector3(2.5, 1.5, 6.4), Vector3(0, 2.1, 1.4), Color(0.70, 0.12, 0.10))  # grain box
	MeshKit.box(st, Vector3(2.52, 0.12, 6.4), Vector3(0, 2.9, 1.4), Color(0.25, 0.27, 0.22))  # tarp
	_wheels(st, 1.0, [-3.8, 1.3, 2.7], 0.5, 0.35)


static func _snowplow(st: SurfaceTool) -> void:
	# A county plow truck: orange, angled blade in front, wing plow on the right.
	var orange := Color(0.95, 0.45, 0.06)
	var steel := Color(0.35, 0.36, 0.38)
	MeshKit.box(st, Vector3(2.5, 1.5, 2.4), Vector3(0, 1.6, -2.8), orange)  # cab
	MeshKit.box(st, Vector3(2.4, 0.9, 1.7), Vector3(0, 2.75, -2.6), GLASS)
	MeshKit.box(st, Vector3(2.5, 0.9, 1.3), Vector3(0, 1.1, -4.2), orange)  # hood
	MeshKit.box(st, Vector3(2.6, 1.6, 5.0), Vector3(0, 2.0, 1.9), orange)  # dump box (salt)
	MeshKit.box(st, Vector3(3.4, 1.1, 0.2), Vector3(0, 0.75, -5.1), steel, 0.35)  # blade
	MeshKit.box(st, Vector3(0.15, 0.7, 3.0), Vector3(1.6, 0.6, -0.5), steel)  # wing
	_wheels(st, 1.0, [-3.6, 1.0, 2.6], 0.5, 0.35)


static func _tractor(st: SurfaceTool) -> void:
	# Tractor in front (-Z) pulling a wagon of small square bales.
	var green := Color(0.13, 0.42, 0.14)
	MeshKit.box(st, Vector3(1.0, 1.0, 2.0), Vector3(0, 1.3, -3.6), green)  # hood
	MeshKit.box(st, Vector3(1.6, 1.4, 1.5), Vector3(0, 2.3, -2.2), GLASS)  # cab
	MeshKit.box(st, Vector3(1.65, 0.1, 1.55), Vector3(0, 3.05, -2.2), green)
	MeshKit.cylinder(st, 0.85, 0.5, Vector3(-0.95, 0.85, -2.1), TIRE, Color(0.85, 0.75, 0.1), 10)
	MeshKit.cylinder(st, 0.85, 0.5, Vector3(0.95, 0.85, -2.1), TIRE, Color(0.85, 0.75, 0.1), 10)
	MeshKit.cylinder(st, 0.45, 0.3, Vector3(-0.75, 0.45, -4.2), TIRE, Color(0.85, 0.75, 0.1), 8)
	MeshKit.cylinder(st, 0.45, 0.3, Vector3(0.75, 0.45, -4.2), TIRE, Color(0.85, 0.75, 0.1), 8)
	MeshKit.box(st, Vector3(0.1, 0.1, 1.2), Vector3(0, 0.6, -0.8), Color(0.2, 0.2, 0.2))  # hitch
	MeshKit.box(st, Vector3(2.3, 0.2, 4.8), Vector3(0, 0.9, 2.2), Color(0.45, 0.33, 0.2))  # wagon bed
	var straw := Color(0.82, 0.72, 0.42)
	for row in 3:
		for z in [0.6, 1.7, 2.8, 3.9]:
			for x in [-0.6, 0.6]:
				MeshKit.box(st, Vector3(1.1, 0.4, 1.0), Vector3(x, 1.2 + row * 0.42, z), straw.darkened(0.06 * ((row + int(z)) % 3)))
	_wheels(st, 0.95, [0.6, 3.8], 0.4, 0.25)
