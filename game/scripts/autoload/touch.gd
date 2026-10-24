extends Node
## Whether the touch controls are up (autoload `Touch`): the on-screen pedals and wheel
## while driving, buttons on the results, hints for tapping in the menus.
##
## Settings' "Touch controls": Auto (the default) brings them up from the start on a phone
## or tablet and as soon as the screen's touched anywhere else, and puts them away again
## when a key or a gamepad is used. On and Off are just that.

signal changed(active: bool)

const MODES := ["auto", "on", "off"]

var active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(refresh)
	refresh()


## Settings changed (or were loaded).
func refresh() -> void:
	match Settings.touch_controls:
		"on":
			_switch(true)
		"off":
			_switch(false)
		_:
			_switch(active or Settings.handheld())


func _input(event: InputEvent) -> void:
	if Settings.touch_controls != "auto":
		return
	if event is InputEventScreenTouch and event.pressed:
		_switch(true)
	elif (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_switch(false)


func _switch(on: bool) -> void:
	if on == active:
		return
	active = on
	changed.emit(on)


## A tap on an on-screen button does what the key would: `action` pressed and let go.
static func tap(action: String) -> void:
	press(action)
	release(action)


static func press(action: String, strength := 1.0) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = strength
	Input.parse_input_event(event)


static func release(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
