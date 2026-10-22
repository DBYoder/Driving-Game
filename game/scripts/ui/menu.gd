class_name Menu
extends CanvasLayer
## A panel of choices: the title screen, the pause menu, the settings, the records.
## ▲ ▼ (W / S, stick, D-pad) picks a line, ◀ ▶ changes a setting, Enter / Space / A
## chooses, Esc / Backspace / B goes back. The mouse works too (click a setting to step it).

signal chosen(id: String)  ## a button line was chosen
signal adjusted(id: String, direction: int)  ## a setting line was changed (±1)
signal closed  ## backed out

const GOLD := Color(1.0, 0.85, 0.3)
const DIM := Color(0.85, 0.87, 0.9)

var selected := 0
var items: Array[Dictionary] = []  ## {id, text, option: bool, value: String}
var _rows: Array[Button] = []
var _panel: PanelContainer
var _column: VBoxContainer
var _title: Label
var _subtitle: Label
var _body: Control  ## optional extra content between the title and the lines (a table)
var _list: VBoxContainer
var _footer: Label


## `side`: "center", or "left" to leave the right of the screen to the car.
func setup(title: String, subtitle := "", side := "center", title_size := 40, panel_layer := 6) -> void:
	layer = panel_layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	if side == "left":
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
		_panel.grow_horizontal = Control.GROW_DIRECTION_END
		_panel.position.x += 32
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_panel.add_child(_column)
	_title = CarSelect._label(title, title_size, GOLD)
	_column.add_child(_title)
	_subtitle = CarSelect._label(subtitle, 18, DIM)
	_subtitle.visible = subtitle != ""
	_column.add_child(_subtitle)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_column.add_child(_list)
	_footer = CarSelect._label("▲ ▼ choose     Enter / A: OK     Esc / B: back", 14, Color(0.7, 0.72, 0.75))
	_column.add_child(_footer)
	visible = false


func add_button(id: String, text: String) -> void:
	items.append({"id": id, "text": text, "option": false, "value": ""})
	_add_row()


## A setting: "text: value", changed with ◀ ▶.
func add_option(id: String, text: String, value: String) -> void:
	items.append({"id": id, "text": text, "option": true, "value": value})
	_add_row()


func set_value(id: String, value: String) -> void:
	for i in items.size():
		if items[i].id == id:
			items[i].value = value
	_refresh()


func set_footer(text: String) -> void:
	_footer.text = text


func set_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle.visible = text != ""


## Extra content (a table) between the title and the lines.
func set_body(control: Control) -> void:
	if _body:
		_body.queue_free()
	_body = control
	_column.add_child(control)
	_column.move_child(control, _list.get_index())


func open(at := 0) -> void:
	selected = clampi(at, 0, items.size() - 1)
	visible = true
	_refresh()


func close() -> void:
	visible = false


func selected_id() -> String:
	return items[selected].id if not items.is_empty() else ""


## The same as pressing a direction or a button (keyboard, gamepad and tests).
func move(step: int) -> void:
	selected = posmod(selected + step, items.size())
	_refresh()


func change(direction: int) -> void:
	if items[selected].option:
		adjusted.emit(items[selected].id, direction)


func accept() -> void:
	if items[selected].option:
		adjusted.emit(items[selected].id, 1)
	else:
		chosen.emit(items[selected].id)


func back() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or items.is_empty() or event.is_echo():
		return
	if event.is_action_pressed("menu_up"):
		move(-1)
	elif event.is_action_pressed("menu_down"):
		move(1)
	elif event.is_action_pressed("menu_left"):
		change(-1)
	elif event.is_action_pressed("menu_right"):
		change(1)
	elif event.is_action_pressed("menu_accept"):
		accept()
	elif event.is_action_pressed("menu_back"):
		back()
	else:
		return
	get_viewport().set_input_as_handled()


func _add_row() -> void:
	var i := _rows.size()
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.mouse_entered.connect(func():
		if visible:
			selected = i
			_refresh())
	b.pressed.connect(func():
		selected = i
		accept())
	_list.add_child(b)
	_rows.append(b)
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var item: Dictionary = items[i]
		var here := i == selected
		var text: String = item.text
		if item.option:
			text = "%s:   %s" % [item.text, "◀  %s  ▶" % item.value if here else item.value]
		elif here:
			text = "›  %s  ‹" % text
		_rows[i].text = text
		var color := GOLD if here else Color.WHITE
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_rows[i].add_theme_color_override(state, color)
