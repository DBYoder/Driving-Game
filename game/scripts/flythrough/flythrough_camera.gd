class_name FlythroughCamera
extends Camera3D
## Phase 0 stand-in for the car: glides up the northbound lane so the real road can be judged.
## Accelerate/brake change speed, camera_next cycles views, pause stops, restart rewinds.

const MPH := 2.23694
const MAX_SPEED := 45.0  # ~100 mph
const MODES := [
	{"name": "Driver", "back": 0.0, "up": 1.25, "look": 30.0, "look_up": 1.0},
	{"name": "Chase", "back": 11.0, "up": 4.0, "look": 25.0, "look_up": 1.0},
	{"name": "Drone", "back": 80.0, "up": 55.0, "look": 90.0, "look_up": 0.0},
]
const LANE_OFFSET := 1.83  # middle of the northbound lane

var route: RouteData
var station := 0.0
var speed := 29.0  # m/s, ~65 mph
var paused := false
var mode := 0


func setup(r: RouteData) -> void:
	route = r
	near = 0.25
	far = 1500.0
	fov = 70.0
	restart()


func restart() -> void:
	station = maxf(route.start_station - 120.0, 0.0)
	place()


func mode_name() -> String:
	return MODES[mode].name


func mph() -> float:
	return 0.0 if paused else speed * MPH


func _process(delta: float) -> void:
	if route == null:
		return
	var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	speed = clampf(speed + throttle * 12.0 * delta, 0.0, MAX_SPEED)
	if not paused:
		station += speed * delta
		if station > route.finish_station + 200.0:
			restart()
	place()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		mode = (mode + 1) % MODES.size()
	elif event.is_action_pressed("pause"):
		paused = not paused
	elif event.is_action_pressed("restart"):
		restart()


func place() -> void:
	var m: Dictionary = MODES[mode]
	var eye_station: float = station - m.back
	var look_station: float = station + m.look
	var eye := route.position_at(eye_station) + route.right_at(eye_station) * LANE_OFFSET
	var target := route.position_at(look_station) + route.right_at(look_station) * LANE_OFFSET
	position = eye + Vector3.UP * m.up
	look_at(target + Vector3.UP * m.look_up, Vector3.UP)
