class_name Menus
extends Node
## The title screen, the pause menu, the settings, the records, the leaderboard and the
## daily challenge, and getting between them. Main does what they ask (see the signals).

signal drive(practice: bool)  ## off to the garage
signal challenge(day: String)  ## drive the daily challenge
signal resume
signal restart
signal garage
signal to_title
signal quit

const VERSION := "v0.9.6"
const SETTINGS := [["preset", "Graphics"], ["render_scale", "Resolution"], ["scenery", "Scenery"],
	["fullscreen", "Display"], ["master_volume", "Volume"], ["effects_volume", "Car and effects"],
	["radio_volume", "Radio"], ["rumble", "Controller rumble"], ["ghost", "Ghost car"], ["touch_controls", "Touch controls"]]

var title: Menu
var pause: Menu
var settings: Menu
var records: Menu
var leaderboard: Menu  ## the shared top tens (when there's a leaderboard)
var daily: Menu  ## the daily challenge: what it is today, and today's top tens
var challenge_day := ""  ## the day the daily challenge is for ("" = today, UTC; the menu QA picks one)
var records_path := ""  ## where the records are kept ("" in tests: none)
var _back_to: Menu  ## where the settings and records go back to


func setup(path: String) -> void:
	records_path = path
	process_mode = Node.PROCESS_MODE_ALWAYS

	var route := Routes.info()
	title = _menu(route.title, "%s → %s" % [route.from, route.to], "left", 64, 6)
	var web := OS.has_feature("web")  # in a browser: no quitting (close the tab), no radio
	var shared := Leaderboard.enabled()
	for b: Array in [["drive", "Drive"], ["challenge", "Daily challenge"], ["practice", "Practice"], ["records", "Records"],
			["leaderboard", "Leaderboard"], ["settings", "Settings"], ["quit", "Quit"]]:
		if not (web and b[0] == "quit") and not (not shared and b[0] == "leaderboard"):
			title.add_button(b[0], b[1])
	title.set_footer("▲ ▼ choose     Enter / A: OK          %s" % VERSION)
	title.chosen.connect(_on_title)
	title.closed.connect(func(): title.open(title.items.size() - 1))  # Esc: over to Quit

	pause = _menu("PAUSED", "", "center", 44, 6)
	for b: Array in [["resume", "Resume"], ["restart", "Restart the run"], ["garage", "Change car"],
			["settings", "Settings"], ["title", "Quit to the title screen"], ["quit", "Quit the game"]]:
		if not (web and b[0] == "quit"):
			pause.add_button(b[0], b[1])
	pause.chosen.connect(_on_pause)
	pause.closed.connect(func(): resume.emit())

	settings = _menu("SETTINGS", "Saved as you change them", "center", 40, 8)
	for s: Array in SETTINGS:
		if not (web and s[0] == "radio_volume"):
			settings.add_option(s[0], s[1], Settings.describe(s[0]))
	if shared:
		settings.add_option("player_name", "Leaderboard name", Settings.describe("player_name"))
	settings.add_button("back", "Back")
	settings.set_footer("▲ ▼ choose     ◀ ▶ change     Esc / B: back")
	settings.adjusted.connect(func(id: String, direction: int):
		Settings.step(id, direction)
		_refresh_settings())
	settings.chosen.connect(func(_id): _close(settings))
	settings.closed.connect(func(): _close(settings))

	records = _menu("RECORDS", "%s: best score and time to %s" % [route.title.capitalize(), route.to], "center", 40, 8)
	records.add_button("back", "Back")
	records.set_footer("Esc / B: back")
	records.chosen.connect(func(_id): _close(records))
	records.closed.connect(func(): _close(records))

	leaderboard = _menu("LEADERBOARD", "%s: the top ten, from everyone's runs" % route.title.capitalize(), "center", 40, 8)
	leaderboard.add_button("back", "Back")
	leaderboard.set_footer("Esc / B: back")
	leaderboard.chosen.connect(func(_id): _close(leaderboard))
	leaderboard.closed.connect(func(): _close(leaderboard))
	Leaderboard.fetched.connect(_on_fetched)

	daily = _menu("DAILY CHALLENGE", "", "center", 40, 8)
	daily.add_button("go", "Drive it")
	daily.add_button("back", "Back")
	daily.chosen.connect(func(id: String):
		if id == "go":
			challenge.emit(daily_challenge().date)  # (main closes it, or says it's loading the route)
		else:
			_close(daily))
	daily.closed.connect(func(): _close(daily))


func any_open() -> bool:
	return title.visible or pause.visible or settings.visible or records.visible or leaderboard.visible or daily.visible


func close_all() -> void:
	for m: Menu in [title, pause, settings, records, leaderboard, daily]:
		m.close()


func open_settings(from: Menu) -> void:
	_back_to = from
	from.close()
	_refresh_settings()
	settings.open()


func open_records(from: Menu) -> void:
	_back_to = from
	from.close()
	records.set_body(_records_table())
	records.open()


func open_leaderboard(from: Menu) -> void:
	_back_to = from
	from.close()
	leaderboard.set_body(CarSelect._label("Loading...", 22, Menu.DIM))
	leaderboard.open()
	Leaderboard.fetch(Routes.current)


## Today's challenge (or challenge_day's).
func daily_challenge() -> Challenge:
	return Challenge.for_date(challenge_day if challenge_day != "" else Challenge.today())


func open_daily(from: Menu) -> void:
	_back_to = from
	from.close()
	var c := daily_challenge()
	daily.set_subtitle(Challenge.describe_date(c.date) + "  ·  the same for everyone today")
	daily.set_body(challenge_card(c, {} if Leaderboard.enabled() else {"ok": false, "error": "off"}))
	daily.open()
	if Leaderboard.enabled():
		Leaderboard.fetch(c.route, c.date)


func _on_fetched(route_id: String, board: Dictionary) -> void:
	var day := String(board.get("challenge", ""))
	if leaderboard.visible and route_id == Routes.current and day == "":
		leaderboard.set_body(leaderboard_table(board))
	elif daily.visible and day != "" and day == daily_challenge().date:
		daily.set_body(challenge_card(daily_challenge(), board))


## What the day's challenge is, and its top tens so far (`board`: {} while they're on
## their way; not ok with error "off": no leaderboard here, so none).
static func challenge_card(c: Challenge, board: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var cond := Condition.preset(c.condition)
	for line: Array in [[Routes.headline(c.route), 24, Color.WHITE],
			["%s  ·  %s  ·  %s" % [CarStats.preset(c.car).display_name, c.paint_name(), cond.display_name], 20, Color.WHITE],
			["%s  The speed traps, deer and traffic are the same every try." % cond.tagline, 16, Menu.DIM]]:
		box.add_child(CarSelect._label(line[0], line[1], line[2]))
	if board.get("error", "") == "off":
		return box
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	box.add_child(CarSelect._label("TODAY'S TOP TEN", 18, Menu.GOLD))
	box.add_child(CarSelect._label("Loading...", 16, Menu.DIM) if board.is_empty() else leaderboard_table(board, 16, false))
	return box


## The top ten times and the top ten scores, side by side (`size`: the rows' text; with
## `cars`, which car each run was in).
static func leaderboard_table(board: Dictionary, size := 18, cars := true) -> Control:
	if not board.get("ok", false):
		return CarSelect._label("Couldn't reach the leaderboard (%s)" % board.get("error", "?"), 22, Menu.DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for side: Array in [["FASTEST", "times"], ["BEST SCORES", "points"]]:
		var column := VBoxContainer.new()
		column.add_child(CarSelect._label(side[0], 20, Menu.GOLD))
		var grid := GridContainer.new()
		grid.columns = 4 if cars else 3
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 6 if size >= 18 else 1)
		var entries: Array = board.get(side[1], [])
		for i in entries.size():
			var e: Dictionary = entries[i]
			var car_id := String(e.get("car", ""))
			var car_name := CarStats.preset(car_id).display_name.substr(5) if car_id in CarStats.CARS else car_id
			var value := RunTracker.format_time(float(e.seconds)) if side[1] == "times" else Hud._fmt(int(e.points))
			for text: String in ["%d." % (i + 1), String(e.get("name", "")), value, car_name].slice(0, grid.columns):
				var label := CarSelect._label(text, size, Color.WHITE if text != car_name else Menu.DIM)
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				grid.add_child(label)
		if entries.is_empty():
			column.add_child(CarSelect._label("No runs yet: be the first", 18, Menu.DIM))
		column.add_child(grid)
		row.add_child(column)
	return row


func _on_title(id: String) -> void:
	match id:
		"drive", "practice":
			title.close()
			drive.emit(id == "practice")
		"challenge":
			open_daily(title)
		"records":
			open_records(title)
		"leaderboard":
			open_leaderboard(title)
		"settings":
			open_settings(title)
		"quit":
			quit.emit()


func _on_pause(id: String) -> void:
	match id:
		"resume":
			resume.emit()
		"restart":
			pause.close()
			restart.emit()
		"garage":
			pause.close()
			garage.emit()
		"settings":
			open_settings(pause)
		"title":
			pause.close()
			to_title.emit()
		"quit":
			quit.emit()


func _close(menu: Menu) -> void:
	menu.close()
	if _back_to:
		var id := {settings: "settings", records: "records", leaderboard: "leaderboard", daily: "challenge"}.get(menu, "records") as String
		_back_to.open(maxi(_back_to.items.find_custom(func(it): return it.id == id), 0))


func _refresh_settings() -> void:
	for s: Array in SETTINGS + [["player_name", ""]]:
		settings.set_value(s[0], Settings.describe(s[0]))


## Best score and time for every car in every condition.
func _records_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = Condition.IDS.size() + 1
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	grid.add_child(CarSelect._label("", 16))
	for id: String in Condition.IDS:
		grid.add_child(CarSelect._label(Condition.preset(id).display_name.replace(" ", "\n"), 16, Menu.GOLD))
	for car_id: String in CarStats.CARS:
		var car_name := CarStats.preset(car_id).display_name
		var name_label := CarSelect._label(car_name.substr(5), 16)  # "1998 Ford Windstar" -> "Ford Windstar"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(name_label)
		for id: String in Condition.IDS:
			var best := RunTracker.saved_records(records_path, Condition.preset(id).records_key(car_name))
			var text := "—"
			if best[0] > 0 or best[1] > 0.0:
				text = "%s\n%s" % [Hud._fmt(best[0]), RunTracker.format_time(best[1]) if best[1] > 0.0 else "no finish"]
			grid.add_child(CarSelect._label(text, 18, Color.WHITE if text != "—" else Menu.DIM))
	return grid


func _menu(text: String, subtitle: String, side: String, size: int, panel_layer: int) -> Menu:
	var m := Menu.new()
	add_child(m)
	m.setup(text, subtitle, side, size, panel_layer)
	return m
