class_name StressDriver
extends RefCounted
## Drives like a hooligan: cruises fast on autopilot, sometimes down the mailbox line,
## the fence line or out through the fields, then throws in bursts of full-lock
## steering, handbrake turns and panic braking, and now and then a full boost (it tops
## the meter up itself). Used by the stress test to shake out physics blow-ups (and
## clipping) at the speeds people will actually drive.

## Where it cruises besides its lane: mailboxes, fences, and out in the fields.
const VERGE_LINES := [PropField.MAILBOX_OFFSET, PropField.FENCE_OFFSET, 30.0]

var _rng := RandomNumberGenerator.new()
var _autopilot := Autopilot.new()
var _hold := 0.0
var _chaos := false
var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _handbrake := false
var _boost := false


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
			_boost = _rng.randf() < 0.2
		else:
			_boost = _rng.randf() < 0.3
			_hold = _rng.randf_range(3.0, 10.0)
			_autopilot.target_speed = _rng.randf_range(40.0, 50.0)  # 90-110 mph
			_autopilot.cruise_lane = Autopilot.LANE_OFFSET
			if _rng.randf() < 0.35:
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				_autopilot.cruise_lane = side * VERGE_LINES[_rng.randi() % VERGE_LINES.size()]
				_autopilot.target_speed = _rng.randf_range(20.0, 35.0)  # 45-80 mph off the road
	if _boost and car.boost.meter == 0.0:
		car.boost.fill(1.0)
	car.boost_held = _boost
	if _chaos:
		car.throttle = _throttle
		car.brake = _brake
		car.steer = _steer
		car.handbrake = _handbrake
	else:
		_autopilot.update(car, delta)
