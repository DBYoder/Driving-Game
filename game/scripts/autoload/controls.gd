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
	"camera_next": [KEY_C, {"button": JOY_BUTTON_Y}],
	"recover": [KEY_T, {"button": JOY_BUTTON_X}],
	"pause": [KEY_P, {"button": JOY_BUTTON_START}],
	"restart": [KEY_R, {"button": JOY_BUTTON_BACK}],
	"mute": [KEY_M],
	"quit": [KEY_ESCAPE],
}


func _ready() -> void:
	for action in bindings:
		var deadzone := TRIGGER_DEADZONE if action in ["accelerate", "brake"] else STICK_DEADZONE
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
