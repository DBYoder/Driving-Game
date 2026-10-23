extends "res://tests/test_case.gd"
## The shared leaderboard on the game's side (the autoload `Leaderboard`; the server's
## own tests are in server/tests).


func test_off_without_a_site() -> void:
	check(not Leaderboard.enabled(), "no leaderboard in a desktop build until it's given the site's address")
	var menus := Menus.new()
	menus.setup("")
	check(menus.title.items.all(func(it): return it.id != "leaderboard"), "so no Leaderboard on the title screen")
	menus.free()


func test_on_with_a_site() -> void:
	var was := Leaderboard.base_url
	Leaderboard.base_url = "https://example.test"
	var menus := Menus.new()
	menus.setup("")
	check(menus.title.items.any(func(it): return it.id == "leaderboard"), "Leaderboard on the title screen")
	check(menus.settings.items.any(func(it): return it.id == "player_name"), "and the name to change in the settings")
	menus.free()
	Leaderboard.base_url = was


func test_names_are_tidied_like_the_server_does() -> void:
	check(Leaderboard.tidy_name("  Big   Dave ") == "Big Dave", "spaces squeezed")
	check(Leaderboard.tidy_name("<b>Ann</b>") == "bAnnb", "only letters, numbers and a few marks")
	check(Leaderboard.tidy_name("A very long name indeed") == "A very long name", "at most 16")
	check(Leaderboard.tidy_name("!!!") == "", "nothing left: no name")


func test_what_gets_posted() -> void:
	var finished := Leaderboard.run_body("highway22", " Ann ", 1234, 512.345, "tercel", "night", "v0.9")
	check(finished.name == "Ann" and finished.points == 1234 and is_equal_approx(finished.seconds, 512.35),
		"a finished run: name, points, time to the hundredth")
	check(finished.route == "highway22" and finished.car == "tercel" and finished.condition == "night", "where and how")
	var wrecked := Leaderboard.run_body("highway1", "Ann", 99, 0.0, "legend", "summer", "v0.9")
	check(wrecked.seconds == null, "a wreck has no time")


func test_where_it_placed() -> void:
	check(Leaderboard.ordinal(1) == "1st" and Leaderboard.ordinal(2) == "2nd" and Leaderboard.ordinal(3) == "3rd"
		and Leaderboard.ordinal(4) == "4th" and Leaderboard.ordinal(11) == "11th" and Leaderboard.ordinal(22) == "22nd", "ordinals")
	check(Leaderboard.placing({"ok": true, "time_rank": 3, "points_rank": 1}, "Highway 1")
		== "3rd fastest and 1st best score on Highway 1!", "both")
	check(Leaderboard.placing({"ok": true, "time_rank": 0, "points_rank": 0}, "Highway 1")
		== "Not in Highway 1's top ten this time", "neither")
	check(Leaderboard.placing({"ok": false, "error": "no connection"}, "Highway 1") == "Couldn't reach the leaderboard",
		"no connection")
	check(Leaderboard.placing({"ok": false, "error": "too many runs from here"}, "Highway 1")
		== "Not on the leaderboard: too many runs from here", "turned away, and why")


func test_the_top_tens_table() -> void:
	var board := {"ok": true, "times": [{"name": "Ann", "seconds": 512.3, "points": 9000, "car": "tercel"}],
		"points": [{"name": "Bob", "seconds": null, "points": 12000, "car": "windstar"},
			{"name": "Ann", "seconds": 512.3, "points": 9000, "car": "tercel"}]}
	var table := Menus.leaderboard_table(board)
	var texts: Array = []
	var stack: Array[Node] = [table]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			texts.append(n.text)
		stack.append_array(n.get_children())
	check(texts.has("FASTEST") and texts.has("BEST SCORES"), "both lists")
	check(texts.has("8:32.3") and texts.has("12,000") and texts.has("Ford Windstar"), "times, points and cars (%s)" % [texts])
	table.free()
	var down := Menus.leaderboard_table({"ok": false, "error": "no connection"})
	check(down is Label and String(down.text).begins_with("Couldn't reach"), "says so when it can't get them")
	down.free()
