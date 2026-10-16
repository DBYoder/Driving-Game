class_name TrafficModels
extends RefCounted
## Low-poly traffic. Every model faces -Z, sits on y = 0 and is centered on its footprint.

const TIRE := Color(0.06, 0.06, 0.06)
const GLASS := Color(0.12, 0.15, 0.18)
const PAINT := [
	Color(0.55, 0.08, 0.10), Color(0.12, 0.22, 0.45), Color(0.85, 0.85, 0.82), Color(0.15, 0.35, 0.22),
	Color(0.62, 0.55, 0.42), Color(0.35, 0.35, 0.37), Color(0.08, 0.08, 0.09), Color(0.58, 0.47, 0.18),
]


static func build(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := MeshKit.begin()
	match kind:
		"car":
			_sedan(st, PAINT[rng.randi() % PAINT.size()])
		"pickup":
			_pickup(st, PAINT[rng.randi() % PAINT.size()])
		"semi":
			_semi(st, PAINT[rng.randi() % PAINT.size()])
		"buggy":
			_buggy(st)
		"tractor":
			_tractor(st)
	return MeshKit.finish(st)


static func _wheels(st: SurfaceTool, half_track: float, zs: Array, radius: float, width := 0.22) -> void:
	for z in zs:
		for x in [-half_track, half_track]:
			MeshKit.cylinder(st, radius, width, Vector3(x, radius, z), TIRE, Color(0.5, 0.5, 0.5), 8)


static func _sedan(st: SurfaceTool, paint: Color) -> void:
	MeshKit.box(st, Vector3(1.78, 0.62, 4.7), Vector3(0, 0.62, 0), paint)
	MeshKit.box(st, Vector3(1.5, 0.48, 2.2), Vector3(0, 1.17, 0.2), GLASS)
	MeshKit.box(st, Vector3(1.52, 0.06, 1.9), Vector3(0, 1.43, 0.25), paint)
	_wheels(st, 0.78, [-1.4, 1.4], 0.33)


static func _pickup(st: SurfaceTool, paint: Color) -> void:
	MeshKit.box(st, Vector3(1.95, 0.7, 5.5), Vector3(0, 0.75, 0), paint)
	MeshKit.box(st, Vector3(1.8, 0.65, 1.6), Vector3(0, 1.42, -0.9), GLASS)
	MeshKit.box(st, Vector3(1.82, 0.06, 1.5), Vector3(0, 1.77, -0.9), paint)
	MeshKit.box(st, Vector3(1.85, 0.35, 2.3), Vector3(0, 1.27, 1.45), paint.darkened(0.25))  # bed sides
	_wheels(st, 0.85, [-1.75, 1.6], 0.38, 0.26)


static func _semi(st: SurfaceTool, paint: Color) -> void:
	# Cab at the front (-Z), long trailer behind.
	MeshKit.box(st, Vector3(2.5, 1.6, 2.4), Vector3(0, 1.6, -9.0), paint)
	MeshKit.box(st, Vector3(2.4, 1.1, 1.8), Vector3(0, 2.9, -8.6), GLASS)
	MeshKit.box(st, Vector3(2.5, 0.8, 1.2), Vector3(0, 1.1, -10.6), paint.darkened(0.2))  # hood
	MeshKit.box(st, Vector3(2.6, 2.9, 15.5), Vector3(0, 2.65, 2.4), Color(0.88, 0.88, 0.86))
	_wheels(st, 1.0, [-10.0, -7.5, 7.0, 8.4], 0.5, 0.35)


static func _buggy(st: SurfaceTool) -> void:
	# Horse in front (-Z), black box buggy behind, orange slow-moving-vehicle triangle on the back.
	var horse := Color(0.33, 0.20, 0.11)
	MeshKit.box(st, Vector3(0.55, 0.65, 1.5), Vector3(0, 1.3, -1.85), horse)  # body
	MeshKit.box(st, Vector3(0.3, 0.7, 0.35), Vector3(0, 1.75, -2.6), horse)  # neck
	MeshKit.box(st, Vector3(0.25, 0.3, 0.6), Vector3(0, 2.05, -2.85), horse)  # head
	for x in [-0.18, 0.18]:
		for z in [-2.4, -1.3]:
			MeshKit.box(st, Vector3(0.12, 1.0, 0.12), Vector3(x, 0.5, z), horse)  # legs
	for x in [-0.55, 0.55]:
		MeshKit.box(st, Vector3(0.05, 0.05, 1.8), Vector3(x, 1.15, -1.3), Color(0.15, 0.12, 0.1))  # shafts
	var black := Color(0.07, 0.07, 0.08)
	MeshKit.box(st, Vector3(1.35, 1.4, 1.9), Vector3(0, 1.55, 0.9), black)
	MeshKit.box(st, Vector3(1.0, 0.4, 0.02), Vector3(0, 1.75, -0.06), Color(0.2, 0.22, 0.25))  # windshield
	_wheels(st, 0.72, [0.2, 1.6], 0.6, 0.06)
	# SMV emblem: an orange triangle with a red border, facing backward (+Z).
	var back := Vector3(0, 1.45, 1.86)
	MeshKit.tri(st, back + Vector3(-0.4, -0.3, 0), back + Vector3(0.4, -0.3, 0), back + Vector3(0, 0.38, 0),
		Vector3.BACK, Color(0.85, 0.08, 0.05))
	back.z += 0.01
	MeshKit.tri(st, back + Vector3(-0.28, -0.22, 0), back + Vector3(0.28, -0.22, 0), back + Vector3(0, 0.26, 0),
		Vector3.BACK, Color(1.0, 0.45, 0.05))


static func _tractor(st: SurfaceTool) -> void:
	# Tractor in front (-Z) pulling a wagon of small square bales.
	var green := Color(0.13, 0.42, 0.14)
	MeshKit.box(st, Vector3(1.0, 1.0, 2.0), Vector3(0, 1.3, -3.6), green)  # hood
	MeshKit.box(st, Vector3(1.6, 1.4, 1.5), Vector3(0, 2.3, -2.2), GLASS)  # cab
	MeshKit.box(st, Vector3(1.65, 0.1, 1.55), Vector3(0, 3.05, -2.2), green)
	MeshKit.cylinder(st, 0.85, 0.5, Vector3(-0.95, 0.85, -2.1), TIRE, Color(0.85, 0.75, 0.1), 10)
	MeshKit.cylinder(st, 0.85, 0.5, Vector3(0.95, 0.85, -2.1), TIRE, Color(0.85, 0.75, 0.1), 10)
	MeshKit.cylinder(st, 0.45, 0.3, Vector3(-0.75, 0.45, -4.2), TIRE, Color(0.85, 0.75, 0.1), 8)
	MeshKit.cylinder(st, 0.45, 0.3, Vector3(0.75, 0.45, -4.2), TIRE, Color(0.85, 0.75, 0.1), 8)
	MeshKit.box(st, Vector3(0.1, 0.1, 1.2), Vector3(0, 0.6, -0.8), Color(0.2, 0.2, 0.2))  # hitch
	MeshKit.box(st, Vector3(2.3, 0.2, 4.8), Vector3(0, 0.9, 2.2), Color(0.45, 0.33, 0.2))  # wagon bed
	var straw := Color(0.82, 0.72, 0.42)
	for row in 3:
		for z in [0.6, 1.7, 2.8, 3.9]:
			for x in [-0.6, 0.6]:
				MeshKit.box(st, Vector3(1.1, 0.4, 1.0), Vector3(x, 1.2 + row * 0.42, z), straw.darkened(0.06 * ((row + int(z)) % 3)))
	_wheels(st, 0.95, [0.6, 3.8], 0.4, 0.25)
