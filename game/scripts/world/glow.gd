class_name Glow
extends RefCounted
## Halos for the lamps at night (shaders/glow.gdshader): soft round glows facing the
## camera, lit when Main says it's night (the lamp_glow shader global). One MultiMesh for
## a whole set of lamps of a kind (a town's street lights, a farm's yard lights) is one
## draw call.

const STREET := Color(1.0, 0.78, 0.48)  ## sodium: the street lights, the lots, the 4-way
const YARD := Color(0.78, 0.88, 1.0)  ## a farm's mercury-vapor pole light, bluish
const GLOBE := Color(1.0, 0.86, 0.62)  ## Wellman's globes
const HEAD := Color(1.0, 0.95, 0.82)  ## headlights
const TAIL := Color(1.0, 0.12, 0.08)  ## tail lights
const LANTERN := Color(1.0, 0.66, 0.25)  ## a buggy's

static var _shader: Shader
static var _quad: QuadMesh
static var _materials := {}


## The material for a halo of `color`, `size` m across the middle, at `offset` in its
## instance's (or node's) space.
static func material(color: Color, size: float, offset := Vector3.ZERO, strength := 1.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color, size, offset, strength]
	if not _materials.has(key):
		if _shader == null:
			_shader = load("res://shaders/glow.gdshader")
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("size", size)
		m.set_shader_parameter("offset", offset)
		m.set_shader_parameter("strength", strength)
		_materials[key] = m
	return _materials[key]


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		# (Moved and turned in the shader: big bounds, so it's never culled where it shows.)
		_quad.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	return _quad


## One halo, as a node to put where the lamp is.
static func sprite(color: Color, size: float, strength := 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = quad()
	node.material_override = material(color, size, Vector3.ZERO, strength)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("no_clip_check", true)
	return node


## Halos at each of `points` (in the node's space), each its own color (times `tint`),
## one draw call: a vehicle's lights.
static func colored(points: PackedVector3Array, colors: PackedColorArray, size: float, tint := Color.WHITE) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad()
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var key := "colored|%s|%s" % [size, tint]
	if not _materials.has(key):
		var m := material(tint, size).duplicate() as ShaderMaterial
		m.set_shader_parameter("instance_color", true)
		_materials[key] = m
	node.material_override = _materials[key]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("no_clip_check", true)
	return node


## Halos at each of `points` (world positions), one draw call.
static func batch(points: PackedVector3Array, color: Color, size: float, strength := 1.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad()
	mm.instance_count = points.size()
	var box := AABB(points[0] if not points.is_empty() else Vector3.ZERO, Vector3.ZERO)
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
		box = box.expand(points[i])
	mm.custom_aabb = box.grow(size * 4.0 + 3.0)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material(color, size, Vector3.ZERO, strength)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
