extends "res://tests/test_case.gd"
## The daily challenge: the day picks the route, car, condition and seed (Challenge), and
## it has its own top tens (the server's side is in server/tests).


func test_the_day_picks_it_the_way_the_server_does() -> void:
	# (The same days and picks as server/tests/test_app.py: the two must agree.)
	for want: Array in [["2026-10-31", "highway22", "legend", "harvest"], ["2026-11-01", "highway1", "legend", "storm"],
			["2026-12-25", "highway22", "tercel", "harvest"]]:
		var c := Challenge.for_date(want[0])
		check(c.route == want[1] and c.car == want[2] and c.condition == want[3],
			"%s: %s, %s, %s (got %s, %s, %s)" % [want[0], want[1], want[2], want[3], c.route, c.car, c.condition])


func test_the_same_all_day_and_new_the_next() -> void:
	var a := Challenge.for_date("2026-10-31")
	var b := Challenge.for_date("2026-10-31")
	check(a.route == b.route and a.car == b.car and a.paint == b.paint and a.condition == b.condition
		and a.seed_value == b.seed_value, "the same day, the same challenge")
	var routes := {}
	var cars := {}
	var conditions := {}
	var seeds := {}
	var t := Time.get_unix_time_from_datetime_string("2026-11-01T00:00:00")
	for i in 40:
		var day := Time.get_date_string_from_unix_time(t + i * 86400)
		var c := Challenge.for_date(day)
		check(c.route in Routes.IDS and c.car in CarStats.CARS and c.condition in Condition.IDS,
			"%s: a route, car and condition there are" % day)
		check(c.seed_value > 0, "and a seed")
		routes[c.route] = true
		cars[c.car] = true
		conditions[c.condition] = true
		seeds[c.seed_value] = true
	check(routes.size() == Routes.IDS.size() and cars.size() == CarStats.CARS.size()
		and conditions.size() == Condition.IDS.size(), "over 40 days, every route, car and condition comes up")
	check(seeds.size() == 40, "and a new seed every day")


func test_the_day_and_the_car_as_shown() -> void:
	check(Challenge.describe_date("2026-10-31") == "Saturday, October 31", Challenge.describe_date("2026-10-31"))
	check(Challenge.describe_date("2027-01-01") == "Friday, January 1", Challenge.describe_date("2027-01-01"))
	var c := Challenge.for_date("2026-10-31")
	var stats := c.car_stats()
	check(stats.id == c.car and CarStats.preset(c.car).paints.any(func(p): return p[1] == stats.body_color),
		"the car in one of its own paints")
	check(c.paint_name() != "", "with its name")
	check(Challenge.today().length() == 10 and Challenge.today().count("-") == 2, "today is YYYY-MM-DD")


func test_posted_with_its_day() -> void:
	var body := Leaderboard.run_body("highway22", "Ann", 1234, 401.0, "legend", "harvest", "v0.9.6", "2026-10-31")
	check(body.challenge == "2026-10-31", "a challenge run says which day's")
	check(not Leaderboard.run_body("highway22", "Ann", 1, 0.0, "legend", "harvest", "v0.9.6").has("challenge"),
		"another run doesn't")


func test_where_a_challenge_run_placed() -> void:
	check(Leaderboard.placing({"ok": true, "time_rank": 0, "points_rank": 0, "challenge_time_rank": 2,
		"challenge_points_rank": 0}, "Highway 22", true) == "2nd fastest today!", "today's")
	check(Leaderboard.placing({"ok": true, "time_rank": 4, "points_rank": 0, "challenge_time_rank": 1,
		"challenge_points_rank": 1}, "Highway 22", true)
		== "1st fastest and 1st best score today!  And 4th fastest on Highway 22!", "and the route's too")
	check(Leaderboard.placing({"ok": true, "time_rank": 0, "points_rank": 0, "challenge_time_rank": 0,
		"challenge_points_rank": 0}, "Highway 22", true) == "Not in today's top ten this time", "neither")


func test_on_the_title_screen_with_its_card() -> void:
	var menus := Menus.new()
	menus.setup("")
	check(menus.title.items[1].id == "challenge", "Daily challenge, under Drive")
	menus.challenge_day = "2026-10-31"
	menus.open_daily(menus.title)
	check(menus.daily.visible and not menus.title.visible, "it opens its card")
	var card := Menus.challenge_card(Challenge.for_date("2026-10-31"), {"ok": false, "error": "off"})
	var texts := _texts(card)
	check(texts.has(Routes.headline("highway22")) and texts.any(func(t): return String(t).begins_with(CarStats.preset("legend").display_name + "  ·  ")),
		"the route and the car (%s)" % [texts])
	check(not texts.has("TODAY'S TOP TEN"), "no top ten without a leaderboard")
	card.free()
	card = Menus.challenge_card(Challenge.for_date("2026-10-31"), {"ok": true, "challenge": "2026-10-31",
		"times": [{"name": "Ann", "seconds": 401.2, "points": 9000, "car": "legend"}], "points": []})
	check(_texts(card).has("TODAY'S TOP TEN") and _texts(card).has("Ann"), "today's top ten with one")
	card.free()
	menus.daily.back()
	check(menus.title.visible and menus.title.selected_id() == "challenge", "Back to the title, on Daily challenge")
	menus.free()


func _texts(root: Node) -> Array:
	var out := []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append(n.text)
		stack.append_array(n.get_children())
	return out
