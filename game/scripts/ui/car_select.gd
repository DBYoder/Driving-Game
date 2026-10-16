class_name CarSelect
extends CanvasLayer
## The garage: pick a car and a paint color before a run. The car sits on the road at
## the start line with the camera circling it. Left/right picks the car, up/down the
## paint, Enter / Space / A drives. Remembers the last pick.

signal browsed(car_id: String, paint: int)  ## the car or paint on show changed
signal chosen(car_id: String, paint: int)  ## drive it

const SAVE_SECTION := "garage"

var car_index := 0
var paint_index := 0
var save_path := ""
var _stats: CarStats
var _panel: PanelContainer
var _name: Label
var _tagline: Label
var _bars := {}  ## stat -> ProgressBar
var _multiplier: Label
var _paint: Label
var _records: Label


func setup(path: String) -> void:
	save_path = path
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if not path.is_empty() and cfg.load(path) == OK:
		car_index = maxi(0, CarStats.CARS.find(cfg.get_value(SAVE_SECTION, "car", CarStats.CARS[0])))
		paint_index = cfg.get_value(SAVE_SECTION, "paint", 0)
	_build()
	visible = false


func current_car() -> String:
	return CarStats.CARS[car_index]


func open() -> void:
	visible = true
	_show()


## Fill in the records line (the run tracker knows them; it's told about the car first).
func set_records(best_score: int, best_time: float) -> void:
	if best_score <= 0 and best_time <= 0.0:
		_records.text = "No best yet"
		return
	_records.text = "Best: %s points%s" % [Hud._fmt(best_score),
		"   ·   %s to Iowa City" % RunTracker.format_time(best_time) if best_time > 0.0 else ""]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_left"):
		car_index = posmod(car_index - 1, CarStats.CARS.size())
		paint_index = 0
		_show()
	elif event.is_action_pressed("menu_right"):
		car_index = posmod(car_index + 1, CarStats.CARS.size())
		paint_index = 0
		_show()
	elif event.is_action_pressed("menu_up"):
		paint_index = posmod(paint_index - 1, _stats.paints.size())
		_show()
	elif event.is_action_pressed("menu_down"):
		paint_index = posmod(paint_index + 1, _stats.paints.size())
		_show()
	elif event.is_action_pressed("menu_accept"):
		visible = false
		_save()
		chosen.emit(current_car(), paint_index)
	else:
		return
	get_viewport().set_input_as_handled()


func _show() -> void:
	_stats = CarStats.preset(current_car())
	paint_index = clampi(paint_index, 0, _stats.paints.size() - 1)
	_name.text = "◀  %s  ▶" % _stats.display_name
	_tagline.text = _stats.tagline
	# Bars against the best of the three.
	_bars.Speed.value = _stats.top_speed / 62.0
	_bars.Acceleration.value = (_stats.wheel_power / _stats.mass) / (135000.0 / 1590.0)
	_bars.Grip.value = _stats.grip / 1.12
	_bars.Toughness.value = _stats.durability / 160.0
	_multiplier.text = "Points ×%s%s" % [str(_stats.score_multiplier),
		"   ·   can't be totaled" if not _stats.can_total else ""]
	_paint.text = "▲  %s  ▼" % _stats.paints[paint_index][0]
	browsed.emit(current_car(), paint_index)


func _save() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value(SAVE_SECTION, "car", current_car())
	cfg.set_value(SAVE_SECTION, "paint", paint_index)
	cfg.save(save_path)


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position.x += 32
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var title := _label("PICK YOUR CAR", 18, Color(1.0, 0.85, 0.3))
	column.add_child(title)
	_name = _label("", 30)
	column.add_child(_name)
	_tagline = _label("", 18, Color(0.85, 0.87, 0.9))
	column.add_child(_tagline)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	for stat in ["Speed", "Acceleration", "Grip", "Toughness"]:
		var l := _label(stat, 16, Color(0.85, 0.87, 0.9))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(260, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(1.0, 0.85, 0.3)
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		bar.add_theme_stylebox_override("background", bg)
		grid.add_child(bar)
		_bars[stat] = bar
	var center := CenterContainer.new()
	center.add_child(grid)
	column.add_child(center)
	_multiplier = _label("", 20, Color(1.0, 0.85, 0.3))
	column.add_child(_multiplier)
	_paint = _label("", 20)
	column.add_child(_paint)
	_records = _label("", 16, Color(0.85, 0.87, 0.9))
	column.add_child(_records)
	column.add_child(_label("◀ ▶ car     ▲ ▼ paint     Enter / Space / A: drive     Esc: quit", 15,
		Color(0.7, 0.72, 0.75)))


static func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
