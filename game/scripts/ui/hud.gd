class_name Hud
extends CanvasLayer
## Trip readout (top left), clock (top right), score and combo (top center), who's
## chasing you (under the combo), speed, the boost meter and car health (bottom right), scoring popups,
## big messages, the results screen, and control hints (bottom left).

const MPH := 2.23694
const RESULTS_DELAY := 2.5  ## seconds of crash cam before the results after a wreck

var route: RouteData
var car: Car
var run: Run
var tracker: RunTracker
var camera: ChaseCamera
var cops: Cops
var condition_name := ""
var practice := false  ## a practice run: nothing's saved
## The shared leaderboard on the results: where the run placed ("" = nothing to say), or a
## box asking for the player's name the first time.
signal name_entered(text: String)
var leaderboard_line := ""
var asking_name := false
var asking_in_page := false  ## the name's being typed in the web page's own box (a phone's keyboard)
var _name_edit: LineEdit
var _name_callback: JavaScriptObject  ## (kept, or the browser's call back finds it gone)
## Touch controls are up (Touch): no key hints, the speed and meters out of the pedals' way
## at the bottom middle, and buttons on the results.
var touch := false
var _results_buttons: HBoxContainer
var deer: Deer  ## for the run's title (deer honked off the road)
var _trip: Label
var _clock: Label
var _score: Label
var _combo: Label
var _chase: Label
var _banner := ""
var _banner_time := 0.0
var _speed: Label
var _health: ProgressBar
var _boost: ProgressBar
var _boost_fill: StyleBoxFlat
var _boost_label: Label
var _boost_flash := 0.0
var _message: Label
var _hint: Label
var _note: Label  ## a small line over the hints (the radio's song)
var _note_time := 0.0
var _results: PanelContainer
var _results_grid: GridContainer
var _popups: VBoxContainer
var _go_flash := 0.0
var _over_time := 0.0


func setup(r: RouteData, c: Car, game_run: Run, cam: ChaseCamera) -> void:
	route = r
	car = c
	run = game_run
	tracker = game_run.tracker
	camera = cam
	process_mode = Node.PROCESS_MODE_ALWAYS

	_trip = _label(20, Control.PRESET_TOP_LEFT, Vector2(24, 18))
	_clock = _label(34, Control.PRESET_TOP_RIGHT, Vector2(-24, 14))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score = _label(40, Control.PRESET_CENTER_TOP, Vector2(0, 10))
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo = _label(26, Control.PRESET_CENTER_TOP, Vector2(0, 62))
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_chase = _label(24, Control.PRESET_CENTER_TOP, Vector2(0, 98))
	_chase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed = _label(52, Control.PRESET_BOTTOM_RIGHT, Vector2(-28, -20))
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health = _health_bar()
	_boost = _boost_bar()
	car.boost.filled.connect(func(_amount): _boost_flash = 0.6)
	_message = _label(40, Control.PRESET_CENTER, Vector2(0, -235))  # above the start banner
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _label(15, Control.PRESET_BOTTOM_LEFT, Vector2(24, -16))
	_hint.text = "W/S or triggers: gas/brake (hold S to reverse)    A/D or stick: steer    Space or A: handbrake    Shift or B: boost\n" \
		+ "H or RB: horn    C or Y: camera    T or X: tow truck (-500)    R or Back: restart    %sEsc or Start: menu" \
		% ("" if OS.has_feature("web") else "N / B: radio    ")
	_note = _label(20, Control.PRESET_BOTTOM_LEFT, Vector2(24, -66))
	_popups = VBoxContainer.new()
	add_child(_popups)
	_popups.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_popups.position += Vector2(-320, -120)
	_popups.custom_minimum_size = Vector2(300, 0)
	_results = _results_panel()

	run.score.scored.connect(_on_scored)
	run.score.combo_lost.connect(func(points): if points > 0: _popup("Combo lost  -%s" % _fmt(points), Color(1, 0.45, 0.4)))
	car.hit.connect(func(damage, _smash): if damage >= Run.HARD_HIT_DAMAGE: _popup("Ouch  -%d%%" % roundi(damage / car.stats.durability * 100.0), Color(1, 0.45, 0.4)))


func _process(delta: float) -> void:
	if car == null:
		return
	var s := car.station
	var finish_mile := route.mile_at(route.finish_station)
	var lines := ["PRACTICE  ·  nothing's saved" if practice else Routes.headline(route.id),
		"%s  ·  points ×%s%s" % [car.stats.display_name, str(car.stats.score_multiplier),
			"  ·  " + condition_name if condition_name != "" else ""],
		"Mile %.1f of %.1f    %s view" % [clampf(route.mile_at(s), 0.0, finish_mile), finish_mile, camera.mode_name()]]
	var next := route.next_crossroad(s)
	if not next.is_empty() and s < route.finish_station:
		var label: String = next.name if next.route == "" else "%s (%s)" % [next.name, next.route]
		lines.append("Next: %s in %.1f mi" % [label, (next.station - s) / RouteData.MILE_M])
	_trip.text = "\n".join(lines)

	var best := "Best  %s" % RunTracker.format_time(tracker.best_time) if tracker.best_time > 0.0 else "No best time yet"
	_clock.text = "%s\n%s" % [RunTracker.format_time(tracker.elapsed), best]
	_score.text = _fmt(run.score.banked)
	var score_keeper := run.score
	_combo.text = "+%s  x%d" % [_fmt(score_keeper.pot), score_keeper.multiplier] if score_keeper.multiplier > 0 else ""
	_speed.text = "%d mph" % roundi(absf(car.forward_speed()) * MPH)
	_speed.visible = camera.mode_name() != "In car"  # the speedometer's right there
	_health.value = car.health / car.stats.durability * 100.0
	_boost.value = car.boost.meter * 100.0
	_boost_flash = maxf(_boost_flash - delta, 0.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 4.0)
	if car.boost.active:
		_boost_fill.bg_color = Color(0.45, 0.85, 1.0).lerp(Color(1, 1, 1), pulse * 0.5)
	elif _boost_flash > 0.0 or car.boost.full():
		_boost_fill.bg_color = Color(1.0, 0.62, 0.15).lerp(Color(1.0, 0.95, 0.6), pulse if _boost_flash > 0.0 else pulse * 0.4)
	else:
		_boost_fill.bg_color = Color(1.0, 0.62, 0.15)
	_boost_label.modulate.a = 1.0 if car.boost.meter > 0.0 else 0.55

	var chase := cops.status() if cops else ""
	_chase.text = chase
	if chase != "":
		var flash := fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
		_chase.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3) if flash else Color(0.45, 0.6, 1.0))

	_banner_time = maxf(_banner_time - delta, 0.0)
	_note_time = maxf(_note_time - delta, 0.0)
	_note.modulate.a = clampf(_note_time, 0.0, 1.0)
	_go_flash = maxf(_go_flash - delta, 0.0)
	_over_time = _over_time + delta if tracker.over() else 0.0
	var show_results := tracker.state == RunTracker.State.FINISHED \
		or (tracker.state == RunTracker.State.WRECKED and _over_time > RESULTS_DELAY)
	if show_results and not _results.visible:
		_fill_results()
	_results.visible = show_results

	if get_tree().paused:
		_show("", 40)  # the pause menu says so
	elif tracker.state == RunTracker.State.READY:
		_show("Gas it: the clock starts at the line", 26)
		_go_flash = 1.2
	elif tracker.state == RunTracker.State.WRECKED and not show_results:
		_show(tracker.wreck_reason.to_upper(), 52)
	elif tracker.over():
		_show("", 40)
	elif _go_flash > 0.0:
		_show("GO!", 56)
	elif _banner_time > 0.0:
		_show(_banner, 48)
	else:
		_show("", 40)


## A big message for a couple of seconds ("SPEED TRAP!").
## A small line at the bottom left for a few seconds (the radio's song).
func note(text: String, seconds := 4.0) -> void:
	_note.text = text
	_note_time = seconds


func banner(text: String, seconds := 2.0) -> void:
	_banner = text
	_banner_time = seconds


func _on_scored(label: String, points: int) -> void:
	_popup("+%s  %s" % [_fmt(points), label], Color(1, 1, 1))


func _popup(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	_popups.add_child(label)
	while _popups.get_child_count() > 5:
		_popups.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _fill_results() -> void:
	for child in _results_grid.get_children():
		child.free()
	var score := run.score
	var finished := tracker.state == RunTracker.State.FINISHED
	_row(("PRACTICE: " if practice else "") + (String(route.info.to).to_upper() + "!" if finished else "WRECKED: %s" % tracker.wreck_reason), "", 34)
	_row(Awards.title_for({"finished": finished, "wreck": "" if finished else tracker.wreck_reason,
		"car": car.stats.id, "seconds": tracker.elapsed, "score": score.banked, "counts": score.counts,
		"raw": score.raw, "honked": deer.honked_off if deer else 0}), "", 24, Color(1.0, 0.85, 0.3))
	var time_note := "  NEW BEST" if tracker.new_best else ""
	_row("Time", RunTracker.format_time(tracker.elapsed) + time_note)
	var labels := score.totals.keys()
	labels.sort()
	for label in labels:
		_row(label, _fmt(score.totals[label]))
	if finished:
		_row("Made it  x%.1f" % ScoreKeeper.FINISH_MULTIPLIER, "+" + _fmt(score.finish_bonus))
		_row("Under %s" % RunTracker.format_time(score.par_seconds).get_slice(".", 0), "+" + _fmt(score.time_bonus))
	else:
		_row("Made it to %s" % route.info.to, "no")
	_row("SCORE", _fmt(score.banked) + ("  NEW BEST" if tracker.new_best_score else ""), 30)
	if practice:
		_row("Practice runs aren't saved", "")
	else:
		_row("Best score", _fmt(tracker.best_score))
	if asking_name and asking_in_page:
		_row("Leaderboard", "Type your name in the box", 22, Menu.GOLD)
	elif asking_name:
		var ask := Label.new()
		ask.text = "Your name for the leaderboard"
		ask.add_theme_font_size_override("font_size", 22)
		ask.add_theme_color_override("font_color", Menu.GOLD)
		_results_grid.add_child(ask)
		_name_edit = LineEdit.new()
		_name_edit.placeholder_text = "then press Enter"
		_name_edit.max_length = Leaderboard.NAME_LENGTH
		_name_edit.custom_minimum_size = Vector2(260, 0)
		_name_edit.add_theme_font_size_override("font_size", 22)
		# (Deferred: the answer rebuilds the results, and the box can't be freed while it's
		# still handling the Enter, or the Enter falls through and opens the garage.)
		_name_edit.text_submitted.connect(func(text: String): name_entered.emit(text), CONNECT_DEFERRED)
		_results_grid.add_child(_name_edit)
		_name_edit.grab_focus.call_deferred()
	elif leaderboard_line != "":
		_row("Leaderboard", leaderboard_line, 22, Menu.GOLD)
	if not touch:
		_row("R: run it again", "Enter / LB: change car    Esc: menu", 20)
	_results_buttons.visible = touch


## Ask for a name for the leaderboard on the results. In a browser with the touch controls
## up it's the page's own text box, so the phone's keyboard comes up for it.
func ask_name() -> void:
	asking_name = true
	leaderboard_line = ""
	asking_in_page = touch and OS.has_feature("web")
	if asking_in_page:
		_name_callback = JavaScriptBridge.create_callback(func(args: Array):
			name_entered.emit.call_deferred(str(args[0]) if args.size() > 0 else ""))
		JavaScriptBridge.get_interface("window").highwayAskName(Settings.player_name, _name_callback)
	_refresh_results()


## Where the run placed on the leaderboard (or that it's on its way).
func set_leaderboard(text: String) -> void:
	asking_name = false
	asking_in_page = false
	leaderboard_line = text
	_refresh_results()


func clear_leaderboard() -> void:
	asking_name = false
	asking_in_page = false
	leaderboard_line = ""


## The touch controls came up or went away.
func set_touch(on: bool) -> void:
	touch = on
	_hint.visible = not on
	_place_meters()
	_refresh_results()


## The speed, health and boost: bottom right, or with the pedals there, top right under
## the pause, camera and tow buttons.
func _place_meters() -> void:
	if touch:
		_put(_speed, Control.PRESET_TOP_RIGHT, Vector2(-28, 192), Control.GROW_DIRECTION_BEGIN, false)
		_put(_boost, Control.PRESET_TOP_RIGHT, Vector2(-30, 268), Control.GROW_DIRECTION_BEGIN, false)
		_put(_health, Control.PRESET_TOP_RIGHT, Vector2(-30, 288), Control.GROW_DIRECTION_BEGIN, false)
		_put(_boost_label, Control.PRESET_TOP_RIGHT, Vector2(-218, 262), Control.GROW_DIRECTION_BEGIN, false)
	else:
		_put(_speed, Control.PRESET_BOTTOM_RIGHT, Vector2(-28, -20), Control.GROW_DIRECTION_BEGIN)
		_put(_health, Control.PRESET_BOTTOM_RIGHT, Vector2(-30, -92), Control.GROW_DIRECTION_BEGIN)
		_put(_boost, Control.PRESET_BOTTOM_RIGHT, Vector2(-30, -112), Control.GROW_DIRECTION_BEGIN)
		_put(_boost_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-218, -106), Control.GROW_DIRECTION_BEGIN)
	_put(_note, Control.PRESET_BOTTOM_LEFT, Vector2(24, -216 if touch else -66), Control.GROW_DIRECTION_END)  # over the wheel


func _put(c: Control, preset: Control.LayoutPreset, offset: Vector2, grow: Control.GrowDirection, up := true) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = grow
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if up else Control.GROW_DIRECTION_END
	c.position += offset


func _refresh_results() -> void:
	if _results.visible:
		_fill_results()


func _row(left: String, right: String, size := 22, color := Color(1, 1, 1)) -> void:
	for text in [left, right]:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", size)
		label.add_theme_color_override("font_color", color)
		_results_grid.add_child(label)
	_results_grid.get_child(_results_grid.get_child_count() - 1).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _results_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	_results_grid = GridContainer.new()
	_results_grid.columns = 2
	_results_grid.add_theme_constant_override("h_separation", 60)
	column.add_child(_results_grid)
	_results_buttons = HBoxContainer.new()
	_results_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_results_buttons.add_theme_constant_override("separation", 16)
	for b: Array in [["Run it again", "restart"], ["Change car", "change_car"], ["Menu", "pause"]]:
		_results_buttons.add_child(_big_button(b[0], func(): Touch.tap(b[1])))
	_results_buttons.visible = false
	column.add_child(_results_buttons)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	return panel


## A button big enough for a thumb.
static func _big_button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(190, 62)
	b.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.85, 0.3) if state == "pressed" else Color(1, 1, 1, 0.14 if state == "normal" else 0.22)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(12)
		b.add_theme_stylebox_override(state, style)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))
	b.pressed.connect(pressed)
	return b


func _health_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.35)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position += Vector2(-30, -92)
	bar.value_changed.connect(func(v): fill.bg_color = Color(0.35, 0.85, 0.35).lerp(Color(0.95, 0.25, 0.2), 1.0 - v / 100.0))
	return bar


## The boost meter, over the health bar, with its name beside it.
func _boost_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 14)
	_boost_fill = StyleBoxFlat.new()
	_boost_fill.bg_color = Color(1.0, 0.62, 0.15)
	bar.add_theme_stylebox_override("fill", _boost_fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position += Vector2(-30, -112)
	_boost_label = _label(16, Control.PRESET_BOTTOM_RIGHT, Vector2(-218, -106))
	_boost_label.text = "BOOST"
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return bar


func _show(text: String, size: int) -> void:
	if _message.text != text:
		_message.text = text
		_message.add_theme_font_size_override("font_size", size)


func _label(size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0 else Control.GROW_DIRECTION_END
	if preset == Control.PRESET_CENTER or preset == Control.PRESET_CENTER_TOP:
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0 and preset != Control.PRESET_CENTER \
		else Control.GROW_DIRECTION_END
	label.position += offset
	return label


## 12345 -> "12,345"
static func _fmt(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
