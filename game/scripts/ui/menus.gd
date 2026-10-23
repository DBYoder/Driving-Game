class_name Menus
extends Node
## The title screen, the pause menu, the settings and the records, and getting between
## them. Main does what they ask (see the signals).

signal drive(practice: bool)  ## off to the garage
signal resume
signal restart
signal garage
signal to_title
signal quit

const VERSION := "v0.8"
const SETTINGS := [["preset", "Graphics"], ["render_scale", "Resolution"], ["scenery", "Scenery"],
	["fullscreen", "Display"], ["master_volume", "Volume"], ["effects_volume", "Car and effects"],
	["radio_volume", "Radio"], ["rumble", "Controller rumble"]]

var title: Menu
var pause: Menu
var settings: Menu
var records: Menu
var records_path := ""  ## where the records are kept ("" in tests: none)
var _back_to: Menu  ## where the settings and records go back to


func setup(path: String) -> void:
	records_path = path
	process_mode = Node.PROCESS_MODE_ALWAYS

	var route := Routes.info()
	title = _menu(route.title, "%s → %s" % [route.from, route.to], "left", 64, 6)
	for b: Array in [["drive", "Drive"], ["practice", "Practice"], ["records", "Records"], ["settings", "Settings"], ["quit", "Quit"]]:
		title.add_button(b[0], b[1])
	title.set_footer("▲ ▼ choose     Enter / A: OK          %s" % VERSION)
	title.chosen.connect(_on_title)
	title.closed.connect(func(): title.open(title.items.size() - 1))  # Esc: over to Quit

	pause = _menu("PAUSED", "", "center", 44, 6)
	for b: Array in [["resume", "Resume"], ["restart", "Restart the run"], ["garage", "Change car"],
			["settings", "Settings"], ["title", "Quit to the title screen"], ["quit", "Quit the game"]]:
		pause.add_button(b[0], b[1])
	pause.chosen.connect(_on_pause)
	pause.closed.connect(func(): resume.emit())

	settings = _menu("SETTINGS", "Saved as you change them", "center", 40, 8)
	for s: Array in SETTINGS:
		settings.add_option(s[0], s[1], Settings.describe(s[0]))
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


func any_open() -> bool:
	return title.visible or pause.visible or settings.visible or records.visible


func close_all() -> void:
	for m: Menu in [title, pause, settings, records]:
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


func _on_title(id: String) -> void:
	match id:
		"drive", "practice":
			title.close()
			drive.emit(id == "practice")
		"records":
			open_records(title)
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
		_back_to.open(_back_to.items.find_custom(func(it): return it.id == ("settings" if menu == settings else "records")))


func _refresh_settings() -> void:
	for s: Array in SETTINGS:
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
