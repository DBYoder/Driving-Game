extends "res://tests/test_case.gd"
## The towns at the finishes: both routes run on past the finish line into town, Wellman
## built out (downtown on 8th Ave, the water tower, the co-op's bins), and the main streets
## through Wellman and into Iowa City with curbs and street lights.

var hw1 := RouteData.load_from(Routes.dir("highway1"))
var hw22 := RouteData.load_from(Routes.dir("highway22"))


func _landmark(r: RouteData, id: String) -> Dictionary:
	for l: Dictionary in r.landmarks:
		if l.id == id:
			return l
	return {}


func test_the_road_runs_on_past_the_finish() -> void:
	# The finish lines stay put (a re-bake mustn't move them: the records are times to them).
	check(hw1.finish_station == 24924.0, "Highway 1's finish at Mormon Trek (%.0f)" % hw1.finish_station)
	check(hw22.finish_station == 11084.0, "Highway 22's finish at 8th Ave (%.0f)" % hw22.finish_station)
	for r: RouteData in [hw1, hw22]:
		check(r.length - r.finish_station > 1900.0, "%s goes on %.0f m past the finish" % [r.id, r.length - r.finish_station])
	var past := func(r: RouteData, name: String) -> bool:
		return r.crossroads.any(func(c): return c.name == name and float(c.station) > r.finish_station)
	check(past.call(hw1, "Sunset St"), "into Iowa City: Sunset St")
	check(past.call(hw22, "9th Ave SW"), "on through Wellman: 9th Ave SW")


func test_tall_barns_are_the_co_ops_bins_and_elevators() -> void:
	var b := {"kind": "barn", "height": 30.6, "length": 16.0, "width": 16.0}
	check(RouteData.tidy_kind(b) == "bin", "a 30 m barn as wide as it's long is a bin")
	b = {"kind": "barn", "height": 27.8, "length": 14.0, "width": 7.0}
	check(RouteData.tidy_kind(b) == "elevator", "a long narrow one is the elevator")
	b = {"kind": "barn", "height": 9.0, "length": 30.0, "width": 14.0}
	check(RouteData.tidy_kind(b) == "barn", "a barn's a barn")
	for r: RouteData in [hw1, hw22]:
		check(not r.buildings.any(func(x): return x.kind == "barn" and float(x.height) >= RouteData.TALL_BARN_M),
			"no barns over %.0f m left on %s" % [RouteData.TALL_BARN_M, r.id])
	var coop: Array = hw22.buildings.filter(func(x): return Vector2(x.x, x.z).distance_to(Vector2(-5523.0, 1056.0)) < 3.0)
	check(coop.size() == 1 and coop[0].kind == "bin", "the co-op's big bin west of 8th Ave")
	check(Scenery.KINDS.has("elevator"), "and the scenery draws elevators")


func test_downtown_wellman() -> void:
	var l := _landmark(hw22, "wellman_downtown")
	check(not l.is_empty(), "downtown's in the data")
	if l.is_empty():
		return
	var sx := float(l.street_x)
	for b: Dictionary in hw22.buildings:
		var inside := absf(float(b.x) - sx) < 45.0 and float(b.z) > 1376.0 and float(b.z) < 1495.0
		check(not inside, "no lidar box on the storefronts' block (a %s at %.0f, %.0f)" % [b.kind, b.x, b.z])
	var landmarks := Landmarks.new()
	landmarks.setup(hw22)
	var west := 0
	var east := 0
	var in_street := 0
	for box: Array in landmarks.building_boxes(Vector3(sx, 0, 1400), 120.0):
		var c: Vector3 = box[0].origin
		var half: Vector3 = box[1]
		if half.y > 1.5 and absf(c.x - sx) > 11.0:  # a building, not a car or a lamp post
			if c.x < sx:
				west += 1
			else:
				east += 1
		if absf(c.x - sx) < 3.0 and c.z > 1300.0 and c.z < 1495.0:
			in_street += 1
	check(west >= 12 and east >= 10, "storefronts both sides of 8th Ave (%d west, %d east)" % [west, east])
	check(in_street == 0, "nothing solid in the lane down the middle (%d)" % in_street)
	var signs := 0
	for child: Node in landmarks.get_children():
		if child is Label3D and WellmanLandmarks.SHOPS.has((child as Label3D).text):
			signs += 1
	check(signs >= 15, "signs over the shops (%d)" % signs)
	landmarks.free()


func test_the_water_tower() -> void:
	var l := _landmark(hw22, "wellman_water_tower")
	check(not l.is_empty(), "the water tower's in the data")
	if l.is_empty():
		return
	var at := Vector3(float(l.x), 0.0, float(l.z))
	check(not hw22.buildings.any(func(b): return Vector2(b.x, b.z).distance_to(Vector2(at.x, at.z)) < 6.0),
		"the lidar's tall 'bin' there is gone: the tower stands in its place")
	var landmarks := Landmarks.new()
	landmarks.setup(hw22)
	var legs := landmarks.building_boxes(at, 8.0).filter(func(b): return b[1].y > 10.0)
	check(legs.size() >= 4, "four legs, solid (%d)" % legs.size())
	var ground := hw22.terrain.height_at(at.x, at.z)
	var letters := ""
	for child: Node in landmarks.get_children():
		if child is Label3D and Vector2(child.position.x - at.x, child.position.z - at.z).length() < 8.0:
			check(child.position.y - ground > 32.0, "the letters are up on the tank")
			letters += (child as Label3D).text
	check(letters == "WELLMANWELLMAN", "WELLMAN round the tank, both ways (%s)" % letters)
	landmarks.free()


func test_main_streets_have_curbs_and_lights() -> void:
	check(hw22.curbed(10800.0) and hw22.curbed(11400.0), "IA 22 through Wellman, on past the finish")
	check(not hw22.curbed(9000.0) and not hw22.curbed(12500.0), "not out in the country either side")
	check(hw1.curbed(25500.0) and not hw1.curbed(20000.0), "IA 1 into Iowa City past Mormon Trek, not before")
	var mesher := RoadMesher.new(hw22)
	var mesh := mesher.build_chunk(int(10800.0 / hw22.spacing) / RoadMesher.CHUNK_SAMPLES)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(colors.size() > 0 and colors[0].g > 0.5, "the road's drawn with its gutters there")
	var landmarks := Landmarks.new()
	landmarks.setup(hw22)
	var lights := 0
	for s in range(10340, 11660, 10):
		var road := hw22.position_at(s)
		for box: Array in landmarks.building_boxes(road, 12.0):
			var c: Vector3 = box[0].origin
			var lateral := absf((c - road).dot(hw22.right_at(s)))
			var along := absf((c - road).dot(hw22.tangent_at(s)))
			if along < 5.0 and box[1].y > 4.0 and lateral < 9.0:
				lights += 1
				check(lateral > RoadMesher.GRAVEL_HALF_WIDTH, "a light pole behind the gutter (%.1f m out)" % lateral)
				for c2: Dictionary in hw22.crossroads:
					check(absf(float(c2.station) - s) > 10.0, "not at %s" % c2.name)
	check(lights >= 15, "street lights the length of town (%d)" % lights)
	landmarks.free()
