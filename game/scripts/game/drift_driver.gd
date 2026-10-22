class_name DriftDriver
extends RefCounted
## A scripted handbrake turn for the drift test, the way you'd actually do one: get to
## 50 mph on autopilot, yank the handbrake at full right lock, let go and catch the slide
## with countersteer and throttle, then straighten the wheel and see how fast the car
## gathers itself up.

enum Phase { ACCELERATE, PULL, HOLD, STRAIGHTEN, DONE }

const ENTRY_SPEED := 22.35  ## 50 mph
const HOLD_TIME := 1.2
const STRAIGHTEN_TIME := 5.0

var pull_time := 0.5  ## how long the handbrake is yanked
var countersteer := -0.6  ## steering while catching the slide
var handbrake := true  ## false: just yank the wheel (a swerve), for seeing how far a car leans
var entry_speed := ENTRY_SPEED
var phase := Phase.ACCELERATE
var phase_time := 0.0
var _autopilot := Autopilot.new()


func _init() -> void:
	_autopilot.target_speed = entry_speed + 0.5


func set_entry_speed(speed: float) -> void:
	entry_speed = speed
	_autopilot.target_speed = speed + 0.5


func update(car: Car, delta: float) -> void:
	phase_time += delta
	match phase:
		Phase.ACCELERATE:
			_autopilot.update(car, delta)
			if car.forward_speed() >= entry_speed and phase_time > 3.0:
				_next(Phase.PULL)
		Phase.PULL:
			_inputs(car, 0.0, 1.0, handbrake)
			if phase_time >= pull_time:
				_next(Phase.HOLD)
		Phase.HOLD:
			_inputs(car, 0.6, countersteer, false)
			if phase_time >= HOLD_TIME:
				_next(Phase.STRAIGHTEN)
		Phase.STRAIGHTEN:
			_inputs(car, 0.3, 0.0, false)
			if phase_time >= STRAIGHTEN_TIME:
				_next(Phase.DONE)
		Phase.DONE:
			_inputs(car, 0.0, 0.0, false)


func _next(p: Phase) -> void:
	phase = p
	phase_time = 0.0


func _inputs(car: Car, throttle: float, steer: float, handbrake: bool) -> void:
	car.throttle = throttle
	car.brake = 0.0
	car.steer = steer
	car.handbrake = handbrake


## Angle (degrees) between where the car points and where it's going, ignoring height.
static func slip_angle(car: Car) -> float:
	var v := car.linear_velocity
	v.y = 0.0
	var f := -car.global_transform.basis.z
	f.y = 0.0
	if v.length() < 2.0 or f.length() < 0.01:
		return 0.0
	return rad_to_deg(v.normalized().angle_to(f.normalized()))
