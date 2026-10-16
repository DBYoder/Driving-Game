extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/route")
var fields := Fields.new(route)


func _field() -> PropField:
	var f := PropField.new()
	f.route = route
	f.fields = fields
	return f


func _all(field: PropField) -> Array:
	var props := []
	for c in ceili(route.length / PropField.CHUNK_LENGTH):
		props.append_array(field.generate(c))
	return props


func test_props_are_the_same_every_run() -> void:
	var a := _all(_field())
	var b := _all(_field())
	check(a.size() == b.size() and a.size() > 0, "same number of props (%d vs %d)" % [a.size(), b.size()])
	for i in mini(a.size(), b.size()):
		if a[i].kind != b[i].kind or not a[i].position.is_equal_approx(b[i].position):
			check(false, "prop %d differs between runs" % i)
			return


func test_prop_density_and_placement() -> void:
	var field := _field()
	var props := _all(field)
	var counts := {"mailbox": 0, "fence": 0, "bale": 0}
	var miles := route.length / RouteData.MILE_M
	for p in props:
		counts[p.kind] += 1
		if p.kind != "bale":
			var s := route.nearest_station(p.position)
			for c in route.crossroads:
				check(absf(c.station - s) >= PropField.CROSSROAD_CLEARANCE - 3.0,
					"%s %d sits on the %s crossroad" % [p.kind, p.id, c.name])
		else:
			var crop := fields.crop_at(p.position.x, p.position.z)
			check(crop == Fields.HAY or crop == Fields.PASTURE, "bale %d is in a %s field" % [p.id, crop])
	print("        props: %d mailboxes, %d fence spans, %d hay bales over %.1f mi" % [
		counts.mailbox, counts.fence, counts.bale, miles])
	check(counts.mailbox / miles > 2.0 and counts.mailbox / miles < 8.0, "a few mailboxes per mile")
	check(counts.fence > 100, "some fence lines")
	check(counts.bale > 10, "some hay bales")


func test_crop_lookup_is_stable() -> void:
	check(Fields.cell_hash(3, -7) == Fields.cell_hash(3, -7), "hash is deterministic")
	var seen := {}
	for x in range(-20, 20):
		for z in range(-20, 20):
			seen[fields.crop_at(x * Fields.FIELD_SIZE + 1.0, z * Fields.FIELD_SIZE + 1.0)] = true
	check(seen.size() == 4, "all four crops appear (%s)" % [seen.keys()])
