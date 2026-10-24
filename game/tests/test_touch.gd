extends "res://tests/test_case.gd"
## Touch controls: when they're up (Touch), the wheel and pedals while driving (TouchPad),
## tapping through the garage and the menus, and a phone's own graphics defaults.

const ACTIONS := ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "boost", "horn", "pause",
	"camera_next", "recover", "menu_left", "menu_right", "menu_up", "menu_down", "menu_accept", "menu_back"]


func _init() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):  # (the Controls autoload adds them in the game)
			InputMap.add_action(action)


func test_auto_follows_the_last_thing_used() -> void:
	var was := Settings.touch_controls
	Settings.touch_controls = "auto"
	Touch._switch(false)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	Touch._input(tap)
	check(Touch.active, "a touch brings them up")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_W
	Touch._input(key)
	check(not Touch.active, "a key puts them away")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	Touch._input(tap)
	Touch._input(pad)
	check(not Touch.active, "so does a gamepad")
	Settings.touch_controls = "on"
	Touch.refresh()
	Touch._input(key)
	check(Touch.active, "On stays on whatever's pressed")
	Settings.touch_controls = "off"
	Touch.refresh()
	Touch._input(tap)
	check(not Touch.active, "Off stays off")
	Settings.touch_controls = was
	Touch._switch(false)


func test_the_setting() -> void:
	var was := Settings.touch_controls
	Settings.touch_controls = "auto"
	var seen := []
	for i in 3:
		seen.append(Settings.describe("touch_controls"))
		Settings.step("touch_controls", 1)
	check(seen == ["Auto (when the screen's touched)", "On", "Off"], "Auto, On, Off: %s" % [seen])
	check(Settings.touch_controls == "auto", "and round again")
	check(Menus.SETTINGS.any(func(s): return s[0] == "touch_controls"), "on the settings screen")
	Settings.touch_controls = was
	Touch._switch(false)


func test_a_phone_draws_the_3d_at_about_600_lines() -> void:
	check(Settings.handheld_render_scale(945) == 0.6, "a Pixel 7 sideways (945 px): 60%")
	check(Settings.handheld_render_scale(1170) == 0.5, "an iPhone sideways (1170 px): 50%")
	check(Settings.handheld_render_scale(720) == 0.8, "720 px: 80%")
	check(Settings.handheld_render_scale(400) == 1.0, "never more than 100%")


func test_the_pedals_and_the_wheel() -> void:
	var pad := TouchPad.new()
	pad._layout()
	pad.driving = true
	check(pad.visible, "up while driving")
	pad.touch_down(0, pad.pads.gas.center)
	Input.flush_buffered_events()
	check(Input.get_action_strength("accelerate") == 1.0, "a thumb on GAS is the gas")
	pad.touch_move(0, pad.pads.brake.center)
	Input.flush_buffered_events()
	check(Input.is_action_pressed("brake") and not Input.is_action_pressed("accelerate"), "slid over to BRAKE: the brake")
	var at := Vector2(200, 600)
	check(pad.in_steering_zone(at) and pad.pad_at(at) == "", "the bottom left is the wheel")
	pad.touch_down(1, at)
	pad.touch_move(1, at + Vector2(TouchPad.STEER_RANGE * 0.5, 0))
	Input.flush_buffered_events()
	check_near(Input.get_axis("steer_left", "steer_right"), 0.5, 0.01, "half the slide right is half lock right")
	pad.touch_move(1, at - Vector2(TouchPad.STEER_RANGE * 3.0, 0))
	Input.flush_buffered_events()
	check_near(Input.get_axis("steer_left", "steer_right"), -1.0, 0.01, "past the end is full lock left")
	pad.touch_up(1)
	Input.flush_buffered_events()
	check(Input.get_axis("steer_left", "steer_right") == 0.0, "let go: straight")
	check(pad.pad_at(pad.pads.pause.center) == "pause" and not pad.in_steering_zone(pad.pads.gas.center),
		"the buttons aren't the wheel")
	pad.driving = false
	Input.flush_buffered_events()
	check(not pad.visible and not Input.is_action_pressed("brake"), "a run that's over lets go of everything")
	pad.free()


func test_two_thumbs_on_one_button() -> void:
	var pad := TouchPad.new()
	pad._layout()
	pad.driving = true
	pad.touch_down(0, pad.pads.boost.center)
	pad.touch_down(1, pad.pads.boost.center + Vector2(10, 0))
	pad.touch_up(0)
	Input.flush_buffered_events()
	check(Input.is_action_pressed("boost"), "still boosting with one thumb left on it")
	pad.touch_up(1)
	Input.flush_buffered_events()
	check(not Input.is_action_pressed("boost"), "both off: no boost")
	pad.free()


func test_the_garage_takes_taps() -> void:
	var garage := CarSelect.new()
	garage.setup("")
	garage.open()
	garage._name.size = Vector2(400, 40)
	var start := garage.car_index
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(350, 20)
	garage._tapped(CarSelect.Row.CAR, tap, garage._name)
	check(garage.car_index == (start + 1) % CarStats.CARS.size(), "the right of the car line: the next car")
	tap.position = Vector2(50, 20)
	garage._tapped(CarSelect.Row.CAR, tap, garage._name)
	check(garage.car_index == start, "the left: back")
	var chosen := []
	garage.chosen.connect(func(car_id, _paint, _condition): chosen.append(car_id))
	garage.drive()
	check(chosen == [CarStats.CARS[start]] and not garage.visible, "Drive drives it")
	Touch._switch(true)
	garage.open()
	check(garage._buttons.visible and not garage._footer.visible, "with touch: Back and Drive instead of the keys")
	check(garage._paint.text.begins_with("◀"), "and every line shows its arrows")
	Touch._switch(false)
	garage.free()


func test_menus_say_tap_with_touch() -> void:
	var menu := Menu.new()
	menu.setup("TEST")
	menu.add_option("a", "A", "1")
	menu.add_button("back", "Back")
	menu.set_footer("keys")
	check(menu._footer.text == "keys", "the keys without touch")
	Touch._switch(true)
	menu.open()
	check(menu._footer.text.begins_with("Tap"), "how to tap with it: %s" % menu._footer.text)
	Touch._switch(false)
	check(menu._footer.text == "keys", "and back to the keys")
	menu.free()
