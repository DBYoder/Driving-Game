extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/routes/highway1")


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


func test_horizon_stays_under_the_detailed_ground() -> void:
	# All across the corridor, the coarse horizon ground has to stay under the detailed
	# tiles, or it would show through them (and through the road, which sits above them).
	var worst := -INF
	var worst_at := ""
	var station := 0.0
	while station <= route.length:
		var center := route.position_at(station)
		var right := route.right_at(station)
		for offset in range(-1150, 1151, 50):
			var p := center + right * offset
			var ground := route.terrain.height_at(p.x, p.z)
			if is_nan(ground):
				continue
			var gap := route.horizon.height_at(p.x, p.z) - ground
			if gap > worst:
				worst = gap
				worst_at = "station %d, %d m from center" % [station, offset]
		station += 100.0
	check(worst <= -0.99, "horizon is only %.2f m under the ground at %s" % [-worst, worst_at])
	check(not is_nan(route.horizon.height_at(route.points[0].x - 4000.0, route.points[0].z)),
		"horizon reaches 4 km past the road")


func test_far_tile_mesh_stays_under_the_detailed_one() -> void:
	var t := route.terrain
	for i in range(0, t.count(), 97):
		var verts: PackedVector3Array = t.build_mesh(i, 1).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var n := (t.grid - 1) / 2 + 1
		check(verts.size() == n * n, "far tile has every other vertex")
		var worst := -INF
		for row in t.grid:
			for col in t.grid:
				var r := mini(row / 2, n - 2)
				var c := mini(col / 2, n - 2)
				var fx := col / 2.0 - c
				var fz := row / 2.0 - r
				var h00 := verts[r * n + c].y
				var h01 := verts[r * n + c + 1].y
				var h10 := verts[(r + 1) * n + c].y
				var h11 := verts[(r + 1) * n + c + 1].y
				var coarse := h00 + fx * (h01 - h00) + fz * (h11 - h01) if fx >= fz \
					else h00 + fz * (h10 - h00) + fx * (h11 - h10)
				worst = maxf(worst, coarse - t.heights[i * t.grid * t.grid + row * t.grid + col])
		check(worst <= 1e-4, "tile %d's far mesh pokes %.2f m above its detailed mesh" % [i, worst])


func test_far_road_chunks_meet_their_neighbors() -> void:
	var road := RoadMesher.new(route)
	var cols := RoadMesher.SECTION.size()
	for c in [0, 5, road.chunk_count() - 1]:
		var near: PackedVector3Array = road.build_chunk(c).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var far: PackedVector3Array = road.build_chunk(c, 4).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(far.size() < near.size() / 3, "far road is lighter")
		for k in cols:
			check(far[k].is_equal_approx(near[k]), "chunk %d starts on the same row" % c)
			check(far[far.size() - cols + k].is_equal_approx(near[near.size() - cols + k]), "chunk %d ends on the same row" % c)
