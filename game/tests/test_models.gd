extends "res://tests/test_case.gd"
## The scenery's models (SceneryMeshes, shaders/scenery.gdshader), each building fitted to
## its own roof, and things along the road keeping out of each other's way.

var hw1 := RouteData.load_from(Routes.dir("highway1"))
var hw22 := RouteData.load_from(Routes.dir("highway22"))


## Every vertex's part (UV.x, less the window sets) and where it is.
func _parts(mesh: ArrayMesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := {"parts": {}, "sets": {}, "roof_slopes": 0, "roof_above": true, "walls_below": true, "verts": verts.size()}
	for i in verts.size():
		var code := uv[i].x
		var part := int(fmod(code, 10.0))
		out.parts[part] = true
		out.sets[int(code / 10.0)] = true
		if part == int(SceneryMeshes.ROOF):
			if uv2[i].x > 0.0 and uv2[i].y > 0.0:
				out.roof_slopes += 1
			if verts[i].y < 0.8:
				out.roof_above = false
		elif part == int(SceneryMeshes.WALLS) and verts[i].y > 2.0001:
			out.walls_below = false
	return out


func test_buildings_are_built_in_two_stretches() -> void:
	for kind: String in ["house", "barn", "shed"]:
		for lod in 2:
			var p := _parts(SceneryMeshes.build(kind, lod))
			var label := "%s lod %d" % [kind, lod]
			check(p.parts.has(int(SceneryMeshes.WALLS)) and p.parts.has(int(SceneryMeshes.ROOF)), label + ": walls and a roof")
			check(p.roof_slopes > 0 and p.roof_above, label + ": the roof up top (y 1 to 2), its slope with it")
			check(p.walls_below, label + ": nothing over the ridge but a chimney or cupola")
	var house := _parts(SceneryMeshes.build("house", 0))
	check(house.sets.has(1) and house.sets.has(2) and house.sets.has(3), "a house has two rows of windows and a door, for the shader to fit")
	check(house.parts.has(int(SceneryMeshes.ROOF_TRIM)) and house.parts.has(int(SceneryMeshes.WALL_TRIM)), "and trim")
	for kind: String in ["tree", "conifer", "bin", "elevator", "yard_light"]:
		var verts: PackedVector3Array = SceneryMeshes.build(kind, 0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var top := 0.0
		for v in verts:
			top = maxf(top, v.y)
		check(top <= 1.0001, "a %s has no roof stretch: all of it under y = 1 (%.3f)" % [kind, top])


func test_far_models_are_lighter() -> void:
	for kind: String in Scenery.KINDS:
		var near := SceneryMeshes.build(kind, 0).surface_get_array_len(0)
		var far := SceneryMeshes.build(kind, 1).surface_get_array_len(0)
		check(far < near, "%s: %d vertices far off, %d near" % [kind, far, near])
	check(SceneryMeshes.build("tree", 1).surface_get_array_len(0) <= 30, "a far tree is a handful of triangles")


func test_each_building_gets_its_roof() -> void:
	var scenery := Scenery.new()
	scenery.route = hw22
	var photo := {"x": 0.0, "z": 0.0, "length": 12.0, "width": 8.0, "yaw": 0.0, "height": 8.0, "eave": 4.0,
		"roof": "gable", "kind": "house", "roof_color": [120, 60, 50]}
	var c := scenery._roof(photo, "house", 1, 0.2, 8.2)
	check(c.r > c.g and c.g > 0.1, "the photo's roof color (%s)" % c)
	check(absf(c.a - 4.2 / 8.2) < 0.001, "the eaves' share of the height, walls under the ground and all (%.3f)" % c.a)
	var flat := photo.duplicate()
	flat.roof = "flat"
	check(scenery._roof(flat, "house", 1, 0.2, 8.2).a == 1.0, "a flat roof: the walls go all the way up")
	var lean := photo.duplicate()
	lean.roof = "lean"
	lean.high = -1
	var l := scenery._roof(lean, "house", 1, 0.2, 8.2).a
	check(l > 4.0 and l < 5.0, "a lean-to up to its -z side: 4 plus the eaves' share (%.3f)" % l)
	lean.high = 1
	l = scenery._roof(lean, "house", 1, 0.2, 8.2).a
	check(l > 2.0 and l < 3.0, "up to its +z side: 2 plus (%.3f)" % l)
	var none := photo.duplicate()
	none.erase("roof_color")
	none.erase("eave")
	var picked := scenery._roof(none, "house", 1, 0.2, 8.2)
	check(picked.a > 0.3 and picked.a < 0.9, "no photo, no eaves in the data: still a roof (%s)" % picked)
	check(scenery._roof(photo, "bin", 1, 0.2, 8.2) == Color(1, 1, 1, 1), "a bin has no roof stretch")
	scenery.free()


func test_the_bake_found_roofs_and_their_colors() -> void:
	for r: RouteData in [hw1, hw22]:
		var shapes := {}
		var colored := 0
		for b: Dictionary in r.buildings:
			shapes[str(b.get("roof", "?"))] = int(shapes.get(str(b.get("roof", "?")), 0)) + 1
			if b.has("roof_color"):
				colored += 1
			check(float(b.get("eave", 0.0)) <= float(b.height) + 0.01, "%s: eaves under the ridge" % r.id)
		check(shapes.get("gable", 0) > r.buildings.size() / 3, "%s: mostly pitched roofs (%s)" % [r.id, shapes])
		check(colored > r.buildings.size() / 2, "%s: most roofs colored from the photos (%d of %d)" % [r.id, colored, r.buildings.size()])


func test_trees_and_yard_lights_stand_clear_of_the_buildings() -> void:
	for r: RouteData in [hw1, hw22]:
		var trunks := 0
		for i in r.trees.size() / 5:
			if r.near_building(r.trees[i * 5], r.trees[i * 5 + 1], 0.3):
				trunks += 1
		check(trunks == 0, "%s: no tree trunk in a building (%d)" % [r.id, trunks])
		var lights := 0
		var bad := 0
		for b: Dictionary in r.buildings:
			if b.get("light") != null:
				lights += 1
				if r.near_building(float(b.light[0]), float(b.light[1]), 1.5):
					bad += 1
		check(lights > 0 and bad == 0, "%s: %d yard lights out in the yards (%d by a wall)" % [r.id, lights, bad])


func test_power_poles_step_round_buildings() -> void:
	var r := hw1
	check(r.near_building(float(r.buildings[0].x), float(r.buildings[0].z), 0.5), "the middle of a building is near it")
	check(not r.near_building(float(r.buildings[0].x) + 500.0, float(r.buildings[0].z) + 500.0, 2.0) \
		or r.buildings.size() > 0, "far off isn't (or there's another there)")
	for route: RouteData in [hw1, hw22]:
		var lines := PowerLines.new()
		lines.route = route
		lines._place(Streets.new(route))
		var hits := 0
		for pole: Transform3D in lines.poles:
			if route.near_building(pole.origin.x, pole.origin.z, PowerLines.CLEAR_OF_BUILDINGS - 0.01):
				hits += 1
		check(lines.poles.size() > 100 and hits == 0, "%s: %d poles, none by a building (%d)" % [route.id, lines.poles.size(), hits])
		lines.free()


func test_kalonas_stores_face_the_road_on_their_lots() -> void:
	for r: RouteData in [hw1, hw22]:
		var stores := r.buildings.filter(func(b): return b.kind == "store")
		check(stores.size() >= 50, "%s: stores in town (%d)" % [r.id, stores.size()])
		var mesh := SceneryMeshes.build("store", 0)
		check(mesh.surface_get_array_len(0) > 0, "a store has a model")
		check(r.lots.size() >= 50, "%s: parking lots off the photos (%d)" % [r.id, r.lots.size()])
		var lots := Lots.new()
		lots.setup(r)
		check(lots.triangle_count > 1000 and lots.get_child_count() > 0, "%s: laid on the ground (%d triangles)" % [r.id, lots.triangle_count])
		lots.free()
		# No tree standing in a lot.
		var trunks := 0
		for lot: Dictionary in r.lots:
			var outline := PackedVector2Array()
			for i in lot.outline.size() / 2:
				outline.append(Vector2(lot.outline[i * 2], lot.outline[i * 2 + 1]))
			var box := Rect2(outline[0], Vector2.ZERO)
			for p in outline:
				box = box.expand(p)
			for i in r.trees.size() / 5:
				var t := Vector2(r.trees[i * 5], r.trees[i * 5 + 1])
				if box.has_point(t) and Geometry2D.is_point_in_polygon(t, outline):
					trunks += 1
		check(trunks == 0, "%s: no tree in a lot (%d)" % [r.id, trunks])
	# The stores round the Kalona 4-way, where both runs start.
	var near := hw1.buildings.filter(func(b): return b.kind == "store" \
		and Vector2(b.x, b.z).distance_to(Vector2(-1080.9, 11689.8)) < 250.0)
	check(near.size() >= 3, "stores by the 4-way in Kalona (%d)" % near.size())
