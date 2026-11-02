class_name Intersections
extends Node3D
## The two intersections the run goes between. Both routes start at the 4-way stop where
## IA 1 meets IA 22 in Kalona (Junction lays it out like the real one): a stop sign with an
## ALL WAY plate each way in, a YIELD sign where each free right turn joins, and an Amish
## buggy waiting its turn. Highway 1 starts from a standstill at its stop line coming up
## from the south; Highway 22 in the intersection itself, pointed west straight out of it.
## Highway 1 ends at the traffic lights at Mormon Trek Blvd in Iowa City, which cycle like
## real ones; Highway 22 where 8th Ave stops for it in Wellman (a two-way stop: IA 22 goes
## through). A banner over the road marks each line. The ways back start at those two
## and finish at the 4-way (Routes "start" and "finish" say which is where).
##
## "IA 1" in here is whichever highway the route follows; "northbound" is our way.

const NEAR := 30.0  ## a crossroad this close to the start/finish line is that intersection
const STOP_LINE := 12.0  ## the 4-way stop's stop lines are this far short of its middle
const SIGN_OFFSET := 5.6  ## stop signs and lights stand this far from IA 1's middle...
const LIGHT_OFFSET := 8.0
const LINE_WIDTH := 0.45  ## stop line, across the lane
const PAINT_LIFT := 0.015
## IA 1's lights: green, yellow, then all red while Mormon Trek goes (and all red again).
const CYCLE := [["ia1", 26.0], ["ia1_yellow", 4.0], ["all_red", 2.0], ["cross", 18.0],
	["cross_yellow", 4.0], ["all_red", 2.0]]
const RED := Color(0.95, 0.12, 0.08)
const AMBER := Color(1.0, 0.62, 0.05)
const GREEN := Color(0.15, 0.95, 0.45)

var route: RouteData
var start_crossroad := {}
var finish_crossroad := {}
var buggy: StaticBody3D  ## waiting at the 4-way stop
var stop_signs := 0
var yield_signs := 0
var signal_heads: Array[Dictionary] = []  ## {lamps: [red, yellow, green] meshes, ia1: bool}
var _time := 0.0
var _shown := ""  ## the phase the lamps show
var _materials := {}


func setup(r: RouteData) -> void:
	route = r
	start_crossroad = _crossroad_near(r.start_station)
	finish_crossroad = _crossroad_near(r.finish_station)
	var start_middle := r.start_station + float(r.info.start_stop_line)
	var finish_middle := r.finish_station + float(r.info.finish_stop_line)
	for end: Array in [[r.info.get("start", "4way"), start_middle, -float(r.info.start_stop_line), start_crossroad],
			[r.info.finish, finish_middle, float(r.info.finish_stop_line), finish_crossroad]]:
		match String(end[0]):
			"4way":
				if r.junction.is_empty():
					_build_stop(end[1], end[3])
				else:
					_build_junction_signs()
			"light":
				_build_lights(end[1], absf(end[2]), end[3])
			"stop":
				_build_side_stop(end[1], end[3])
	if r.info.finish == "stop":
		_ia1_stop_line(r.finish_station, 1.0)  # (we don't stop: the line's just the finish)
	for line: Array in [[r.start_station, "START", r.info.get("start", "4way"), r.info.from],
			[r.finish_station, "FINISH", r.info.finish, r.info.to]]:
		_add_banner(line[0], "%s  ·  %s" % [String(line[3]).to_upper(), line[1]], 7.9 if line[2] == "light" else 5.9)  # (up over the signal heads)
	_update_lights()


## Our highway's name on the cross street's signs ("IOWA 1").
func _highway_name() -> String:
	return "IOWA %s" % route.info.number


## Is this crossroad one of the two built here (so Roadside leaves out its usual sign)?
static func at_line(r: RouteData, c: Dictionary) -> bool:
	return c.kind != "ramp" and (absf(float(c.station) - r.start_station) < NEAR
		or absf(float(c.station) - r.finish_station) < NEAR)


## Which lights IA 1 shows now: "green", "yellow" or "red".
func ia1_light() -> String:
	return _lights_for(_phase())[0]


func _process(delta: float) -> void:
	_time += delta
	_update_lights()


func _phase() -> String:
	var total := 0.0
	for p: Array in CYCLE:
		total += p[1]
	var t := fmod(_time, total)
	for p: Array in CYCLE:
		if t < p[1]:
			return p[0]
		t -= p[1]
	return CYCLE[0][0]


## [IA 1's color, Mormon Trek's color] in a phase of the cycle.
static func _lights_for(phase: String) -> Array:
	match phase:
		"ia1":
			return ["green", "red"]
		"ia1_yellow":
			return ["yellow", "red"]
		"cross":
			return ["red", "green"]
		"cross_yellow":
			return ["red", "yellow"]
	return ["red", "red"]


func _update_lights() -> void:
	var phase := _phase()
	if phase == _shown:
		return
	_shown = phase
	var colors := _lights_for(phase)
	for head: Dictionary in signal_heads:
		var color: String = colors[0] if head.ia1 else colors[1]
		for k in 3:
			var lamp: MeshInstance3D = head.lamps[k]
			var lit: bool = ["red", "yellow", "green"][k] == color
			lamp.material_override = _lamp_material(k, lit)


func _crossroad_near(station: float) -> Dictionary:
	var best := {}
	for c: Dictionary in route.crossroads:
		if c.kind != "ramp" and absf(float(c.station) - station) < NEAR \
				and (best.is_empty() or absf(float(c.station) - station) < absf(float(best.station) - station)):
			best = c
	return best


## Where the cross street meets IA 1 on each side: {end, out (away from IA 1), half_width,
## y, name} for every street piece that joins IA 1 within NEAR of `station`.
func approaches(station: float) -> Array[Dictionary]:
	var center := route.position_at(station)
	var out: Array[Dictionary] = []
	for st: Dictionary in route.streets:
		var flat: PackedFloat32Array = st.points
		var n := flat.size() / 5
		for e: int in [0, 1]:
			if not st.joins[e]:
				continue
			var i := 0 if e == 0 else n - 1
			var j := 1 if e == 0 else n - 2
			var end := Vector3(flat[i * 5], flat[i * 5 + 2], flat[i * 5 + 4])
			if Vector2(end.x - center.x, end.z - center.z).length() > NEAR:
				continue
			var away := Vector3(flat[j * 5] - end.x, 0.0, flat[j * 5 + 4] - end.z).normalized()
			out.append({"end": end, "out": away, "half_width": float(st.half_width), "name": st.name})
	return out


# --- The 4-way stop -------------------------------------------------------------------

## The 4-way's signs, where the junction has them (the stop lines are its paint), and the
## buggy at its stop line on the side you see from the start.
func _build_junction_signs() -> void:
	var j: Dictionary = route.junction
	for s: Dictionary in j.stops:
		_stop_sign(_facing(Vector3(s.x, float(s.y) - 0.15, s.z), Vector3(s.forward[0], 0.0, s.forward[1])), s.street)
	for s: Dictionary in j.yields:
		_yield_sign(_facing(Vector3(s.x, float(s.y) - 0.25, s.z), Vector3(s.forward[0], 0.0, s.forward[1])))
	var b: Dictionary = j.buggy
	_add_buggy(Vector3(b.x, b.y, b.z), Vector3(b.forward[0], 0.0, b.forward[1]))


## A 4-way stop with its `center` (station) there, where there's no junction.json.
func _build_stop(center: float, crossroad: Dictionary) -> void:
	if crossroad.is_empty():
		return
	var line := center - STOP_LINE  # ours
	var far_line := center + STOP_LINE  # the southbound stop line
	# Northbound (us) and southbound on IA 1.
	_stop_sign(_on_ia1(line - 1.0, SIGN_OFFSET, 1.0), crossroad.name)
	_stop_sign(_on_ia1(far_line + 1.0, -SIGN_OFFSET, -1.0), crossroad.name)
	_ia1_stop_line(line, 1.0)
	_ia1_stop_line(far_line, -1.0)
	# Each way in on the cross street.
	var waiting := false
	for a: Dictionary in approaches(center):
		var fwd: Vector3 = -a.out  # a driver coming in, toward IA 1
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var stop_at: Vector3 = a.end + a.out * 2.6
		var sign_pos: Vector3 = stop_at + a.out * 1.0 + right * (a.half_width + 1.3)
		_stop_sign(_facing(sign_pos, fwd), _highway_name())
		_street_stop_line(stop_at, fwd, right, a.half_width)
		# A buggy waits its turn on the side you can see from the start.
		if not waiting and a.out.dot(route.right_at(center)) > 0.5:
			_add_buggy(stop_at - fwd * 0.4 + right * a.half_width * 0.45, fwd)
			waiting = true


## A holder at `station` on IA 1, `offset` to the right, facing drivers going `direction`
## (+1 northbound, -1 southbound): its +Z points back at them.
func _on_ia1(station: float, offset: float, direction: float) -> Node3D:
	var pos := route.position_at(station) + route.right_at(station) * offset
	pos.y = route.position_at(station).y - 0.1
	return _facing(pos, route.tangent_at(station) * direction)


func _facing(pos: Vector3, driver_forward: Vector3) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var flat := Vector3(driver_forward.x, 0.0, driver_forward.z).normalized()
	holder.transform = Transform3D(Basis.looking_at(flat, Vector3.UP), pos)  # -Z along their way
	return holder


# --- Where the cross street stops for us ----------------------------------------------

## Stop signs and stop lines for the cross street coming in each way to the intersection
## at `center` (station): we don't stop.
func _build_side_stop(center: float, crossroad: Dictionary) -> void:
	if crossroad.is_empty():
		return
	for a: Dictionary in approaches(center):
		var fwd: Vector3 = -a.out
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var stop_at: Vector3 = a.end + a.out * 2.6
		var sign_pos: Vector3 = stop_at + a.out * 1.0 + right * (a.half_width + 1.3)
		_stop_sign(_facing(sign_pos, fwd), _highway_name(), false)
		_street_stop_line(stop_at, fwd, right, a.half_width)


## A STOP sign with an ALL WAY plate under it (at a 4-way stop) and a street-name blade on top.
func _stop_sign(holder: Node3D, street: String, all_way := true) -> void:
	stop_signs += 1
	var gray := _material(Color(0.55, 0.55, 0.57))
	_box(holder, Vector3(0.07, 3.2, 0.07), Vector3(0, 1.6, 0), gray)
	var face := Vector3(0, 2.15, 0.05)
	_octagon(holder, 0.40, face + Vector3(0, 0, -0.015), gray)  # the back
	_octagon(holder, 0.40, face, _material(Color.WHITE))
	_octagon(holder, 0.37, face + Vector3(0, 0, 0.006), _material(RED.darkened(0.15)))
	var stop := _label("STOP", 46, Color.WHITE)
	stop.position = face + Vector3(0, 0, 0.022)
	holder.add_child(stop)
	if all_way:
		_box(holder, Vector3(0.5, 0.16, 0.02), Vector3(0, 1.6, 0.05), _material(Color.WHITE))
		_box(holder, Vector3(0.47, 0.13, 0.022), Vector3(0, 1.6, 0.05), _material(RED.darkened(0.15)))
		var plate := _label("ALL WAY", 22, Color.WHITE)
		plate.position = Vector3(0, 1.6, 0.075)
		holder.add_child(plate)
	# The street name, on a blade across the top of the post.
	var blade := Node3D.new()
	holder.add_child(blade)
	blade.position = Vector3(0, 3.05, 0)
	blade.rotation.y = PI / 2.0
	_box(blade, Vector3(1.1, 0.2, 0.02), Vector3.ZERO, _material(Roadside.SIGN_GREEN))
	for side: float in [1.0, -1.0]:
		var name_label := _label(street, 26, Color.WHITE)
		name_label.position = Vector3(0, 0, 0.012 * side)
		name_label.rotation.y = 0.0 if side > 0.0 else PI
		blade.add_child(name_label)


## A YIELD sign: a red triangle point down, white inside, YIELD in red.
func _yield_sign(holder: Node3D) -> void:
	yield_signs += 1
	var gray := _material(Color(0.55, 0.55, 0.57))
	_box(holder, Vector3(0.07, 2.9, 0.07), Vector3(0, 1.45, 0), gray)
	var face := Vector3(0, 2.35, 0.05)
	_triangle(holder, 0.55, face + Vector3(0, 0, -0.015), gray)  # the back
	_triangle(holder, 0.55, face, _material(RED.darkened(0.15)))
	_triangle(holder, 0.34, face + Vector3(0, 0.03, 0.006), _material(Color.WHITE))
	var word := _label("YIELD", 20, RED.darkened(0.15))
	word.position = face + Vector3(0, 0.1, 0.02)
	holder.add_child(word)


## A flat triangle, point down, facing +Z (the driver) and seen from behind too, `radius`
## to its corners.
func _triangle(holder: Node3D, radius: float, pos: Vector3, material: Material) -> void:
	var a := Vector3(-radius * 0.866, radius * 0.5, 0.0)
	var b := Vector3(radius * 0.866, radius * 0.5, 0.0)
	var c := Vector3(0.0, -radius, 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c, a, c, b])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)


func _octagon(holder: Node3D, radius: float, pos: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.012
	mesh.radial_segments = 8
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	# Turned a sixteenth of a turn about its axis so the top's flat, then tipped so the
	# axis points at the driver.
	node.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, PI / 8.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)


func _ia1_stop_line(station: float, direction: float) -> void:
	var c := route.position_at(station)
	var right := route.right_at(station)
	var fwd := route.tangent_at(station) * direction
	var corners: Array[Vector3] = []
	for lateral: float in [0.25, RoadMesher.LANE_WIDTH - 0.1]:
		var off := lateral * direction
		var p := c + right * off
		p.y = c.y + RoadMesher.surface_height(off) + PAINT_LIFT
		corners.append(p)
	_paint_bar(corners[0], corners[1], Vector3(fwd.x, 0.0, fwd.z).normalized())


func _street_stop_line(at: Vector3, fwd: Vector3, right: Vector3, half_width: float) -> void:
	var a := at + right * 0.2
	var b := at + right * (half_width - 0.2)
	a.y = at.y + PAINT_LIFT
	b.y = at.y + PAINT_LIFT
	_paint_bar(a, b, fwd)


## A white bar LINE_WIDTH wide from `a` to `b`, across a lane going `fwd`.
func _paint_bar(a: Vector3, b: Vector3, fwd: Vector3) -> void:
	var h := fwd * LINE_WIDTH * 0.5
	var verts := PackedVector3Array([a - h, a + h, b + h, b - h])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2])  # both sides up
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(Color(0.92, 0.92, 0.92))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("paint", true)
	add_child(node)


func _add_buggy(front: Vector3, fwd: Vector3) -> void:
	var spec: Dictionary = Traffic.KINDS.buggy
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	buggy = StaticBody3D.new()
	buggy.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	buggy.collision_mask = 0
	add_child(buggy)
	# The model faces -Z with the horse's nose ~3 m ahead of its middle.
	var middle := front - fwd * 3.0
	buggy.transform = Transform3D(Basis.looking_at(Vector3(fwd.x, 0.0, fwd.z), Vector3.UP),
		Vector3(middle.x, front.y - 0.03, middle.z))
	var model := MeshInstance3D.new()
	model.mesh = TrafficModels.build("buggy", rng)
	buggy.add_child(model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(spec.width, 2.2, spec.length)
	shape.shape = box
	shape.position = Vector3(0, 1.1, spec.center)
	buggy.add_child(shape)


# --- The stop light -------------------------------------------------------------------

## Traffic lights at the intersection at `center` (station), IA 1's stop lines `stop_line`
## m short of its middle each way.
func _build_lights(center: float, stop_line: float, crossroad: Dictionary) -> void:
	if crossroad.is_empty():
		return
	var line: float = center - stop_line
	var far_line: float = center + stop_line
	var street: String = crossroad.name
	_ia1_stop_line(line, 1.0)
	_ia1_stop_line(far_line, -1.0)
	# IA 1, both ways: a mast arm from the far right corner, a head over each half lane.
	for way: Array in [[far_line + 2.0, 1.0], [line - 8.0, -1.0]]:
		var holder := _on_ia1(way[0], LIGHT_OFFSET * way[1], way[1])
		_mast(holder, LIGHT_OFFSET, [LIGHT_OFFSET - 1.0, LIGHT_OFFSET - 3.2], true, street)
	# The cross street, each way in: a pole on the far right corner, across IA 1.
	for a: Dictionary in approaches(center):
		var fwd: Vector3 = -a.out
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var stop_at: Vector3 = a.end + a.out * 2.6
		_street_stop_line(stop_at, fwd, right, a.half_width)
		var reach: float = a.half_width + 1.5
		var pole: Vector3 = a.end + fwd * (2.0 * RoadMesher.GRAVEL_HALF_WIDTH + 1.0) + right * reach
		pole.y -= 0.1
		var holder := _facing(pole, fwd)
		_mast(holder, reach, [reach - a.half_width * 0.25, reach - a.half_width * 0.75], false, _highway_name())


## A signal pole in `holder` (facing its drivers), an arm reaching `arm` m to the left over
## the road, and a 3-light head at each of `heads` (m left of the pole).
func _mast(holder: Node3D, arm: float, heads: Array, ia1: bool, street: String) -> void:
	var metal := _material(Color(0.42, 0.43, 0.45))
	_box(holder, Vector3(0.28, 7.2, 0.28), Vector3(0, 3.6, 0), metal)
	_box(holder, Vector3(arm + 0.3, 0.16, 0.16), Vector3(-arm / 2.0, 6.6, 0), metal)
	for x: float in heads:
		var head := Node3D.new()
		holder.add_child(head)
		head.position = Vector3(-x, 5.6, 0.05)
		_box(head, Vector3(0.05, 0.6, 0.05), Vector3(0, 0.75, 0), metal)
		_box(head, Vector3(0.42, 1.12, 0.3), Vector3.ZERO, _material(Color(0.12, 0.12, 0.10)))
		_box(head, Vector3(0.62, 1.32, 0.03), Vector3(0, 0, -0.16), _material(Color(0.08, 0.08, 0.08)))
		var lamps: Array[MeshInstance3D] = []
		for k in 3:
			var lamp := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.13
			disc.bottom_radius = 0.13
			disc.height = 0.04
			disc.radial_segments = 12
			lamp.mesh = disc
			lamp.rotation.x = PI / 2.0
			lamp.position = Vector3(0, 0.36 - k * 0.36, 0.16)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			head.add_child(lamp)
			lamps.append(lamp)
		signal_heads.append({"lamps": lamps, "ia1": ia1})
	# The cross street's name on the arm.
	_box(holder, Vector3(1.6, 0.36, 0.03), Vector3(-arm * 0.45, 6.25, 0.1), _material(Roadside.SIGN_GREEN))
	var label := _label(street, 34, Color.WHITE)
	label.position = Vector3(-arm * 0.45, 6.25, 0.12)
	holder.add_child(label)


func _lamp_material(k: int, lit: bool) -> Material:
	var key := "%d%s" % [k, lit]
	if not _materials.has(key):
		var color: Color = [RED, AMBER, GREEN][k]
		var m := StandardMaterial3D.new()
		if lit:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = color * 1.15
		else:
			m.albedo_color = color.darkened(0.82)
			m.roughness = 0.4
		_materials[key] = m
	return _materials[key]


# --- Banners --------------------------------------------------------------------------

## A checkered banner across the road on two poles, `height` up, the line under it.
func _add_banner(station: float, text: String, height: float) -> void:
	var holder := _on_ia1(station, 0.0, 1.0)
	var metal := _material(Color(0.55, 0.55, 0.57))
	var span := 2.0 * (RoadMesher.GRAVEL_HALF_WIDTH + 0.8)
	for x: float in [-span / 2.0, span / 2.0]:
		_box(holder, Vector3(0.16, height + 0.7, 0.16), Vector3(x, (height + 0.7) / 2.0, 0), metal)
	_box(holder, Vector3(span - 0.4, 1.0, 0.06), Vector3(0, height, 0), _material(Color(0.96, 0.95, 0.9)))
	for y: float in [height + 0.62, height - 0.62]:
		_box(holder, Vector3(span - 0.4, 0.24, 0.07), Vector3(0, y, 0), _checker_material())
	for side: float in [1.0, -1.0]:
		var label := _label(text, 120, Color(0.1, 0.1, 0.12))
		label.position = Vector3(0, height, 0.04 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		holder.add_child(label)


func _checker_material() -> Material:
	if not _materials.has("checker"):
		var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
		image.set_pixel(0, 0, Color.BLACK)
		image.set_pixel(1, 1, Color.BLACK)
		image.set_pixel(1, 0, Color.WHITE)
		image.set_pixel(0, 1, Color.WHITE)
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(image)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3(4.2, 4.2, 4.2)
		m.roughness = 1.0
		_materials["checker"] = m
	return _materials["checker"]


# --- Bits -----------------------------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		_materials[key] = m
	return _materials[key]


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.005
	label.outline_size = 0
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.double_sided = false
	return label
