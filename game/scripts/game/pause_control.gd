extends Node
## Pause, quit and going back to the garage keep working while the game is paused.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not get_parent().garage.visible:
		get_tree().paused = not get_tree().paused
	elif event.is_action_pressed("change_car") and get_tree().paused:
		get_parent().open_garage()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quit"):
		get_tree().quit()
