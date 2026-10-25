class_name PlayerDriver
extends RefCounted
## Reads the keyboard / gamepad into car inputs. Not while a text box has the keys (the
## leaderboard name on the results): typing "Dave" shouldn't steer the car about.


func update(car: Car, _delta: float) -> void:
	if typing(car):
		car.throttle = 0.0
		car.brake = 0.0
		car.steer = 0.0
		car.handbrake = false
		car.boost_held = false
		car.horn = false
		return
	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.steer = Input.get_axis("steer_left", "steer_right")
	car.handbrake = Input.is_action_pressed("handbrake")
	car.boost_held = Input.is_action_pressed("boost")
	car.horn = Input.is_action_pressed("horn")


## Is a text box taking the keyboard?
static func typing(node: Node) -> bool:
	return node.is_inside_tree() and node.get_viewport().gui_get_focus_owner() is LineEdit
