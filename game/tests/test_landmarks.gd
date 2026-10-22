extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/routes/highway1")


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
