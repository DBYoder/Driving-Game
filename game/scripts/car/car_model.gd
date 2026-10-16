class_name CarModel
extends Node3D
## Placeholder low-poly car built from boxes: body, greenhouse, bumpers, lights,
## four wheels that steer and spin, and a soft blob shadow (no real-time shadows on a potato).

const GLASS := Color(0.10, 0.13, 0.16)
const TRIM := Color(0.08, 0.08, 0.08)
const TIRE := Color(0.06, 0.06, 0.06)
const HUB := Color(0.62, 0.63, 0.65)

var _wheel_pivots: Array[Node3D] = []
var _wheel_spinners: Array[Node3D] = []
var _shadow: MeshInstance3D


func build(stats: CarStats, wheels: Array) -> void:
	var w := stats.body_size.x
	var l := stats.body_size.z
	var paint := _material(stats.body_color)
	# Lower body sits between the wheel tops; greenhouse slightly behind center like a '90s sedan.
	_box(Vector3(w, 0.62, l), Vector3(0, -0.06, 0), paint)
	_box(Vector3(w * 0.84, 0.48, l * 0.46), Vector3(0, 0.49, 0.18), _material(GLASS))
	_box(Vector3(w * 0.86, 0.06, l * 0.40), Vector3(0, 0.75, 0.22), paint)
	_box(Vector3(w * 1.01, 0.18, 0.14), Vector3(0, -0.30, -l / 2.0), _material(TRIM))
	_box(Vector3(w * 1.01, 0.18, 0.14), Vector3(0, -0.30, l / 2.0), _material(TRIM))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.36, 0.12, 0.05), Vector3(side * w * 0.34, 0.08, -l / 2.0 - 0.01),
			_material(Color(1.0, 0.95, 0.75), true))
		_box(Vector3(0.40, 0.12, 0.05), Vector3(side * w * 0.33, 0.08, l / 2.0 + 0.01),
			_material(Color(0.75, 0.05, 0.05), true))

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = stats.wheel_radius
	tire_mesh.bottom_radius = stats.wheel_radius
	tire_mesh.height = 0.22
	tire_mesh.radial_segments = 12
	tire_mesh.rings = 1
	var hub_mesh := BoxMesh.new()
	hub_mesh.size = Vector3(0.23, stats.wheel_radius * 1.1, 0.10)
	for wheel in wheels:
		var pivot := Node3D.new()
		pivot.position = wheel.mount
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var tire := MeshInstance3D.new()
		tire.mesh = tire_mesh
		tire.material_override = _material(TIRE)
		tire.rotation_degrees = Vector3(0, 0, 90)
		spinner.add_child(tire)
		var hub := MeshInstance3D.new()  # a spoke, so you can see the wheel turn
		hub.mesh = hub_mesh
		hub.material_override = _material(HUB)
		spinner.add_child(hub)
		_wheel_pivots.append(pivot)
		_wheel_spinners.append(spinner)

	_shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w * 1.25, l * 1.1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = quad
	_shadow.material_override = _shadow_material()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func update_wheels(wheels: Array, steer_angle: float, stats: CarStats) -> void:
	var ground_y := 0.0
	var grounded := 0
	for i in wheels.size():
		var wheel: Car.Wheel = wheels[i]
		var pivot := _wheel_pivots[i]
		pivot.position = wheel.mount - Vector3(0, wheel.spring_length, 0)
		pivot.rotation.y = steer_angle if wheel.front else 0.0
		_wheel_spinners[i].rotation.x = -wheel.spin
		if wheel.grounded:
			ground_y += pivot.position.y - stats.wheel_radius
			grounded += 1
	_shadow.visible = grounded > 0
	if grounded > 0:
		_shadow.position = Vector3(0, ground_y / grounded + 0.03, 0)


func _box(size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _material(color: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


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
