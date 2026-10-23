extends "res://tests/test_case.gd"
## The hand-built landmarks: Kalona Cheese on Highway 1, Mid-Prairie High School on
## Highway 22. Each stands at its real spot, the lidar's own boxes and trees there are left
## out, and it's solid and clear of the road.

var route := RouteData.load_from("res://data/routes/highway1")
var hw22 := RouteData.load_from(Routes.dir("highway22"))


func _cheese() -> Dictionary:
	for l: Dictionary in route.landmarks:
		if l.id == "kalona_cheese":
			return l
	return {}


func test_kalona_cheese_is_at_the_corner_of_540th_street() -> void:
	var l := _cheese()
	check(not l.is_empty(), "the Kalona Cheese landmark is in the data")
	if l.is_empty():
		return
	var corner := -1.0
	for c: Dictionary in route.crossroads:
		if c.name == "540th St SW":
			corner = c.station
	var at := Vector3(l.x, 0, l.z)
	var s := route.nearest_station(at, corner, 400.0)
	check(s > corner and s < corner + 100.0, "just north of 540th St (%.0f m past it)" % (s - corner))
	var road := route.position_at(s)
	var lateral := (at - Vector3(road.x, 0, road.z)).dot(route.right_at(s))
	check(lateral > 15.0 and lateral < 35.0, "on the east side, by the road (%.0f m)" % lateral)


func test_the_lidar_leaves_room_for_it() -> void:
	for b: Dictionary in route.buildings:
		check(not route.in_landmark(b.x, b.z), "a lidar %s at %.0f, %.0f is inside a landmark" % [b.kind, b.x, b.z])
	for i in route.trees.size() / 5:
		check(not route.in_landmark(route.trees[i * 5], route.trees[i * 5 + 1]), "a lidar tree is inside a landmark")
	check(route.buildings.size() > 2300, "and only there (%d buildings left)" % route.buildings.size())


func test_it_is_built_solid_and_off_the_road() -> void:
	var landmarks := Landmarks.new()
	landmarks.setup(route)
	check(landmarks.box_count() >= 8, "solid boxes for the store and the plant (%d)" % landmarks.box_count())
	var l := _cheese()
	var corner := route.nearest_station(Vector3(l.x, 0, l.z), 6000.0, 1000.0)
	for box: Array in landmarks.building_boxes(Vector3(l.x, 0, l.z), 200.0):
		var center: Vector3 = box[0].origin
		var half: Vector3 = box[1]
		var s := route.nearest_station(center, corner, 300.0)
		var right := route.right_at(s)
		var lateral := (center - route.position_at(s)).dot(right)
		var nearest := absf(lateral) - (absf(right.x) * half.x + absf(right.z) * half.z)
		check(nearest > RoadMesher.GRAVEL_HALF_WIDTH, "clear of the shoulder (a box %.1f m from the centerline)" % nearest)
	check(landmarks.get_child_count() > 3, "meshes and lettering")
	landmarks.free()


func _school() -> Dictionary:
	for l: Dictionary in hw22.landmarks:
		if l.id == "mid_prairie":
			return l
	return {}


func _crossroad_22(name: String) -> float:
	for c: Dictionary in hw22.crossroads:
		if c.name == name:
			return float(c.station)
	return -1.0


func test_mid_prairie_is_up_the_slope_east_of_wellman() -> void:
	var l := _school()
	check(not l.is_empty(), "Mid-Prairie High School is in Highway 22's data")
	if l.is_empty():
		return
	var at := Vector3(l.x, 0, l.z)
	var s := hw22.nearest_station(at, 9900.0, 600.0)
	check(s > _crossroad_22("Gum Ave") and s < _crossroad_22("1st Ave SE"), "between Gum Ave and 1st Ave SE (%.0f)" % s)
	var to_go := hw22.mile_at(hw22.finish_station) - hw22.mile_at(s)
	check(to_go > 0.5 and to_go < 1.0, "%.2f mi short of 8th Ave in Wellman" % to_go)
	var road := hw22.position_at(s)
	var lateral := (at - Vector3(road.x, 0, road.z)).dot(hw22.right_at(s))
	check(lateral > 80.0 and lateral < 150.0, "on the north side, up the slope from the road (%.0f m)" % lateral)


func test_the_lidar_leaves_room_for_the_school() -> void:
	for b: Dictionary in hw22.buildings:
		check(not hw22.in_landmark(b.x, b.z), "a lidar %s at %.0f, %.0f is inside the school" % [b.kind, b.x, b.z])
	var near_school := 0
	var by_the_circle_drive := 0
	for i in hw22.trees.size() / 5:
		var p := Vector2(hw22.trees[i * 5], hw22.trees[i * 5 + 1])
		check(not hw22.in_landmark(p.x, p.y), "a lidar tree at %s is inside the school" % p)
		if p.distance_to(Vector2(-3985.0, 990.0)) < 200.0:
			near_school += 1
		if p.distance_to(Vector2(-4030.0, 1038.0)) < 12.0:
			by_the_circle_drive += 1
	# The main building is turned 23 degrees: its clearing is too, so the trees on the lawn
	# out front (inside a square box round it) stay.
	check(by_the_circle_drive > 0, "the trees by the circle drive are still there (%d)" % by_the_circle_drive)
	check(near_school > 20, "and the rest round it (%d)" % near_school)
	check(hw22.buildings.size() > 1000, "only the school's own boxes are gone (%d left)" % hw22.buildings.size())


func test_the_school_is_built_solid_and_off_the_road() -> void:
	var l := _school()
	var landmarks := Landmarks.new()
	landmarks.setup(hw22)
	check(landmarks.box_count() >= 40, "solid wings, gym, front building, bus barn and parked cars (%d)" % landmarks.box_count())
	var origin := Vector3(l.x, 0, l.z)
	var hint := hw22.nearest_station(origin, 9900.0, 600.0)
	var closest := INF
	for box: Array in landmarks.building_boxes(origin, 400.0):
		var xf: Transform3D = box[0]
		var half: Vector3 = box[1]
		for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
			var p := xf * (corner * half)
			var s := hw22.nearest_station(p, hint, 400.0)
			closest = minf(closest, absf((p - hw22.position_at(s)).dot(hw22.right_at(s))))
	check(closest > RoadMesher.DITCH_EDGE + 4.0, "nothing solid on the road or its ditch (closest %.1f m out)" % closest)
	var flags := 0
	var texts := []
	for child: Node in landmarks.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D \
				and ((child as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture != null:
			flags += 1
		if child is Label3D:
			texts.append((child as Label3D).text)
	check(flags == 2, "the Stars and Stripes and Iowa's flag (%d)" % flags)
	check("MID-PRAIRIE\nHIGH SCHOOL" in texts and "HOME OF THE GOLDEN HAWKS" in texts, "the sign by the road: %s" % [texts])
	landmarks.free()
