class_name Car
extends RigidBody3D
## Arcade raycast car. Each wheel is a ray: a spring-damper pushes the body up, and the
## tire pushes back against sliding sideways and drives/brakes along its heading,
## capped by friction. All tuning comes from CarStats.
##
## Body axes: -Z is forward, +X is right, +Y is up.

const WORLD_LAYER := 1
const CAR_LAYER := 2
const DEBRIS_LAYER := 3
const WRECK_LAYER := 4  ## crashed traffic: solid to the car, unlike flying mailboxes
const GRAVITY := 9.8

## Something hit the car (or the car hit something) hard enough to do damage.
## `smash` is true for things you're meant to plow through (mailboxes, hay bales).
signal hit(damage: float, smash: bool)

## Grip multiplier and extra rolling resistance per surface.
const SURFACES := {
	"asphalt": {"grip": 1.0, "rolling": 0.0},
	"gravel": {"grip": 0.72, "rolling": 0.03},
	"grass": {"grip": 0.6, "rolling": 0.07},
}


class Wheel:
	var mount: Vector3  ## top of the suspension, body space
	var front: bool
	var left: bool
	var grounded := false
	var compression := 0.0
	var spring_length := 0.0
	var load := 0.0  ## suspension force, N
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var surface := "asphalt"
	var spin := 0.0  ## radians, for the visual
	var slide := 0.0  ## sideways slip speed, m/s


## Driver inputs, written every physics tick by whoever is driving.
var throttle := 0.0  ## 0..1
var brake := 0.0  ## 0..1; also reverse when stopped
var steer := 0.0  ## -1 (left) .. 1 (right)
var handbrake := false
var driver: Object  ## anything with update(car: Car, delta: float)

var stats: CarStats
var route: RouteData
var station := 0.0  ## distance along the route of the nearest centerline point
var lateral := 0.0  ## meters right of the centerline
var wheels: Array[Wheel] = []
var steer_angle := 0.0  ## radians, positive turns left
var model: CarModel
var _rear_loose := 0.0  ## 0 = rear tires gripping, 1 = locked and sliding (handbrake)
var health := 100.0
var _last_velocity := Vector3.ZERO
var _impact_grace := 0.0  ## seconds to ignore jolts after being placed
var peak_jolt := 0.0  ## biggest one-tick velocity change seen (m/s), for tuning damage


func setup(car_stats: CarStats, r: RouteData) -> void:
	stats = car_stats
	route = r
	mass = stats.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, stats.center_of_mass_y, 0.0)
	continuous_cd = true
	# Our own drag model handles air resistance; the engine's default damping would add
	# another ~4 kN at highway speed.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	collision_layer = 1 << (CAR_LAYER - 1)
	collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (WRECK_LAYER - 1))

	var shape := BoxShape3D.new()
	shape.size = Vector3(stats.body_size.x, 0.72, stats.body_size.z * 0.97)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.08, 0.0)
	add_child(col)

	var half_track := stats.track / 2.0
	var half_base := stats.wheelbase / 2.0
	for z in [-half_base, half_base]:
		for x in [-half_track, half_track]:
			var w := Wheel.new()
			w.mount = Vector3(x, stats.mount_y, z)
			w.front = z < 0.0
			w.left = x < 0.0
			w.spring_length = stats.rest_length
			wheels.append(w)

	model = CarModel.new()
	add_child(model)
	model.build(stats, wheels)
	repair()


func repair() -> void:
	health = stats.durability
	model.set_damage(0.0)


## Plowing through something: lose `velocity_scale` of the speed and take `damage`,
## without the slowdown also counting as a second impact.
func bump(velocity_scale: float, damage: float, smash := true) -> void:
	bump_to(linear_velocity * velocity_scale, damage, smash)


## A collision that leaves the car moving at `velocity` (momentum shared with whatever
## it hit), without the change also counting as a second impact.
func bump_to(velocity: Vector3, damage: float, smash := false) -> void:
	linear_velocity = velocity
	_last_velocity = velocity
	apply_hit(damage, smash)


## Take damage from a collision.
func apply_hit(damage: float, smash := false) -> void:
	if damage <= 0.0:
		return
	health = maxf(health - damage, 0.0)
	model.set_damage(1.0 - health / stats.durability)
	hit.emit(damage, smash)


## Put the car on the road at a station, in the northbound lane, stopped.
func place_at(s: float, lane_offset := 1.83) -> void:
	station = s
	var pos := route.position_at(s) + route.right_at(s) * lane_offset
	var ahead := route.position_at(s + 5.0) + route.right_at(s + 5.0) * lane_offset
	ahead.y = pos.y
	pos.y += 0.9
	ahead.y += 0.9
	global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(ahead, Vector3.UP)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer_angle = 0.0
	for w in wheels:
		w.compression = 0.0
		w.spring_length = stats.rest_length
	_last_velocity = Vector3.ZERO
	_impact_grace = 0.5
	reset_physics_interpolation()


## Forward speed in m/s (negative when reversing).
func forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


func grounded_wheels() -> int:
	var n := 0
	for w in wheels:
		if w.grounded:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if stats == null:
		return
	if driver:
		driver.update(self, delta)
	else:
		throttle = 0.0
		brake = 0.0
		steer = 0.0
		handbrake = false
	_track_route()
	_check_impact(delta)

	var xf := global_transform
	var up := xf.basis.y
	var forward := -xf.basis.z
	var speed := linear_velocity.dot(forward)
	var limit := stats.steer_limit(speed)
	steer_angle = move_toward(steer_angle, -steer * limit, stats.steer_rate * delta)

	var space := get_world_3d().direct_space_state
	for w in wheels:
		_suspend(w, xf, up, space, delta)
	_anti_roll(xf, up)

	# Drive split across the front tires; reverse when the brake is held at a standstill.
	var reversing := brake > 0.1 and throttle < 0.1 and speed < 0.5
	var drive := throttle * stats.drive_force(maxf(speed, 0.0))
	var braking := brake
	if reversing:
		drive = -brake * stats.reverse_force * clampf((stats.reverse_speed + speed) / 2.0, 0.0, 1.0)
		braking = 0.0
	elif throttle < 0.05 and brake < 0.05 and absf(speed) < 0.6:
		braking = 0.5  # hold still on hills with no pedals pressed, like an automatic
	_update_rear_grip(delta)
	_handbrake_kick(up, speed)
	_stabilize_spin(up)
	var com := xf * center_of_mass
	for w in wheels:
		if w.grounded:
			_tire(w, forward, up, com, drive * 0.5 if w.front else 0.0, braking)

	apply_central_force(-linear_velocity * linear_velocity.length() * stats.drag)
	model.update_wheels(wheels, steer_angle, stats)


## A collision shows up as a sudden change in velocity. Normal driving stays under
## ~0.3 m/s per physics tick, drifts ~0.7, and landing big ditch jumps ~1.8.
func _check_impact(delta: float) -> void:
	var jolt := (linear_velocity - _last_velocity).length()
	_last_velocity = linear_velocity
	_impact_grace = maxf(_impact_grace - delta, 0.0)
	if _impact_grace > 0.0:
		return
	peak_jolt = maxf(peak_jolt, jolt)
	if jolt > stats.impact_threshold:
		apply_hit((jolt - stats.impact_threshold) * stats.impact_damage)


func _track_route() -> void:
	station = route.nearest_station(global_position, station, 60.0)
	var center := route.position_at(station)
	lateral = (global_position - center).dot(route.right_at(station))


func _suspend(w: Wheel, xf: Transform3D, up: Vector3, space: PhysicsDirectSpaceState3D, delta: float) -> void:
	var origin := xf * w.mount
	var reach := stats.rest_length + stats.wheel_radius
	var query := PhysicsRayQueryParameters3D.create(origin, origin - up * reach, 1 << (WORLD_LAYER - 1), [get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		w.grounded = false
		w.load = 0.0
		w.compression = 0.0
		w.spring_length = stats.rest_length
		return

	w.grounded = true
	w.contact = hit.position
	w.normal = hit.normal
	w.surface = _surface_at(hit)
	w.spring_length = clampf(origin.distance_to(hit.position) - stats.wheel_radius, 0.0, stats.rest_length)
	var compression := stats.rest_length - w.spring_length
	var force := stats.spring * compression + stats.damper * (compression - w.compression) / delta
	w.compression = compression
	if w.spring_length < 0.04:  # bump stop
		force += (0.04 - w.spring_length) * stats.spring * 8.0
	w.load = clampf(force, 0.0, stats.mass * GRAVITY * 2.5)
	apply_force(up * w.load, origin - global_position)


## The handbrake locks the rears: they lose most of their sideways grip. Letting go brings
## the grip back over a moment rather than instantly, so a yank swings the tail out
## and the slide carries on long enough to catch with countersteer and throttle.
func _update_rear_grip(delta: float) -> void:
	_rear_loose = 1.0 if handbrake else move_toward(_rear_loose, 0.0, stats.drift_recovery * delta)


## While the handbrake is held, nudge the car's rotation toward a target yaw rate set by
## the steering. A tap gives an immediate, proportional swing. The kick only starts the
## slide: it stops once the car is well sideways, so it never spins the car by itself
## (holding the handbrake at full lock too long still will, the honest way).
func _handbrake_kick(up: Vector3, speed: float) -> void:
	if not handbrake or speed < 3.0 or steer == 0.0:
		return
	if DriftDriver.slip_angle(self) > stats.handbrake_kick_max_slip:
		return
	var target := -steer * deg_to_rad(stats.handbrake_yaw_rate)
	var current := angular_velocity.dot(up)
	if signf(target - current) != signf(target):
		return  # already swinging at least that fast
	var yaw_inertia := stats.mass * (stats.body_size.x ** 2 + stats.body_size.z ** 2) / 12.0
	var torque := clampf((target - current) * yaw_inertia * 8.0, -stats.handbrake_yaw_assist, stats.handbrake_yaw_assist)
	apply_torque(up * torque * clampf(speed / 12.0, 0.0, 1.0))


## Arcade drift assist: once the car is far sideways (40-80 degrees), damp its rotation
## so big slides are holdable and a full spin takes real effort.
func _stabilize_spin(up: Vector3) -> void:
	if linear_velocity.length() < 8.0 or grounded_wheels() < 2:
		return
	var weight := smoothstep(40.0, 80.0, DriftDriver.slip_angle(self))
	if weight == 0.0:
		return
	var yaw_inertia := stats.mass * (stats.body_size.x ** 2 + stats.body_size.z ** 2) / 12.0
	apply_torque(-up * angular_velocity.dot(up) * yaw_inertia * stats.spin_damping * weight)


## Roll bars: push the low side of each axle up and the high side down.
func _anti_roll(xf: Transform3D, up: Vector3) -> void:
	for pair in [[0, 1], [2, 3]]:
		var l: Wheel = wheels[pair[0]]
		var r: Wheel = wheels[pair[1]]
		if not (l.grounded and r.grounded):
			continue
		var force := (l.compression - r.compression) * stats.anti_roll
		apply_force(up * force, xf * l.mount - global_position)
		apply_force(-up * force, xf * r.mount - global_position)


func _tire(w: Wheel, forward: Vector3, up: Vector3, com: Vector3, drive: float, braking: float) -> void:
	var n := w.normal
	var heading := forward.rotated(up, steer_angle) if w.front else forward
	var fwd := (heading - n * heading.dot(n)).normalized()
	var side := fwd.cross(n)
	var v := linear_velocity + angular_velocity.cross(w.contact - com)
	var v_long := v.dot(fwd)
	var v_lat := v.dot(side)
	var surface: Dictionary = SURFACES[w.surface]
	var rear_handbrake := handbrake and not w.front
	var loose := 0.0 if w.front else _rear_loose

	var f_lat := -v_lat * stats.cornering_stiffness * lerpf(1.0, stats.handbrake_grip, loose)
	var f_long := drive
	if braking > 0.0:
		var b := braking * stats.brake_force / 4.0
		f_long -= clampf(v_long * 2000.0, -b, b)
	if rear_handbrake:
		var hb := stats.handbrake_force / 2.0
		f_long -= clampf(v_long * 2000.0, -hb, hb)
	f_long -= clampf(v_long, -1.0, 1.0) * (stats.rolling_resistance + surface.rolling) * w.load

	# Friction circle: total tire force can't exceed grip x load.
	# Rubber grips best just before it lets go: a tire sliding sideways has less grip,
	# which is what lets a drift keep going once it's started.
	var sliding := lerpf(1.0, stats.slide_friction, smoothstep(2.0, 6.0, absf(v_lat)))
	var limit: float = stats.grip * surface.grip * w.load * sliding * lerpf(1.0, stats.handbrake_friction, loose)
	var total := Vector2(f_long, f_lat).length()
	if total > limit and total > 0.0:
		f_long *= limit / total
		f_lat *= limit / total
	w.slide = absf(v_lat)
	w.spin += v_long / stats.wheel_radius * get_physics_process_delta_time()
	apply_force(fwd * f_long + side * f_lat, w.contact - global_position)


## Road colliders are tagged "road"; where on the road decides asphalt vs gravel shoulder.
func _surface_at(hit: Dictionary) -> String:
	var collider: Object = hit.collider
	if collider == null or collider.get_meta("surface", "grass") != "road":
		return "grass"
	var center := route.position_at(station)
	var offset := absf((hit.position - center).dot(route.right_at(station)))
	return "asphalt" if offset <= RoadMesher.PAVED_HALF_WIDTH else "gravel"
