class_name TireMarks
extends Node3D
## What the tires leave behind: black skid marks on the asphalt when they slide, brown
## ruts in the gravel and grass, and a cloud kicked up behind the car. Dust off gravel
## and dirt, tire smoke from a hard slide on the asphalt, spray when it's wet, snow in
## winter.
##
## The marks are quads in one MultiMesh, the oldest reused once there are MAX_MARKS.

const MAX_MARKS := 1600
const MARK_WIDTH := 0.24
const MIN_STEP := 0.35  ## a new piece of mark every this many meters
const LIFT := 0.03  ## above the surface, so it doesn't flicker into it
## Sideways slip (m/s) that starts marking, per surface.
const SLIDE_MARKS := {"asphalt": 3.0, "gravel": 1.6, "grass": 1.6}
const MARK_COLORS := {
	"asphalt": Color(0.03, 0.03, 0.03, 0.6),
	"gravel": Color(0.33, 0.28, 0.22, 0.55),
	"grass": Color(0.24, 0.21, 0.12, 0.6),
}
const DUST_SPEED := 9.0  ## m/s on gravel or grass before it kicks up dust

var car: Car
var count := 0  ## marks laid since the last clear (QA and tests read it)
var wet := false  ## spray instead of dust
var snowy := false
var particle_scale := 1.0
var _marks: MultiMeshInstance3D
var _next := 0
var _last: Array = []  ## per wheel: where its mark got to (or null)
var _dust: Array[CPUParticles3D] = []


func setup(c: Car) -> void:
	car = c
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = MAX_MARKS
	multimesh.visible_instance_count = 0
	_marks = MultiMeshInstance3D.new()
	_marks.multimesh = multimesh
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marks.material_override = m
	# Marks are spread all along the road: never cull the lot for being off screen.
	_marks.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(_marks)
	_last.resize(car.wheels.size())
	for i in 2:
		_dust.append(_make_dust())


## Forget every mark (a new run).
func clear() -> void:
	_marks.multimesh.visible_instance_count = 0
	_next = 0
	count = 0
	_last.fill(null)
	for d in _dust:
		d.emitting = false
		if is_inside_tree():
			d.restart()  # clears the puffs still in the air
			d.emitting = false


func _physics_process(_delta: float) -> void:
	if car == null or car.stats == null:
		return
	var speed := car.linear_velocity.length()
	var rear := 0
	for i in car.wheels.size():
		var w: Car.Wheel = car.wheels[i]
		var threshold: float = SLIDE_MARKS.get(w.surface, 2.0)
		var marking := w.grounded and speed > 2.0 and w.slide > threshold
		if marking:
			var at := w.contact + w.normal * LIFT
			if _last[i] == null:
				_last[i] = at
			elif at.distance_to(_last[i]) >= MIN_STEP:
				_add_mark(_last[i], at, w.normal, MARK_COLORS[w.surface] if MARK_COLORS.has(w.surface) else MARK_COLORS.grass,
					clampf((w.slide - threshold) / 4.0 + 0.5, 0.5, 1.0))
				_last[i] = at
		else:
			_last[i] = null
		if not w.front and rear < _dust.size() and is_inside_tree():
			_kick_up(_dust[rear], w, speed)
			rear += 1


func _add_mark(from: Vector3, to: Vector3, normal: Vector3, color: Color, strength: float) -> void:
	var along := to - from
	var length := along.length() + 0.05  # a hair of overlap: no gaps between pieces
	var z := along / along.length()
	var x := normal.cross(z).normalized()
	var y := z.cross(x).normalized()
	var basis := Basis(x * MARK_WIDTH, y, z * length)
	var multimesh := _marks.multimesh
	multimesh.set_instance_transform(_next, Transform3D(basis, (from + to) * 0.5))
	multimesh.set_instance_color(_next, Color(color, color.a * strength))
	_next = (_next + 1) % MAX_MARKS
	count += 1
	multimesh.visible_instance_count = mini(count, MAX_MARKS)


## Dust, smoke, spray or snow behind a rear wheel, depending on what it's on and doing.
func _kick_up(dust: CPUParticles3D, w: Car.Wheel, speed: float) -> void:
	var amount := 0.0
	var color := Color(0.62, 0.55, 0.42, 0.45)
	if w.grounded:
		if w.surface == "asphalt":
			if w.slide > 6.0:  # a proper smoky slide
				amount = smoothstep(6.0, 11.0, w.slide)
				color = Color(0.86, 0.86, 0.86, 0.4)
			elif wet and speed > 15.0:
				amount = smoothstep(15.0, 35.0, speed) * 0.7
				color = Color(0.78, 0.81, 0.84, 0.28)
		else:
			amount = maxf(smoothstep(DUST_SPEED, 30.0, speed), smoothstep(1.5, 5.0, w.slide))
			if w.surface == "grass":
				amount *= 0.5
				color = Color(0.45, 0.40, 0.28, 0.4)
			if wet:
				color = Color(0.40, 0.35, 0.28, 0.5)  # mud
				amount *= 0.5
	if snowy and w.grounded and speed > 10.0:
		amount = maxf(amount, smoothstep(10.0, 30.0, speed) * 0.8)
		color = Color(0.95, 0.96, 0.98, 0.6)
	amount *= particle_scale
	dust.emitting = amount > 0.05
	if dust.emitting:
		dust.position = w.contact + Vector3.UP * 0.2  # (this node stays at the origin)
		dust.color = Color(color, color.a * clampf(0.3 + amount * 0.7, 0.0, 1.0))  # fainter when it's light


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.6
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.6
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	# A plain billboard that keeps each particle's scale: finished particles are scaled to
	# nothing (BILLBOARD_PARTICLES drew them as black puffs at the wheel).
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _puff_texture()
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static var _puff: ImageTexture


## A soft round puff, made once.
static func _puff_texture() -> ImageTexture:
	if _puff == null:
		var n := 32
		var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
				image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
		_puff = ImageTexture.create_from_image(image)
	return _puff
