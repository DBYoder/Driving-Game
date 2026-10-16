class_name Hud
extends CanvasLayer
## Trip readout (top left), clock (top right), speedometer (bottom right),
## big messages (center) and control hints (bottom left).

const MPH := 2.23694

var route: RouteData
var car: Car
var tracker: RunTracker
var camera: ChaseCamera
var _trip: Label
var _clock: Label
var _speed: Label
var _message: Label
var _hint: Label
var _go_flash := 0.0


func setup(r: RouteData, c: Car, t: RunTracker, cam: ChaseCamera) -> void:
	route = r
	car = c
	tracker = t
	camera = cam
	process_mode = Node.PROCESS_MODE_ALWAYS

	_trip = _label(20, Control.PRESET_TOP_LEFT, Vector2(24, 18))
	_clock = _label(34, Control.PRESET_TOP_RIGHT, Vector2(-24, 14))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed = _label(52, Control.PRESET_BOTTOM_RIGHT, Vector2(-28, -20))
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_message = _label(40, Control.PRESET_CENTER, Vector2(0, -235))  # above the start banner
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _label(15, Control.PRESET_BOTTOM_LEFT, Vector2(24, -16))
	_hint.text = "W/S or triggers: gas/brake (hold S to reverse)    A/D or stick: steer    Space or A: handbrake\n" \
		+ "C or Y: camera    T or X: back on the road    R or Back: restart    P or Start: pause    Esc: quit"


func _process(delta: float) -> void:
	if car == null:
		return
	var s := car.station
	var finish_mile := route.mile_at(route.finish_station)
	var lines := ["HIGHWAY 1  ·  Kalona → Iowa City",
		"Mile %.1f of %.1f    %s view" % [clampf(route.mile_at(s), 0.0, finish_mile), finish_mile, camera.mode_name()]]
	var next := route.next_crossroad(s)
	if not next.is_empty() and s < route.finish_station:
		var label: String = next.name if next.route == "" else "%s (%s)" % [next.name, next.route]
		lines.append("Next: %s in %.1f mi" % [label, (next.station - s) / RouteData.MILE_M])
	_trip.text = "\n".join(lines)

	var best := "Best  %s" % RunTracker.format_time(tracker.best_time) if tracker.best_time > 0.0 else "No best time yet"
	_clock.text = "%s\n%s" % [RunTracker.format_time(tracker.elapsed), best]
	_speed.text = "%d mph" % roundi(absf(car.forward_speed()) * MPH)

	_go_flash = maxf(_go_flash - delta, 0.0)
	if get_tree().paused:
		_show("PAUSED", 48)
	elif tracker.state == RunTracker.State.READY:
		_show("Cross the line in Kalona to start the clock", 26)
		_go_flash = 1.2
	elif tracker.state == RunTracker.State.FINISHED:
		_show("IOWA CITY!  %s%s\nR to run it again" % [
			RunTracker.format_time(tracker.elapsed), "\nNEW BEST" if tracker.new_best else ""], 40)
	elif _go_flash > 0.0:
		_show("GO!", 56)
	else:
		_show("", 40)


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
	if preset == Control.PRESET_CENTER:
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN if offset.y < 0 and preset != Control.PRESET_CENTER \
		else Control.GROW_DIRECTION_END
	label.position += offset
	return label
