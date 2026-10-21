class_name CopDriver
extends RefCounted
## Drives a sheriff's cruiser. Parked: waits by the road. Chasing: runs down the road in
## the player's lane flat out, then sits on their tail at a following distance; off the
## road it heads straight for them. It doesn't ram: it waits for you to stop (see
## Pursuit). Giving up: pulls onto the shoulder and stops.

enum Mode { PARKED, CHASING, GIVING_UP }

const FOLLOW_GAP := 10.0  ## m behind the player while chasing
const STOP_GAP := 7.0  ## m: close enough, stop here
const SHOULDER := 6.0  ## m right of the centerline, where it pulls over (Cops.PARK_OFFSET)

var mode := Mode.PARKED
var target: Car


func update(car: Car, delta: float) -> void:
	car.handbrake = false
	match mode:
		Mode.PARKED:
			_hold(car)
		Mode.GIVING_UP:
			_give_up(car)
		Mode.CHASING:
			_chase(car)


func _chase(car: Car) -> void:
	var speed := car.forward_speed()
	var to_target := target.global_position - car.global_position
	var gap := Vector2(to_target.x, to_target.z).length()
	var both_on_road := absf(target.lateral) < RoadMesher.DITCH_EDGE and absf(car.lateral) < RoadMesher.DITCH_EDGE
	var their_speed := target.linear_velocity.dot(car.route.tangent_at(target.station))
	if both_on_road and target.station < car.station and their_speed > 5.0:
		# They're still coming up from behind: get rolling along the shoulder and let them
		# go by before pulling out.
		var s := car.station + 20.0
		var local_ahead := car.global_transform.affine_inverse() * (car.route.position_at(s) + car.route.right_at(s) * SHOULDER)
		car.steer = Autopilot.steer_toward(local_ahead, car.stats.steer_limit(speed))
		_speed_to(car, minf(their_speed * 0.4, 15.0), speed)
		return
	var aim := target.global_position
	if both_on_road and target.station > car.station + 20.0:
		# Down the road, in their lane.
		var look := clampf(speed * 0.9, 12.0, 40.0)
		var s := minf(car.station + look, target.station)
		var lane := clampf(target.lateral, -RoadMesher.PAVED_HALF_WIDTH + 1.0, RoadMesher.PAVED_HALF_WIDTH - 1.0)
		aim = car.route.position_at(s) + car.route.right_at(s) * lane
	var local := car.global_transform.affine_inverse() * aim
	car.steer = Autopilot.steer_toward(local, car.stats.steer_limit(speed))
	# Flat out to catch up, then match their speed a following distance back.
	var wanted := car.stats.top_speed
	if gap < 150.0:
		wanted = target.linear_velocity.length() + (gap - FOLLOW_GAP) * 0.5
	if gap < STOP_GAP:
		wanted = 0.0
	# Facing away from them (after they spun past): slow down to turn around.
	var off_angle := absf(atan2(local.x, -local.z))
	wanted = lerpf(wanted, minf(wanted, 8.0), clampf((off_angle - 0.5) / 0.7, 0.0, 1.0))
	_speed_to(car, clampf(wanted, 0.0, car.stats.top_speed), speed)


func _give_up(car: Car) -> void:
	var speed := car.forward_speed()
	var s := car.station + clampf(speed * 0.9, 8.0, 30.0)
	var local := car.global_transform.affine_inverse() * (car.route.position_at(s) + car.route.right_at(s) * SHOULDER)
	car.steer = Autopilot.steer_toward(local, car.stats.steer_limit(speed))
	_speed_to(car, 0.0, speed)


func _hold(car: Car) -> void:
	car.throttle = 0.0
	car.steer = 0.0
	# No pedals at a standstill: the car's automatic hold keeps it put (holding the
	# brake would put it in reverse).
	car.brake = 0.0 if absf(car.forward_speed()) < 0.6 else 1.0


func _speed_to(car: Car, wanted: float, speed: float) -> void:
	if wanted < 0.5 and absf(speed) < 0.6:
		_hold(car)
		return
	var error := wanted - speed
	car.throttle = clampf(error * 0.4, 0.0, 1.0)
	car.brake = clampf(-error * 0.3, 0.0, 1.0)
