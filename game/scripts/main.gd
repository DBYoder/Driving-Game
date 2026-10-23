extends Node3D
## Entry point: loads the baked road, builds the world around the car, and runs the game.
##
## Command-line options (after `--`):
##   --route=<id>         highway1 (Kalona to Iowa City) or highway22 (Kalona to Wellman);
##                        default: the garage's pick (highway1 in tests)
##   --station=<m>        start the car here instead of at the Kalona 4-way stop
##   --view=<n>           camera: 0 chase, 1 in car, 2 far chase, 3 drone, 4 hood
##   --autopilot          let the autopilot drive (demo mode)
##   --autopilot-mph=<n>  the autopilot's cruising speed (default 70)
##   --car=<id>           windstar, tercel or legend (skips the car-select screen)
##   --garage             open the car-select screen even with other options (--practice: for a practice run)
##   --title              open the title screen even with other options
##   --menu=<id>          and open settings, records or pause (for screenshots)
##   --damage=<0..1>      start with the car beaten up (for looking at the damage)
##   --orbit              circle the car with the camera (for screenshots)
##   --chase              start with a deputy on your tail
##   --boost              a full boost meter, burned on autopilot from the start (screenshots)
##   --deer[=<m>]         send a herd of deer across the road just ahead (45 m)
##   --condition=<id>     summer, harvest, night, storm or winter (default: the garage's pick)
##   --scenery=<0..1>     how much of the buildings and trees to draw (F2 in the game)
##   --preset=<id>        graphics preset for this run: low, medium or high (not saved)
##   --seed=<n>           fix where the speed traps and deer are (random each run
##                        otherwise; tests and screenshots default to 1)
##   --tune=<k:v,...>     override CarStats values, e.g. --tune=handbrake_grip:0.2
##   --no-traffic         an empty road
##   --no-cops            no speed traps
##   --no-deer            no deer
##   --traffic-near       start with a buggy, a tractor and oncoming traffic in view
##   --qa-drive           autopilot the whole route, check for problems, exit 0/1
##   --qa-stress          random inputs for 4 minutes, check the physics holds up, exit 0/1
##   --qa-drift           a scripted handbrake turn; checks it slides and recovers, exit 0/1
##   --qa-cops=bust|line  speed past a speed trap: then stop and get busted, or run for
##                        the county line; checks the chase plays out, exit 0/1
##   --qa-menus           click through the title screen, settings, records, practice,
##                        the pause menu and back; checks each does what it should, exit 0/1
##   --qa-deer            drive through a herd of deer (one freezes in the lane), then
##                        hit one; checks they miss, then that the hit does what it should
##                        (--seed=<n> picks the random sequence; run the QA modes
##                        headless with --fixed-fps 60 to go faster than real time)
##   --smoke-test         load everything, drop the car on the road, check it, exit 0/1
##   --benchmark          autopilot at 70 mph for 40 s, print fps, draw calls, triangles
##   --screenshot=<path>  let the car settle, save a PNG, exit

const SPAWN_BEHIND_START := 3.0  ## stopped with the bumper at the start line in Kalona
const LOST_SECONDS := 2.0  ## off the edge of the world this long -> towed back
const FOG_BEGIN := 450.0
const FOG_END := 3000.0  ## nothing past this is visible


## Floors it on autopilot with the boost held (--boost, for screenshots).
class BoostDemo:
	var autopilot := Autopilot.new()

	func update(car: Car, delta: float) -> void:
		autopilot.target_speed = 100.0
		autopilot.update(car, delta)
		car.boost_held = true


var route: RouteData
var fields: Fields
var streamer: WorldStreamer
var scenery: Scenery
var landmarks: Landmarks
var intersections: Intersections
var junction: Junction
var bridges: Bridges
var tire_marks: TireMarks
var power_lines: PowerLines
var weather: Weather
var radio: Radio
var condition: Condition
var environment: Environment
var sky_material: ShaderMaterial  ## shaders/sky.gdshader
var sun: DirectionalLight3D
var props: PropField
var traffic: Traffic
var cops: Cops
var deer: Deer
var corn: CornField
var car: Car
var camera: ChaseCamera
var tracker: RunTracker
var run: Run
var hud: Hud
var garage: CarSelect
var menus: Menus
var _driver: Object
var _demo: Autopilot  ## drives the title screen's car
var _demo_wait := 0.0
var _practice := false  ## the garage was opened for a practice run
var _pending_run := {}  ## the run on its way to the leaderboard
var _default_spawn := 0.0  ## where a run starts (just behind the Kalona line, or --station)
var _testing := false
var _spawn_station := 0.0
var _lost_time := 0.0
var _seed := 0  ## where the speed traps and deer are this run (fixed in tests, random otherwise)
## Set when the garage switched routes and the game reloaded for it: open the garage
## again ("garage" or "practice") on the new route, which takes over from --route.
static var _reopen := ""


func _ready() -> void:
	var args := _parse_args()
	var testing_args := args.has("qa-drive") or args.has("qa-stress") or args.has("qa-drift") \
		or args.has("qa-cops") or args.has("qa-deer") or args.has("qa-menus") or args.has("smoke-test") \
		or args.has("screenshot")
	if _reopen.is_empty():
		var picked := Routes.DEFAULT if testing_args else Routes.saved(RunTracker.SAVE_PATH)
		Routes.current = String(args.get("route", picked))
	if not Routes.current in Routes.IDS:
		push_error("unknown route %s" % Routes.current)
		Routes.current = Routes.DEFAULT
	route = RouteData.load_from(Routes.dir(Routes.current))
	if route == null:
		get_tree().quit(1)
		return
	fields = Fields.new(route)
	_testing = args.has("qa-drive") or args.has("qa-stress") or args.has("qa-drift") or args.has("qa-cops") \
		or args.has("qa-deer") or args.has("qa-menus")

	_add_environment()
	add_child(preload("res://scripts/game/pause_control.gd").new())
	streamer = WorldStreamer.new()
	streamer.setup(route)
	streamer.fields = fields  # one patchwork, so harvest cuts the same fields everywhere
	add_child(streamer)
	scenery = Scenery.new()
	add_child(scenery)
	scenery.setup(route)
	landmarks = Landmarks.new()
	add_child(landmarks)
	landmarks.setup(route)
	# The player's settings; tests and screenshots always use the defaults.
	if _testing or args.has("smoke-test") or args.has("screenshot"):
		Settings.save_path = ""
		Settings.reset()
	else:
		Settings.load_file()
	if args.has("preset") and args.preset in Settings.PRESETS:
		Settings.set_preset(args.preset, false)
	if args.has("scenery"):
		Settings.scenery = float(args.scenery)
	scenery.density = Settings.scenery
	var roadside := Roadside.new()
	add_child(roadside)
	roadside.setup(route)
	junction = Junction.new()
	add_child(junction)
	junction.setup(route)
	intersections = Intersections.new()
	add_child(intersections)
	intersections.setup(route)
	bridges = Bridges.new()
	add_child(bridges)
	bridges.setup(route)
	power_lines = PowerLines.new()
	add_child(power_lines)
	power_lines.setup(route, streamer.streets)

	var stats := CarStats.preset(args.get("car", "legend"))
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
	run.score.par_seconds = route.info.par_seconds
	run.wrecked.connect(_on_wrecked)
	run.finished.connect(_on_run_over)
	run.wrecked.connect(func(_reason: String): _on_run_over())
	var feel := CarFeel.new()
	add_child(feel)
	feel.setup(car, run)
	tire_marks = TireMarks.new()
	add_child(tire_marks)
	tire_marks.setup(car)

	props = PropField.new()
	add_child(props)
	props.setup(route, fields, car, run.score)
	corn = CornField.new()
	add_child(corn)
	corn.setup(route, fields, car, run.score)
	corn.canopy_material = streamer.canopy_material
	car.part_lost.connect(props.add_debris)
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(route, car, run, int(args.get("seed", "1")))
	traffic.enabled = not args.has("no-traffic") and not args.has("qa-drift")
	cops = Cops.new()
	add_child(cops)
	var fixed_seed: bool = _testing or args.has("seed") or args.has("screenshot")
	_seed = int(args.get("seed", "1")) if fixed_seed else randi()
	cops.setup(route, car, run, traffic, _seed)
	cops.enabled = not args.has("no-cops") and not args.has("qa-drift") and not args.has("qa-deer")
	deer = Deer.new()
	add_child(deer)
	deer.setup(route, car, run, props, traffic, _seed)
	deer.enabled = not args.has("no-deer") and not args.has("qa-drift") and not args.has("qa-cops")
	if _driver is Autopilot:
		_driver.traffic = traffic
		_driver.deer = deer

	camera = ChaseCamera.new()
	add_child(camera)
	if args.has("view"):
		camera.mode = int(args.view)
	_spawn_station = float(args.station) if args.has("station") else route.start_station - SPAWN_BEHIND_START
	if drift:
		_spawn_station = route.start_station + 1.5 * RouteData.MILE_M  # the long straight out of Kalona
	_default_spawn = _spawn_station
	_spawn(_spawn_station)
	camera.setup(car)

	weather = Weather.new()
	add_child(weather)
	weather.setup(car, camera, environment, sky_material, _seed)
	radio = Radio.new()
	add_child(radio)
	apply_settings()
	Settings.changed.connect(apply_settings)
	Settings.apply_window()

	hud = Hud.new()
	add_child(hud)
	hud.setup(route, car, run, camera)
	hud.name_entered.connect(_on_name_entered)
	Leaderboard.posted.connect(_on_posted)
	hud.cops = cops
	hud.deer = deer
	radio.now_playing.connect(func(title: String):
		hud.note(title)
		Cockpit.radio_text = title.trim_prefix("♪  ").to_upper())
	cops.chase_started.connect(func(county):
		hud.banner("SPEED TRAP!\n%s County deputy" % county)
		hud.note("Near misses fill your boost: Shift or B to lose the deputy", 6.0))
	garage = CarSelect.new()
	add_child(garage)
	garage.setup("" if _testing else RunTracker.SAVE_PATH)
	garage.browsed.connect(_show_car)
	garage.chosen.connect(_drive)
	garage.back.connect(open_title)
	garage.route_changed.connect(change_route)
	garage.starts = _practice_starts()
	menus = Menus.new()
	add_child(menus)
	menus.setup("" if _testing else RunTracker.SAVE_PATH)
	menus.drive.connect(open_garage)
	menus.resume.connect(resume)
	menus.restart.connect(func():
		resume()
		restart())
	menus.garage.connect(func(): open_garage(_practice))
	menus.to_title.connect(open_title)
	menus.quit.connect(func(): get_tree().quit())
	_demo = Autopilot.new()
	_demo.traffic = traffic
	_demo.deer = deer
	_demo.target_speed = 55.0 / Hud.MPH
	var condition_id: String = args.get("condition", "summer" if _testing else garage.current_condition())
	if not condition_id in Condition.IDS:
		push_error("unknown condition %s" % condition_id)
		condition_id = "summer"
	apply_condition(Condition.preset(condition_id))
	# Dev and screenshot setups, now the condition's set (traffic mix, deer).
	if args.has("traffic-near"):
		traffic.populate_near()
	if args.has("damage"):
		_beat_up(float(args.damage))
	camera.showroom = args.has("orbit")
	if args.has("chase"):
		cops.chase_from_behind()
	if args.has("boost"):
		car.boost.fill(1.0)
		_driver = BoostDemo.new()
		car.driver = _driver
	if args.has("deer"):
		deer.cross_now(45.0 if args.deer is bool else float(args.deer))
	var skip_garage := args.has("car") or _testing or args.has("smoke-test") or args.has("screenshot") \
		or args.has("benchmark") or args.has("autopilot")
	if not _reopen.is_empty():
		var practice_run := _reopen == "practice"
		_reopen = ""
		open_garage(practice_run, true)
	elif args.has("garage"):
		open_garage(args.has("practice"))
	elif args.has("title") or args.has("qa-menus") or not skip_garage:
		open_title()
	elif not _testing and not args.has("smoke-test") and not args.has("screenshot") and not args.has("benchmark"):
		radio.start()
	match args.get("menu", ""):
		"settings":
			menus.open_settings(menus.title if menus.title.visible else menus.pause)
		"records":
			menus.open_records(menus.title)
		"pause":
			toggle_pause()

	if args.has("smoke-test"):
		_smoke_test()
	elif args.has("qa-menus"):
		var walk := QaMenus.new()
		walk.main = self
		add_child(walk)
	elif _testing:
		var qa := QaDrive.new()
		qa.car = car
		qa.run = run
		qa.stress = args.has("qa-stress")
		qa.drift = drift
		qa.cop_scenario = args.get("qa-cops", "")
		qa.deer_scenario = args.has("qa-deer")
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
		drift.handbrake = args.get("drift-handbrake", "1") != "0"
		if args.has("drift-mph"):
			drift.set_entry_speed(float(args["drift-mph"]) / Hud.MPH)
		_driver = drift
	elif args.has("autopilot") or args.has("qa-drive") or args.has("qa-cops") or args.has("qa-deer") \
			or args.has("benchmark"):
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
	scenery.focus = car.global_position
	# The title screen's car: off again from Kalona if it wrecks or gets to the finish.
	if menus.title.visible and (tracker.over() or car.driver == null):
		_demo_wait += delta
		if _demo_wait > 3.0:
			_start_demo()
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
	if garage.visible or menus.any_open():
		return
	if event.is_action_pressed("change_car") and tracker.over():
		open_garage(_practice)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		restart()
	elif event.is_action_pressed("recover"):
		_tow()
	elif event.is_action_pressed("scenery_detail"):
		Settings.step("scenery", 1)
		hud.note("Scenery: " + Settings.describe("scenery"))
	elif event.is_action_pressed("mute"):
		var master := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master, not AudioServer.is_bus_mute(master))


## Back to the start (Kalona, or a practice run's mile) with a fresh car and everything
## put back.
func restart() -> void:
	_reset_world()
	car.driver = _driver
	_pending_run = {}
	hud.clear_leaderboard()


## A run ended (finished or wrecked): onto the shared leaderboard, if there is one, under
## the player's name (asked for the first time). Only whole runs from Kalona count: not
## practice, and not a run started down the road with --station.
func _on_run_over() -> void:
	var from_kalona := is_equal_approx(_spawn_station, route.start_station - SPAWN_BEHIND_START)
	if _testing or tracker.practice or not from_kalona or not Leaderboard.enabled():
		return
	var seconds := tracker.elapsed if tracker.state == RunTracker.State.FINISHED else 0.0
	_pending_run = Leaderboard.run_body(Routes.current, Settings.player_name, run.score.banked, seconds,
		car.stats.id, condition.id, Menus.VERSION)
	if Settings.player_name.is_empty():
		hud.ask_name()
	else:
		_send_run()


func _on_name_entered(text: String) -> void:
	var player := Leaderboard.tidy_name(text)
	if player.is_empty() or _pending_run.is_empty():
		return
	Settings.player_name = player
	Settings.save()
	_pending_run.name = player
	_send_run()


func _send_run() -> void:
	hud.set_leaderboard("Sending...")
	Leaderboard.post_run(_pending_run)


func _on_posted(result: Dictionary) -> void:
	if not _pending_run.is_empty():
		hud.set_leaderboard(Leaderboard.placing(result, String(route.info.title).capitalize()))
		_pending_run = {}


func _reset_world() -> void:
	run.restart()
	car.repair()
	camera.crash_cam = false
	props.reset()
	traffic.reset()
	corn.reset()
	_seed += 1
	cops.reset(_seed)
	deer.reset(_seed)
	_spawn(_spawn_station)


## Pause (the pause menu) or carry on. Not over the garage or the other menus.
func toggle_pause() -> void:
	if garage.visible or menus.title.visible or menus.settings.visible or menus.records.visible:
		return
	if get_tree().paused:
		resume()
	else:
		get_tree().paused = true
		menus.pause.open()


func resume() -> void:
	menus.pause.close()
	get_tree().paused = false


## The title screen: the car you drove last cruising up the road on its own in the
## conditions you drove in, the camera circling it, the menu beside it.
func open_title() -> void:
	get_tree().paused = false
	menus.close_all()
	garage.visible = false
	hud.visible = false
	_practice = false
	tracker.practice = false
	hud.practice = false
	_spawn_station = _default_spawn
	var c := garage.current_condition()
	if condition == null or condition.id != c:
		apply_condition(Condition.preset(c))
	var stats := CarStats.preset(garage.current_car())
	stats.body_color = stats.paints[clampi(garage.paint_index, 0, stats.paints.size() - 1)][1]
	car.change(stats)
	run.car_changed()
	_start_demo()
	camera.showroom = true
	menus.title.open()
	radio.start()


func _start_demo() -> void:
	_demo_wait = 0.0
	_reset_world()
	car.driver = _demo


## Where practice runs can start: Kalona, then every mile (with the crossroad there, if
## there's one close by).
func _practice_starts() -> Array:
	var out: Array = [[route.start_station - SPAWN_BEHIND_START, "Kalona (the 4-way stop)"]]
	var mile := 1
	while route.start_station + (mile + 0.5) * RouteData.MILE_M < route.finish_station:
		var s := route.start_station + mile * RouteData.MILE_M
		var label := "Mile %d" % mile
		for c: Dictionary in route.crossroads:
			if absf(float(c.station) - s) < 0.25 * RouteData.MILE_M and c.kind != "ramp":
				label += "  ·  %s" % c.name
				break
		out.append([s, label])
		mile += 1
	return out


## Hits from all around adding up to `amount` of the car's health.
func _beat_up(amount: float) -> void:
	var hits := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD + Vector3.LEFT]
	for d: Vector3 in hits:
		car.apply_hit(car.stats.durability * amount / hits.size(), true, car.global_transform.basis * d)


## The car-select screen: the car waits on the road while you choose (at the start line,
## or for practice wherever you pick).
func open_garage(practice := false, on_route := false) -> void:
	get_tree().paused = false
	menus.close_all()
	_practice = practice
	run.restart()
	car.driver = null
	camera.crash_cam = false
	camera.showroom = true
	hud.visible = false
	garage.open(practice, on_route)


## The garage picked another route: build the world again for it. The whole game reloads
## (a frame later, so the garage's "Loading..." shows) and the garage opens again.
func change_route(id: String) -> void:
	if id == Routes.current or not id in Routes.IDS:
		return
	Routes.current = id
	_reopen = "practice" if _practice else "garage"
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	get_tree().reload_current_scene()


## Show a car in the garage (it's swapped in for real, so it sits on the road).
func _show_car(car_id: String, paint: int, condition_id: String) -> void:
	if condition == null or condition.id != condition_id:
		apply_condition(Condition.preset(condition_id))
	var stats := CarStats.preset(car_id)
	stats.body_color = stats.paints[paint][1]
	car.change(stats)
	run.car_changed()
	garage.set_records(tracker.best_score, tracker.best_time)
	var at := garage.start_station()
	_spawn_station = at if at >= 0.0 else _default_spawn
	_spawn(_spawn_station)


## The graphics settings, applied to the world (and again whenever they change): the 3D
## resolution, anti-aliasing, how much scenery and how detailed, how much rain and snow.
func apply_settings() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = Settings.render_scale
	vp.msaa_3d = Viewport.MSAA_2X if Settings.msaa() else Viewport.MSAA_DISABLED
	scenery.near_lod = Settings.detail_distance()
	if scenery.density != Settings.scenery:
		scenery.density = Settings.scenery
	weather.set_particle_scale(Settings.particles())
	tire_marks.particle_scale = Settings.particles()


## Light, weather, land, traffic, deer and grip for one of the five conditions.
func apply_condition(c: Condition) -> void:
	var harvest_changed := condition == null or condition.harvested != c.harvested
	condition = c
	Cockpit.clock_start = c.clock
	Cockpit.clock_since = Time.get_ticks_msec()
	for pair: Array in [["sky_top_color", c.sky_top], ["sky_horizon_color", c.sky_horizon],
			["ground_horizon_color", c.haze], ["ground_bottom_color", c.haze], ["cloud_cover", c.cloud_cover],
			["cloud_color", c.cloud_color], ["cloud_shade", c.cloud_shade], ["stars", c.stars]]:
		sky_material.set_shader_parameter(pair[0], pair[1])
	environment.ambient_light_color = c.ambient
	environment.ambient_light_energy = c.ambient_energy
	environment.fog_light_color = c.haze
	environment.fog_depth_begin = c.fog_begin
	environment.fog_depth_end = c.fog_end
	sun.rotation_degrees = c.sun_rotation
	sun.light_color = c.sun_color
	sun.light_energy = c.sun_energy
	streamer.apply_condition(c)
	corn.apply_condition(c)
	if harvest_changed:
		corn.reset()
		corn.warm_up()
	scenery.set_look(c.leaf, c.snow, c.night)
	landmarks.set_look(c.snow, c.night)
	junction.apply_condition(c)
	bridges.set_look(c.snow)
	weather.apply(c)
	tire_marks.wet = c.rain > 0.0
	tire_marks.snowy = c.snow > 0.0
	car.grip_scale = c.grip
	car.ice_grip = c.ice_grip
	car.ice = Weather.ice_patches(route) if c.ice_grip < 1.0 else PackedFloat32Array()
	streamer.set_ice(car.ice)
	car.headlights = c.night > 0.5
	traffic.apply_condition(c)
	cops.night = c.night > 0.5
	deer.rate = c.deer_rate
	deer.reset(_seed)
	run.condition = c
	run.car_changed()
	hud.condition_name = c.display_name


func _drive(_car_id: String, _paint: int, _condition_id: String) -> void:
	camera.showroom = false
	hud.visible = true
	var at := garage.start_station()
	_spawn_station = at if at >= 0.0 else _default_spawn
	tracker.practice = at >= 0.0
	hud.practice = tracker.practice
	restart()
	radio.start()


func _on_wrecked(_reason: String) -> void:
	camera.crash_cam = true
	if not _testing:
		car.driver = null  # hands off the wheel; let it tumble


## The tow truck: back on the road at the nearest point, facing up the route. Costs points
## once the clock is running.
func _tow() -> void:
	if tracker.state == RunTracker.State.WRECKED:
		return
	if cops.chasing():
		cops.bust()  # calling a tow truck with a deputy on your tail: busted
		return
	_lost_time = 0.0
	run.tow()
	_spawn(clampf(car.station, 0.0, route.length - 10.0))


## Put the car on the road and build everything around it right away.
func _spawn(station: float) -> void:
	if tire_marks:
		tire_marks.clear()
	streamer.warm_up(route.position_at(station))
	scenery.warm_up(route.position_at(station))
	car.place_at(station)
	props.refresh()
	corn.warm_up()
	if camera.car:
		camera.snap()


func _add_environment() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	# Below the horizon the sky only shows past the edge of the terrain; it's haze (each
	# condition sets its own: apply_condition).
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	environment = env
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

	sun = DirectionalLight3D.new()
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
	var expect := route.info
	if route.mile_at(route.finish_station) < float(expect.min_miles):
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
	if route.buildings.size() < int(expect.min_buildings) or route.trees.size() / 5 < int(expect.min_trees):
		problems.append("only %d buildings and %d trees in the data" % [route.buildings.size(), route.trees.size() / 5])
	if expect.landmark and (route.landmarks.is_empty() or landmarks.box_count() < 8):
		problems.append("the landmark didn't build (%d landmarks, %d solid boxes)" % [route.landmarks.size(), landmarks.box_count()])
	scenery.warm_up(route.position_at(route.length * 0.5))
	if scenery.instance_count() < 100:
		problems.append("only %d buildings and trees around mid-route" % scenery.instance_count())
	if problems.is_empty():
		print("SMOKE OK: %s, %.2f mi, %d crossroads, %d terrain tiles, %d buildings, %d trees, car settled on %s" % [
			route.id, route.mile_at(route.finish_station), route.crossroads.size(), route.terrain.count(),
			route.buildings.size(), route.trees.size() / 5, car.wheels[0].surface])
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
