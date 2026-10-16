extends Node3D
## Phase 0 entry point: loads the baked road, builds the world around a flythrough camera.
##
## Command-line options (after `--`):
##   --smoke-test               load everything, check it, print a summary, exit 0/1
##   --screenshot=<path>        render a few frames and save a PNG, then exit
##   --station=<m> --view=<n>   where the screenshot camera starts and which view it uses

const ROUTE_DIR := "res://data/route"

var route: RouteData
var streamer: WorldStreamer
var camera: FlythroughCamera


func _ready() -> void:
	var args := _parse_args()
	route = RouteData.load_from(ROUTE_DIR)
	if route == null:
		get_tree().quit(1)
		return

	_add_environment()
	streamer = WorldStreamer.new()
	streamer.setup(route)
	add_child(streamer)

	var roadside := Roadside.new()
	add_child(roadside)
	roadside.setup(route)

	camera = FlythroughCamera.new()
	add_child(camera)
	camera.setup(route)
	if args.has("station"):
		camera.station = float(args.station)
	if args.has("view"):
		camera.mode = int(args.view)

	var hud := Hud.new()
	add_child(hud)
	hud.setup(route, camera)

	if args.has("smoke-test"):
		_smoke_test()
		return
	camera.paused = args.has("screenshot")
	camera.place()
	streamer.warm_up(camera.position)
	if args.has("screenshot"):
		_screenshot(args.screenshot)


func _process(_delta: float) -> void:
	if camera:
		streamer.focus = camera.position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()


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


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out


## Proves an exported build can find and use its data. Run by CI on the packaged game.
func _smoke_test() -> void:
	var problems: Array[String] = []
	if route.mile_at(route.finish_station) < 14.5:
		problems.append("route is only %.2f mi" % route.mile_at(route.finish_station))
	if route.crossroads.size() < 10:
		problems.append("only %d crossroads" % route.crossroads.size())
	for station in [route.start_station, route.length * 0.5, route.finish_station]:
		streamer.warm_up(route.position_at(station))
		if streamer.loaded_tile_count() < 20 or streamer.loaded_chunk_count() < 5:
			problems.append("streaming near station %d loaded %d tiles, %d road chunks" % [
				station, streamer.loaded_tile_count(), streamer.loaded_chunk_count()])
	if problems.is_empty():
		print("SMOKE OK: %.2f mi, %d crossroads, %d terrain tiles" % [
			route.mile_at(route.finish_station), route.crossroads.size(), route.terrain.count()])
		get_tree().quit(0)
	else:
		for p in problems:
			printerr("SMOKE FAIL: ", p)
		get_tree().quit(1)


func _screenshot(path: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("screenshot ", path, " -> ", error_string(err))
	get_tree().quit(0 if err == OK else 1)
