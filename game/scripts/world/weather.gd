class_name Weather
extends Node3D
## What falls from the sky and blows across the road: rain or snow around the camera,
## lightning (a flash of the sky, then thunder a moment later) and side gusts that shove
## the car, hardest on the tallest, slab-sided ones. Plus where the black ice is in winter.

const WIND_FROM := Vector3(-1.0, 0.0, 0.0)  ## gusts blow from the west, across the road
const GUST_SECONDS := Vector2(4.0, 11.0)  ## between gusts
const GUST_LENGTH := 2.2  ## seconds a gust lasts
const LIGHTNING_SECONDS := Vector2(7.0, 18.0)
const ICE_TREE_REACH := 12.0  ## trees reaching this close to the centerline shade the road: black ice there
const ICE_PATCH := 15.0  ## meters of ice around each shaded spot or bridge end
const MIX_RATE := 22050.0

var car: Car
var camera: Camera3D
var env: Environment
var sky: ShaderMaterial
var condition: Condition
var gust := 0.0  ## side pressure right now, N/m² (QA and the HUD can read it)
var flashes := 0
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _next_gust := 3.0
var _gust_t := -1.0
var _gust_peak := 0.0
var _next_flash := 5.0
var _flash := -1.0
var _thunder_in := -1.0
var _rumble := 0.0  ## thunder loudness, decaying
var _base_ambient := 0.55
var _base_sky := Color()
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _brown := 0.0
var _hiss := 0.0


func setup(c: Car, cam: Camera3D, environment: Environment, sky_material: ShaderMaterial) -> void:
	car = c
	camera = cam
	env = environment
	sky = sky_material
	_rng.randomize()
	_rain = _particles(900, 0.75, Vector3(26, 1, 26), Vector2(0.025, 0.8), Color(0.72, 0.78, 0.84, 0.35), true)
	_snow = _particles(1400, 5.0, Vector3(32, 1, 32), Vector2(0.09, 0.09), Color(0.97, 0.98, 1.0, 0.95), false)
	_audio = AudioStreamPlayer.new()
	_audio.bus = "Effects"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.15
	_audio.stream = generator
	_audio.volume_db = -6.0
	add_child(_audio)


func apply(c: Condition) -> void:
	condition = c
	_base_ambient = c.ambient_energy
	_base_sky = c.sky_top
	_rain.emitting = c.rain > 0.0
	_rain.visible = c.rain > 0.0
	_snow.emitting = c.snowfall > 0.0
	_snow.visible = c.snowfall > 0.0
	gust = 0.0
	_gust_t = -1.0
	_flash = -1.0
	_rumble = 0.0
	var sound := c.rain > 0.0 or c.lightning
	if sound and not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback()
	elif not sound and _audio.playing:
		_audio.stop()
		_playback = null


## How much rain and snow to draw (the graphics preset: Low halves it).
func set_particle_scale(scale: float) -> void:
	_rain.amount = maxi(int(900 * scale), 50)
	_snow.amount = maxi(int(1400 * scale), 50)


## Stretches of black ice for a condition that has it: the bridges, and wherever trees
## stand close enough to the road to shade it. [from, to] station pairs.
static func ice_patches(route: RouteData) -> PackedFloat32Array:
	var spots: Array[float] = []
	for b: Array in route.bridges:
		spots.append(float(b[0]))
		spots.append(float(b[1]))
	for i in route.trees.size() / 5:
		var x := route.trees[i * 5]
		var z := route.trees[i * 5 + 1]
		if route.terrain.road_distance_smooth(x, z) - route.trees[i * 5 + 3] > ICE_TREE_REACH:
			continue
		var hint := route.terrain.station_hint(x, z)
		if hint >= 0.0:
			spots.append(route.nearest_station(Vector3(x, 0, z), hint, 300.0))
	spots.sort()
	var out := PackedFloat32Array()
	for s in spots:
		if not out.is_empty() and s - ICE_PATCH <= out[out.size() - 1]:
			out[out.size() - 1] = s + ICE_PATCH
		else:
			out.append(s - ICE_PATCH)
			out.append(s + ICE_PATCH)
	return out


func _particles(amount: int, lifetime: float, box: Vector3, size: Vector2, color: Color, streaks: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3.DOWN
	p.spread = 4.0 if streaks else 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 26.0 if streaks else 1.2
	p.initial_velocity_max = 32.0 if streaks else 2.4
	var quad := QuadMesh.new()
	quad.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if streaks else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	quad.material = m
	p.mesh = quad
	p.emitting = false
	p.visible = false
	add_child(p)
	return p


func _process(delta: float) -> void:
	if condition == null or camera == null:
		return
	# Keep the weather around and a little ahead of the camera.
	var ahead := car.linear_velocity * 0.5 if car else Vector3.ZERO
	_rain.global_position = camera.global_position + ahead + Vector3.UP * 16.0
	var drift := Vector3(condition.wind_gusts * 0.004 + gust * 0.01, 0, 0)
	_snow.gravity = drift
	_snow.global_position = camera.global_position + (ahead * 3.0 if car else Vector3.ZERO) + Vector3.UP * 10.0
	if condition.lightning:
		_lightning(delta)
	_fill_audio()


func _lightning(delta: float) -> void:
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(LIGHTNING_SECONDS.x, LIGHTNING_SECONDS.y)
		_flash = 0.0
		flashes += 1
		_thunder_in = _rng.randf_range(0.4, 2.8)
	if _flash >= 0.0:
		_flash += delta
		# Two quick pulses.
		var lit := (_flash < 0.07) or (_flash > 0.14 and _flash < 0.26)
		env.ambient_light_energy = _base_ambient + (2.2 if lit else 0.0)
		sky.set_shader_parameter("sky_top_color", _base_sky.lerp(Color(0.85, 0.88, 1.0), 0.8 if lit else 0.0))
		if _flash > 0.3:
			_flash = -1.0
			env.ambient_light_energy = _base_ambient
			sky.set_shader_parameter("sky_top_color", _base_sky)
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			_rumble = 1.0


func _physics_process(delta: float) -> void:
	if condition == null or car == null or condition.wind_gusts <= 0.0:
		gust = 0.0
		return
	_next_gust -= delta
	if _next_gust <= 0.0 and _gust_t < 0.0:
		_gust_t = 0.0
		_gust_peak = condition.wind_gusts * _rng.randf_range(0.6, 1.0)
		_next_gust = _rng.randf_range(GUST_SECONDS.x, GUST_SECONDS.y)
	if _gust_t >= 0.0:
		_gust_t += delta
		gust = _gust_peak * sin(PI * clampf(_gust_t / GUST_LENGTH, 0.0, 1.0))
		if _gust_t > GUST_LENGTH:
			_gust_t = -1.0
			gust = 0.0
	if gust <= 0.0 or car.freeze:
		return
	# Pressure on the car's side: the bigger the side, the harder the shove, and the wind
	# is stronger higher up, so tall cars catch more of it. It acts up at the middle of the
	# side, so it rolls a tall car over as it pushes.
	var size := car.stats.body_size
	var side := car.global_transform.basis.x
	var across := absf(side.dot(-WIND_FROM))
	var force := -WIND_FROM * gust * size.y * size.z * (size.y / 1.5) * across
	car.apply_force(force, car.global_transform.basis.y * size.y * 0.55)


## Rain hiss and thunder rumble, from noise.
func _fill_audio() -> void:
	if _playback == null:
		return
	var hiss := 0.06 * condition.rain
	for i in _playback.get_frames_available():
		var white := _rng.randf() * 2.0 - 1.0
		_hiss = _hiss * 0.6 + white * 0.4
		_brown = clampf(_brown * 0.985 + white * 0.05, -1.0, 1.0)
		_rumble = maxf(_rumble - 0.25 / MIX_RATE, 0.0)
		var s := _hiss * hiss + _brown * _rumble * 1.6
		_playback.push_frame(Vector2(s, s))
