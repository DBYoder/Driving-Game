class_name CarModel
extends Node3D
## Low-poly model of one of the three cars: side outlines extruded across the car
## (CarStats.style picks the minivan, compact or sedan shape), wheels that steer and
## spin, and a blob shadow (no real-time shadows on a potato). The body leans out of
## corners and dips under braking more than the physics does, to sell the weight.
##
## The wheels sit in arches cut through the body, with dark wheel wells behind them.
## Each arch is sized from the car's tires, suspension and lean so a tire never passes
## through the bodywork: steered to full lock, pushed up as far as it's drawn going
## (VISUAL_BUMP over its resting height), with the body leaned out as far as it's drawn
## leaning, and dented in from anywhere (dents don't reach into the arches).
## ModelCheck sweeps all of that in the tests and watches it live in the QA runs.
##
## Damage shows three ways: the paint dulls and smoke pours out when it's bad, the body
## dents in where it was hit, and each car loses its own parts, nearest the hit first:
## the Windstar's hubcaps and sliding door fly off, the Tercel sheds its mirrors and
## bumpers, and the Legend's hood and trunk lid pop open and flap (the hood goes in the
## end).

signal part_lost(body: RigidBody3D)  ## a piece came off; it's a physics body now

const GLASS := Color(0.10, 0.13, 0.16)
const TRIM := Color(0.08, 0.08, 0.08)
const TIRE := Color(0.06, 0.06, 0.06)
const HUB := Color(0.62, 0.63, 0.65)
const BAY := Color(0.10, 0.10, 0.10)  ## under the hood and trunk lid
const HEADLIGHT := Color(1.0, 0.95, 0.75)
const TAILLIGHT := Color(0.75, 0.05, 0.05)
const MAX_DENT := 0.3  ## meters any point of the body can be pushed in
const DENT_RADIUS := 1.3  ## meters around the hit that give
const EDGE_STEP := 0.45  ## outline edges are split this fine, so dents have something to bend
const TIRE_WIDTH := 0.22
const WHEEL_REACH := 0.125  ## the tire's half width plus a Windstar hubcap
const VISUAL_BUMP := 0.04  ## the wheels are drawn at most this far above where they rest...
const ARCH_SIDE := 0.05  ## ...and the arches clear them by this much fore and aft
const ARCH_TOP := 0.03  ## and this much above, with everything else at its worst
const PITCH_MAX_DEG := 1.0  ## the body dips under braking (squats under power) at most this far

## Outlines seen from the right side, going around: [fraction of the length from the
## front bumper, height above the body origin, what the edge to the next point is].
## "cabin" outlines are the greenhouse, narrower at the roof than at the beltline.
const SHAPES := {
	"minivan": {
		"body": [[0.0, -0.32, "paint"], [0.0, 0.06, "paint"], [0.025, 0.16, "paint"], [0.19, 0.29, "paint"],
			[1.0, 0.31, "paint"], [1.0, -0.32, "trim"], [0.88, -0.40, "paint"], [0.12, -0.40, "trim"]],
		"cabin": [[0.19, 0.29, "glass"], [0.37, 1.0, "paint"], [0.975, 1.0, "glass"], [1.0, 0.31, "paint"]],
		"roof_taper": 0.84,
	},
	"compact": {
		"body": [[0.0, -0.28, "paint"], [0.0, 0.06, "paint"], [0.03, 0.14, "paint"], [0.27, 0.22, "paint"],
			[0.79, 0.24, "paint"], [0.97, 0.22, "paint"], [1.0, 0.10, "paint"], [1.0, -0.28, "trim"],
			[0.88, -0.36, "paint"], [0.12, -0.36, "trim"]],
		"cabin": [[0.27, 0.22, "glass"], [0.43, 0.74, "paint"], [0.70, 0.74, "glass"], [0.83, 0.24, "paint"]],
		"roof_taper": 0.80,
	},
	"cruiser": {
		"body": [[0.0, -0.30, "paint"], [0.0, 0.08, "paint"], [0.02, 0.16, "paint"], [0.31, 0.24, "paint"],
			[0.72, 0.26, "paint"], [0.975, 0.24, "paint"], [1.0, 0.14, "paint"], [1.0, -0.30, "trim"],
			[0.85, -0.37, "paint"], [0.15, -0.37, "trim"]],
		"cabin": [[0.31, 0.24, "glass"], [0.43, 0.76, "paint"], [0.68, 0.76, "glass"], [0.80, 0.26, "paint"]],
		"roof_taper": 0.82,
	},
	"sedan": {
		"body": [[0.0, -0.30, "paint"], [0.0, 0.06, "paint"], [0.02, 0.13, "bay"], [0.31, 0.22, "paint"],
			[0.72, 0.24, "bay"], [0.975, 0.22, "paint"], [1.0, 0.12, "paint"], [1.0, -0.30, "trim"],
			[0.85, -0.37, "paint"], [0.15, -0.37, "trim"]],
		"cabin": [[0.31, 0.22, "glass"], [0.46, 0.70, "paint"], [0.67, 0.70, "glass"], [0.79, 0.24, "paint"]],
		"roof_taper": 0.80,
	},
}

var _stats: CarStats
var _paint: StandardMaterial3D
var _glass: StandardMaterial3D
var _lights: StandardMaterial3D
var _body: Node3D  ## everything that leans (not the wheels)
var _body_mesh: MeshInstance3D
var _floor_mesh: MeshInstance3D  ## the top of the body under the cabin (see show_cabin_floor)
var _rest := {}  ## surface -> PackedVector3Array as built
var _dents := {}  ## surface -> PackedVector3Array of offsets
var _colors := {}  ## surface -> PackedColorArray
var _parts: Array = []  ## {node, at, threshold, kind ("fly"/"hinge"), state}
var _wheel_pivots: Array[Node3D] = []
var _wheel_spinners: Array[Node3D] = []
var _shadow: MeshInstance3D
var _smoke: CPUParticles3D
var _beacons: Array[StandardMaterial3D] = []  ## a cruiser's red and blue lights
var _beacons_on := false
var _headlights: Array[SpotLight3D] = []
var _flame: MeshInstance3D  ## out of the tailpipe while boosting
var _boosting := false
var _lean := Vector2.ZERO  ## smoothed (roll, pitch) in radians
var _max_lean := Vector2.ZERO  ## (roll, pitch): the lean is kept inside this ellipse
var _static_spring := 0.0  ## the suspension's length at rest under the car's weight
var _arches: Array[Dictionary] = []  ## {z, top, half, center_y, x_in}: see _plan_wheels
var _time := 0.0
var _damage := 0.0


func build(stats: CarStats, wheels: Array) -> void:
	_stats = stats
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.albedo_color = stats.body_color
	_paint.roughness = 0.6
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = GLASS
	_glass.metallic = 0.2
	_glass.roughness = 0.35
	_lights = StandardMaterial3D.new()
	_lights.vertex_color_use_as_albedo = true
	_lights.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body = Node3D.new()
	add_child(_body)

	var shape: Dictionary = SHAPES.get(stats.style, SHAPES.sedan)
	var w := stats.body_size.x
	var l := stats.body_size.z
	_plan_wheels(stats)
	var surfaces := {"body": [PackedVector3Array(), PackedColorArray()], "glass": [PackedVector3Array(), PackedColorArray()],
		"lights": [PackedVector3Array(), PackedColorArray()], "floor": [PackedVector3Array(), PackedColorArray()]}
	var lower := _cut_arches(_outline(shape.body, l))
	var cabin: Array = shape.cabin
	var under_cabin := Vector2(-l / 2.0 + float(cabin[0][0]) * l, -l / 2.0 + float(cabin[cabin.size() - 1][0]) * l)
	_extrude(surfaces, lower, w / 2.0, w / 2.0, under_cabin)
	_extrude(surfaces, _outline(shape.cabin, l), w / 2.0 * 0.96, w / 2.0 * shape.roof_taper)
	_wheel_wells(surfaces, lower)
	_details(surfaces, stats.style, w, l)
	for s in surfaces:
		_rest[s] = surfaces[s][0]
		_colors[s] = surfaces[s][1]
		var offsets := PackedVector3Array()
		offsets.resize(surfaces[s][0].size())
		_dents[s] = offsets
	_body_mesh = MeshInstance3D.new()
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_body_mesh)
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_floor_mesh)
	_rebuild_body()

	_build_wheels(stats, wheels)
	_build_parts(stats, w, l)
	if stats.style == "cruiser":
		_build_light_bar(stats, w, l)
	_smoke = _make_smoke(l)
	_body.add_child(_smoke)
	_flame = _make_flame()
	_flame.set_meta("no_clip_check", true)  # fire, not bodywork
	_body.add_child(_flame)
	_shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w * 1.25, l * 1.1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = quad
	_shadow.material_override = _shadow_material()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


## 0 = showroom, 1 = totaled: the paint goes dull and dark, smoke pours out when it's bad,
## and parts come off (or open) as it passes each one's threshold, the one nearest
## `local_hit` (where the car was hit, in its own space) first.
func set_damage(amount: float, local_hit := Vector3.ZERO) -> void:
	_damage = clampf(amount, 0.0, 1.0)
	_paint.albedo_color = _stats.body_color.lerp(Color(0.12, 0.1, 0.09), _damage * 0.7)
	_smoke.emitting = _damage > 0.6
	var due := 0
	for part in _parts:
		if _damage >= part.threshold:
			due += 1
	var done := _parts.filter(func(p): return p.state != "on").size()
	while done < due:
		# Whatever's nearest the hit goes, but a hood has to be open before it can tear off.
		var candidates := _parts.filter(func(p): return p.state == "on" and (not p.has("after") or p.after.state == "open"))
		if candidates.is_empty():
			break
		candidates.sort_custom(func(a, b): return a.at.distance_to(local_hit) < b.at.distance_to(local_hit))
		_break(candidates[0])
		done += 1


## Push the body in around where it was hit: `local_dir` points from the middle of the
## car toward the hit, `amount` is the share of the car's health it cost.
func dent(local_dir: Vector3, amount: float) -> void:
	var d := Vector3(local_dir.x, 0.0, local_dir.z)
	if d.length() < 0.01 or amount <= 0.0:
		return
	d = d.normalized()
	var half := Vector2(_stats.body_size.x, _stats.body_size.z) / 2.0
	var reach := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.z), 0.001))
	var at := d * reach + Vector3.UP * 0.1
	var depth := clampf(amount * 0.9, 0.0, 0.2)
	for s in _rest:
		var rest: PackedVector3Array = _rest[s]
		var offsets: PackedVector3Array = _dents[s]
		for i in rest.size():
			var f := 1.0 - smoothstep(0.0, DENT_RADIUS, (rest[i] + offsets[i]).distance_to(at))
			f *= smoothstep(0.03, 0.3, _arch_distance(rest[i]))  # the arches keep their shape
			if f > 0.0:
				offsets[i] = (offsets[i] - (d + Vector3.DOWN * 0.2) * depth * f).limit_length(MAX_DENT)
		_dents[s] = offsets
	_rebuild_body()


## Per frame: wheels follow the suspension, the body leans with the car's acceleration
## (`accel` in the car's own space, m/s²), and loose lids flap with speed.
func update(wheels: Array, steer_angle: float, accel: Vector3, speed: float, delta: float) -> void:
	_time += delta
	var ground_y := 0.0
	var grounded := 0
	for i in wheels.size():
		var wheel: Car.Wheel = wheels[i]
		var pivot := _wheel_pivots[i]
		pivot.position = wheel.mount - Vector3(0, maxf(wheel.spring_length, _static_spring - VISUAL_BUMP), 0)
		pivot.rotation.y = steer_angle if wheel.front else 0.0
		_wheel_spinners[i].rotation.x = -wheel.spin
		if wheel.grounded:
			ground_y += pivot.position.y - _stats.wheel_radius
			grounded += 1
	_shadow.visible = grounded > 0
	if grounded > 0:
		_shadow.position = Vector3(0, ground_y / grounded + 0.03, 0)
	# Lean out of the turn, dip under braking (only while on the ground).
	var g := 9.8
	var target := Vector2(accel.x / g * deg_to_rad(_stats.body_lean_deg), -accel.z / g * deg_to_rad(1.5))
	if grounded == 0:
		target = Vector2.ZERO
	var reach := pow(target.x / _max_lean.x, 2.0) + pow(target.y / _max_lean.y, 2.0)
	if reach > 1.0:
		target /= sqrt(reach)
	_lean = _lean.lerp(target, 1.0 - exp(-delta * 6.0))
	_body.rotation = Vector3(_lean.y, 0.0, _lean.x)
	if not _beacons.is_empty():
		var flash := fmod(_time, 0.5) < 0.25
		_beacons[0].albedo_color = Color(1.0, 0.1, 0.1) if _beacons_on and flash else Color(0.35, 0.05, 0.05)
		_beacons[1].albedo_color = Color(0.15, 0.3, 1.0) if _beacons_on and not flash else Color(0.05, 0.08, 0.3)
	_flame.visible = _boosting
	if _boosting:
		var flicker := 0.75 + 0.25 * sin(_time * 53.0) * sin(_time * 31.0 + 1.0)
		var length := (1.1 + clampf(speed / 60.0, 0.0, 1.0) * 0.9) * flicker
		_flame.scale = Vector3(1.0, length, 1.0)
		_flame.position = Vector3(_stats.body_size.x * 0.28, -0.3, _stats.body_size.z / 2.0 + length / 2.0)
	for part in _parts:
		if part.state == "open":
			var flap: float = sin(_time * (7.0 + speed * 0.2) + part.at.z) * clampf(speed / 30.0, 0.0, 1.0)
			part.node.rotation.x = part.open_angle * (0.75 + 0.25 * flap)


## For ModelCheck: the wheels' pivots (steered, at the suspension's height), the tire
## size, and the node everything that leans hangs off.
func wheel_pivots() -> Array[Node3D]:
	return _wheel_pivots


func wheel_radius() -> float:
	return _stats.wheel_radius


func body_node() -> Node3D:
	return _body


## The in-car view hides the top of the body under the cabin: from the driver's seat
## it'd be a floor at window-sill height, over the dash and the gauges. The Cockpit
## draws the inside of the car there instead.
func show_cabin_floor(on: bool) -> void:
	_floor_mesh.visible = on


## A flame out of the tailpipe while the boost burns.
func set_boost(on: bool) -> void:
	_boosting = on


## A cruiser's lights: flashing red and blue while it's chasing someone.
func set_beacons(on: bool) -> void:
	_beacons_on = on


## Two headlight beams down the road (night).
func set_headlights(on: bool) -> void:
	for light in _headlights:
		light.queue_free()
	_headlights.clear()
	if not on or _stats == null:
		return
	var w := _stats.body_size.x
	var l := _stats.body_size.z
	for side: float in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.position = Vector3(side * w * 0.3, -0.05, -l / 2.0 - 0.05)
		beam.rotation_degrees = Vector3(-3.5, 0, 0)
		beam.spot_range = 110.0
		beam.spot_angle = 30.0
		beam.spot_attenuation = 0.6
		beam.light_energy = 11.0
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.shadow_enabled = false
		_body.add_child(beam)
		_headlights.append(beam)


## The light bar on the roof and SHERIFF on the doors.
func _build_light_bar(stats: CarStats, w: float, l: float) -> void:
	var roof_y: float = SHAPES.cruiser.cabin[1][1]
	var roof_z := -l / 2.0 + l * 0.52
	var base := [PackedVector3Array(), PackedColorArray()]
	_box(base, Vector3(w * 0.7, 0.06, 0.28), Vector3(0, roof_y + 0.03, roof_z), TRIM)
	_body.add_child(_mesh_of(base, _flat(Color.WHITE)))
	for side: float in [-1.0, 1.0]:
		var lamp := [PackedVector3Array(), PackedColorArray()]
		_box(lamp, Vector3(w * 0.32, 0.12, 0.24), Vector3(side * w * 0.17, roof_y + 0.12, roof_z), Color.WHITE)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beacons.append(m)
		_body.add_child(_mesh_of(lamp, m))
	var push_bar := [PackedVector3Array(), PackedColorArray()]
	_box(push_bar, Vector3(w * 0.6, 0.35, 0.08), Vector3(0, -0.12, -l / 2.0 - 0.12), TRIM)
	_body.add_child(_mesh_of(push_bar, _flat(Color.WHITE)))
	var dark := stats.body_color.get_luminance() < 0.5
	for side: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = "SHERIFF"
		label.font_size = 64
		label.pixel_size = 0.005
		label.outline_size = 0
		label.modulate = Color(0.95, 0.8, 0.3) if dark else Color(0.1, 0.3, 0.2)
		label.double_sided = false
		label.position = Vector3(side * (w / 2.0 + 0.01), 0.02, 0.1)
		label.rotation.y = side * PI / 2.0
		label.visibility_range_end = 120.0
		_body.add_child(label)


func _rebuild_body() -> void:
	var meshes := {"body": ArrayMesh.new(), "floor": ArrayMesh.new()}
	for s in _rest:
		var rest: PackedVector3Array = _rest[s]
		if rest.is_empty():
			continue
		var offsets: PackedVector3Array = _dents[s]
		var verts := PackedVector3Array()
		verts.resize(rest.size())
		var normals := PackedVector3Array()
		normals.resize(rest.size())
		for i in rest.size():
			verts[i] = rest[i] + offsets[i]
		for t in range(0, verts.size(), 3):
			# Flat shading: each triangle's own normal (Godot's front faces are clockwise).
			var n := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
			normals[t] = n
			normals[t + 1] = n
			normals[t + 2] = n
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = _colors[s]
		var mesh: ArrayMesh = meshes.floor if s == "floor" else meshes.body
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, {"lights": _lights, "glass": _glass}.get(s, _paint))
	_body_mesh.mesh = meshes.body
	_floor_mesh.mesh = meshes.floor


## A side outline as points (z, y) and the kind of each edge to the next point.
static func _outline(outline: Array, length: float) -> Array:
	var points := PackedVector2Array()
	var kinds: Array[String] = []
	for p: Array in outline:
		points.append(Vector2(-length / 2.0 + p[0] * length, p[1]))
		kinds.append(p[2])
	return [points, kinds]


## Extrude a side outline ([points, kinds], as _outline makes) across the car: half
## width `half_low` at its lowest point narrowing to `half_high` at its highest. Glass
## goes in its own surface, and so does the top between `under_cabin` (z, front to back).
func _extrude(surfaces: Dictionary, outline: Array, half_low: float, half_high: float,
		under_cabin := Vector2(INF, -INF)) -> void:
	var corners: PackedVector2Array = outline[0]
	var corner_kinds: Array = outline[1]
	var points: Array[Vector2] = []  ## (z, y)
	var kinds: Array[String] = []
	for i in corners.size():
		var pa := corners[i]
		var pb := corners[(i + 1) % corners.size()]
		var pieces := maxi(1, ceili(pa.distance_to(pb) / EDGE_STEP))
		for k in pieces:
			points.append(pa.lerp(pb, float(k) / pieces))
			kinds.append(corner_kinds[i])
	var y_lo := INF
	var y_hi := -INF
	for p in points:
		y_lo = minf(y_lo, p.y)
		y_hi = maxf(y_hi, p.y)
	var half := func(y: float) -> float: return lerpf(half_low, half_high, clampf((y - y_lo) / maxf(y_hi - y_lo, 0.01), 0.0, 1.0))
	var at := func(p: Vector2, side: float) -> Vector3: return Vector3(side * half.call(p.y), p.y, p.x)

	# The two sides: the outline, triangulated.
	var flat := PackedVector2Array(points)
	var tris := Geometry2D.triangulate_polygon(flat)
	var side_kind := "glass" if kinds.has("glass") else "paint"
	for side: float in [-1.0, 1.0]:
		for t in range(0, tris.size(), 3):
			_tri(surfaces[_surface(side_kind)], at.call(points[tris[t]], side), at.call(points[tris[t + 1]], side),
				at.call(points[tris[t + 2]], side), Vector3(side, 0, 0), _color(side_kind))
	# Around the outline: a strip across the car for each edge, facing out of the
	# outline (by its winding, not toward its middle: the arches make it concave).
	var area := 0.0
	for i in points.size():
		area += points[i].cross(points[(i + 1) % points.size()])
	var turn := 1.0 if area > 0.0 else -1.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var edge := b - a
		var outward := Vector2(edge.y, -edge.x) * turn
		var normal := Vector3(0.0, outward.y, outward.x).normalized()
		var kind := kinds[i]
		var out: Array = surfaces[_surface(kind)]
		var mid := (a.x + b.x) / 2.0
		if normal.y > 0.7 and mid > under_cabin.x and mid < under_cabin.y:
			out = surfaces.floor
		_tri(out, at.call(a, -1.0), at.call(a, 1.0), at.call(b, 1.0), normal, _color(kind))
		_tri(out, at.call(a, -1.0), at.call(b, 1.0), at.call(b, -1.0), normal, _color(kind))



## Where the wheels sit and how big their arches are. A tire rests where the springs
## hold the car up; it's drawn at most VISUAL_BUMP above that. The body leans at most
## _max_lean (an ellipse of roll and pitch), which brings an arch down on its tire by
## up to `lean_dy`. Each arch is a stadium (a half disc on top of a slot running down
## off the bottom of the car), wide enough for the tire at full lock.
func _plan_wheels(stats: CarStats) -> void:
	_static_spring = stats.rest_length - clampf(stats.mass * 9.8 / (4.0 * stats.spring), 0.0, stats.rest_length * 0.7)
	_max_lean = Vector2(deg_to_rad(minf(stats.body_lean_deg, 4.0)), deg_to_rad(PITCH_MAX_DEG))
	var r := stats.wheel_radius
	var half_track := stats.track / 2.0
	var lean_dy := Vector2((half_track + WHEEL_REACH) * sin(_max_lean.x),
		(stats.wheelbase / 2.0 + r + ARCH_SIDE) * sin(_max_lean.y)).length()
	var rest_y := stats.mount_y - _static_spring
	var steer := deg_to_rad(stats.max_steer_deg)
	_arches.clear()
	for z: float in [-stats.wheelbase / 2.0, stats.wheelbase / 2.0]:
		var front := z < 0.0
		# A steered tire seen from the side is a little longer than it is round.
		var reach := maxf(r, r * cos(steer) + WHEEL_REACH * sin(steer)) if front else r
		var half := reach + ARCH_SIDE
		var top := rest_y + r + VISUAL_BUMP + lean_dy + ARCH_TOP
		# The inner wall of the wheel well: clear of the tire's inside edge at full lock.
		var x_in := half_track - WHEEL_REACH - (r * sin(steer) if front else 0.0) - 0.06
		_arches.append({"z": z, "top": top, "half": half, "center_y": top - half, "x_in": x_in})


## The stadium's outline (z, y), counterclockwise, running well below the car.
func _arch_polygon(arch: Dictionary) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var z: float = arch.z
	var half: float = arch.half
	var cy: float = arch.center_y
	poly.append(Vector2(z + half, -5.0))
	for i in 13:
		var a := PI * i / 12.0
		poly.append(Vector2(z + cos(a) * half, cy + sin(a) * half))
	poly.append(Vector2(z - half, -5.0))
	return poly


## How far a point (body space) is outside the nearest arch, in the side view (negative
## inside one).
func _arch_distance(p: Vector3) -> float:
	var best := INF
	for arch in _arches:
		var dz := absf(p.z - float(arch.z))
		var d: float
		if p.y <= float(arch.center_y):
			d = dz - float(arch.half)
		else:
			d = Vector2(dz, p.y - float(arch.center_y)).length() - float(arch.half)
		best = minf(best, d)
	return best


## The side outline with the arches cut out of its bottom. Edges along an arch are the
## dark inside of the wheel well; the rest keep the kind of the edge they lie on.
func _cut_arches(outline: Array) -> Array:
	var shape: PackedVector2Array = outline[0]
	for arch in _arches:
		var cut := Geometry2D.clip_polygons(shape, _arch_polygon(arch))
		if cut.size() == 1:
			shape = cut[0]
	var kinds: Array[String] = []
	var original: PackedVector2Array = outline[0]
	for i in shape.size():
		var mid := (shape[i] + shape[(i + 1) % shape.size()]) / 2.0
		var kind := "well"
		for k in original.size():
			var a := original[k]
			var b := original[(k + 1) % original.size()]
			if Geometry2D.get_closest_point_to_segment(mid, a, b).distance_to(mid) < 0.002:
				kind = outline[1][k]
				break
		kinds.append(kind)
	return [shape, kinds]


## The back walls of the wheel wells: a dark box between each pair of wheels filling
## the arch, so you can't see through the car from one wheel to the other.
func _wheel_wells(surfaces: Dictionary, lower: Array) -> void:
	var shape: PackedVector2Array = lower[0]
	for arch in _arches:
		var z: float = arch.z
		var half: float = arch.half
		# The bottom of the body just fore and aft of the arch.
		var bottom := INF
		for p in shape:
			if absf(p.x - z) < half + 0.2:
				bottom = minf(bottom, p.y)
		var x_in: float = arch.x_in
		var top: float = arch.top
		_box(surfaces.body, Vector3(x_in * 2.0, top - bottom, half * 2.0), Vector3(0, (top + bottom) / 2.0, z), BAY)

static func _surface(kind: String) -> String:
	return "glass" if kind == "glass" else "body"


## Vertex color, which the paint material multiplies by the paint color.
func _color(kind: String) -> Color:
	match kind:
		"trim":
			return TRIM
		"bay", "well":
			return BAY
		_:
			return Color.WHITE


## One flat triangle, wound to face `outward`.
static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	var verts: PackedVector3Array = out[0]
	var colors: PackedColorArray = out[1]
	for p in [a, b, c]:
		verts.append(p)
		colors.append(color)
	out[0] = verts
	out[1] = colors


static func _box(out: Array, size: Vector3, center: Vector3, color: Color) -> void:
	var h := size / 2.0
	for axis in 3:
		for side: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var f := center + n * h[axis]
			_tri(out, f - u - v, f + u - v, f + u + v, n, color)
			_tri(out, f - u - v, f + u + v, f - u + v, n, color)


## Bumpers and lights that stay put (the Tercel's bumpers come off, so they're parts).
func _details(surfaces: Dictionary, style: String, w: float, l: float) -> void:
	var body: Array = surfaces.body
	var lights: Array = surfaces.lights
	if style != "compact":
		_box(body, Vector3(w * 1.01, 0.18, 0.14), Vector3(0, -0.24, -l / 2.0), TRIM)
		_box(body, Vector3(w * 1.01, 0.18, 0.14), Vector3(0, -0.24, l / 2.0), TRIM)
	var lamp_y := 0.02 if style != "minivan" else 0.05
	for side: float in [-1.0, 1.0]:
		_box(lights, Vector3(0.36, 0.11, 0.04), Vector3(side * w * 0.33, lamp_y, -l / 2.0 - 0.01), HEADLIGHT)
		if style == "minivan":
			# Tall taillights up the back pillars.
			_box(lights, Vector3(0.10, 0.55, 0.04), Vector3(side * w * 0.44, 0.35, l / 2.0 + 0.01), TAILLIGHT)
		else:
			_box(lights, Vector3(0.42, 0.12, 0.04), Vector3(side * w * 0.32, lamp_y + 0.04, l / 2.0 + 0.01), TAILLIGHT)
		if style != "compact":
			_box(body, Vector3(0.10, 0.08, 0.16), Vector3(side * (w / 2.0 + 0.05), 0.36 if style == "minivan" else 0.30,
				-l / 2.0 + l * (0.21 if style == "minivan" else 0.33)), TRIM)  # mirrors


func _build_wheels(stats: CarStats, wheels: Array) -> void:
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = stats.wheel_radius
	tire_mesh.bottom_radius = stats.wheel_radius
	tire_mesh.height = TIRE_WIDTH
	tire_mesh.radial_segments = 12
	tire_mesh.rings = 1
	var hub_mesh := BoxMesh.new()
	hub_mesh.size = Vector3(0.23, stats.wheel_radius * 1.1, 0.10)
	var tire_material := _flat(TIRE)
	var hub_material := _flat(HUB)
	for wheel in wheels:
		var pivot := Node3D.new()
		pivot.position = wheel.mount
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var tire := MeshInstance3D.new()
		tire.mesh = tire_mesh
		tire.material_override = tire_material
		tire.rotation_degrees = Vector3(0, 0, 90)
		spinner.add_child(tire)
		var hub := MeshInstance3D.new()  # a spoke, so you can see the wheel turn
		hub.mesh = hub_mesh
		hub.material_override = hub_material
		spinner.add_child(hub)
		_wheel_pivots.append(pivot)
		_wheel_spinners.append(spinner)


## Each car's signature parts, with the damage at which each one goes.
func _build_parts(stats: CarStats, w: float, l: float) -> void:
	match stats.style:
		"minivan":
			# Hubcaps one by one, then the sliding door (passenger side).
			for i in _wheel_spinners.size():
				var cap := Node3D.new()
				var side := -1.0 if _wheel_spinners[i].get_parent().position.x < 0.0 else 1.0
				var out := [PackedVector3Array(), PackedColorArray()]
				_disc(out, stats.wheel_radius * 0.78, Vector3(side * 0.12, 0, 0), HUB)
				cap.add_child(_mesh_of(out, _flat(Color.WHITE)))
				_wheel_spinners[i].add_child(cap)
				_parts.append({"node": cap, "at": _wheel_spinners[i].get_parent().position, "threshold": 0.12 + 0.12 * i,
					"kind": "fly", "state": "on"})
			var door := Node3D.new()
			var panel := [PackedVector3Array(), PackedColorArray()]
			_box(panel, Vector3(0.03, 0.62, 1.15), Vector3(0, 0.0, 0), Color.WHITE)
			door.add_child(_mesh_of(panel, _paint))
			var window := [PackedVector3Array(), PackedColorArray()]
			_box(window, Vector3(0.03, 0.55, 1.05), Vector3(-0.03, 0.62, 0.0), Color.WHITE)
			door.add_child(_mesh_of(window, _glass))
			door.position = Vector3(w / 2.0 + 0.02, -0.02, -l / 2.0 + l * 0.5)
			_body.add_child(door)
			_parts.append({"node": door, "at": door.position, "threshold": 0.55, "kind": "fly", "state": "on"})
		"compact":
			# Mirrors, then the bumpers.
			for side: float in [-1.0, 1.0]:
				var mirror := Node3D.new()
				var m := [PackedVector3Array(), PackedColorArray()]
				_box(m, Vector3(0.10, 0.08, 0.14), Vector3.ZERO, Color.WHITE)
				mirror.add_child(_mesh_of(m, _paint))
				mirror.position = Vector3(side * (w / 2.0 + 0.05), 0.30, -l / 2.0 + l * 0.29)
				_body.add_child(mirror)
				_parts.append({"node": mirror, "at": mirror.position, "threshold": 0.15 if side < 0 else 0.28,
					"kind": "fly", "state": "on"})
			for end: float in [-1.0, 1.0]:
				var bumper := Node3D.new()
				var b := [PackedVector3Array(), PackedColorArray()]
				_box(b, Vector3(w * 1.01, 0.2, 0.16), Vector3.ZERO, Color(0.35, 0.35, 0.36))
				bumper.add_child(_mesh_of(b, _flat(Color.WHITE)))
				bumper.position = Vector3(0, -0.22, end * l / 2.0)
				_body.add_child(bumper)
				_parts.append({"node": bumper, "at": bumper.position, "threshold": 0.45 if end < 0 else 0.62,
					"kind": "fly", "state": "on"})
		"sedan":
			# The hood and trunk lid pop open; much later the hood tears off.
			var shape: Array = SHAPES.sedan.body
			_parts.append(_lid(shape[2], shape[3], true, w, l, 0.35, deg_to_rad(38.0)))
			_parts.append(_lid(shape[4], shape[5], false, w, l, 0.55, deg_to_rad(-55.0)))
			var hood_off: Dictionary = _parts[0].duplicate()
			hood_off.threshold = 0.85
			hood_off.kind = "fly"
			hood_off.state = "on"
			hood_off.after = _parts[0]
			_parts.append(hood_off)


## A hood or trunk lid covering the outline edge from `a` to `b`, hinged at the cabin end.
func _lid(a: Array, b: Array, hood: bool, w: float, l: float, threshold: float, open_angle: float) -> Dictionary:
	var front := Vector3(0, a[1] + 0.012, -l / 2.0 + a[0] * l)
	var back := Vector3(0, b[1] + 0.012, -l / 2.0 + b[0] * l)
	var hinge := back if hood else front
	var free := front if hood else back
	var pivot := Node3D.new()
	pivot.position = hinge
	var out := [PackedVector3Array(), PackedColorArray()]
	var half := w / 2.0 * 0.97
	var p0 := Vector3(-half, 0, 0)
	var p1 := Vector3(half, 0, 0)
	var q := free - hinge
	_tri(out, p0, p1, p1 + q, Vector3.UP, Color.WHITE)
	_tri(out, p0, p1 + q, p0 + q, Vector3.UP, Color.WHITE)
	_tri(out, p0, p1 + q, p1, Vector3.DOWN, BAY)
	_tri(out, p0, p0 + q, p1 + q, Vector3.DOWN, BAY)
	pivot.add_child(_mesh_of(out, _paint))
	_body.add_child(pivot)
	return {"node": pivot, "at": (front + back) / 2.0, "threshold": threshold, "kind": "hinge", "state": "on",
		"open_angle": open_angle}


## A flat disc facing along X.
static func _disc(out: Array, radius: float, center: Vector3, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		for i in 10:
			var a0 := TAU * i / 10.0
			var a1 := TAU * (i + 1) / 10.0
			_tri(out, center, center + Vector3(0, cos(a0), sin(a0)) * radius,
				center + Vector3(0, cos(a1), sin(a1)) * radius, Vector3(side, 0, 0), color)


func _mesh_of(out: Array, material: Material) -> MeshInstance3D:
	var verts: PackedVector3Array = out[0]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, verts.size(), 3):
		var n := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
		normals[t] = n
		normals[t + 1] = n
		normals[t + 2] = n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = out[1]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A part gives: a lid pops open, anything else flies off as a physics body.
func _break(part: Dictionary) -> void:
	if part.has("after"):
		part.after.state = "gone"  # the open hood it was is tearing off
	if part.kind == "hinge":
		part.state = "open"
		return
	part.state = "gone"
	var node: Node3D = part.node
	var xf := node.global_transform
	var body := RigidBody3D.new()
	body.mass = 8.0
	# Nothing it can hit but the ground: not even the car it came off.
	body.collision_layer = 0
	body.collision_mask = 1 << (Car.WORLD_LAYER - 1)
	body.set_meta("car_part", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = box
	body.add_child(shape)
	var car := get_parent() as RigidBody3D
	var scene := get_tree().current_scene
	scene.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	node.reparent(body)
	var outward := (xf.origin - global_position)
	outward.y = 0.0
	body.linear_velocity = (car.linear_velocity if car else Vector3.ZERO) * 0.9 \
		+ outward.normalized() * 4.0 + Vector3.UP * 3.0
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	part_lost.emit(body)


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	return m


func _make_smoke(length: float) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 24
	smoke.lifetime = 1.6
	smoke.position = Vector3(0, 0.3, -length * 0.38)  # from under the hood
	smoke.direction = Vector3.UP
	smoke.spread = 25.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.2
	var puff := QuadMesh.new()
	puff.size = Vector2(0.8, 0.8)
	smoke.mesh = puff
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.25, 0.25, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke.material_override = m
	return smoke


## Cones pointing backward from the tailpipe, orange round a hot core (scaled along
## their length as they flicker).
func _make_flame() -> MeshInstance3D:
	var flame := _flame_cone(0.2, Color(1.0, 0.45, 0.08))
	var core := _flame_cone(0.09, Color(1.0, 0.92, 0.6))
	core.scale = Vector3(1.0, 0.6, 1.0)
	core.position = Vector3(0, -0.2, 0)
	flame.add_child(core)
	flame.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # the cones' tips (+Y) point back (+Z)
	flame.visible = false
	return flame


func _flame_cone(radius: float, color: Color) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	cone.material = m
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _shadow_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.55))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
