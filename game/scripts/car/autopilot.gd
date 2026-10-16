class_name Autopilot
extends RefCounted
## Drives the northbound lane at a target speed: steers toward a point down the road
## (pure pursuit) and works the pedals to hold speed. Used by the QA drive and for demos.

const LANE_OFFSET := 1.83

var target_speed := 31.3  ## m/s, 70 mph


func update(car: Car, _delta: float) -> void:
	var speed := car.forward_speed()
	var look := clampf(speed * 0.9, 12.0, 40.0)
	var s := car.station + look
	var target := car.route.position_at(s) + car.route.right_at(s) * LANE_OFFSET
	var local := car.global_transform.affine_inverse() * target
	car.steer = steer_toward(local, car.stats.steer_limit(speed))

	# Facing the wrong way (after a spin): slow down to make the U-turn, or the steering
	# lock shrinks with speed and the car runs off across the fields.
	var off_angle := absf(atan2(local.x, -local.z))
	var wanted := lerpf(target_speed, 8.0, clampf((off_angle - 0.5) / 0.7, 0.0, 1.0))
	var error := wanted - speed
	car.throttle = clampf(error * 0.4, 0.0, 1.0)
	car.brake = clampf(-error * 0.25, 0.0, 1.0)
	car.handbrake = false


## Steering input (-1 left .. 1 right) that points the front wheels at a target given
## in the car's local space (-Z forward, +X right).
static func steer_toward(local_target: Vector3, steer_limit: float) -> float:
	var angle := atan2(local_target.x, -local_target.z)
	return clampf(angle * 2.0 / maxf(steer_limit, 0.01), -1.0, 1.0)
