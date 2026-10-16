extends Node3D
## Entry point: loads the baked road, builds the world around the car, and runs the game.
##
## Command-line options (after `--`):
##   --station=<m>        start the car here instead of just behind the Kalona start line
##   --view=<n>           camera: 0 chase, 1 hood, 2 far chase, 3 drone
##   --autopilot          let the autopilot drive (demo mode)
##   --autopilot-mph=<n>  the autopilot's cruising speed (default 70)
##   --tune=<k:v,...>     override CarStats values, e.g. --tune=handbrake_grip:0.2
##   --no-traffic         an empty road
##   --traffic-near       start with a buggy, a tractor and oncoming traffic in view
##   --qa-drive           autopilot the whole route, check for problems, exit 0/1
##   --qa-stress          random inputs for 4 minutes, check the physics holds up, exit 0/1
##   --qa-drift           a scripted handbrake turn; checks it slides and recovers, exit 0/1
##                        (--seed=<n> picks the random sequence; run the QA modes
##                        headless with --fixed-fps 60 to go faster than real time)
##   --smoke-test         load everything, drop the car on the road, check it, exit 0/1
##   --benchmark          autopilot at 70 mph for 40 s, print fps, draw calls, triangles
##   --screenshot=<path>  let the car settle, save a PNG, exit

const ROUTE_DIR := "res://data/route"
const SPAWN_BEHIND_START := 25.0
const LOST_SECONDS := 2.0  ## off the edge of the world this long -> towed back
const FOG_BEGIN := 450.0
const FOG_END := 3000.0  ## nothing past this is visible

var route: RouteData
var fields: Fields
var streamer: WorldStreamer
var props: PropField
var traffic: Traffic
var corn: CornField
var car: Car
var camera: ChaseCamera
var tracker: RunTracker
var run: Run
var hud: Hud
var _driver: Object
var _testing := false
var _spawn_station := 0.0
var _lost_time := 0.0


func _ready() -> void:
	var args := _parse_args()
	route = RouteData.load_from(ROUTE_DIR)
	if route == null:
		get_tree().quit(1)
		return
	fields = Fields.new(route)
	_testing = args.has("qa-drive") or args.has("qa-stress") or args.has("qa-drift")

	_add_environment()
	add_child(preload("res://scripts/game/pause_control.gd").new())
	streamer = WorldStreamer.new()
	streamer.setup(route)
	add_child(streamer)
	var roadside := Roadside.new()
	add_child(roadside)
	roadside.setup(route)

	var stats := CarStats.new()
	if args.has("tune"):
		_apply_tuning(stats, args.tune)
	car = Car.new()
	add_child(car)
	car.setup(stats, route)
	var drift := _pick_driver(args)
	var sound := EngineSound.new()
	sound.car = car
	car.add_child(sound)

	tracker = RunTracker.new(route.start_station, route.finish_station, car.stats.display_name,
		"" if _testing else RunTracker.SAVE_PATH)
	run = Run.new()
	add_child(run)
	run.setup(car, tracker)
	run.wrecked.connect(_on_wrecked)

	props = PropField.new()
	add_child(props)
	props.setup(route, fields, car, run.score)
	corn = CornField.new()
	add_child(corn)
	corn.setup(route, fields, car, run.score)
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(route, car, run, int(args.get("seed", "1")))
	traffic.enabled = not args.has("no-traffic") and not args.has("qa-drift")
	if _driver is Autopilot:
		_driver.traffic = traffic

	camera = ChaseCamera.new()
	add_child(camera)
	if args.has("view"):
		camera.mode = int(args.view)
	_spawn_station = float(args.station) if args.has("station") else route.start_station - SPAWN_BEHIND_START
	if drift:
		_spawn_station = route.start_station + 1.5 * RouteData.MILE_M  # the long straight north of Kalona
	_spawn(_spawn_station)
	camera.setup(car)
	if args.has("traffic-near"):
		traffic.populate_near()

	hud = Hud.new()
	add_child(hud)
	hud.setup(route, car, run, camera)

	if args.has("smoke-test"):
		_smoke_test()
	elif _testing:
		var qa := QaDrive.new()
		qa.car = car
		qa.run = run
		qa.stress = args.has("qa-stress")
		qa.drift = drift
		add_child(qa)
	elif args.has("screenshot"):
		_screenshot(args.screenshot)
	elif args.has("benchmark"):
		add_child(Benchmark.new())


## Who's driving. Returns the drift script when that's the test being run.
func _pick_driver(args: Dictionary) -> DriftDriver:
	var drift: DriftDriver = null
	if args.has("qa-stress"):
		_driver = StressDriver.new(int(args.get("seed", "1")))
	elif args.has("qa-drift"):
		drift = DriftDriver.new()
		drift.pull_time = float(args.get("drift-pull", drift.pull_time))
		drift.countersteer = float(args.get("drift-counter", drift.countersteer))
		_driver = drift
	elif args.has("autopilot") or args.has("qa-drive") or args.has("benchmark"):
		var autopilot := Autopilot.new()
		if args.has("autopilot-mph"):
			autopilot.target_speed = float(args["autopilot-mph"]) / Hud.MPH
		_driver = autopilot
	else:
		_driver = PlayerDriver.new()
	car.driver = _driver
	return drift


func _physics_process(delta: float) -> void:
	streamer.focus = car.global_position
	# Tow a car that's left the corridor or fallen out of the world.
	var pos := car.global_position
	var ground := route.terrain.height_at(pos.x, pos.z)
	if is_nan(ground) or pos.y < ground - 5.0:
		_lost_time += delta
		if _lost_time > LOST_SECONDS:
			_tow()
	else:
		_lost_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart()
	elif event.is_action_pressed("recover"):
		_tow()
	elif event.is_action_pressed("mute"):
		var master := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master, not AudioServer.is_bus_mute(master))


## Back to Kalona with a fresh car and everything put back.
func restart() -> void:
	run.restart()
	car.repair()
	car.driver = _driver
	camera.crash_cam = false
	props.reset()
	traffic.reset()
	corn.reset()
	_spawn(_spawn_station)


func _on_wrecked(_reason: String) -> void:
	camera.crash_cam = true
	if not _testing:
		car.driver = null  # hands off the wheel; let it tumble


## The tow truck: back on the road at the nearest point, facing north. Costs points
## once the clock is running.
func _tow() -> void:
	if tracker.state == RunTracker.State.WRECKED:
		return
	_lost_time = 0.0
	run.tow()
	_spawn(clampf(car.station, 0.0, route.length - 10.0))


## Put the car on the road and build everything around it right away.
func _spawn(station: float) -> void:
	streamer.warm_up(route.position_at(station))
	car.place_at(station)
	props.refresh()
	corn.warm_up()
	if camera.car:
		camera.snap()


func _add_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.55, 0.82)
	sky_material.sky_horizon_color = Color(0.78, 0.83, 0.86)
	# Below the horizon the sky only shows past the edge of the terrain; make it haze.
	sky_material.ground_horizon_color = Color(0.76, 0.81, 0.85)
	sky_material.ground_bottom_color = Color(0.76, 0.81, 0.85)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Neutral fill light; sky-colored ambient turns the asphalt blue.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.82, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Summer haze: a long view over the fields that fades out before the world ends
	# (the coarse horizon ground reaches ~4 km past the road) and hides things arriving.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.76, 0.81, 0.85)
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_sky_affect = 0.25

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)


## --tune=handbrake_grip:0.2,top_speed:50 overrides CarStats values, for tuning sweeps.
func _apply_tuning(stats: CarStats, spec: String) -> void:
	for pair in spec.split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2 and kv[0] in stats:
			stats.set(kv[0], float(kv[1]))
		else:
			push_warning("ignoring --tune entry '%s'" % pair)


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out


## Proves an exported build can find its data and that the car lands on the road.
## Run by CI on the packaged game.
func _smoke_test() -> void:
	var problems: Array[String] = []
	if route.mile_at(route.finish_station) < 14.5:
		problems.append("route is only %.2f mi" % route.mile_at(route.finish_station))
	if route.crossroads.size() < 10:
		problems.append("only %d crossroads" % route.crossroads.size())
	if streamer.collider_count() < 3:
		problems.append("only %d colliders around the start" % streamer.collider_count())
	for i in 90:
		await get_tree().physics_frame
	if car.grounded_wheels() != 4:
		problems.append("car has %d wheels on the ground after landing" % car.grounded_wheels())
	if absf(car.forward_speed()) > 0.5:
		problems.append("car is creeping at %.2f m/s with no input" % car.forward_speed())
	if car.health < car.stats.durability:
		problems.append("car took %.1f damage just landing" % (car.stats.durability - car.health))
	for station in [route.length * 0.5, route.finish_station]:
		streamer.warm_up(route.position_at(station))
	if streamer.loaded_tile_count() < 20 or streamer.loaded_chunk_count() < 5:
		problems.append("streaming loaded %d tiles, %d road chunks" % [
			streamer.loaded_tile_count(), streamer.loaded_chunk_count()])
	if problems.is_empty():
		print("SMOKE OK: %.2f mi, %d crossroads, %d terrain tiles, car settled on %s" % [
			route.mile_at(route.finish_station), route.crossroads.size(), route.terrain.count(),
			car.wheels[0].surface])
		get_tree().quit(0)
	else:
		for p in problems:
			printerr("SMOKE FAIL: ", p)
		get_tree().quit(1)


func _screenshot(path: String) -> void:
	for i in 90:
		await get_tree().physics_frame
	for i in 4:
		await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path, " -> ", error_string(err))
	get_tree().quit(0 if err == OK else 1)
