extends Node
## Registers every input action in code, so keyboard and gamepad bindings live in one readable place.

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.1

## action -> list of bindings. Ints are keys; dictionaries describe gamepad inputs.
var bindings := {
	"accelerate": [KEY_W, KEY_UP, {"axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}],
	"brake": [KEY_S, KEY_DOWN, {"axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}],
	"steer_left": [KEY_A, KEY_LEFT, {"axis": JOY_AXIS_LEFT_X, "value": -1.0}],
	"steer_right": [KEY_D, KEY_RIGHT, {"axis": JOY_AXIS_LEFT_X, "value": 1.0}],
	"handbrake": [KEY_SPACE, {"button": JOY_BUTTON_A}],
	"boost": [KEY_SHIFT, {"button": JOY_BUTTON_B}],
	"horn": [KEY_H, {"button": JOY_BUTTON_RIGHT_SHOULDER}],
	"camera_next": [KEY_C, {"button": JOY_BUTTON_Y}],
	"recover": [KEY_T, {"button": JOY_BUTTON_X}],
	"pause": [KEY_P, KEY_ESCAPE, {"button": JOY_BUTTON_START}],  ## the pause menu
	"restart": [KEY_R, {"button": JOY_BUTTON_BACK}],
	"mute": [KEY_M],
	"radio_next": [KEY_N, {"button": JOY_BUTTON_DPAD_RIGHT}],
	"radio_power": [KEY_B, {"button": JOY_BUTTON_DPAD_LEFT}],
	"scenery_detail": [KEY_F2],
	# The car-select screen.
	"menu_left": [KEY_A, KEY_LEFT, {"button": JOY_BUTTON_DPAD_LEFT}, {"axis": JOY_AXIS_LEFT_X, "value": -1.0}],
	"menu_right": [KEY_D, KEY_RIGHT, {"button": JOY_BUTTON_DPAD_RIGHT}, {"axis": JOY_AXIS_LEFT_X, "value": 1.0}],
	"menu_up": [KEY_W, KEY_UP, {"button": JOY_BUTTON_DPAD_UP}, {"axis": JOY_AXIS_LEFT_Y, "value": -1.0}],
	"menu_down": [KEY_S, KEY_DOWN, {"button": JOY_BUTTON_DPAD_DOWN}, {"axis": JOY_AXIS_LEFT_Y, "value": 1.0}],
	"menu_accept": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, {"button": JOY_BUTTON_A}],
	"menu_back": [KEY_ESCAPE, KEY_BACKSPACE, {"button": JOY_BUTTON_B}],
	"change_car": [KEY_ENTER, KEY_KP_ENTER, {"button": JOY_BUTTON_LEFT_SHOULDER}],
}


func _ready() -> void:
	for action in bindings:
		var deadzone := TRIGGER_DEADZONE if action in ["accelerate", "brake"] else STICK_DEADZONE
		if action.begins_with("menu_"):
			deadzone = 0.6  # a deliberate push of the stick, one step at a time
		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
		for binding in bindings[action]:
			InputMap.action_add_event(action, _event_for(binding))


func _event_for(binding) -> InputEvent:
	if binding is int:
		var key := InputEventKey.new()
		key.physical_keycode = binding
		return key
	if binding.has("axis"):
		var motion := InputEventJoypadMotion.new()
		motion.axis = binding.axis
		motion.axis_value = binding.value
		return motion
	var button := InputEventJoypadButton.new()
	button.button_index = binding.button
	return button
