class_name CarStats
extends Resource
## Tuning for one car. SI units throughout: kg, m, N, m/s, W.
## The defaults are the v0.1 placeholder: a mid-size '90s front-drive sedan.

@export var display_name := "Placeholder sedan"
@export var body_color := Color(0.50, 0.07, 0.09)

@export_group("Body")
@export var mass := 1500.0
@export var body_size := Vector3(1.78, 1.38, 4.85)  ## width, height, length (visual)
@export var center_of_mass_y := -0.25  ## below the body origin; higher = tippier

@export_group("Suspension")
@export var wheel_radius := 0.33
@export var track := 1.54  ## left-right distance between wheels
@export var wheelbase := 2.76
@export var mount_y := -0.08  ## top of the suspension, relative to the body origin
@export var rest_length := 0.34
@export var spring := 52000.0  ## N/m per wheel (~1.9 Hz)
@export var damper := 5000.0  ## N·s/m per wheel
@export var anti_roll := 16000.0  ## N/m per axle

@export_group("Engine")
@export var wheel_power := 115000.0  ## W at the wheels (~200 hp at the crank)
@export var max_drive_force := 6200.0  ## N; what the front tires can put down from a stop
@export var top_speed := 55.0  ## m/s, ~123 mph
@export var reverse_force := 3500.0
@export var reverse_speed := 9.0

@export_group("Tires and brakes")
@export var grip := 1.05  ## friction coefficient on dry asphalt
@export var cornering_stiffness := 8500.0  ## N per m/s of sideways slide, per tire
@export var brake_force := 12000.0  ## N, all four tires together
@export var handbrake_force := 3500.0  ## N, rear tires together
@export var handbrake_grip := 0.35  ## rear sideways grip while the handbrake is on
@export var rolling_resistance := 0.015
@export var drag := 0.38  ## N per (m/s)^2

@export_group("Steering")
@export var max_steer_deg := 32.0  ## at parking-lot speeds
@export var high_speed_steer_deg := 5.0  ## at steer_falloff_speed and above
@export var steer_falloff_speed := 40.0
@export var steer_rate := 2.6  ## rad/s the front wheels can turn


## Forward force from the engine at a given speed, before traction limits.
## Constant force off the line, then power-limited, fading out at top speed.
func drive_force(speed: float) -> float:
	if speed >= top_speed:
		return 0.0
	var force := minf(max_drive_force, wheel_power / maxf(speed, 1.0))
	return force * clampf((top_speed - speed) / 4.0, 0.0, 1.0)


## Front-wheel steering lock (radians) at a given speed.
func steer_limit(speed: float) -> float:
	var t := clampf(absf(speed) / steer_falloff_speed, 0.0, 1.0)
	return deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, t))
