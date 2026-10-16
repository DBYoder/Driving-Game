class_name ChaseCamera
extends Camera3D
## Follows the car. camera_next cycles chase / hood / far chase / drone.
## Runs in _process off the car's interpolated transform, so it stays smooth at any frame rate.

const MODES := [
	{"name": "Chase", "back": 6.5, "up": 2.3, "look_ahead": 6.0, "look_up": 0.9},
	{"name": "Hood", "back": -1.05, "up": 0.62, "look_ahead": 30.0, "look_up": 0.4},  # just ahead of the windshield
	{"name": "Far chase", "back": 13.0, "up": 4.5, "look_ahead": 10.0, "look_up": 1.0},
	{"name": "Drone", "back": 60.0, "up": 42.0, "look_ahead": 50.0, "look_up": 0.0},
]

var car: Car
var mode := 0
var _heading := Vector3.FORWARD


func setup(c: Car) -> void:
	car = c
	near = 0.1
	far = 1500.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	snap()


func mode_name() -> String:
	return MODES[mode].name


## Jump straight to the follow position (after a respawn or camera change).
func snap() -> void:
	_heading = _flat_forward(car.get_global_transform_interpolated())
	_follow(1.0)


func _process(delta: float) -> void:
	if car:
		_follow(1.0 - exp(-delta * 5.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		mode = (mode + 1) % MODES.size()
		snap()


func _follow(blend: float) -> void:
	var xf := car.get_global_transform_interpolated()
	var m: Dictionary = MODES[mode]
	if m.name == "Hood":
		global_transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, m.up, m.back))
		fov = 75.0
		return
	# Swing behind the direction of travel with a little lag, ignoring pitch and roll.
	_heading = _heading.slerp(_flat_forward(xf), blend).normalized()
	var pos: Vector3 = xf.origin - _heading * m.back + Vector3.UP * m.up
	var ground := car.route.terrain.height_at(pos.x, pos.z)
	if not is_nan(ground):
		pos.y = maxf(pos.y, ground + 0.8)
	global_position = pos
	look_at(xf.origin + _heading * m.look_ahead + Vector3.UP * m.look_up, Vector3.UP)
	# A wider view at speed sells the sense of speed.
	fov = lerpf(68.0, 82.0, clampf(car.linear_velocity.length() / 45.0, 0.0, 1.0))


func _flat_forward(xf: Transform3D) -> Vector3:
	var f := -xf.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else _heading
