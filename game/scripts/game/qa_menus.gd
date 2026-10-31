class_name QaMenus
extends Node
## A scripted walk through the menus, pressing buttons the way a player would:
##   HighwayOne --headless --fixed-fps 60 -- --qa-menus
## Title screen (its car drives itself, on runs that don't count) → Settings (High
## graphics) → Records → Practice from mile 4 (gas, horn, a deputy on your tail) → pause →
## Change car (the chase stays behind) → back to the title → Drive a real run from Kalona →
## pause → quit to the title → the daily challenge (a day's that's on this route): its car,
## condition and seed, the same traps again on a restart → quit to the title. Checks each
## screen shows up and does what it should; prints a report and exits 0/1.

var main: Node
var _steps: Array[Callable] = []
var _wait := 0.0
var _problems: Array[String] = []
var _log: Array[String] = []
var _challenge: Challenge
var _traps: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_steps = [
		func(): _expect(main.menus.title.visible, "the title screen is up at the start"),
		func(): _hold(3.0),
		func():
			_expect(main.car.forward_speed() > 5.0, "the title screen's car drives itself (%.0f mph)" % (main.car.forward_speed() * Hud.MPH))
			_expect(main.tracker.running() and not main.tracker.counts(), "on a run that doesn't count (no records, nothing posted)")
			_press("menu_down", 4)
			_expect(main.menus.title.selected_id() == "settings", "▼ ×4 gets to Settings")
			_press("menu_accept"),
		func():
			_expect(main.menus.settings.visible and not main.menus.title.visible, "Settings opens over the title")
			_press("menu_right")
			_expect(Settings.preset == "high", "◀ ▶ changes the graphics (now %s)" % Settings.preset)
			_expect(get_viewport().msaa_3d == Viewport.MSAA_2X, "High turns on anti-aliasing")
			_press("menu_left")
			_press("menu_back"),
		func():
			_expect(main.menus.title.visible and main.menus.title.selected_id() == "settings", "Esc goes back to the title")
			_press("menu_down")
			_expect(main.menus.title.selected_id() == "quit", "▼ to Quit")
			_press("menu_up", 2)
			_press("menu_accept"),
		func():
			_expect(main.menus.records.visible, "Records opens")
			_press("menu_accept"),
		func():
			_expect(main.menus.title.visible, "and closes")
			_press("menu_up")
			_expect(main.menus.title.selected_id() == "practice", "▲ to Practice")
			_press("menu_accept"),
		func():
			_expect(main.garage.visible and main.garage.practice, "Practice opens the garage for a practice run")
			_press("menu_down", 3)
			_press("menu_right", 4)
			_expect(main.garage.start_index == 4, "◀ ▶ picks where to start (mile %d)" % main.garage.start_index)
			_press("menu_accept"),
		func():
			var mile: float = main.route.mile_at(main.car.station)
			_expect(main.hud.visible and not main.garage.visible, "the run starts")
			_expect(absf(mile - 4.0) < 0.1, "at mile 4 (%.2f)" % mile)
			_expect(main.tracker.practice and main.hud.practice, "as practice")
			Input.action_press("accelerate")
			Input.action_press("horn"),
		func(): _hold(3.0),
		func():
			_expect(main.car.forward_speed() > 8.0, "the gas works (%.0f mph)" % (main.car.forward_speed() * Hud.MPH))
			_expect(main.car.horn, "so does the horn")
			_expect(main.tracker.running(), "the clock's running")
			Input.action_release("accelerate")
			Input.action_release("horn")
			main.cops.chase_from_behind()
			_expect(main.cops.chasing(), "a deputy's on your tail")
			_press("pause"),
		func():
			_expect(get_tree().paused and main.menus.pause.visible, "Esc pauses, with the pause menu")
			_press("menu_down", 2)
			_press("menu_accept"),
		func():
			_expect(not get_tree().paused and main.garage.visible and main.garage.practice, "Change car goes to the garage (still practice)")
			_expect(not main.cops.chasing() and not main.cops.siren.on, "and the deputy doesn't follow you there")
			_press("menu_back"),
		func():
			_expect(main.menus.title.visible and not main.garage.visible, "Esc in the garage goes back to the title")
			_expect(not main.tracker.practice, "and that's the end of practice")
			_expect(main.menus.title.selected_id() == "drive", "Drive is picked")
			_press("menu_accept"),
		func():
			_expect(main.garage.visible and not main.garage.practice, "Drive opens the garage for a real run")
			_press("menu_accept"),
		func():
			_expect(main.car.station < main.route.start_station, "a real run starts behind the Kalona line")
			_expect(main.tracker.counts() and not main.hud.practice, "and counts")
			_press("pause"),
		func():
			_expect(main.menus.pause.visible, "paused again")
			_press("menu_up", 2)
			_expect(main.menus.pause.selected_id() == "title", "▲ ▲ to Quit to the title screen")
			_press("menu_accept"),
		func():
			_expect(main.menus.title.visible and not get_tree().paused, "back at the title screen, unpaused")
			_challenge = _challenge_here()
			main.menus.challenge_day = _challenge.date
			_press("menu_down")
			_expect(main.menus.title.selected_id() == "challenge", "▼ to Daily challenge")
			_press("menu_accept"),
		func():
			_expect(main.menus.daily.visible, "the daily challenge's card (%s: %s, %s)" % [_challenge.date, _challenge.car, _challenge.condition])
			_press("menu_accept"),
		func():
			_expect(main.hud.visible and not main.menus.any_open() and main.challenge != null and main.hud.challenge,
				"Drive it starts the challenge")
			_expect(main.car.stats.id == _challenge.car and main.condition.id == _challenge.condition,
				"in its car and condition (%s, %s)" % [main.car.stats.id, main.condition.id])
			_expect(main.car.station < main.route.start_station and main.tracker.counts(), "from Kalona, a run that counts")
			_expect(main._seed == _challenge.seed_value, "on the day's seed")
			_traps = main.cops.traps.map(func(t): return t.station)
			_press("restart"),
		func():
			_expect(main.challenge != null and main._seed == _challenge.seed_value, "R: the challenge again, the same seed")
			_expect(main.cops.traps.map(func(t): return t.station) == _traps, "and the speed traps in the same places (%s)" % [_traps])
			_press("pause"),
		func():
			_press("menu_up", 2)
			_press("menu_accept"),
		func():
			_expect(main.menus.title.visible and main.challenge == null and not main.hud.challenge, "quit to the title: the challenge is over")
			_expect(main.car.stats.id == main.garage.current_car(), "and the garage's car is back")
			_finish(),
	]


## A day whose challenge is on this route (the walk can't build the world again).
func _challenge_here() -> Challenge:
	var t := Time.get_unix_time_from_datetime_string(Challenge.today() + "T12:00:00")
	for i in 60:
		var c := Challenge.for_date(Time.get_date_string_from_unix_time(t + i * 86400))
		if c.route == Routes.current:
			return c
	return Challenge.for_date(Challenge.today())


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	if _steps.is_empty():
		return
	var step: Callable = _steps.pop_front()
	step.call()
	_wait = maxf(_wait, 0.25)  # a few frames for the screens to react


## Press (and let go of) a button `times` times.
func _press(action: String, times := 1) -> void:
	for i in times:
		for pressed: bool in [true, false]:
			var e := InputEventAction.new()
			e.action = action
			e.pressed = pressed
			Input.parse_input_event(e)
		Input.flush_buffered_events()


func _hold(seconds: float) -> void:
	_wait = seconds


func _expect(ok: bool, what: String) -> void:
	_log.append(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_problems.append(what)


func _finish() -> void:
	print("QA menus:")
	for line in _log:
		print(line)
	if _problems.is_empty():
		print("QA OK")
		get_tree().quit(0)
	else:
		print("QA FAIL: %d problems" % _problems.size())
		get_tree().quit(1)
