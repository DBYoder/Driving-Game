extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/route")


func _spots(seed_value: int) -> Array[float]:
	var deer := Deer.new()
	deer.route = route
	deer.reset(seed_value)
	var out: Array[float] = []
	for spot in deer.spots:
		out.append(spot.station)
	deer.free()
	return out


func test_crossings_are_spread_along_the_route() -> void:
	for seed_value in [1, 2, 3, 99]:
		var spots := _spots(seed_value)
		check(spots.size() >= 4, "seed %d: only %d crossings" % [seed_value, spots.size()])
		for i in spots.size():
			check(spots[i] > route.start_station + 400.0 and spots[i] < route.finish_station - 200.0,
				"seed %d: crossing at %.0f is off the route" % [seed_value, spots[i]])
			if i > 0:
				check(spots[i] - spots[i - 1] >= Deer.SPOT_SPACING,
					"seed %d: crossings %.0f m apart" % [seed_value, spots[i] - spots[i - 1]])


func test_most_crossings_are_at_the_creeks() -> void:
	var at_creeks := 0
	var total := 0
	for seed_value in 20:
		for s in _spots(seed_value):
			total += 1
			for b: Array in route.bridges:
				if absf(s - (float(b[0]) + float(b[1])) / 2.0) < 1.0:
					at_creeks += 1
	check(at_creeks * 2 > total, "%d of %d crossings at creeks" % [at_creeks, total])


func test_same_seed_same_deer() -> void:
	check(_spots(7) == _spots(7), "a run's deer are fixed by its seed")
	check(_spots(7) != _spots(8), "a different run, different deer")
