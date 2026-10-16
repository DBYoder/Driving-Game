class_name CarStats
extends Resource
## Tuning for one car. SI units throughout: kg, m, N, m/s, W.
## The defaults are a mid-size '90s front-drive sedan (the v0.1 placeholder); preset()
## makes the three real cars from it.

const CARS := ["windstar", "tercel", "legend"]

@export var id := "placeholder"
@export var display_name := "Placeholder sedan"
@export var tagline := ""
@export var body_color := Color(0.50, 0.07, 0.09)
## [name, Color] pairs offered on the car-select screen; the first is the default.
@export var paints: Array = []
@export var score_multiplier := 1.0  ## every point scored in this car is worth this much
@export var can_total := true  ## false: running out of health doesn't end the run
@export var style := "sedan"  ## which CarModel body: "minivan", "compact" or "sedan"
@export var engine_note := 1.0  ## pitch of the engine sound
@export var engine_rasp := 0.4  ## how much buzz is in it (0 smooth .. 1 harsh)

@export_group("Body")
@export var mass := 1500.0
@export var durability := 100.0  ## health; 0 = totaled
@export var impact_threshold := 2.0  ## m/s of instant speed change before a hit does damage
@export var impact_damage := 8.0  ## health lost per m/s over the threshold
@export var body_size := Vector3(1.78, 1.38, 4.85)  ## width, height, length (visual)
@export var center_of_mass_y := -0.25  ## below the body origin; higher = tippier
@export var body_lean_deg := 2.5  ## how far the model leans out per g of cornering (looks only)

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
@export var handbrake_force := 1800.0  ## N, rear tires together

@export_group("Handbrake drifts")
@export var handbrake_grip := 0.35  ## rear sideways stiffness with the rears locked
@export var handbrake_friction := 0.8  ## rear grip limit with the rears locked
@export var drift_recovery := 2.0  ## per second; how fast rear grip comes back after letting go
@export var handbrake_yaw_rate := 75.0  ## deg/s the handbrake kick swings the car toward, at full lock
@export var handbrake_yaw_assist := 6000.0  ## N·m; the most the kick can push
@export var handbrake_kick_max_slip := 30.0  ## deg sideways at which the kick lets go
@export var spin_damping := 6.0  ## per second; resists rotation once the car is far sideways
@export var slide_friction := 0.8  ## grip of a tire sliding sideways, vs. one that's rolling
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


## One of the three real cars (see CARS), tuned from the defaults: springs, tires and the
## handbrake kick scale with weight and size, so the handling only differs where it's
## meant to.
static func preset(car_id: String) -> CarStats:
	var s := CarStats.new()
	var base := CarStats.new()
	s.id = car_id
	match car_id:
		"windstar":
			# A heavy boat: soft and top-heavy, so yank the wheel and it leans way over.
			s.display_name = "1998 Ford Windstar"
			s.tagline = "Heavy boat. Leans hard, plows through anything."
			s.paints = [["Spruce Green", Color(0.10, 0.27, 0.21)], ["Toreador Red", Color(0.45, 0.06, 0.08)],
				["Prairie Tan", Color(0.70, 0.62, 0.48)], ["Silver Frost", Color(0.66, 0.68, 0.70)]]
			s.style = "minivan"
			s.score_multiplier = 1.2
			s.mass = 1830.0
			s.durability = 160.0
			s.impact_damage = 6.0
			s.body_size = Vector3(1.95, 1.72, 5.08)
			s.center_of_mass_y = 0.25  # high: it leans about twice as far as the others
			s.body_lean_deg = 6.0
			s.wheel_radius = 0.35
			s.track = 1.63
			s.wheelbase = 3.07
			s.spring = 42000.0  # soft, ~1.5 Hz
			s.damper = 4300.0 * s.mass / base.mass
			s.anti_roll = 2000.0
			s.wheel_power = 112000.0  # 3.8 L V6, 200 hp
			s.max_drive_force = 6800.0
			s.top_speed = 49.0  # ~110 mph
			s.grip = 0.95
			s.drag = 0.55  # a big flat front
			s.brake_force = 13500.0
			s.max_steer_deg = 30.0
			s.steer_rate = 2.1
			s.handbrake_yaw_rate = 60.0
			s.engine_note = 0.85
			s.engine_rasp = 0.3
		"tercel":
			# Light and slow; nimble, and it gets air off crests. It gets beaten up easily,
			# but the engine never dies.
			s.display_name = "1997 Toyota Tercel"
			s.tagline = "93 hp of pure willpower. Panels fall off; the engine never dies."
			s.paints = [["Sunfire Red", Color(0.70, 0.08, 0.10)], ["Super White", Color(0.90, 0.90, 0.88)],
				["Teal", Color(0.08, 0.38, 0.40)], ["Silver", Color(0.64, 0.65, 0.67)]]
			s.style = "compact"
			s.score_multiplier = 1.5
			s.can_total = false
			s.mass = 930.0
			s.durability = 70.0
			s.body_size = Vector3(1.66, 1.36, 4.12)
			s.center_of_mass_y = -0.22
			s.body_lean_deg = 3.0
			s.wheel_radius = 0.29
			s.track = 1.43
			s.wheelbase = 2.38
			s.spring = base.spring * s.mass / base.mass
			s.damper = base.damper * 0.85 * s.mass / base.mass
			s.anti_roll = base.anti_roll * s.mass / base.mass
			s.wheel_power = 48000.0  # 1.5 L four, 93 hp
			s.max_drive_force = 3800.0
			s.top_speed = 46.0  # ~103 mph, downhill with a tailwind
			s.grip = 1.0
			s.drag = 0.36
			s.brake_force = 8200.0
			s.max_steer_deg = 34.0
			s.steer_rate = 3.0
			s.handbrake_yaw_rate = 85.0
			s.engine_note = 1.3
			s.engine_rasp = 0.7
		"legend":
			# Fast, grippy and smooth: the easy car, so its points count the least.
			s.display_name = "1993 Acura Legend"
			s.tagline = "Fastest and grippiest. Smooth. Points count the least."
			s.paints = [["Milano Red", Color(0.42, 0.04, 0.06)], ["Granada Black", Color(0.06, 0.06, 0.07)],
				["Cayman Green", Color(0.07, 0.22, 0.16)], ["Frost White", Color(0.88, 0.88, 0.86)]]
			s.style = "sedan"
			s.score_multiplier = 1.0
			s.mass = 1590.0
			s.durability = 110.0
			s.body_size = Vector3(1.81, 1.37, 4.95)
			s.center_of_mass_y = -0.30
			s.body_lean_deg = 1.8
			s.wheel_radius = 0.32
			s.track = 1.55
			s.wheelbase = 2.91
			s.spring = 58000.0 * s.mass / base.mass
			s.damper = 5600.0 * s.mass / base.mass
			s.anti_roll = 19000.0
			s.wheel_power = 135000.0  # 3.2 L V6, 230 hp
			s.max_drive_force = 6800.0
			s.top_speed = 62.0  # ~139 mph
			s.grip = 1.12
			s.drag = 0.36
			s.brake_force = 13500.0
			s.steer_rate = 2.8
			s.engine_note = 1.05
			s.engine_rasp = 0.2
		_:
			push_error("no car called '%s'" % car_id)
			return base
	# Grip, brakes and the handbrake kick scale with the weight and size they move.
	var weight := s.mass / base.mass
	var inertia := weight * pow(s.body_size.z / base.body_size.z, 2.0)
	s.cornering_stiffness = base.cornering_stiffness * weight
	s.handbrake_force = base.handbrake_force * weight
	s.reverse_force = base.reverse_force * weight
	s.handbrake_yaw_assist = base.handbrake_yaw_assist * inertia
	s.body_color = s.paints[0][1]
	return s


## Front-wheel steering lock (radians) at a given speed.
func steer_limit(speed: float) -> float:
	var t := clampf(absf(speed) / steer_falloff_speed, 0.0, 1.0)
	return deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, t))
