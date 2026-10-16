extends Node3D
## Entry point: loads the baked road, builds the world around the car, and times the run.
##
## Command-line options (after `--`):
##   --station=<m>        start the car here instead of just behind the Kalona start line
##   --view=<n>           camera: 0 chase, 1 hood, 2 far chase, 3 drone
##   --autopilot          let the autopilot drive (demo mode)
##   --autopilot-mph=<n>  the autopilot's cruising speed (default 70)
##   --tune=<k:v,...>     override CarStats values, e.g. --tune=handbrake_grip:0.2
##   --qa-drive           autopilot the whole route, check for problems, exit 0/1
##   --qa-stress          random inputs for 4 minutes, check the physics holds up, exit 0/1
##   --qa-drift           a scripted handbrake turn; checks it slides and recovers, exit 0/1
##                        (--seed=<n> picks the random sequence; run both QA modes
##                        headless with --fixed-fps 60 to go faster than real time)
##   --smoke-test         load everything, drop the car on the road, check it, exit 0/1
##   --screenshot=<path>  let the car settle, save a PNG, exit

const ROUTE_DIR := "res://data/route"
const SPAWN_BEHIND_START := 25.0
const LOST_SECONDS := 2.0  ## off the edge of the world this long -> back on the road

var route: RouteData
var streamer: WorldStreamer
var car: Car
var camera: ChaseCamera
var tracker: RunTracker
var _spawn_station := 0.0
var _lost_time := 0.0


func _ready() -> void:
	var args := _parse_args()
	route = RouteData.load_from(ROUTE_DIR)
	if route == null:
		get_tree().quit(1)
		return

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
	var drift: DriftDriver = null
	if args.has("qa-stress"):
		car.driver = StressDriver.new(int(args.get("seed", "1")))
	elif args.has("qa-drift"):
		drift = DriftDriver.new()
		drift.pull_time = float(args.get("drift-pull", drift.pull_time))
		drift.countersteer = float(args.get("drift-counter", drift.countersteer))
		car.driver = drift
	elif args.has("autopilot") or args.has("qa-drive"):
		var autopilot := Autopilot.new()
		if args.has("autopilot-mph"):
			autopilot.target_speed = float(args["autopilot-mph"]) / Hud.MPH
		car.driver = autopilot
	else:
		car.driver = PlayerDriver.new()
	var sound := EngineSound.new()
	sound.car = car
	car.add_child(sound)

	var testing := args.has("qa-drive") or args.has("qa-stress") or args.has("qa-drift")
	var save_path := "" if testing else RunTracker.SAVE_PATH
	tracker = RunTracker.new(route.start_station, route.finish_station, car.stats.display_name, save_path)

	camera = ChaseCamera.new()
	add_child(camera)
	if args.has("view"):
		camera.mode = int(args.view)
	_spawn_station = float(args.station) if args.has("station") else route.start_station - SPAWN_BEHIND_START
	if drift:
		_spawn_station = route.start_station + 1.5 * RouteData.MILE_M  # the long straight north of Kalona
	_spawn(_spawn_station)
	camera.setup(car)

	var hud := Hud.new()
	add_child(hud)
	hud.setup(route, car, tracker, camera)

	if args.has("smoke-test"):
		_smoke_test()
	elif testing:
		var qa := QaDrive.new()
		qa.car = car
		qa.tracker = tracker
		qa.stress = args.has("qa-stress")
		qa.drift = drift
		add_child(qa)
	elif args.has("screenshot"):
		_screenshot(args.screenshot)


func _physics_process(delta: float) -> void:
	tracker.update(car.station, delta)
	streamer.focus = car.global_position
	# Rescue a car that's left the corridor or fallen out of the world.
	var pos := car.global_position
	var ground := route.terrain.height_at(pos.x, pos.z)
	if is_nan(ground) or pos.y < ground - 5.0:
		_lost_time += delta
		if _lost_time > LOST_SECONDS:
			_recover()
	else:
		_lost_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		tracker.reset()
		_spawn(_spawn_station)
	elif event.is_action_pressed("recover"):
		_recover()
	elif event.is_action_pressed("mute"):
		var master := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master, not AudioServer.is_bus_mute(master))


## Back on the road at the nearest point, facing north, clock still running.
func _recover() -> void:
	_lost_time = 0.0
	_spawn(clampf(car.station, 0.0, route.length - 10.0))


func _spawn(station: float) -> void:
	streamer.warm_up(route.position_at(station))
	car.place_at(station)
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
	# Summer haze: hides the edge of the world and the tiles streaming in.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.76, 0.81, 0.85)
	env.fog_depth_begin = 250.0
	env.fog_depth_end = 1150.0
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
