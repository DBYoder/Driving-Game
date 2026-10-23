class_name Car
extends RigidBody3D
## Arcade raycast car. Each wheel is a ray: a spring-damper pushes the body up, and the
## tire pushes back against sliding sideways and drives/brakes along its heading,
## capped by friction. All tuning comes from CarStats.
##
## Body axes: -Z is forward, +X is right, +Y is up.

const WORLD_LAYER := 1
const CAR_LAYER := 2
const DEBRIS_LAYER := 3  ## smashed props
const WRECK_LAYER := 4  ## crashed traffic
const COP_LAYER := 5  ## police cruisers (physics cars like the player's)
const GRAVITY := 9.8

## Something hit the car (or the car hit something) hard enough to do damage.
## `smash` is true for things you're meant to plow through (mailboxes, hay bales).
signal hit(damage: float, smash: bool)
## A piece of the car came off (a hubcap, a bumper...); it's a physics body now.
signal part_lost(body: RigidBody3D)

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
var boost_held := false  ## burn the boost meter (if there's any in it)
var horn := false  ## leaning on the horn (it scares deer off the road)
var driver: Object  ## anything with update(car: Car, delta: float)

var stats: CarStats
var route: RouteData
var station := 0.0  ## distance along the route of the nearest centerline point
var lateral := 0.0  ## meters right of the centerline
var wheels: Array[Wheel] = []
var steer_angle := 0.0  ## radians, positive turns left
var model: CarModel
var body_shape: CollisionShape3D  ## the lower body's box
var grip_scale := 1.0  ## the weather's: wet or snowy roads grip less (Condition.grip)
var ice := PackedFloat32Array()  ## [from, to] station pairs of black ice on the road
var ice_grip := 1.0  ## grip on it
var on_ice := false
var boost := Boost.new()  ## filled by near misses (Traffic), burned with boost_held
var headlights := false:  ## at night
	set(value):
		headlights = value
		if model:
			model.set_headlights(value)
var _rear_loose := 0.0  ## 0 = rear tires gripping, 1 = locked and sliding (handbrake)
var health := 100.0
var _last_velocity := Vector3.ZERO
var _accel := Vector3.ZERO  ## smoothed acceleration in the car's own space, for the body lean
var _accel_last_velocity := Vector3.ZERO
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
	collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (DEBRIS_LAYER - 1)) | (1 << (WRECK_LAYER - 1)) \
		| (1 << (COP_LAYER - 1))
	if stats.style == "cruiser":
		collision_layer = 1 << (COP_LAYER - 1)
		collision_mask = (1 << (WORLD_LAYER - 1)) | (1 << (CAR_LAYER - 1)) | (1 << (DEBRIS_LAYER - 1)) \
			| (1 << (WRECK_LAYER - 1))

	# The lower body, from the bottom of the bumpers up to the beltline: what you see
	# scrape on a hard landing is what touches the ground.
	var shape := BoxShape3D.new()
	shape.size = Vector3(stats.body_size.x, 0.84, stats.body_size.z * 0.97)
	body_shape = CollisionShape3D.new()
	body_shape.shape = shape
	body_shape.position = Vector3(0.0, 0.02, 0.0)
	add_child(body_shape)

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

	repair()


## Become another car (the car-select screen): its body, wheels and model, good as new.
func change(car_stats: CarStats) -> void:
	body_shape.free()
	wheels.clear()
	setup(car_stats, route)


## Good as new: full health, a fresh body with every part back on.
func repair() -> void:
	health = stats.durability
	if model:
		model.free()
	model = CarModel.new()
	add_child(model)
	model.build(stats, wheels)
	model.part_lost.connect(func(body): part_lost.emit(body))
	model.set_headlights(headlights)


## Plowing through something: lose `velocity_scale` of the speed and take `damage`,
## without the slowdown also counting as a second impact.
func bump(velocity_scale: float, damage: float, smash := true) -> void:
	bump_to(linear_velocity * velocity_scale, damage, smash)


## A collision that leaves the car moving at `velocity` (momentum shared with whatever
## it hit), without the change also counting as a second impact.
func bump_to(velocity: Vector3, damage: float, smash := false) -> void:
	var change := velocity - linear_velocity
	linear_velocity = velocity
	_last_velocity = velocity
	apply_hit(damage, smash, -change)


## Take damage from a collision. `toward_hit` (world space) points from the car toward
## what it hit, which is where it dents and what falls off first.
func apply_hit(damage: float, smash := false, toward_hit := Vector3.ZERO) -> void:
	if damage <= 0.0:
		return
	health = maxf(health - damage, 0.0)
	var local := global_transform.basis.inverse() * toward_hit
	local.y = 0.0
	model.dent(local, damage / stats.durability)
	var at := local.normalized() * stats.body_size.z / 2.0 if local.length() > 0.01 else Vector3.ZERO
	model.set_damage(1.0 - health / stats.durability, at)
	hit.emit(damage, smash)


## Put the car on the road at a station, in the northbound lane, stopped.
func place_at(s: float, lane_offset := NAN) -> void:
	station = s
	if is_nan(lane_offset):
		lane_offset = route.lane_offset(s)
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
	_accel_last_velocity = Vector3.ZERO
	_accel = Vector3.ZERO
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
		boost_held = false
		horn = false
	_track_route()
	on_ice = false
	for i in range(0, ice.size(), 2):
		if station >= ice[i] and station <= ice[i + 1]:
			on_ice = true
			break
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
	# Boosting, the engine pulls past its usual top speed and a shove on top of that
	# (straight through the body, so the tires keep their grip for steering).
	var boosting := boost.update(boost_held and brake < 0.1 and not freeze, delta)
	var reversing := brake > 0.1 and throttle < 0.1 and speed < 0.5
	var boost_top := Boost.top_speed(stats.top_speed)
	var drive := throttle * stats.drive_force(maxf(speed, 0.0), boost_top - stats.top_speed if boosting else 0.0)
	if boosting:
		_boost_push(forward, up, clampf((boost_top - speed) / 4.0, 0.0, 1.0))
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
	var accel := global_transform.basis.inverse() * (linear_velocity - _accel_last_velocity) / delta
	_accel_last_velocity = linear_velocity
	_accel = _accel.lerp(accel, 1.0 - exp(-delta * 8.0))
	model.set_boost(boosting)
	model.update(wheels, steer_angle, _accel, speed, delta)


## The boost's shove (`amount` of it: it fades out near the boosted top speed): along
## the car on the ground, level in the air (so a jump goes further, not higher).
func _boost_push(forward: Vector3, up: Vector3, amount: float) -> void:
	var push := forward
	if grounded_wheels() < 2 or up.y < 0.5:
		push = Vector3(forward.x, 0.0, forward.z)
		if push.length() < 0.1:
			return
		push = push.normalized()
	apply_central_force(push * Boost.THRUST * stats.mass * amount)


## A collision shows up as a sudden change in velocity. Normal driving stays under
## ~0.3 m/s per physics tick, drifts ~0.7, and landing big ditch jumps ~1.8.
func _check_impact(delta: float) -> void:
	var change := linear_velocity - _last_velocity
	var jolt := change.length()
	_last_velocity = linear_velocity
	if freeze:
		# Moved around by script (a far-off cruiser on rails): no collisions to feel, and a
		# moment's grace once it's let go.
		_impact_grace = 0.5
		return
	_impact_grace = maxf(_impact_grace - delta, 0.0)
	if _impact_grace > 0.0:
		return
	peak_jolt = maxf(peak_jolt, jolt)
	if jolt > stats.impact_threshold:
		apply_hit((jolt - stats.impact_threshold) * stats.impact_damage, false, -change)


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
	var weather := grip_scale * (ice_grip if on_ice and w.surface != "grass" else 1.0)
	var limit: float = stats.grip * surface.grip * weather * w.load * sliding * lerpf(1.0, stats.handbrake_friction, loose)
	var total := Vector2(f_long, f_lat).length()
	if total > limit and total > 0.0:
		f_long *= limit / total
		f_lat *= limit / total
	w.slide = absf(v_lat)
	w.spin += v_long / stats.wheel_radius * get_physics_process_delta_time()
	apply_force(fwd * f_long + side * f_lat, w.contact - global_position)


## Road colliders are tagged "road"; where on the road decides asphalt vs gravel shoulder.
## Streets are tagged with their own surface.
func _surface_at(hit: Dictionary) -> String:
	var collider: Object = hit.collider
	var tag: String = collider.get_meta("surface", "grass") if collider != null else "grass"
	if tag != "road":
		return tag if SURFACES.has(tag) else "grass"
	var center := route.position_at(station)
	var offset := absf((hit.position - center).dot(route.right_at(station)))
	return "asphalt" if offset <= RoadMesher.PAVED_HALF_WIDTH else "gravel"
