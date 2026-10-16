class_name StressDriver
extends RefCounted
## Drives like a hooligan: cruises fast on autopilot, then throws in bursts of full-lock
## steering, handbrake turns and panic braking. Used by the stress test to shake out
## physics blow-ups at the speeds people will actually drive.

var _rng := RandomNumberGenerator.new()
var _autopilot := Autopilot.new()
var _hold := 0.0
var _chaos := false
var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _handbrake := false


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func update(car: Car, delta: float) -> void:
	_hold -= delta
	if _hold <= 0.0:
		_chaos = not _chaos and _rng.randf() < 0.6
		if _chaos:
			_hold = _rng.randf_range(0.3, 1.5)
			_throttle = _rng.randf() if _rng.randf() < 0.6 else 0.0
			_brake = 1.0 if _rng.randf() < 0.25 else 0.0
			_steer = _rng.randf_range(-1.0, 1.0) if _rng.randf() < 0.5 else signf(_rng.randf() - 0.5)
			_handbrake = _rng.randf() < 0.35
		else:
			_hold = _rng.randf_range(3.0, 10.0)
			_autopilot.target_speed = _rng.randf_range(40.0, 50.0)  # 90-110 mph
	if _chaos:
		car.throttle = _throttle
		car.brake = _brake
		car.steer = _steer
		car.handbrake = _handbrake
	else:
		_autopilot.update(car, delta)
