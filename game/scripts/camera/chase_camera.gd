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
var crash_cam := false  ## slowly circle the car (after a wreck)
var showroom := false  ## circle close and low, for the car-select screen
var _heading := Vector3.FORWARD
var _orbit := 0.0


func setup(c: Car) -> void:
	car = c
	near = 0.2
	far = 3300.0  # just past where the fog is total
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	snap()


func mode_name() -> String:
	return MODES[mode].name


## Jump straight to the follow position (after a respawn or camera change).
func snap() -> void:
	_heading = _flat_forward(car.get_global_transform_interpolated())
	_follow(1.0)


func _process(delta: float) -> void:
	if car == null:
		return
	if showroom:
		_circle(delta, 7.0, 1.4, 0.25, 50.0, 2.4)  # the car on the right, the garage panel on the left
	elif crash_cam:
		_circle(delta, 9.0, 3.5, 0.5, 60.0)
	else:
		_follow(1.0 - exp(-delta * 5.0))


## Circle the car; `aside` shifts it that far to the right of the frame.
func _circle(delta: float, radius: float, height: float, rate: float, view: float, aside := 0.0) -> void:
	var target := car.get_global_transform_interpolated().origin
	_orbit += delta * rate
	var pos := target + Vector3(cos(_orbit) * radius, height, sin(_orbit) * radius)
	var ground := car.route.terrain.height_at(pos.x, pos.z)
	if not is_nan(ground):
		pos.y = maxf(pos.y, ground + 1.0)
	global_position = pos
	var right := (target - pos).cross(Vector3.UP).normalized()
	look_at(target + Vector3.UP * 0.5 - right * aside, Vector3.UP)
	fov = view


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
