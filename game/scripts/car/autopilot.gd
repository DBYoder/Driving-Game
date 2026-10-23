class_name Autopilot
extends RefCounted
## Drives the northbound lane at a target speed: steers toward a point down the road
## (pure pursuit) and works the pedals to hold speed. With traffic, it follows slow
## vehicles and overtakes them where the line is dashed and the oncoming lane is clear.
## With deer crossing ahead it holds its speed and its lane (they time their run to
## miss a car doing that). On a wet or snowy road it leaves more room, and it slows
## down for black ice it can see coming.
## Used by the QA drives
## and for demos.

const LANE_OFFSET := 1.83
const PASS_CLEARANCE := 450.0  ## meters of empty oncoming lane needed to pass
const FOLLOW_GAP := 25.0
const ICE_SPEED := 22.0  ## m/s (50 mph) over black ice
const ICE_LOOK_SECONDS := 4.0
const STUCK_SECONDS := 4.0  ## flooring it and going nowhere this long: back out
const BACK_OUT_SECONDS := 2.0

var target_speed := 31.3  ## m/s, 70 mph
var cruise_lane := LANE_OFFSET  ## meters right of the centerline it holds when not passing
var traffic: Traffic  ## optional
var deer: Deer  ## optional
var passing := false
var lane := LANE_OFFSET  ## where it's steering: the northbound lane, or the other one to pass
var _passing_vehicle: Traffic.Vehicle
var unstuck_count := 0  ## times it had to back out of something (QA reports it)
var _stuck := 0.0
var _backing := 0.0


func update(car: Car, delta: float) -> void:
	var speed := car.forward_speed()
	var wanted := target_speed
	var deer_ahead := deer != null and deer.danger_ahead(car.station, maxf(speed * 4.0, 80.0)) < INF
	if traffic:
		wanted = minf(wanted, _plan_traffic(car, deer_ahead))
	if deer_ahead:
		wanted = minf(wanted, maxf(speed, 0.0) + 0.2)  # no speeding up into them
	if _ice_ahead(car, maxf(speed * ICE_LOOK_SECONDS, 60.0)):
		wanted = minf(wanted, ICE_SPEED)
	# Across to the other lane and back, gently when slow (the car has to keep up).
	lane = move_toward(lane, -LANE_OFFSET if passing else cruise_lane, clampf(speed * 0.12, 1.0, 3.0) * delta)

	var look := clampf(speed * 0.9, 12.0, 40.0)
	var s := car.station + look
	# (Through the 4-way the lanes shift out for the turn lanes: so does the line it holds.)
	var lateral := lane + signf(lane) * (car.route.lane_offset(s) - RouteData.LANE)
	var target := car.route.position_at(s) + car.route.right_at(s) * lateral
	var local := car.global_transform.affine_inverse() * target
	car.steer = steer_toward(local, car.stats.steer_limit(speed))

	# Facing the wrong way (after a spin): slow down to make the U-turn, or the steering
	# lock shrinks with speed and the car runs off across the fields.
	var off_angle := absf(atan2(local.x, -local.z))
	wanted = lerpf(wanted, 8.0, clampf((off_angle - 0.5) / 0.7, 0.0, 1.0))
	var error := wanted - speed
	car.throttle = clampf(error * 0.4, 0.0, 1.0)
	car.brake = clampf(-error * 0.25, 0.0, 1.0)
	car.handbrake = false
	# Pinned against something (a wreck across the road): back out, wheel turned away.
	_stuck = _stuck + delta if car.throttle > 0.8 and absf(speed) < 0.5 else 0.0
	if _stuck > STUCK_SECONDS:
		_stuck = 0.0
		_backing = BACK_OUT_SECONDS
		unstuck_count += 1
		passing = false
		_passing_vehicle = null
	if _backing > 0.0:
		_backing -= delta
		car.throttle = 0.0
		car.brake = 1.0  # held at a standstill: reverse
		car.steer = -car.steer


## Decide whether to follow, start passing or finish passing. Returns the speed to hold.
## A line of slow vehicles (a car stuck behind a buggy) is passed as one: the oncoming
## lane has to be clear for all of it, and the pass isn't over until the whole line is.
func _plan_traffic(car: Car, deer_ahead: bool) -> float:
	var stopping := _stopping_distance(car)
	if passing:
		var last := _passing_vehicle
		var done: bool = last == null or not traffic.vehicles.has(last) \
			or car.station > last.station + Traffic.KINDS[last.kind].length / 2.0 + 15.0
		if done:
			# Something else slow too close ahead to pull in and stop behind: carry on past it.
			var next := traffic.leader(car.station, 1.0, stopping, false)
			if next and next.speed < target_speed - 2.0 and traffic.oncoming_clear(car.station, 150.0 + stopping):
				_passing_vehicle = _end_of_line(next, stopping)
				return target_speed
			passing = false
			_passing_vehicle = null
		elif not traffic.oncoming_clear(car.station, 150.0):
			passing = false  # abort: tuck back in behind
		return target_speed
	var lead := traffic.leader(car.station, 1.0, 150.0, false)
	if lead == null or lead.speed > target_speed - 2.0:
		return target_speed
	var gap: float = lead.station - car.station - Traffic.KINDS[lead.kind].length / 2.0
	var last := _end_of_line(lead, stopping)
	var line_length: float = last.station - lead.station + Traffic.KINDS[last.kind].length
	var may_pass := not car.route.no_passing(car.station, 1.0) \
		and not car.route.no_passing(car.station + 150.0 + line_length, 1.0)
	var icy := _ice_ahead(car, 150.0 + line_length)  # no passing on black ice
	if gap < 90.0 and may_pass and not deer_ahead and not icy and traffic.oncoming_clear(car.station, PASS_CLEARANCE + 2.0 * line_length):
		passing = true
		_passing_vehicle = last
		return target_speed
	# Can't pass yet: follow, further back and slowing earlier the less grip there is.
	var grip := car.grip_scale
	return minf(target_speed, lead.speed + maxf(gap - FOLLOW_GAP / grip, 0.0) * 0.3 * grip)


## Black ice on the road within `ahead` meters (or under the car)?
func _ice_ahead(car: Car, ahead: float) -> bool:
	for i in range(0, car.ice.size(), 2):
		if car.ice[i + 1] >= car.station and car.ice[i] <= car.station + ahead:
			return true
	return false


## Meters to stop from the speed it's going, gently, on this road's grip (plus room).
func _stopping_distance(car: Car) -> float:
	var v := maxf(car.forward_speed(), 0.0)
	return maxf(60.0, v * v / (2.0 * 4.0 * car.grip_scale) + 20.0)


## The last of a line of slow vehicles that starts with `first`: each one less than
## `room` (the stopping distance) beyond the last, so there's no pulling in between them.
func _end_of_line(first: Traffic.Vehicle, room: float) -> Traffic.Vehicle:
	var last := first
	for i in 8:
		var next := traffic.leader(last.station, 1.0, Traffic.KINDS[last.kind].length / 2.0 + room, false)
		if next == null or next.speed > target_speed - 2.0:
			break
		last = next
	return last


## Steering input (-1 left .. 1 right) that points the front wheels at a target given
## in the car's local space (-Z forward, +X right).
static func steer_toward(local_target: Vector3, steer_limit: float) -> float:
	var angle := atan2(local_target.x, -local_target.z)
	return clampf(angle * 2.0 / maxf(steer_limit, 0.01), -1.0, 1.0)
