class_name Hud
extends CanvasLayer
## Top-left trip readout and bottom-left control hints.

var route: RouteData
var camera: FlythroughCamera
var _trip: Label
var _hint: Label


func setup(r: RouteData, cam: FlythroughCamera) -> void:
	route = r
	camera = cam
	_trip = _label(22)
	_trip.position = Vector2(24, 18)
	_hint = _label(16)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 24
	_hint.offset_top = -92
	_hint.offset_bottom = -16
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.text = "PHASE 0 FLYTHROUGH: the car arrives in v0.1\n" \
		+ "W/S or triggers: faster/slower    C or Y: camera    P or Start: pause\n" \
		+ "R or Back: restart    Esc: quit"


func _process(_delta: float) -> void:
	if route == null:
		return
	var s := camera.station
	var mile := clampf(route.mile_at(s), 0.0, route.mile_at(route.finish_station))
	var lines := [
		"HIGHWAY 1  ·  Kalona → Iowa City",
		"Mile %.1f of %.1f    %d mph    %s view" % [
			mile, route.mile_at(route.finish_station), roundi(camera.mph()), camera.mode_name()],
	]
	var next := route.next_crossroad(s)
	if s > route.finish_station:
		lines.append("You made it to Iowa City.")
	elif not next.is_empty():
		var label: String = next.name if next.route == "" else "%s (%s)" % [next.name, next.route]
		lines.append("Next: %s in %.1f mi" % [label, (next.station - s) / RouteData.MILE_M])
	_trip.text = "\n".join(lines)


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label
