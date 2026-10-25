extends "res://tests/test_case.gd"
## Building the world as you drive: what gets built where, and that the big jobs don't
## stall a frame.


## The scenery for a route, in the world (collision needs its physics space).
func _scenery(route: RouteData) -> Scenery:
	var scenery := Scenery.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(scenery)
	scenery.setup(route)
	return scenery


## The block with the most trees.
func _woodiest(scenery: Scenery) -> Scenery.Block:
	var best: Scenery.Block = null
	for block: Scenery.Block in scenery._blocks.values():
		if best == null or block.trees.size() > best.trees.size():
			best = block
	return best


func test_a_block_worked_out_a_slice_at_a_time_comes_out_the_same() -> void:
	# The single-threaded web build works blocks out a slice a frame instead of on a worker.
	var scenery := _scenery(RouteData.load_from(Routes.dir("highway22")))
	var block := _woodiest(scenery)
	scenery._compute(block)
	var at_once := block.buffers
	block.buffers = {}
	var slices := 1
	while not scenery._compute_until(block, 0):  # out of time after every slice
		slices += 1
	check(slices > 10, "thousands of trees take many slices (%d)" % slices)
	check(block.work == null, "and it's done with")
	for kind: String in Scenery.KINDS:
		check(block.buffers[kind] == at_once[kind], "%s: the same instances either way" % kind)
	scenery.free()


func test_woods_are_solid_and_quick_to_build() -> void:
	var scenery := _scenery(RouteData.load_from(Routes.dir("highway22")))
	var block := _woodiest(scenery)
	scenery._compute(block)
	block.node = Node3D.new()
	scenery.add_child(block.node)
	block.lod = 0
	scenery._instantiate(block)
	var start := Time.get_ticks_usec()
	scenery._make_body(block)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	# Shapes added to a body already in the space rebuilt it every time: 1.5 s here.
	check(ms < 150.0, "%d trees' collision builds in a few ms (%.0f ms)" % [block.trees.size(), ms])
	var trees: PackedFloat32Array = block.buffers.tree
	var shapes := PhysicsServer3D.body_get_shape_count(block.body)
	check(shapes >= trees.size() / 16, "a trunk for every tree (%d shapes)" % shapes)
	var first := PhysicsServer3D.body_get_shape_transform(block.body, 0).origin
	var tree := Vector3(trees[3], trees[7], trees[11])
	check(Vector2(first.x - tree.x, first.z - tree.z).length() < 0.01,
		"where the tree is (%s), even headless (%s)" % [tree, first])
	check(PhysicsServer3D.body_get_space(block.body) == scenery.get_world_3d().space, "in the world")
	scenery.free()


func test_building_boxes_are_where_the_buildings_are() -> void:
	# (Read from the renderer, a headless run put every one at the origin.)
	var route := RouteData.load_from(Routes.dir("highway1"))
	var scenery := _scenery(route)
	var b: Dictionary = route.buildings[route.buildings.size() / 2]
	var spot := Vector3(float(b.x), 0.0, float(b.z))
	scenery.warm_up(spot)
	var boxes := scenery.building_boxes(spot, 30.0)
	check(not boxes.is_empty(), "a building's box near it")
	for box: Array in boxes:
		var at: Vector3 = box[0].origin
		check(Vector2(at.x - spot.x, at.z - spot.z).length() < 40.0, "the box is there (%s, not %s)" % [spot, at])
	scenery.free()


func test_the_world_is_built_around_you_and_taken_down_behind() -> void:
	var route := RouteData.load_from(Routes.dir("highway1"))
	var streamer := WorldStreamer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(streamer)
	streamer.setup(route)
	for station: float in [3000.0, 9000.0]:
		streamer.warm_up(route.position_at(station))
		var missing := 0
		var stale := 0
		for kind: String in WorldStreamer.RADII:
			var keys: PackedStringArray = streamer._keys[kind]
			for i in keys.size():
				var d := streamer._distance(kind, i)
				var built: bool = streamer._meshes.has(keys[i])
				if d <= WorldStreamer.RADII[kind][0] and not built:
					missing += 1
				elif d > WorldStreamer.RADII[kind][1] and built:
					stale += 1
		check(missing == 0, "at %d m: everything in range is built (%d missing)" % [station, missing])
		check(stale == 0, "at %d m: everything out of range is taken down (%d left)" % [station, stale])
	check(streamer.collider_count() > 0, "with collision under the car")
	streamer.free()
