class_name Cockpit
extends Node3D
## The inside of the player's car, for the in-car view: the dash with its instrument
## cluster and radio, a steering wheel that turns with the front wheels, the roof lining,
## pillars and window frames, the sun visors and the rear-view mirror, and the door panels.
## Fitted to each car's own body (CarModel.cabin_points and CarModel.interior): the lining
## is the greenhouse's own shape turned inward, the dash runs right up to the hood's edge
## and the doors up to the bottom of the windows, so there's nowhere to see out through
## the bodywork. It hangs off the body, so it leans with it and the view stays put
## behind the dash.
##
## The gauges (Gauges) are drawn into a texture each frame while the view is on: speed,
## revs, fuel (it runs down on the way to Iowa City, fastest in the Windstar), engine
## temperature (it warms up, and climbs as the car gets beaten up), warning lights, the
## odometer and trip, the gear, the dash clock and what the radio's playing.

const FOV := 64.0  ## the in-car view's field of view (narrower than outside, so the gauges read)
const EYE_PITCH_DEG := -8.0  ## looking a little down the road
const EYE_TO_DASH := 0.62  ## from the driver's eyes forward to the face of the dash
const DASH_BELOW_EYE := 0.19  ## and down to the top of it
const WHEEL_AT := Vector3(0.0, -0.32, -0.44)  ## the steering wheel's hub, from the driver's eyes
const WHEEL_TILT_DEG := 24.0  ## its top leans this far toward the dash
const WHEEL_RATIO := 13.0  ## the steering wheel turns this many times as far as the front wheels
const WHEEL_RADIUS := 0.19
const CLUSTER_WIDTH := 0.52
const COWL_LAP := 0.004  ## the dash's top edge sits this far over the hood's back edge
const SILL_LAP := 0.01  ## and the doors' tops this far up the bottom of the windows
const IDLE_RPM := 750.0
const CARS := {
	"windstar": {"redline": 5800.0, "odometer": 142318.0, "thirst": 0.72, "trim": Color(0.33, 0.35, 0.39)},
	"tercel": {"redline": 6500.0, "odometer": 213907.0, "thirst": 0.38, "trim": Color(0.14, 0.14, 0.15)},
	"legend": {"redline": 6800.0, "odometer": 168442.0, "thirst": 0.6, "trim": Color(0.22, 0.20, 0.19)},
}
const LINING := Color(0.66, 0.62, 0.55)
const WOOD := Color(0.42, 0.24, 0.11)

## The dash clock at the start of a run, in minutes after midnight (Main sets it for the
## conditions), and what the radio says (Main passes on what's playing).
static var clock_start := 16 * 60 + 12
static var clock_since := 0
static var radio_text := "FM 94.1  KRNA"

var eye := Transform3D()  ## the driver's eyes in the body's space: the camera goes here
var gauges: Gauges
var active := false:
	set(value):
		active = value
		visible = value
		if _viewport:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
var _viewport: SubViewport
var _screens: Array = []  ## [the quad, the part of the gauges' texture on it, its size in meters]
var _wheel_spin: Node3D
var _engine: EngineSound
var _warm := 0.0
var _spec: Dictionary


func build(stats: CarStats) -> void:
	set_meta("no_clip_check", true)  # ModelCheck: nothing in here can touch a tire
	_spec = CARS.get(stats.id, CARS.legend)
	var cabin := CarModel.cabin_points(stats)
	var inside := CarModel.interior(stats)
	var minivan := stats.style == "minivan"
	var z_ws: float = cabin.windshield_base.x  # the bottom of the windshield
	var y_ws: float = cabin.windshield_base.y
	var z_rf: float = cabin.roof_front.x  # the top of it, where the roof starts
	var y_roof: float = cabin.roof_front.y
	var belt_back: Vector2 = cabin.belt_back
	# The driver's eyes, on the left, and everything else from there.
	var w := stats.body_size.x
	var x_d := -w * 0.21
	var y_eye := y_roof - (0.31 if minivan else 0.25)
	var z_eye := z_rf + (0.36 if minivan else 0.28)
	eye = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(EYE_PITCH_DEG)), Vector3(x_d, y_eye, z_eye))
	var z_face := z_eye - EYE_TO_DASH
	var y_top := y_eye - DASH_BELOW_EYE
	var y_floor := y_top - 0.62
	var z_back := z_eye + 0.9
	var side_in := w / 2.0 - 0.1  # the inside of the doors
	var cowl: PackedVector3Array = inside.cowl
	var wide := absf(cowl[0].x)  # the body's half width where the dash meets the hood
	var trim: Color = _spec.trim
	var dark := trim.darkened(0.35)
	# The beltline (the bottom of the side windows), from the windshield back.
	var belt := func(z: float) -> float:
		return lerpf(y_ws, belt_back.y, clampf((z - z_ws) / (belt_back.x - z_ws), 0.0, 1.0))

	var st := MeshKit.begin()
	# The greenhouse from the inside: its roof lining, pillars and window frames, the
	# body's own shape turned inward.
	var lining: PackedVector3Array = inside.lining
	for t in range(0, lining.size(), 3):
		var n := (lining[t + 2] - lining[t]).cross(lining[t + 1] - lining[t])
		var roof := n.normalized().y < -0.4 and (lining[t] + lining[t + 1] + lining[t + 2]).z / 3.0 > z_rf - 0.01
		MeshKit.tri(st, lining[t], lining[t + 1], lining[t + 2], n, LINING if roof else trim)
	# The dash: its top runs from the gauges right up to the hood's edge at the bottom of
	# the windshield, all the way across, so there's no seeing in under the hood; then the
	# face with the gauges and the radio, and below that the part your knees go under.
	for k in cowl.size() - 1:
		var a := cowl[k] + Vector3(0, COWL_LAP, 0)
		var b := cowl[k + 1] + Vector3(0, COWL_LAP, 0)
		MeshKit.quad(st, Vector3(a.x, y_top, z_face), Vector3(b.x, y_top, z_face), b, a, Vector3.UP, trim.darkened(0.2))
	MeshKit.box(st, Vector3(wide * 2.0, 0.3, 0.1), Vector3(0, y_top - 0.15, z_face - 0.05), trim)
	MeshKit.box(st, Vector3(wide * 2.0, y_top - 0.3 - y_floor, 0.1), Vector3(0, (y_top - 0.3 + y_floor) / 2.0, z_face - 0.14),
		trim.darkened(0.1))
	if stats.id == "legend":  # a strip of wood across the passenger's side
		MeshKit.box(st, Vector3(side_in - 0.2, 0.04, 0.01), Vector3((side_in + 0.2) / 2.0, y_top - 0.11, z_face + 0.005), WOOD)
	MeshKit.box(st, Vector3(side_in - 0.32, 0.15, 0.01), Vector3((side_in + 0.26) / 2.0, y_top - 0.23, z_face + 0.004),
		trim.darkened(0.08))  # the glovebox
	for x: float in [-side_in + 0.08, side_in - 0.08]:  # the vents at the ends
		MeshKit.box(st, Vector3(0.1, 0.06, 0.01), Vector3(x, y_top - 0.06, z_face + 0.004), dark)
	# The binnacle over the gauges: a hood and its sides.
	MeshKit.box(st, Vector3(CLUSTER_WIDTH + 0.08, 0.03, 0.12), Vector3(x_d, y_top + 0.03, z_face + 0.02), dark)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.03, 0.23, 0.11), Vector3(x_d + side * (CLUSTER_WIDTH / 2.0 + 0.03), y_top - 0.08, z_face + 0.025), dark)
	# The center stack, just right of the gauges: the radio, vents, the heater's knobs.
	var x_stack := x_d + CLUSTER_WIDTH / 2.0 + 0.18
	MeshKit.box(st, Vector3(0.28, 0.42, 0.08), Vector3(x_stack, y_top - 0.22, z_face + 0.03), trim.darkened(0.25))
	for x: float in [-0.065, 0.065]:
		MeshKit.box(st, Vector3(0.11, 0.05, 0.01), Vector3(x_stack + x, y_top - 0.19, z_face + 0.075), Color(0.05, 0.05, 0.06))
	for x: float in [-0.08, 0.0, 0.08]:
		MeshKit.box(st, Vector3(0.04, 0.04, 0.025), Vector3(x_stack + x, y_top - 0.3, z_face + 0.08), Color(0.12, 0.12, 0.13))
	# The floor, from under the dash back, and the console between the seats.
	var z_toe := z_face - 0.3
	MeshKit.box(st, Vector3(wide * 2.0, 0.02, z_back - z_toe), Vector3(0, y_floor, (z_toe + z_back) / 2.0), Color(0.12, 0.12, 0.13))
	MeshKit.box(st, Vector3(0.24, 0.22, z_back - z_face - 0.4), Vector3(0.0, y_floor + 0.11, (z_face + z_back + 0.4) / 2.0), dark)
	# The doors, up to the bottom of the windows and out over the top of the body's side
	# (the sill), with armrests.
	for side: float in [-1.0, 1.0]:
		var top_front: float = belt.call(z_face) + SILL_LAP
		var top_back: float = belt.call(z_back) + SILL_LAP
		var out := side * (CarModel.body_half_width(stats, maxf(top_front, top_back)) + 0.01)
		MeshKit.quad(st, Vector3(side * side_in, y_floor, z_face), Vector3(side * side_in, y_floor, z_back),
			Vector3(side * side_in, top_back, z_back), Vector3(side * side_in, top_front, z_face), Vector3(-side, 0, 0), trim)
		MeshKit.quad(st, Vector3(side * side_in, top_front, z_face), Vector3(side * side_in, top_back, z_back),
			Vector3(out, top_back, z_back), Vector3(out, top_front, z_face), Vector3.UP, trim.darkened(0.1))
		# The kick panel, under the dash ahead of the door.
		MeshKit.box(st, Vector3(wide - side_in + 0.02, y_top - 0.3 - y_floor, z_face - z_toe),
			Vector3(side * (side_in + wide) / 2.0, (y_top - 0.3 + y_floor) / 2.0, (z_face + z_toe) / 2.0), trim.darkened(0.1))
		var arm_y: float = minf(belt.call(z_eye) - 0.12, y_top - 0.2)
		MeshKit.box(st, Vector3(0.07, 0.05, 0.5), Vector3(side * (side_in - 0.02), arm_y, z_eye - 0.05), trim.darkened(0.15))
	# Sun visors and the mirror, up against the roof lining.
	for side: float in [-1.0, 1.0]:
		var x := side * w * 0.22
		var y := _lining_y(lining, x, z_rf + 0.12, y_roof)
		MeshKit.box(st, Vector3(0.42, 0.02, 0.17), Vector3(x, y - 0.025, z_rf + 0.12), LINING.darkened(0.1))
	var mirror := Vector3(0.0, y_eye + 0.1, z_eye - 0.46)
	var glass_y := _lining_y(inside.glass, 0.0, mirror.z - 0.03, mirror.y)
	_beam(st, mirror + Vector3(0, 0.02, -0.01), Vector3(0.0, glass_y, mirror.z - 0.03), 0.025, dark)
	MeshKit.box(st, Vector3(0.23, 0.065, 0.03), mirror, Color(0.1, 0.1, 0.11))
	MeshKit.box(st, Vector3(0.21, 0.05, 0.005), mirror + Vector3(0, 0, 0.016), Color(0.3, 0.34, 0.38))
	var shell := MeshInstance3D.new()
	shell.mesh = MeshKit.finish(st)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)

	# The steering wheel: a rim, a hub and three spokes, tipped toward the dash, on its
	# column.
	var column := Node3D.new()
	column.position = Vector3(x_d, y_eye, z_eye) + WHEEL_AT
	column.rotation.x = deg_to_rad(-WHEEL_TILT_DEG)
	add_child(column)
	var cs := MeshKit.begin()
	_beam(cs, Vector3(0, 0, -0.03), Vector3(0, 0, -0.42), 0.07, dark)
	var column_mesh := MeshInstance3D.new()
	column_mesh.mesh = MeshKit.finish(cs)
	column_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.add_child(column_mesh)
	_wheel_spin = Node3D.new()
	column.add_child(_wheel_spin)
	var ws := MeshKit.begin()
	var grip := Color(0.08, 0.08, 0.09)
	_ring(ws, WHEEL_RADIUS, 0.015, grip)
	MeshKit.box(ws, Vector3(0.11, 0.085, 0.05), Vector3.ZERO, trim.darkened(0.4))
	for spoke: Vector3 in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0)]:
		MeshKit.box(ws, Vector3(0.14 if spoke.y == 0 else 0.03, 0.03 if spoke.y == 0 else 0.13, 0.02),
			spoke * 0.11, trim.darkened(0.3))
	var wheel_mesh := MeshInstance3D.new()
	wheel_mesh.mesh = MeshKit.finish(ws)
	wheel_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel_spin.add_child(wheel_mesh)

	# The gauges, drawn into a texture, on the cluster and the radio.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(Gauges.SIZE)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	gauges = Gauges.new()
	gauges.car_id = stats.id if CARS.has(stats.id) else "legend"
	_viewport.add_child(gauges)
	var screen := StandardMaterial3D.new()
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.albedo_texture = _viewport.get_texture()
	var cluster_size := Vector2(CLUSTER_WIDTH, CLUSTER_WIDTH * Gauges.CLUSTER.size.y / Gauges.CLUSTER.size.x)
	_screen(Gauges.CLUSTER, cluster_size, screen, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)),
		Vector3(x_d, y_top - 0.005 - cluster_size.y / 2.0, z_face + 0.022)))
	var radio_size := Vector2(0.22, 0.22 * Gauges.RADIO.size.y / Gauges.RADIO.size.x)
	_screen(Gauges.RADIO, radio_size, screen, Transform3D(Basis.IDENTITY, Vector3(x_stack, y_top - 0.07, z_face + 0.075)))
	active = false


## Point the gauges, the wheel and the lights at what the car's doing.
func update(car: Car, delta: float) -> void:
	_read(car, car.forward_speed(), delta)


## The same, with the car's forward speed (m/s) given.
func _read(car: Car, speed: float, delta: float) -> void:
	if _engine == null:
		for child in car.get_children():
			if child is EngineSound:
				_engine = child
	_warm = minf(_warm + delta / 45.0, 1.0)
	_wheel_spin.rotation.z = car.steer_angle * WHEEL_RATIO
	var g := gauges
	g.speed_mph = absf(speed) * Hud.MPH
	var revs := _engine.rpm_fraction() if _engine else 0.15
	g.rpm = lerpf(IDLE_RPM, _spec.redline, clampf((revs - 0.15) / 0.85, 0.0, 1.0))
	var finish := car.route.mile_at(car.route.finish_station)
	var progress := clampf(car.route.mile_at(car.station) / finish, 0.0, 1.0)
	g.fuel = 0.88 - float(_spec.thirst) * progress
	var health := car.health / car.stats.durability
	g.temp = lerpf(0.12, 0.5, _warm) + maxf(0.55 - health, 0.0) * 0.8 + (0.08 if car.boost.active else 0.0)
	g.oil = lerpf(0.25, 0.8, clampf((revs - 0.15) / 0.85, 0.0, 1.0)) * (1.0 if health > 0.2 else 0.4)
	g.trip = maxf(car.route.mile_at(car.station), 0.0)
	g.odometer = float(_spec.odometer) + g.trip
	g.gear = "R" if speed < -0.3 else "D"
	g.lights = {"check": health < 0.6, "brake": car.handbrake, "beam": car.headlights, "boost": car.boost.active,
		"fuel": g.fuel < 0.2}
	var minutes := clock_start + int((Time.get_ticks_msec() - clock_since) / 60000)
	var hour := (minutes / 60) % 12
	g.clock = "%d:%02d" % [12 if hour == 0 else hour, minutes % 60]
	g.radio = radio_text
	g.queue_redraw()


## The quads the gauges show on (the cluster and the radio).
func screens() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for screen: Array in _screens:
		out.append(screen[0])
	return out


## Where a point of the gauges' texture shows on the dash, in the body's space.
func gauge_point(p: Vector2) -> Vector3:
	for screen: Array in _screens:
		var region: Rect2 = screen[1]
		if region.has_point(p):
			var size: Vector2 = screen[2]
			var f := (p - region.get_center()) / region.size
			return (screen[0] as Node3D).transform * Vector3(f.x * size.x, -f.y * size.y, 0.0)
	return Vector3.INF


## A quad showing `region` of the gauges texture, `size` meters, facing +Z (the driver).
func _screen(region: Rect2, size: Vector2, material: Material, xf: Transform3D) -> MeshInstance3D:
	var u0 := region.position / Gauges.SIZE
	var u1 := region.end / Gauges.SIZE
	var h := size / 2.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-h.x, h.y, 0), Vector3(h.x, h.y, 0), Vector3(h.x, -h.y, 0), Vector3(-h.x, -h.y, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u0.x, u0.y), Vector2(u1.x, u0.y), Vector2(u1.x, u1.y), Vector2(u0.x, u1.y)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = xf
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_screens.append([node, region, size])
	return node


## How high the roof lining (or the glass) is over (x, z): the lowest bit of it above `from`.
static func _lining_y(lining: PackedVector3Array, x: float, z: float, from: float) -> float:
	var best := INF
	var start := Vector3(x, from - 1.0, z)
	for t in range(0, lining.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(start, Vector3.UP, lining[t], lining[t + 1], lining[t + 2])
		if hit != null and hit.y > from - 0.2:
			best = minf(best, hit.y)
	return best if best < INF else from


## A rim of `radius` in the XY plane, `thickness` round (an octagon swept round).
static func _ring(st: SurfaceTool, radius: float, thickness: float, color: Color) -> void:
	const AROUND := 40
	const SIDES := 8
	for i in AROUND:
		for k in SIDES:
			var corners: Array[Vector3] = []
			for c: Array in [[i, k], [i + 1, k], [i + 1, k + 1], [i, k + 1]]:
				var a: float = TAU * c[0] / AROUND
				var b: float = TAU * c[1] / SIDES
				var out := Vector3(cos(a), sin(a), 0.0)
				corners.append(out * (radius + cos(b) * thickness) + Vector3(0, 0, sin(b) * thickness))
			var mid := TAU * (i + 0.5) / AROUND
			var center := Vector3(cos(mid), sin(mid), 0.0) * radius
			var outward := ((corners[0] + corners[2]) / 2.0 - center).normalized()
			MeshKit.quad(st, corners[0], corners[1], corners[2], corners[3], outward, color)


## A square bar `thickness` across from `a` to `b`.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var along := b - a
	var z := along.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := x.cross(z).normalized()
	var h := thickness / 2.0
	var corners := [a + (x + y) * h, a + (x - y) * h, a + (-x - y) * h, a + (-x + y) * h]
	for i in 4:
		var p: Vector3 = corners[i]
		var q: Vector3 = corners[(i + 1) % 4]
		var outward := ((p + q) / 2.0 - a).normalized()
		MeshKit.quad(st, p, q, q + along, p + along, outward, color)

