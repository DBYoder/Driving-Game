extends "res://tests/test_case.gd"
## Phase 6: settings, menus, practice runs, sounds, the horn and the run's title.

const SettingsScript := preload("res://scripts/autoload/settings.gd")
const TEMP_SETTINGS := "user://test_settings.cfg"

var route := RouteData.load_from("res://data/route")


func test_presets_set_everything_and_the_rest_can_change() -> void:
	var s = SettingsScript.new()
	s.set_preset("low", false)
	check(s.render_scale < 1.0 and s.scenery == 0.5 and s.particles() < 1.0 and not s.msaa(), "Low: lower resolution, half the trees, less rain")
	s.set_preset("high", false)
	check(s.render_scale == 1.0 and s.msaa() and s.detail_distance() > Scenery.NEAR_LOD, "High: anti-aliasing, detail further out")
	s.step("render_scale", -1)
	check(s.render_scale == 0.9 and s.preset == "high", "the resolution changes on its own; the preset stays")
	s.step("scenery", 1)
	check(s.scenery == 0.5, "scenery: everything -> half")
	s.step("scenery", 1)
	s.step("scenery", 1)
	check(s.scenery == 1.0, "and round again")
	s.step("master_volume", -1)
	s.step("master_volume", -1)
	check_near(s.master_volume, 0.8, 0.001, "volume in 10% steps")
	for i in 20:
		s.step("radio_volume", -1)
	check(s.radio_volume == 0.0 and s.describe("radio_volume") == "0%", "down to 0, no further")
	s.step("rumble", 1)
	check(not s.rumble and s.describe("rumble") == "Off", "rumble switches off")
	s.free()


func test_settings_are_saved_and_come_back() -> void:
	var s = SettingsScript.new()
	s.save_path = TEMP_SETTINGS
	s.set_preset("low", false)
	s.step("effects_volume", -1)
	s.step("fullscreen", 1)
	s.save()
	var t = SettingsScript.new()
	t.load_file(TEMP_SETTINGS)
	check(t.preset == "low" and t.render_scale == s.render_scale and t.scenery == 0.5, "graphics come back")
	check_near(t.effects_volume, 0.9, 0.001, "volumes come back")
	check(t.fullscreen, "full screen comes back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	t.load_file(TEMP_SETTINGS)
	check(t.preset == "medium" and t.rumble, "no file: the defaults")
	s.free()
	t.free()


func test_a_menu_moves_chooses_and_changes() -> void:
	var m := Menu.new()
	m.setup("TEST")
	m.add_button("a", "First")
	m.add_option("b", "Second", "On")
	m.add_button("c", "Third")
	var chosen := []
	var adjusted := []
	var closed := []
	m.chosen.connect(func(id): chosen.append(id))
	m.adjusted.connect(func(id, d): adjusted.append([id, d]))
	m.closed.connect(func(): closed.append(true))
	m.open()
	m.move(-1)
	check(m.selected_id() == "c", "▲ from the top wraps to the bottom")
	m.accept()
	check(chosen == ["c"], "Enter chooses a button")
	m.move(-1)
	m.change(-1)
	m.accept()
	check(adjusted == [["b", -1], ["b", 1]], "◀ ▶ and Enter change a setting")
	m.change(1)
	m.move(-1)
	m.change(1)
	check(adjusted.size() == 3, "◀ ▶ do nothing on a button")
	m.back()
	check(closed.size() == 1, "Esc backs out")
	m.set_value("b", "Off")
	check(m.items[1].value == "Off", "settings show their value")
	m.free()


func test_practice_runs_save_nothing() -> void:
	var path := "user://test_practice_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var t := RunTracker.new(100.0, 1000.0, "Test car", path)
	t.practice = true
	t.update(500.0, 0.0)
	check(t.running(), "a practice run starts wherever it starts")
	t.update(1000.0, 30.0)
	t.record_score(5000)
	check(t.best_time == 0.0 and t.best_score == 0 and not t.new_best, "nothing's saved")
	check(RunTracker.saved_records(path, "Test car") == [0, 0.0], "not even on disk")
	var real := RunTracker.new(100.0, 1000.0, "Test car", path)
	real.update(150.0, 0.0)
	real.update(1000.0, 600.0)
	real.record_score(4321)
	check(RunTracker.saved_records(path, "Test car") == [4321, 600.0], "a real run is")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_sounds_are_made_from_scratch() -> void:
	for id: String in ["crunch", "thud", "clang", "crack", "whoosh"]:
		var w := Sfx.get_stream(id)
		var seconds := w.data.size() / 2.0 / Sfx.RATE
		check(seconds > 0.2 and seconds < 1.0 and w.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s: %.2f s, once" % [id, seconds])
		var loudest := 0
		for i in range(0, w.data.size(), 2):
			loudest = maxi(loudest, absi(w.data.decode_s16(i)))
		check(loudest > 20000, "%s isn't silent" % id)
	for car_id: String in CarStats.CARS:
		var horn := Sfx.get_stream("horn_" + car_id)
		check(horn.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s's horn loops while held" % car_id)
	check(Sfx.get_stream("horn_tercel") != Sfx.get_stream("horn_windstar"), "each car has its own horn")


func test_the_horn_spooks_deer_ahead() -> void:
	var car := Car.new()
	car.stats = CarStats.preset("legend")
	car.route = route
	car.station = 5000.0
	car.lateral = 1.83
	var run := Run.new()
	var deer := Deer.new()
	deer.setup(route, car, run, PropField.new(), Traffic.new(), 1)
	deer.spots.clear()
	# One frozen in the lane 60 m ahead, one coming in from the field 100 m ahead, one
	# behind the car, one far up the road.
	var frozen := deer._add_animal(deer.add_spot(5060.0, 1.0, 1, false), 0, 1.83)  # in the right lane
	frozen.frozen = true
	var coming := deer._add_animal(deer.add_spot(5100.0, 1.0, 1, false), 0, 80.0)
	var behind := deer._add_animal(deer.add_spot(4950.0, 1.0, 1, false), 0, 80.0)
	var far := deer._add_animal(deer.add_spot(5600.0, 1.0, 1, false), 0, 80.0)
	var coming_dir := coming.dir
	check(deer.spook(Deer.HORN_RANGE) == 2, "a honk spooks the two deer ahead in range")
	check(not frozen.frozen and frozen.spooked, "the one in the road snaps out of it")
	var right := route.right_at(frozen.station)
	check(frozen.dir.dot(right) > 0.9, "and runs for the nearer ditch (the right)")
	check(coming.dir.is_equal_approx(-coming_dir), "the one coming turns back")
	check(not behind.spooked and not far.spooked, "the ones behind and far ahead don't care")
	check(deer.honked_off == 2, "counted")
	deer.free()
	run.free()
	car.free()


func test_runs_get_a_title() -> void:
	check(Awards.title_for({"wreck": "You hit an Amish buggy"}) == "The horse saw that coming.", "the buggy")
	check(Awards.title_for({"wreck": "Rolled it", "car": "windstar"}).begins_with("Minivan gymnastics"), "rolling the Windstar")
	check(Awards.title_for({"wreck": "Head-on with a semi"}).begins_with("Two lanes"), "a head-on")
	check(Awards.title_for({"raw": {"Corn": 2000}}).contains("400 m of corn"), "plowing corn (5 points a meter)")
	check(Awards.title_for({"counts": {"Mailbox": 9}}).begins_with("Federal mailbox offender"), "mailboxes")
	check(Awards.title_for({"counts": {"Lost the cop": 1, "Jurisdiction": 1}}) == "The Dukes of Washington County.", "two escapes")
	check(Awards.title_for({"finished": true, "seconds": 600.0, "score": 20000}) == "Hauling cheese curds.", "a fast finish")
	check(Awards.title_for({"finished": true, "seconds": 900.0, "score": 1000}) == "Drove it like a rental.", "a timid finish")
	check(Awards.title_for({}) == "Just another day on Highway 1.", "nothing much")


func test_the_score_counts_what_happened() -> void:
	var s := ScoreKeeper.new()
	s.car_multiplier = 1.5
	s.add("Mailbox", 50)
	s.add("Mailbox", 50)
	s.add("Corn", 25, false)
	check(s.counts.Mailbox == 2 and s.raw.Mailbox == 100, "two mailboxes, 100 points before multipliers")
	check(s.raw.Corn == 25, "5 m of corn")
	s.reset()
	check(s.counts.is_empty() and s.raw.is_empty(), "a new run starts from nothing")
