extends Node
## Pause and quit keep working while the game is paused.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
	elif event.is_action_pressed("quit"):
		get_tree().quit()
