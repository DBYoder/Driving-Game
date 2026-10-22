class_name PlayerDriver
extends RefCounted
## Reads the keyboard / gamepad into car inputs.


func update(car: Car, _delta: float) -> void:
	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.steer = Input.get_axis("steer_left", "steer_right")
	car.handbrake = Input.is_action_pressed("handbrake")
	car.boost_held = Input.is_action_pressed("boost")
