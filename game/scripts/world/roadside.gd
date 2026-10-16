class_name Roadside
extends Node3D
## Street-name signs at the real crossroads, green mile markers, and the start and finish banners.

const SIGN_GREEN := Color(0.05, 0.40, 0.18)
const POST_GRAY := Color(0.55, 0.55, 0.57)
const SIGN_RANGE := 1100.0  ## signs further than this are a pixel or two in the haze: not drawn

var route: RouteData


func setup(r: RouteData) -> void:
	route = r
	var green := _material(SIGN_GREEN)
	var gray := _material(POST_GRAY)

	for c in route.crossroads:
		if c.kind == "ramp":
			continue
		var text: String = c.name
		if c.route != "":
			text = "%s\n%s" % [c.route, c.name]
		_add_sign(c.station - 12.0, 8.5, text, green, gray)

	var mile := 1
	while route.start_station + mile * RouteData.MILE_M < route.finish_station:
		_add_marker(route.start_station + mile * RouteData.MILE_M, mile, green, gray)
		mile += 1

	_add_banner(route.start_station, "KALONA\nSTART")
	_add_banner(route.finish_station, "IOWA CITY\nFINISH")


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


## A sign standing on the right shoulder, facing northbound traffic.
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


func _add_marker(station: float, mile: int, face: Material, post: Material) -> void:
	var holder := _place(station, 7.6)
	_box(holder, Vector3(0.06, 1.3, 0.06), Vector3(0, 0.65, 0), post)
	_box(holder, Vector3(0.45, 0.6, 0.03), Vector3(0, 1.3, 0), face)
	var label := _label(str(mile), 56)
	label.position = Vector3(0, 1.3, 0.02)
	label.visibility_range_end = SIGN_RANGE
	holder.add_child(label)


func _add_banner(station: float, text: String) -> void:
	var holder := _place(station, 0.0)
	var label := _label(text, 160)
	label.position = Vector3(0, 7.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	holder.add_child(label)


func _place(station: float, offset: float) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var pos := route.position_at(station) + route.right_at(station) * offset
	pos.y = route.position_at(station).y - 0.1
	holder.position = pos
	# Face the approaching (northbound) driver: +Z of the holder points back down the road.
	holder.look_at(pos + route.tangent_at(station), Vector3.UP)
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
