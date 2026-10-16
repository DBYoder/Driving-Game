extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/route")


func test_ground_never_pokes_through_the_road() -> void:
	# Check the rendered terrain against the road surface across the whole cross-section
	# (pavement, shoulders and the foreslopes down to the ditches), every 10 m.
	var offsets: Array[float] = []
	for o in range(-95, 96, 5):
		offsets.append(o / 10.0)
	var worst := -INF
	var worst_at := ""
	var station := 0.0
	while station <= route.length:
		var center := route.position_at(station)
		var right := route.right_at(station)
		for offset in offsets:
			var p := center + right * offset
			var ground := route.terrain.height_at(p.x, p.z)
			check(not is_nan(ground), "terrain exists under the road at station %d" % station)
			var gap := ground - (center.y + RoadMesher.surface_height(offset))
			if gap > worst:
				worst = gap
				worst_at = "station %d, %.1f m from center" % [station, offset]
		station += 10.0
	check(worst < 0.0, "ground is %.2f m above the road at %s" % [worst, worst_at])


func test_terrain_mesh_matches_height_lookup() -> void:
	var t := route.terrain
	var mesh := t.build_mesh(0)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(verts.size() == t.grid * t.grid, "one vertex per height sample")
	var v := verts[t.grid * 5 + 7]
	check_near(t.height_at(v.x, v.z), v.y, 1e-4, "height_at hits mesh vertices exactly")
	check(is_nan(t.height_at(1.0e6, 1.0e6)), "no ground far outside the corridor")


func test_road_chunks_cover_the_route() -> void:
	var road := RoadMesher.new(route)
	var vertices := 0
	for c in road.chunk_count():
		vertices += road.build_chunk(c).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var rows := route.points.size() + road.chunk_count() - 1  # chunks repeat their seam row
	check(vertices == rows * RoadMesher.SECTION.size(), "every sample has a cross-section")
