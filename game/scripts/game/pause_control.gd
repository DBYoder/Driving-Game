extends Node
## Esc / P / Start: the pause menu (or back out of it). Keeps working while paused.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		get_parent().toggle_pause()
		get_viewport().set_input_as_handled()
