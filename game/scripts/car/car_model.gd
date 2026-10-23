class_name CarModel
extends Node3D
## Low-poly model of one of the cars, after photos of the real ones: the 1998 Ford
## Windstar, the 1993 Acura Legend sedan and the 1997 Toyota Tercel coupe (and the
## deputies' Crown Victoria). Wheels that steer and spin, and a blob shadow (no real-time
## shadows on a potato). The body leans out of corners and dips under braking more than
## the physics does, to sell the weight.
##
## Each body is two pieces, the lower body and the greenhouse, each a side outline
## (SHAPES) carried across the car: the sides follow the car's cross-section (tucked in at
## the sills, full at the shoulders, leaning in above the beltline) and round off at the
## nose and tail, and the hood and roof crown up in the middle. The side glass sits flush
## in the greenhouse between its pillars, and the lights, grille, plates and trim strips
## are drawn into the surface, so nothing stands proud of the bodywork but the mirrors,
## the Windstar's roof rails and the Tercel's bumpers.
##
## The wheels sit in arches cut through the body, with dark wheel wells behind them.
## Each arch is sized from the car's tires, suspension and lean so a tire never passes
## through the bodywork: steered to full lock, pushed up as far as it's drawn going
## (VISUAL_BUMP over its resting height), with the body leaned out as far as it's drawn
## leaning, and dented in from anywhere (dents don't reach into the arches).
## ModelCheck sweeps all of that in the tests and watches it live in the QA runs.
##
## Damage shows three ways: the paint dulls and smoke pours out when it's bad, the body
## dents in where it was hit, and each car loses its own parts, nearest the hit first:
## the Windstar's hubcaps and sliding door fly off, the Tercel sheds its mirrors and
## bumpers, and the Legend's hood and trunk lid pop open and flap (the hood goes in the
## end).

signal part_lost(body: RigidBody3D)  ## a piece came off; it's a physics body now

const TIRE := Color(0.06, 0.06, 0.06)
const HUB := Color(0.70, 0.71, 0.73)
const BAY := Color(0.09, 0.09, 0.09)  ## under the hood and trunk lid, the doorway
const MAX_DENT := 0.3  ## meters any point of the body can be pushed in
const DENT_RADIUS := 1.3  ## meters around the hit that give
const EDGE_STEP := 0.6  ## outline edges are split at least this fine, so dents have something to bend
const CELL := Vector2(0.8, 0.35)  ## the sides are cut at least this fine (z, y), for the same reason
const S_BASE := [0.0, 0.45, 0.8, 0.94, 1.0]  ## across the car (mirrored): where the top bends round
const TIRE_WIDTH := 0.22
const WHEEL_REACH := 0.125  ## the tire's half width plus a Windstar hubcap
const VISUAL_BUMP := 0.04  ## the wheels are drawn at most this far above where they rest...
const ARCH_SIDE := 0.05  ## ...and the arches clear them by this much fore and aft
const ARCH_TOP := 0.03  ## and this much above, with everything else at its worst
const PITCH_MAX_DEG := 1.0  ## the body dips under braking (squats under power) at most this far
const PATCH_OFFSET := 0.012  ## a door or a lid sits this far out from the body under it

## What each kind of surface is: [surface, vertex color]. Paint takes the car's color (the
## vertex color multiplies it); the rest are their own colors.
const KINDS := {
	"paint": ["body", Color(1, 1, 1)],
	"under": ["trim", Color(0.06, 0.06, 0.06)],
	"bay": ["trim", Color(0.09, 0.09, 0.09)],
	"well": ["trim", Color(0.08, 0.08, 0.08)],
	"trim": ["trim", Color(0.05, 0.05, 0.055)],  ## black plastic and rubber
	"plastic": ["trim", Color(0.19, 0.19, 0.20)],  ## unpainted gray bumpers
	"chrome": ["trim", Color(0.80, 0.81, 0.83)],
	"grille": ["trim", Color(0.025, 0.025, 0.03)],
	"plate": ["trim", Color(0.90, 0.90, 0.86)],
	"glass": ["glass", Color(0.25, 0.30, 0.35)],
	"screen": ["glass", Color(0.29, 0.34, 0.39)],  ## the windshield and back glass: more sky in them
	"tint": ["glass", Color(0.10, 0.12, 0.15)],  ## privacy glass
	"headlight": ["lights", Color(0.84, 0.86, 0.86)],
	"amber": ["lights", Color(1.0, 0.52, 0.08)],
	"taillight": ["lights", Color(0.62, 0.04, 0.05)],
	"reverse": ["lights", Color(0.90, 0.90, 0.90)],
}

## Each body, measured off photos and the real cars' dimensions. Positions along the car
## are meters back from the front bumper; heights are meters above the ground with the
## car at rest.
##   body, cabin       side outlines going round (front bottom, up the front, along the
##                     top, down the back, along the bottom): [along, up, the kind of the
##                     edge to the next point]. The cabin is the greenhouse; its first
##                     three points are the bottom and top of the windshield and the back
##                     of the roof (the Cockpit fits itself to them).
##   *_section         the cross-section: [height, share of the half width there]
##   nose, tail        the corners round off over this length, pulled in by this share
##   crown             the hood and roof (body, cabin) rise this much more in the middle
##   glass             the side windows: this far in from the greenhouse's outline, a
##                     frame round them (kind, width), the pillars between them [from,
##                     to, kind], privacy glass from here back, and how much of the
##                     windshield and back glass's width is pillar at each side, and what
##   side              drawn on the sides: [from, to, bottom, top, kind, which side
##                     (1 the right, -1 the left, 0 both)]; the first listed wins
##   marks             small things just proud of the sides (door handles), the same way
##   front, back       drawn on the nose and tail: [from, to (shares of the half width
##                     out from the middle), bottom, top, kind]
##   mirror            [along, up, kind]; door: the Windstar's sliding door [from, to,
##                     bottom, top, side]; rails: its roof rails [from, to]
##   wheel             what's on the wheels
const SHAPES := {
	"minivan": {  # 1998 Ford Windstar: a short sloping nose, the long windshield, a tall flat-sided box
		"body": [[0.06, 0.30, "paint"], [0.0, 0.47, "paint"], [0.02, 0.60, "paint"], [0.06, 0.66, "paint"],
			[0.17, 0.84, "paint"], [0.32, 0.92, "paint"], [1.35, 1.05, "paint"], [5.04, 1.18, "paint"],
			[5.08, 1.13, "paint"], [5.08, 0.40, "paint"], [5.03, 0.31, "under"], [4.70, 0.33, "under"],
			[0.40, 0.33, "under"]],
		"cabin": [[1.35, 1.05, "glass"], [2.12, 1.66, "paint"], [4.90, 1.65, "paint"], [5.06, 1.53, "glass"],
			[5.08, 1.18, "paint"]],
		"body_section": [[0.30, 0.90], [0.42, 0.975], [0.60, 1.0], [0.85, 1.0], [1.10, 0.98]],
		"cabin_section": [[1.05, 0.97], [1.35, 0.94], [1.66, 0.87]],
		"nose": [0.60, 0.13],
		"tail": [0.25, 0.05],
		"crown": [0.07, 0.07],
		"glass": {"margin": 0.025, "frame": ["trim", 0.015], "pillars": [[2.60, 2.70, "trim"], [3.62, 3.72, "trim"], [4.86, 9.0, "trim"]],
			"tint_from": 2.70, "windshield": [0.90, "paint"], "backlight": [0.84, "trim"]},
		"marks": [[2.40, 2.52, 0.95, 0.985, "trim", 0], [2.73, 2.85, 0.97, 1.005, "trim", 1]],
		"side": [[1.50, 1.86, 1.05, 1.22, "trim", 0],  # the mirror's sail
			[1.50, 3.58, 0.62, 0.665, "trim", 0],  # the rubbing strip
			[0.02, 0.20, 0.665, 0.83, "amber", 0], [5.02, 5.08, 0.52, 1.13, "taillight", 0]],
		"front": [[0.0, 0.07, 0.69, 0.73, "chrome"], [0.0, 0.36, 0.665, 0.77, "grille"],
			[0.40, 0.86, 0.665, 0.83, "headlight"], [0.86, 1.0, 0.665, 0.83, "amber"],
			[0.0, 0.25, 0.46, 0.58, "plate"], [0.0, 0.62, 0.35, 0.44, "grille"]],
		"back": [[0.80, 1.0, 0.52, 0.60, "reverse"], [0.80, 1.0, 0.52, 1.13, "taillight"],
			[0.0, 0.25, 0.62, 0.78, "plate"], [0.0, 1.0, 0.31, 0.36, "plastic"]],
		"mirror": [1.76, 1.12, "trim"],
		"door": [2.70, 3.62, 0.34, 1.62, 1],
		"rails": [2.20, 4.75],
		"wheel": "turbine",
	},
	"compact": {  # 1997 Toyota Tercel coupe: small and rounded, a big greenhouse, black bumpers
		"body": [[0.05, 0.27, "paint"], [0.0, 0.33, "paint"], [0.0, 0.46, "paint"], [0.035, 0.48, "paint"],
			[0.04, 0.56, "paint"], [0.09, 0.63, "paint"], [1.22, 0.80, "paint"], [3.55, 0.92, "paint"],
			[4.03, 0.93, "paint"], [4.09, 0.88, "paint"], [4.09, 0.48, "paint"], [4.12, 0.46, "paint"],
			[4.12, 0.33, "paint"], [4.08, 0.27, "under"], [3.80, 0.28, "under"], [0.30, 0.28, "under"]],
		"cabin": [[1.22, 0.80, "glass"], [1.88, 1.29, "paint"], [2.50, 1.31, "paint"], [2.98, 1.27, "glass"],
			[3.55, 0.92, "paint"]],
		"body_section": [[0.27, 0.90], [0.40, 0.975], [0.58, 1.0], [0.80, 0.965]],
		"cabin_section": [[0.80, 0.94], [1.05, 0.88], [1.30, 0.80]],
		"nose": [0.42, 0.11],
		"tail": [0.30, 0.06],
		"crown": [0.06, 0.07],
		"glass": {"margin": 0.03, "frame": ["trim", 0.035], "pillars": [[2.60, 2.69, "trim"]],
			"tint_from": 99.0, "windshield": [0.91, "paint"], "backlight": [0.88, "paint"]},
		"marks": [[2.20, 2.32, 0.74, 0.77, "trim", 0]],
		"side": [[0.04, 0.14, 0.49, 0.60, "amber", 0],
			[4.05, 4.12, 0.62, 0.78, "taillight", 0],
			[0.0, 0.45, 0.27, 0.48, "plastic", 0], [3.70, 4.12, 0.27, 0.48, "plastic", 0]],  # the bumpers' ends
		"front": [[0.0, 0.05, 0.525, 0.565, "chrome"], [0.0, 0.34, 0.51, 0.58, "grille"],
			[0.38, 0.84, 0.49, 0.60, "headlight"], [0.84, 1.0, 0.49, 0.60, "amber"],
			[0.0, 0.26, 0.34, 0.45, "plate"], [0.0, 1.0, 0.27, 0.485, "plastic"]],
		"back": [[0.42, 0.56, 0.62, 0.78, "amber"], [0.56, 1.0, 0.62, 0.78, "taillight"],
			[0.0, 0.24, 0.62, 0.76, "plate"], [0.0, 1.0, 0.27, 0.485, "plastic"]],
		"mirror": [1.46, 0.89, "trim"],
		"wheel": "five_spoke",
	},
	"sedan": {  # 1993 Acura Legend: a long low hood, a tall upright greenhouse with chrome round the glass
		"body": [[0.06, 0.21, "paint"], [0.0, 0.33, "paint"], [0.0, 0.50, "paint"], [0.03, 0.63, "paint"],
			[0.10, 0.67, "bay"], [1.60, 0.86, "paint"], [4.00, 0.96, "bay"], [4.84, 0.96, "paint"],
			[4.93, 0.90, "paint"], [4.95, 0.62, "paint"], [4.95, 0.37, "paint"], [4.90, 0.24, "under"],
			[4.60, 0.25, "under"], [0.35, 0.24, "under"]],
		"cabin": [[1.60, 0.86, "glass"], [2.32, 1.34, "paint"], [3.45, 1.35, "glass"], [4.00, 0.96, "paint"]],
		"body_section": [[0.21, 0.90], [0.36, 0.975], [0.55, 1.0], [0.75, 0.995], [0.92, 0.965]],
		"cabin_section": [[0.86, 0.95], [1.10, 0.90], [1.35, 0.84]],
		"nose": [0.45, 0.07],
		"tail": [0.35, 0.05],
		"crown": [0.05, 0.06],
		"glass": {"margin": 0.03, "frame": ["chrome", 0.012], "pillars": [[2.86, 2.95, "trim"], [3.55, 3.60, "chrome"]],
			"tint_from": 99.0, "windshield": [0.90, "paint"], "backlight": [0.88, "paint"]},
		"marks": [[2.50, 2.62, 0.80, 0.83, "chrome", 0], [3.38, 3.50, 0.81, 0.84, "chrome", 0]],
		"side": [[1.25, 3.50, 0.46, 0.50, "trim", 0],  # the rubbing strip
			[0.0, 0.12, 0.52, 0.63, "amber", 0], [4.86, 4.95, 0.62, 0.78, "taillight", 0]],
		"front": [[0.0, 0.05, 0.545, 0.585, "chrome"], [0.0, 0.36, 0.515, 0.615, "grille"],
			[0.0, 0.39, 0.50, 0.63, "chrome"], [0.42, 0.85, 0.52, 0.63, "headlight"], [0.85, 1.0, 0.52, 0.63, "amber"],
			[0.0, 1.0, 0.42, 0.46, "trim"], [0.0, 0.25, 0.27, 0.41, "plate"], [0.50, 0.78, 0.30, 0.35, "amber"]],
		"back": [[0.0, 0.24, 0.63, 0.77, "plate"], [0.32, 0.44, 0.62, 0.78, "reverse"], [0.32, 1.0, 0.62, 0.78, "taillight"],
			[0.0, 0.32, 0.62, 0.78, "trim"], [0.0, 1.0, 0.40, 0.44, "trim"]],
		"mirror": [1.70, 0.93, "paint"],
		"wheel": "fins",
	},
	"cruiser": {  # the deputies' Ford Crown Victoria
		"body": [[0.08, 0.24, "paint"], [0.0, 0.36, "paint"], [0.0, 0.58, "paint"], [0.05, 0.72, "paint"],
			[1.80, 0.92, "paint"], [4.12, 0.98, "paint"], [5.30, 0.98, "paint"], [5.38, 0.92, "paint"],
			[5.39, 0.65, "paint"], [5.39, 0.38, "paint"], [5.33, 0.26, "under"], [5.00, 0.27, "under"],
			[0.40, 0.26, "under"]],
		"cabin": [[1.80, 0.92, "glass"], [2.55, 1.44, "paint"], [3.55, 1.44, "glass"], [4.12, 0.98, "paint"]],
		"body_section": [[0.24, 0.90], [0.38, 0.975], [0.60, 1.0], [0.98, 0.965]],
		"cabin_section": [[0.92, 0.95], [1.20, 0.90], [1.44, 0.84]],
		"nose": [0.50, 0.08],
		"tail": [0.40, 0.06],
		"crown": [0.05, 0.06],
		"glass": {"margin": 0.035, "frame": ["trim", 0.012], "pillars": [[3.05, 3.15, "trim"]],
			"tint_from": 99.0, "windshield": [0.90, "paint"], "backlight": [0.88, "paint"]},
		"side": [[0.0, 0.12, 0.58, 0.70, "amber", 0], [5.30, 5.39, 0.66, 0.82, "taillight", 0]],
		"front": [[0.0, 0.36, 0.56, 0.70, "grille"], [0.40, 0.85, 0.58, 0.70, "headlight"],
			[0.85, 1.0, 0.58, 0.70, "amber"], [0.0, 0.25, 0.30, 0.44, "plate"]],
		"back": [[0.0, 0.24, 0.66, 0.80, "plate"], [0.45, 1.0, 0.66, 0.82, "taillight"]],
		"mirror": [1.95, 1.00, "trim"],
		"wheel": "steel",
	},
}

var _stats: CarStats
var _shape: Dictionary
var _paint: StandardMaterial3D
var _trim: StandardMaterial3D
var _glass: StandardMaterial3D
var _lights: StandardMaterial3D
var _body: Node3D  ## everything that leans (not the wheels)
var _body_mesh: MeshInstance3D
var _floor_mesh: MeshInstance3D  ## the top of the body under the cabin (see show_cabin_floor)
var _rest := {}  ## surface -> PackedVector3Array as built
var _dents := {}  ## surface -> PackedVector3Array of offsets
var _colors := {}  ## surface -> PackedColorArray
var _parts: Array = []  ## {node, at, threshold, kind ("fly"/"hinge"), state}
var _wheel_pivots: Array[Node3D] = []
var _wheel_spinners: Array[Node3D] = []
var _shadow: MeshInstance3D
var _smoke: CPUParticles3D
var _beacons: Array[StandardMaterial3D] = []  ## a cruiser's red and blue lights
var _beacons_on := false
var _headlights: Array[SpotLight3D] = []
var _flame: MeshInstance3D  ## out of the tailpipe while boosting
var _boosting := false
var _lean := Vector2.ZERO  ## smoothed (roll, pitch) in radians
var _max_lean := Vector2.ZERO  ## (roll, pitch): the lean is kept inside this ellipse
var _static_spring := 0.0  ## the suspension's length at rest under the car's weight
var _arches: Array[Dictionary] = []  ## {z, top, half, center_y, x_in}: see _plan_wheels
var _pieces := {}  ## "body", "cabin" -> what _piece worked out (for the doors and lids)
var _time := 0.0
var _damage := 0.0


## Where the ground is under the body origin with the car at rest (body y).
static func ground_y(stats: CarStats) -> float:
	var static_spring := stats.rest_length - clampf(stats.mass * 9.8 / (4.0 * stats.spring), 0.0, stats.rest_length * 0.7)
	return stats.mount_y - static_spring - stats.wheel_radius


## The greenhouse in body space, for the Cockpit and the tests: the bottom and top of the
## windshield and the back of the roof as (z, y), the beltline's lowest height, and the
## share of the half width at the beltline and the roof.
static func cabin_points(stats: CarStats) -> Dictionary:
	var shape: Dictionary = SHAPES.get(stats.style, SHAPES.sedan)
	var l := stats.body_size.z
	var g := ground_y(stats)
	var at := func(p: Array) -> Vector2: return Vector2(-l / 2.0 + float(p[0]), g + float(p[1]))
	var cabin: Array = shape.cabin
	var section: Array = shape.cabin_section
	var belt := INF
	for p: Array in cabin:
		belt = minf(belt, g + float(p[1]))
	return {"windshield_base": at.call(cabin[0]), "roof_front": at.call(cabin[1]), "roof_back": at.call(cabin[2]),
		"belt": belt, "belt_taper": float(section[0][1]), "roof_taper": float(section[section.size() - 1][1])}


func build(stats: CarStats, wheels: Array) -> void:
	_stats = stats
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.albedo_color = stats.body_color
	_paint.roughness = 0.42
	_paint.metallic = 0.15
	_trim = _flat(Color.WHITE)
	_trim.roughness = 0.5
	_glass = StandardMaterial3D.new()
	_glass.vertex_color_use_as_albedo = true
	_glass.metallic = 0.25
	_glass.roughness = 0.2
	_lights = StandardMaterial3D.new()
	_lights.vertex_color_use_as_albedo = true
	_lights.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body = Node3D.new()
	add_child(_body)

	_shape = SHAPES.get(stats.style, SHAPES.sedan)
	var w := stats.body_size.x
	var l := stats.body_size.z
	_plan_wheels(stats)
	var key := _body_key(stats)
	if not _made.has(key):
		_made[key] = _make_body()
	var made: Dictionary = _made[key]
	_pieces = made.pieces
	var surfaces: Dictionary = made.surfaces.duplicate(true)
	for s in surfaces:
		_rest[s] = surfaces[s][0]
		_colors[s] = surfaces[s][1]
		var offsets := PackedVector3Array()
		offsets.resize(surfaces[s][0].size())
		_dents[s] = offsets
	_body_mesh = MeshInstance3D.new()
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_body_mesh)
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_floor_mesh)
	_rebuild_body()

	_build_wheels(stats, wheels)
	_build_parts(stats, w, l)
	if stats.style == "cruiser":
		_build_light_bar(stats, w, l)
	_smoke = _make_smoke(l)
	_body.add_child(_smoke)
	_flame = _make_flame()
	_flame.set_meta("no_clip_check", true)  # fire, not bodywork
	_body.add_child(_flame)
	_shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w * 1.25, l * 1.1)
	quad.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = quad
	_shadow.material_override = _shadow_material()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


## Bodies already worked out, by everything that shapes them: working one out takes a
## while, and the deputies' cars are built as you come up on them.
static var _made := {}


static func _body_key(stats: CarStats) -> String:
	return var_to_str([stats.style, stats.body_size, stats.wheel_radius, stats.track, stats.wheelbase, stats.mount_y,
		stats.rest_length, stats.mass, stats.spring, stats.max_steer_deg, stats.body_lean_deg])


## Work out a car's body ahead of time (the deputies' cars, while the game loads).
static func prepare(stats: CarStats) -> void:
	if _made.has(_body_key(stats)):
		return
	var model := CarModel.new()
	model._stats = stats
	model._shape = SHAPES.get(stats.style, SHAPES.sedan)
	model._plan_wheels(stats)
	_made[_body_key(stats)] = model._make_body()
	model.free()


## The body's surfaces (and the pieces they were laid out from, for the doors and lids).
func _make_body() -> Dictionary:
	var w := _stats.body_size.x
	var l := _stats.body_size.z
	var surfaces := _new_surfaces()
	var lower := _cut_arches(_outline(_shape.body, l, ground_y(_stats)))
	var cabin := _outline(_shape.cabin, l, ground_y(_stats))
	var cabin_points: PackedVector2Array = cabin[0]
	_pieces = {}
	_pieces.body = _piece(lower, "body", Vector2(cabin_points[0].x, cabin_points[cabin_points.size() - 1].x))
	_pieces.cabin = _piece(cabin, "cabin")
	for name: String in ["body", "cabin"]:
		_emit_strips(surfaces, _pieces[name])
		for side: float in [-1.0, 1.0]:
			_emit_side(surfaces, _pieces[name], side)
	_wheel_wells(surfaces, lower)
	_details(surfaces, w, l)
	_marks(surfaces)
	return {"surfaces": surfaces, "pieces": _pieces}


static func _new_surfaces() -> Dictionary:
	var out := {}
	for s: String in ["body", "trim", "glass", "lights", "floor"]:
		out[s] = [PackedVector3Array(), PackedColorArray()]
	return out


## 0 = showroom, 1 = totaled: the paint goes dull and dark, smoke pours out when it's bad,
## and parts come off (or open) as it passes each one's threshold, the one nearest
## `local_hit` (where the car was hit, in its own space) first.
func set_damage(amount: float, local_hit := Vector3.ZERO) -> void:
	_damage = clampf(amount, 0.0, 1.0)
	_paint.albedo_color = _stats.body_color.lerp(Color(0.12, 0.1, 0.09), _damage * 0.7)
	_smoke.emitting = _damage > 0.6
	var due := 0
	for part in _parts:
		if _damage >= part.threshold:
			due += 1
	var done := _parts.filter(func(p): return p.state != "on").size()
	while done < due:
		# Whatever's nearest the hit goes, but a hood has to be open before it can tear off.
		var candidates := _parts.filter(func(p): return p.state == "on" and (not p.has("after") or p.after.state == "open"))
		if candidates.is_empty():
			break
		candidates.sort_custom(func(a, b): return a.at.distance_to(local_hit) < b.at.distance_to(local_hit))
		_break(candidates[0])
		done += 1


## Push the body in around where it was hit: `local_dir` points from the middle of the
## car toward the hit, `amount` is the share of the car's health it cost.
func dent(local_dir: Vector3, amount: float) -> void:
	var d := Vector3(local_dir.x, 0.0, local_dir.z)
	if d.length() < 0.01 or amount <= 0.0:
		return
	d = d.normalized()
	var half := Vector2(_stats.body_size.x, _stats.body_size.z) / 2.0
	var reach := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.z), 0.001))
	var at := d * reach + Vector3.UP * 0.1
	var depth := clampf(amount * 0.9, 0.0, 0.2)
	for s in _rest:
		var rest: PackedVector3Array = _rest[s]
		var offsets: PackedVector3Array = _dents[s]
		for i in rest.size():
			var dist := (rest[i] + offsets[i]).distance_to(at)
			if dist >= DENT_RADIUS:
				continue
			var f := 1.0 - smoothstep(0.0, DENT_RADIUS, dist)
			f *= smoothstep(0.03, 0.3, _arch_distance(rest[i]))  # the arches keep their shape
			if f > 0.0:
				offsets[i] = (offsets[i] - (d + Vector3.DOWN * 0.2) * depth * f).limit_length(MAX_DENT)
		_dents[s] = offsets
	_rebuild_body()


## Per frame: wheels follow the suspension, the body leans with the car's acceleration
## (`accel` in the car's own space, m/s²), and loose lids flap with speed.
func update(wheels: Array, steer_angle: float, accel: Vector3, speed: float, delta: float) -> void:
	_time += delta
	var ground_y := 0.0
	var grounded := 0
	for i in wheels.size():
		var wheel: Car.Wheel = wheels[i]
		var pivot := _wheel_pivots[i]
		pivot.position = wheel.mount - Vector3(0, maxf(wheel.spring_length, _static_spring - VISUAL_BUMP), 0)
		pivot.rotation.y = steer_angle if wheel.front else 0.0
		_wheel_spinners[i].rotation.x = -wheel.spin
		if wheel.grounded:
			ground_y += pivot.position.y - _stats.wheel_radius
			grounded += 1
	_shadow.visible = grounded > 0
	if grounded > 0:
		_shadow.position = Vector3(0, ground_y / grounded + 0.03, 0)
	# Lean out of the turn, dip under braking (only while on the ground).
	var g := 9.8
	var target := Vector2(accel.x / g * deg_to_rad(_stats.body_lean_deg), -accel.z / g * deg_to_rad(1.5))
	if grounded == 0:
		target = Vector2.ZERO
	var reach := pow(target.x / _max_lean.x, 2.0) + pow(target.y / _max_lean.y, 2.0)
	if reach > 1.0:
		target /= sqrt(reach)
	_lean = _lean.lerp(target, 1.0 - exp(-delta * 6.0))
	_body.rotation = Vector3(_lean.y, 0.0, _lean.x)
	if not _beacons.is_empty():
		var flash := fmod(_time, 0.5) < 0.25
		_beacons[0].albedo_color = Color(1.0, 0.1, 0.1) if _beacons_on and flash else Color(0.35, 0.05, 0.05)
		_beacons[1].albedo_color = Color(0.15, 0.3, 1.0) if _beacons_on and not flash else Color(0.05, 0.08, 0.3)
	_flame.visible = _boosting
	if _boosting:
		var flicker := 0.75 + 0.25 * sin(_time * 53.0) * sin(_time * 31.0 + 1.0)
		var length := (1.1 + clampf(speed / 60.0, 0.0, 1.0) * 0.9) * flicker
		_flame.scale = Vector3(1.0, length, 1.0)
		_flame.position = Vector3(_stats.body_size.x * 0.28, -0.3, _stats.body_size.z / 2.0 + length / 2.0)
	for part in _parts:
		if part.state == "open":
			var flap: float = sin(_time * (7.0 + speed * 0.2) + part.at.z) * clampf(speed / 30.0, 0.0, 1.0)
			part.node.rotation.x = part.open_angle * (0.75 + 0.25 * flap)


## For ModelCheck: the wheels' pivots (steered, at the suspension's height), the tire
## size, and the node everything that leans hangs off.
func wheel_pivots() -> Array[Node3D]:
	return _wheel_pivots


func wheel_radius() -> float:
	return _stats.wheel_radius


func body_node() -> Node3D:
	return _body


## The in-car view hides the top of the body under the cabin: from the driver's seat
## it'd be a floor at window-sill height, over the dash and the gauges. The Cockpit
## draws the inside of the car there instead.
func show_cabin_floor(on: bool) -> void:
	_floor_mesh.visible = on


## A flame out of the tailpipe while the boost burns.
func set_boost(on: bool) -> void:
	_boosting = on


## A cruiser's lights: flashing red and blue while it's chasing someone.
func set_beacons(on: bool) -> void:
	_beacons_on = on


## Two headlight beams down the road (night).
func set_headlights(on: bool) -> void:
	for light in _headlights:
		light.queue_free()
	_headlights.clear()
	if not on or _stats == null:
		return
	var w := _stats.body_size.x
	var l := _stats.body_size.z
	for side: float in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.position = Vector3(side * w * 0.3, -0.05, -l / 2.0 - 0.05)
		beam.rotation_degrees = Vector3(-3.5, 0, 0)
		beam.spot_range = 110.0
		beam.spot_angle = 30.0
		beam.spot_attenuation = 0.6
		beam.light_energy = 11.0
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.shadow_enabled = false
		_body.add_child(beam)
		_headlights.append(beam)


## The light bar on the roof and SHERIFF on the doors.
func _build_light_bar(stats: CarStats, w: float, l: float) -> void:
	var roof_y: float = cabin_points(stats).roof_front.y + float(_shape.crown[1])
	var roof_z := -l / 2.0 + l * 0.52
	var base := [PackedVector3Array(), PackedColorArray()]
	_box(base, Vector3(w * 0.7, 0.06, 0.28), Vector3(0, roof_y + 0.03, roof_z), KINDS.trim[1])
	_body.add_child(_mesh_of(base, _trim))
	for side: float in [-1.0, 1.0]:
		var lamp := [PackedVector3Array(), PackedColorArray()]
		_box(lamp, Vector3(w * 0.32, 0.12, 0.24), Vector3(side * w * 0.17, roof_y + 0.12, roof_z), Color.WHITE)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beacons.append(m)
		_body.add_child(_mesh_of(lamp, m))
	var push_bar := [PackedVector3Array(), PackedColorArray()]
	_box(push_bar, Vector3(w * 0.6, 0.35, 0.08), Vector3(0, ground_y(stats) + 0.52, -l / 2.0 - 0.12), KINDS.trim[1])
	_body.add_child(_mesh_of(push_bar, _trim))
	var dark := stats.body_color.get_luminance() < 0.5
	for side: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = "SHERIFF"
		label.font_size = 64
		label.pixel_size = 0.005
		label.outline_size = 0
		label.modulate = Color(0.95, 0.8, 0.3) if dark else Color(0.1, 0.3, 0.2)
		label.double_sided = false
		var y := ground_y(stats) + 0.68
		label.position = Vector3(side * (_half(_pieces.body, y, 0.1) + 0.01), y, 0.1)
		label.rotation.y = side * PI / 2.0
		label.visibility_range_end = 120.0
		_body.add_child(label)


func _rebuild_body() -> void:
	var meshes := {"body": ArrayMesh.new(), "floor": ArrayMesh.new()}
	for s in _rest:
		var rest: PackedVector3Array = _rest[s]
		if rest.is_empty():
			continue
		var offsets: PackedVector3Array = _dents[s]
		var verts := PackedVector3Array()
		verts.resize(rest.size())
		var normals := PackedVector3Array()
		normals.resize(rest.size())
		for i in rest.size():
			verts[i] = rest[i] + offsets[i]
		for t in range(0, verts.size(), 3):
			# Flat shading: each triangle's own normal (Godot's front faces are clockwise).
			var n := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
			normals[t] = n
			normals[t + 1] = n
			normals[t + 2] = n
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = _colors[s]
		var mesh: ArrayMesh = meshes.floor if s == "floor" else meshes.body
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for(s))
	_body_mesh.mesh = meshes.body
	_floor_mesh.mesh = meshes.floor


func _material_for(surface: String) -> Material:
	return {"lights": _lights, "glass": _glass, "trim": _trim}.get(surface, _paint)


## A side outline in body space: points (z, y) and the kind of each edge to the next point.
static func _outline(outline: Array, length: float, ground: float) -> Array:
	var points := PackedVector2Array()
	var kinds: Array[String] = []
	for p: Array in outline:
		points.append(Vector2(-length / 2.0 + float(p[0]), ground + float(p[1])))
		kinds.append(p[2])
	return [points, kinds]


static func _rect(z0: float, y0: float, z1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(z0, y0), Vector2(z1, y0), Vector2(z1, y1), Vector2(z0, y1)])


# --- Laying out the body ------------------------------------------------------------------

## Work out one piece of the body ("body" or "cabin") from its outline: its cross-section,
## the grid its sides are cut on (fine enough to bend, and lined up with everything drawn
## on them so nothing's ever an island inside a cell), its outline split on that grid (so
## the sides and the strips across the car share every edge), what's drawn on each side
## in order, and how much each outline point crowns. `floor_range` (z) is where the top of
## the lower body is under the cabin.
func _piece(outline: Array, name: String, floor_range := Vector2(INF, -INF)) -> Dictionary:
	var l := _stats.body_size.z
	var g := ground_y(_stats)
	var z0 := -l / 2.0
	var poly: PackedVector2Array = outline[0]
	var p := {"name": name, "half": _stats.body_size.x / 2.0, "z0": z0, "z1": l / 2.0,
		"nose": Vector2(_shape.nose[0], _shape.nose[1]), "tail": Vector2(_shape.tail[0], _shape.tail[1]),
		"crown": float(_shape.crown[0 if name == "body" else 1]), "floor": floor_range}
	var section := PackedVector2Array()
	for s: Array in _shape[name + "_section"]:
		section.append(Vector2(g + float(s[0]), float(s[1])))
	p.section = section
	var to_y := func(d: Array) -> Array: return [float(d[0]), float(d[1]), g + float(d[2]), g + float(d[3]), d[4]]
	p.front = _shape.front.map(to_y)
	p.back = _shape.back.map(to_y)

	# What's drawn on each side, the first listed winning.
	var layers := {-1.0: [], 1.0: []}
	for r: Array in _shape.side:
		var rect := _rect(z0 + float(r[0]), g + float(r[2]), z0 + float(r[1]), g + float(r[3]))
		for side: float in [-1.0, 1.0]:
			if int(r[5]) == 0 or float(r[5]) == side:
				layers[side].append([[rect], r[4]])
	var door_rect := PackedVector2Array()
	if _shape.has("door"):
		var d: Array = _shape.door
		door_rect = _rect(z0 + float(d[0]), g + float(d[2]), z0 + float(d[1]), g + float(d[3]))
	if name == "cabin":
		var gl: Dictionary = _shape.glass
		var margin: float = gl.margin
		var frame_width: float = gl.frame[1]
		var outer := Geometry2D.offset_polygon(poly, -margin, Geometry2D.JOIN_MITER)
		var inner := Geometry2D.offset_polygon(poly, -(margin + frame_width), Geometry2D.JOIN_MITER) if frame_width > 0.0 else outer
		for pillar: Array in gl.pillars:
			for side: float in [-1.0, 1.0]:
				layers[side].append([[_rect(z0 + float(pillar[0]), -10.0, z0 + float(pillar[1]), 10.0)], pillar[2]])
		if not door_rect.is_empty():
			layers[float(_shape.door[4])].append([[door_rect], "bay"])
		var tinted: Array = []
		var behind := _rect(z0 + float(gl.tint_from), -10.0, l, 10.0)
		for g_poly: PackedVector2Array in inner:
			tinted.append_array(Geometry2D.intersect_polygons(g_poly, behind))
		for side: float in [-1.0, 1.0]:
			if not tinted.is_empty():
				layers[side].append([tinted, "tint"])
			layers[side].append([inner, "glass"])
			if frame_width > 0.0:
				layers[side].append([outer, gl.frame[0]])
	elif not door_rect.is_empty():
		layers[float(_shape.door[4])].append([[door_rect], "bay"])
	p.layers = layers

	# The sides are cut in bands at the cross-section's bends and at the top and bottom of
	# everything drawn on them (so nothing drawn is ever an island in a band, which would
	# leave a hole), and across them every so far and through the rounding at the ends.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var zs: Array[float] = []
	var ys: Array[float] = []
	var steps := ceili((hi.x - lo.x) / CELL.x)
	for k in steps + 1:
		zs.append(lerpf(lo.x, hi.x, float(k) / steps))
	steps = ceili((hi.y - lo.y) / CELL.y)
	for k in steps + 1:
		ys.append(lerpf(lo.y, hi.y, float(k) / steps))
	for s in section:
		ys.append(s.x)
	for k in range(1, 4):
		zs.append(z0 + float(p.nose.x) * k / 3.0)
		zs.append(l / 2.0 - float(p.tail.x) * k / 3.0)
	for side: float in [-1.0, 1.0]:
		for layer: Array in layers[side]:
			for shape_poly: PackedVector2Array in layer[0]:
				for q in shape_poly:
					ys.append(q.y)
	p.zs = _grid(zs, lo.x, hi.x)
	p.ys = _grid(ys, lo.y, hi.y)
	# The outline's also cut at the top and bottom of what's drawn on the nose and tail.
	var cuts: Array[float] = []
	cuts.append_array(Array(p.ys))
	for d: Array in p.front + p.back:
		cuts.append(d[2])
		cuts.append(d[3])
	var cut_ys := _grid(cuts, lo.y, hi.y)

	# The outline split at those lines (and at least every EDGE_STEP).
	var kinds: Array = outline[1]
	var points := PackedVector2Array()
	var point_kinds: Array[String] = []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var ts: Array[float] = [0.0]
		for z: float in p.zs:
			if (z - a.x) * (z - b.x) < 0.0:
				ts.append((z - a.x) / (b.x - a.x))
		for y: float in cut_ys:
			if (y - a.y) * (y - b.y) < 0.0:
				ts.append((y - a.y) / (b.y - a.y))
		var pieces := ceili(a.distance_to(b) / EDGE_STEP)
		for k in range(1, pieces):
			ts.append(float(k) / pieces)
		ts.sort()
		var last := -1.0
		for t in ts:
			if t - last < 0.004 or t > 0.996:
				continue
			points.append(a.lerp(b, t))
			point_kinds.append(kinds[i])
			last = t
	p.points = points
	p.kinds = point_kinds

	# Each edge's outward normal (z, y), and how much each point crowns: the more it faces
	# up, the more (never the cabin's bottom, which sits on the body).
	var area := 0.0
	for i in points.size():
		area += points[i].cross(points[(i + 1) % points.size()])
	var turn := 1.0 if area > 0.0 else -1.0
	var normals := PackedVector2Array()
	for i in points.size():
		var e := points[(i + 1) % points.size()] - points[i]
		normals.append(Vector2(e.y, -e.x).normalized() * turn)
	var weights := PackedFloat32Array()
	var belt := lo.y
	for i in points.size():
		var n := (normals[i] + normals[(i - 1 + points.size()) % points.size()]).normalized()
		var wgt := smoothstep(0.35, 0.85, n.y)
		if name == "cabin" and points[i].y < belt + 0.01:
			wgt = 0.0
		weights.append(wgt)
	p.normals = normals
	p.weights = weights

	# Across the car: where the top bends round (S_BASE), and where the nose and tail's
	# lights and the glass's pillars start and stop.
	var ends: Array[float] = []
	for d: Array in p.front + p.back:
		ends.append(d[0])
		ends.append(d[1])
	p.across = _mirrored(Array(S_BASE))
	p.across_flat = PackedFloat32Array([-1.0, 1.0])
	p.across_ends = _mirrored(ends + Array(S_BASE))
	p.across_glass = _mirrored(Array(S_BASE) + [float(_shape.glass.windshield[0]), float(_shape.glass.backlight[0])])
	return p


## Shares of the half width (0 to 1) as positions across the car, -1 to 1.
static func _mirrored(shares: Array) -> PackedFloat32Array:
	var half := _grid(shares, 0.0, 1.0)
	var out := PackedFloat32Array()
	for k in range(half.size() - 1, 0, -1):
		out.append(-half[k])
	out.append_array(half)
	return out


## Sorted grid lines between lo and hi, ones closer than a centimeter merged.
static func _grid(values: Array, lo: float, hi: float) -> PackedFloat32Array:
	var sorted := values.duplicate()
	sorted.append(lo)
	sorted.append(hi)
	sorted.sort()
	var out := PackedFloat32Array()
	for v: float in sorted:
		if v < lo - 0.0001 or v > hi + 0.0001:
			continue
		if out.is_empty() or v - out[out.size() - 1] > 0.01:
			out.append(clampf(v, lo, hi))
	return out


## The half width of a piece at height y, z along the car: its cross-section, pulled in
## round the corners at the nose and tail.
func _half(p: Dictionary, y: float, z: float) -> float:
	var section: PackedVector2Array = p.section
	var f := section[0].y if y <= section[0].x else section[section.size() - 1].y
	for i in section.size() - 1:
		if y >= section[i].x and y <= section[i + 1].x:
			f = lerpf(section[i].y, section[i + 1].y, (y - section[i].x) / maxf(section[i + 1].x - section[i].x, 0.001))
			break
	var h := f * float(p.half)
	for end: Array in [[p.nose, z - float(p.z0)], [p.tail, float(p.z1) - z]]:
		var round_off: Vector2 = end[0]
		var d: float = end[1]
		if round_off.x > 0.0 and d < round_off.x:
			var t := 1.0 - clampf(d / round_off.x, 0.0, 1.0)
			h *= 1.0 - round_off.y * (1.0 - sqrt(maxf(1.0 - t * t, 0.0)))
	return h


## A point on a piece: (z, y) on its outline, s across the car (-1 the left side, 1 the
## right), crowned up by `weight` in the middle; `offset` pushes a side out.
func _at(p: Dictionary, q: Vector2, s: float, weight: float, offset := 0.0) -> Vector3:
	return Vector3(s * (_half(p, q.y, q.x) + offset), q.y + float(p.crown) * weight * (1.0 - s * s), q.x)


## The strips across the car round a piece's outline: the front, the hood and roof, the
## glass, the back and the underside. `only` picks the edges (all of them if it's not
## valid); `lift` raises them (a lid over its bay); `kind` paints them all one kind.
func _emit_strips(surfaces: Dictionary, p: Dictionary, only := Callable(), lift := 0.0, kind := "") -> void:
	var points: PackedVector2Array = p.points
	var across: PackedFloat32Array = p.across
	var n := points.size()
	var floor_range: Vector2 = p.floor
	for i in n:
		if only.is_valid() and not only.call(i):
			continue
		var a := points[i]
		var b := points[(i + 1) % n]
		var normal: Vector2 = p.normals[i]
		var outward := Vector3(0.0, normal.y, normal.x)
		var wa: float = p.weights[i]
		var wb: float = p.weights[(i + 1) % n]
		var mid := (a + b) / 2.0
		var under_cabin := normal.y > 0.7 and mid.x > floor_range.x and mid.x < floor_range.y
		var edge_kind := String(p.kinds[i])
		# Only as many columns as it needs: none between the sides where it doesn't crown,
		# and the lights' and pillars' edges where they're drawn. Those extra ones sit on
		# the straight lines between the crowned ones, so the edge it shares with the next
		# strip has no gaps.
		var columns: PackedFloat32Array = across
		if edge_kind == "glass":
			columns = p.across_glass
		elif edge_kind == "paint" and absf(normal.x) > 0.35:
			columns = p.across_ends
		elif wa == 0.0 and wb == 0.0:
			columns = p.across_flat
		var row_a := _row(p, a, wa, columns, across)
		var row_b := _row(p, b, wb, columns, across)
		var up := Vector3(0, lift, 0)
		for j in columns.size() - 1:
			var k := kind if kind != "" else _strip_kind(p, edge_kind, normal, absf(columns[j] + columns[j + 1]) / 2.0, mid.y)
			var spec: Array = KINDS[k]
			var out: Array = surfaces.floor if under_cabin and kind == "" else surfaces[spec[0]]
			_tri(out, row_a[j] + up, row_a[j + 1] + up, row_b[j + 1] + up, outward, spec[1])
			_tri(out, row_a[j] + up, row_b[j + 1] + up, row_b[j] + up, outward, spec[1])


## A row of points across the car at outline point q: on the crowned curve at the base
## columns, and on the straight lines between them for any others.
func _row(p: Dictionary, q: Vector2, weight: float, columns: PackedFloat32Array, base: PackedFloat32Array) -> Array[Vector3]:
	var row: Array[Vector3] = []
	for s in columns:
		var k := 0
		while k < base.size() - 2 and base[k + 1] < s:
			k += 1
		var t := clampf((s - base[k]) / (base[k + 1] - base[k]), 0.0, 1.0)
		if t == 0.0 or t == 1.0:
			row.append(_at(p, q, s, weight))
		else:
			row.append(_at(p, q, base[k], weight).lerp(_at(p, q, base[k + 1], weight), t))
	return row


## What a bit of strip is: glass has pillars at its sides; the nose and tail have their
## lights, grille and plates drawn on.
func _strip_kind(p: Dictionary, kind: String, normal: Vector2, s: float, y: float) -> String:
	if kind == "glass":
		var spec: Array = _shape.glass.windshield if normal.x < 0.0 else _shape.glass.backlight
		return spec[1] if s > float(spec[0]) else "screen"
	if kind == "paint" and absf(normal.x) > 0.35:
		for d: Array in (p.front if normal.x < 0.0 else p.back):
			if s >= float(d[0]) and s <= float(d[1]) and y >= float(d[2]) and y <= float(d[3]):
				return d[4]
	return kind


## One side of a piece (side -1 the left, 1 the right), cell by cell, each cell split
## into what's drawn on it. `clip` keeps only what's inside it, `offset` stands it off
## the body (a door), and `skip` leaves out some of what's drawn (the doorway under it).
func _emit_side(surfaces: Dictionary, p: Dictionary, side: float, clip := PackedVector2Array(), offset := 0.0,
		skip: Array = []) -> void:
	var poly: PackedVector2Array = p.points
	var zs: PackedFloat32Array = p.zs
	var ys: PackedFloat32Array = p.ys
	var layers: Array = p.layers[side]
	for zi in zs.size() - 1:
		for yi in ys.size() - 1:
			var cell := _rect(zs[zi], ys[yi], zs[zi + 1], ys[yi + 1])
			var pieces := Geometry2D.intersect_polygons(poly, cell)
			if not clip.is_empty():
				var clipped: Array[PackedVector2Array] = []
				for piece in pieces:
					clipped.append_array(Geometry2D.intersect_polygons(piece, clip))
				pieces = clipped
			for piece in pieces:
				for part: Array in _partition(piece, layers, skip):
					_fill(surfaces, p, part[0], part[1], side, offset)


## Split a bit of side among what's drawn on it ([polygons, kind], first wins); the rest
## is paint.
static func _partition(piece: PackedVector2Array, layers: Array, skip: Array) -> Array:
	var out := []
	var remaining: Array[PackedVector2Array] = [piece]
	var box := _bounds(piece)
	for layer: Array in layers:
		if layer[1] in skip:
			continue
		for shape: PackedVector2Array in layer[0]:
			if not box.intersects(_bounds(shape), true):
				continue
			var left: Array[PackedVector2Array] = []
			for r in remaining:
				for inside in Geometry2D.intersect_polygons(r, shape):
					out.append([inside, layer[1]])
				left.append_array(Geometry2D.clip_polygons(r, shape))
			remaining = left
		if remaining.is_empty():
			break
	for r in remaining:
		out.append([r, "paint"])
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	return box


## A flat bit of side, triangulated and laid on the car.
func _fill(surfaces: Dictionary, p: Dictionary, poly: PackedVector2Array, kind: String, side: float, offset: float) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	var spec: Array = KINDS[kind]
	var out: Array = surfaces[spec[0]]
	for t in range(0, tris.size(), 3):
		_tri(out, _at(p, poly[tris[t]], side, 0.0, offset), _at(p, poly[tris[t + 1]], side, 0.0, offset),
			_at(p, poly[tris[t + 2]], side, 0.0, offset), Vector3(side, 0, 0), spec[1])


## Where the wheels sit and how big their arches are. A tire rests where the springs
## hold the car up; it's drawn at most VISUAL_BUMP above that. The body leans at most
## _max_lean (an ellipse of roll and pitch), which brings an arch down on its tire by
## up to `lean_dy`. Each arch is a stadium (a half disc on top of a slot running down
## off the bottom of the car), wide enough for the tire at full lock.
func _plan_wheels(stats: CarStats) -> void:
	_static_spring = stats.rest_length - clampf(stats.mass * 9.8 / (4.0 * stats.spring), 0.0, stats.rest_length * 0.7)
	_max_lean = Vector2(deg_to_rad(minf(stats.body_lean_deg, 4.0)), deg_to_rad(PITCH_MAX_DEG))
	var r := stats.wheel_radius
	var half_track := stats.track / 2.0
	var lean_dy := Vector2((half_track + WHEEL_REACH) * sin(_max_lean.x),
		(stats.wheelbase / 2.0 + r + ARCH_SIDE) * sin(_max_lean.y)).length()
	var rest_y := stats.mount_y - _static_spring
	var steer := deg_to_rad(stats.max_steer_deg)
	_arches.clear()
	for z: float in [-stats.wheelbase / 2.0, stats.wheelbase / 2.0]:
		var front := z < 0.0
		# A steered tire seen from the side is a little longer than it is round.
		var reach := maxf(r, r * cos(steer) + WHEEL_REACH * sin(steer)) if front else r
		var half := reach + ARCH_SIDE
		var top := rest_y + r + VISUAL_BUMP + lean_dy + ARCH_TOP
		# The inner wall of the wheel well: clear of the tire's inside edge at full lock.
		var x_in := half_track - WHEEL_REACH - (r * sin(steer) if front else 0.0) - 0.06
		_arches.append({"z": z, "top": top, "half": half, "center_y": top - half, "x_in": x_in})


## The stadium's outline (z, y), counterclockwise, running well below the car.
func _arch_polygon(arch: Dictionary) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var z: float = arch.z
	var half: float = arch.half
	var cy: float = arch.center_y
	poly.append(Vector2(z + half, -5.0))
	for i in 13:
		var a := PI * i / 12.0
		poly.append(Vector2(z + cos(a) * half, cy + sin(a) * half))
	poly.append(Vector2(z - half, -5.0))
	return poly


## How far a point (body space) is outside the nearest arch, in the side view (negative
## inside one).
func _arch_distance(p: Vector3) -> float:
	var best := INF
	for arch in _arches:
		var dz := absf(p.z - float(arch.z))
		var d: float
		if p.y <= float(arch.center_y):
			d = dz - float(arch.half)
		else:
			d = Vector2(dz, p.y - float(arch.center_y)).length() - float(arch.half)
		best = minf(best, d)
	return best


## The side outline with the arches cut out of its bottom. Edges along an arch are the
## dark inside of the wheel well; the rest keep the kind of the edge they lie on.
func _cut_arches(outline: Array) -> Array:
	var shape: PackedVector2Array = outline[0]
	for arch in _arches:
		var cut := Geometry2D.clip_polygons(shape, _arch_polygon(arch))
		if cut.size() == 1:
			shape = cut[0]
	var kinds: Array[String] = []
	var original: PackedVector2Array = outline[0]
	for i in shape.size():
		var mid := (shape[i] + shape[(i + 1) % shape.size()]) / 2.0
		var kind := "well"
		for k in original.size():
			var a := original[k]
			var b := original[(k + 1) % original.size()]
			if Geometry2D.get_closest_point_to_segment(mid, a, b).distance_to(mid) < 0.002:
				kind = outline[1][k]
				break
		kinds.append(kind)
	return [shape, kinds]


## The back walls of the wheel wells: a dark box between each pair of wheels filling
## the arch, so you can't see through the car from one wheel to the other.
func _wheel_wells(surfaces: Dictionary, lower: Array) -> void:
	var shape: PackedVector2Array = lower[0]
	for arch in _arches:
		var z: float = arch.z
		var half: float = arch.half
		# The bottom of the body just fore and aft of the arch.
		var bottom := INF
		for p in shape:
			if absf(p.x - z) < half + 0.2:
				bottom = minf(bottom, p.y)
		var x_in: float = arch.x_in
		var top: float = arch.top
		_box(surfaces.trim, Vector3(x_in * 2.0, top - bottom, half * 2.0), Vector3(0, (top + bottom) / 2.0, z), KINDS.well[1])


## One flat triangle, wound to face `outward`.
static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	var verts: PackedVector3Array = out[0]
	var colors: PackedColorArray = out[1]
	for p in [a, b, c]:
		verts.append(p)
		colors.append(color)
	out[0] = verts
	out[1] = colors


static func _box(out: Array, size: Vector3, center: Vector3, color: Color) -> void:
	var h := size / 2.0
	for axis in 3:
		for side: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var f := center + n * h[axis]
			_tri(out, f - u - v, f + u - v, f + u + v, n, color)
			_tri(out, f - u - v, f + u + v, f - u + v, n, color)


## What stands proud of the bodywork and stays put: the mirrors (the Tercel's come off,
## so they're parts) and the Windstar's roof rails.
func _details(surfaces: Dictionary, _w: float, l: float) -> void:
	if _stats.style != "compact":
		for side: float in [-1.0, 1.0]:
			_mirror(surfaces, side)
	if _shape.has("rails"):
		var cabin: Dictionary = _pieces.cabin
		var c := cabin_points(_stats)
		var rails: Array = _shape.rails
		var z0 := -l / 2.0 + float(rails[0])
		var z1 := -l / 2.0 + float(rails[1])
		var s := 0.8
		var roof := func(z: float) -> float:
			var t := clampf((z - c.roof_front.x) / (c.roof_back.x - c.roof_front.x), 0.0, 1.0)
			return lerpf(c.roof_front.y, c.roof_back.y, t)
		var black: Color = KINDS.trim[1]
		for side: float in [-1.0, 1.0]:
			var x := side * _half(cabin, roof.call(z0), (z0 + z1) / 2.0) * s
			var y := float(_at(cabin, Vector2((z0 + z1) / 2.0, roof.call((z0 + z1) / 2.0)), s, 1.0).y)
			_box(surfaces.trim, Vector3(0.035, 0.03, z1 - z0), Vector3(x, y + 0.06, (z0 + z1) / 2.0), black)
			for z: float in [z0 + 0.05, z1 - 0.05]:
				_box(surfaces.trim, Vector3(0.05, 0.06, 0.10), Vector3(x, y + 0.025, z), black)
		for z: float in [z0 + 0.6, z1 - 0.6]:
			var x := _half(cabin, roof.call(z), z) * s
			var y := float(_at(cabin, Vector2(z, roof.call(z)), s, 1.0).y)
			_box(surfaces.trim, Vector3(x * 2.0, 0.018, 0.035), Vector3(0, y + 0.08, z), black)


## The small things just proud of the sides (door handles): `door` draws the ones on the
## sliding door (in its own space), otherwise it's the rest.
func _marks(surfaces: Dictionary, door := PackedVector2Array(), side_of_door := 0.0) -> void:
	var g := ground_y(_stats)
	var z0 := -_stats.body_size.z / 2.0
	for m: Array in _shape.get("marks", []):
		var rect := _rect(z0 + float(m[0]), g + float(m[2]), z0 + float(m[1]), g + float(m[3]))
		var spec: Array = KINDS[m[4]]
		for side: float in [-1.0, 1.0]:
			if int(m[5]) != 0 and float(m[5]) != side:
				continue
			var on_door := side == side_of_door and Geometry2D.is_point_in_polygon(_bounds(rect).get_center(), door)
			if on_door != (not door.is_empty()):
				continue
			var c: Array[Vector3] = []
			for q in rect:
				c.append(_at(_pieces.body, q, side, 0.0, PATCH_OFFSET * (2.0 if on_door else 0.5)))
			_tri(surfaces[spec[0]], c[0], c[1], c[2], Vector3(side, 0, 0), spec[1])
			_tri(surfaces[spec[0]], c[0], c[2], c[3], Vector3(side, 0, 0), spec[1])


## A side mirror at the bottom of the windshield pillar: an arm out from the door and a
## housing on it.
func _mirror(surfaces: Dictionary, side: float) -> void:
	var m: Array = _shape.mirror
	var z := -_stats.body_size.z / 2.0 + float(m[0])
	var y := ground_y(_stats) + float(m[1])
	var x := _half(_pieces.cabin, y, z)
	var spec: Array = KINDS[m[2]]
	var out: Array = surfaces[spec[0]]
	_box(out, Vector3(0.12, 0.035, 0.06), Vector3(side * (x + 0.05), y - 0.02, z + 0.03), spec[1])
	_box(out, Vector3(0.08, 0.14, 0.20), Vector3(side * (x + 0.13), y + 0.02, z + 0.02), spec[1])
	_box(surfaces.glass, Vector3(0.06, 0.11, 0.01), Vector3(side * (x + 0.135), y + 0.02, z + 0.125), KINDS.glass[1])


func _build_wheels(stats: CarStats, wheels: Array) -> void:
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = stats.wheel_radius
	tire_mesh.bottom_radius = stats.wheel_radius
	tire_mesh.height = TIRE_WIDTH
	tire_mesh.radial_segments = 16
	tire_mesh.rings = 1
	var tire_material := _flat(TIRE)
	var faces := {}
	var style: String = "steel" if _shape.wheel == "turbine" else _shape.wheel  # under the Windstar's hubcaps
	for side: float in [-1.0, 1.0]:
		var out := [PackedVector3Array(), PackedColorArray()]
		_wheel_face(out, style, stats.wheel_radius, side, TIRE_WIDTH / 2.0 + 0.004, false)
		faces[side] = _array_mesh(out)
	for wheel in wheels:
		var pivot := Node3D.new()
		pivot.position = wheel.mount
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var tire := MeshInstance3D.new()
		tire.mesh = tire_mesh
		tire.material_override = tire_material
		tire.rotation_degrees = Vector3(0, 0, 90)
		spinner.add_child(tire)
		var face := MeshInstance3D.new()  # the wheel: you can see it turn
		face.mesh = faces[-1.0 if wheel.mount.x < 0.0 else 1.0]
		face.material_override = _trim
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spinner.add_child(face)
		_wheel_pivots.append(pivot)
		_wheel_spinners.append(spinner)


## A wheel's face, on the `side` of the tire at `x` out from its middle, its design by
## `style`: the Windstar's swirled hubcaps ("turbine"), the Legend's finned wheel covers
## ("fins"), five-spoke alloys ("five_spoke") and plain black steel ("steel"). `both`
## for a part that might be seen from behind (a hubcap flying off).
static func _wheel_face(out: Array, style: String, r: float, side: float, x: float, both: bool) -> void:
	var n := Vector3(side, 0, 0)
	var at := func(p: Vector2, lift: float) -> Vector3: return Vector3(side * (x + lift), p.x, p.y)
	var silver := Color(0.74, 0.75, 0.77)
	var dark := Color(0.16, 0.16, 0.17)
	var disc := func(radius: float, lift: float, color: Color) -> void:
		for i in 16:
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			_face_tri(out, at.call(Vector2.ZERO, lift), at.call(Vector2.from_angle(a0) * radius, lift),
				at.call(Vector2.from_angle(a1) * radius, lift), n, color, both)
	var quad := func(pts: Array, lift: float, color: Color) -> void:
		_face_tri(out, at.call(pts[0], lift), at.call(pts[1], lift), at.call(pts[2], lift), n, color, both)
		_face_tri(out, at.call(pts[0], lift), at.call(pts[2], lift), at.call(pts[3], lift), n, color, both)
	match style:
		"turbine":  # swirled slots round a silver cap
			disc.call(r * 0.80, 0.0, silver)
			for i in 12:
				var a := TAU * i / 12.0
				var p0 := Vector2.from_angle(a) * r * 0.36
				var p1 := Vector2.from_angle(a + 0.38) * r * 0.72
				var across := Vector2.from_angle(a + PI / 2.0) * r * 0.035
				quad.call([p0 - across, p0 + across, p1 + across * 1.6, p1 - across * 1.6], 0.003, dark)
			disc.call(r * 0.2, 0.003, Color(0.6, 0.61, 0.63))
		"fins":  # a silver disc with a ring of narrow slots
			disc.call(r * 0.82, 0.0, silver)
			for i in 18:
				var a := TAU * i / 18.0
				var d := Vector2.from_angle(a)
				var across := Vector2.from_angle(a + PI / 2.0) * r * 0.025
				quad.call([d * r * 0.44 - across, d * r * 0.44 + across, d * r * 0.76 + across * 1.8, d * r * 0.76 - across * 1.8], 0.003, dark)
			disc.call(r * 0.24, 0.003, Color(0.82, 0.83, 0.85))
		"five_spoke":  # spokes out to a bright rim, dark between them
			disc.call(r * 0.84, 0.0, dark)
			for i in 5:
				var a := TAU * i / 5.0
				var d := Vector2.from_angle(a)
				var across := Vector2.from_angle(a + PI / 2.0)
				quad.call([d * r * 0.18 - across * r * 0.08, d * r * 0.18 + across * r * 0.08,
					d * r * 0.80 + across * r * 0.13, d * r * 0.80 - across * r * 0.13], 0.003, silver)
			for i in 20:
				var a0 := TAU * i / 20.0
				var a1 := TAU * (i + 1) / 20.0
				quad.call([Vector2.from_angle(a0) * r * 0.78, Vector2.from_angle(a1) * r * 0.78,
					Vector2.from_angle(a1) * r * 0.86, Vector2.from_angle(a0) * r * 0.86], 0.003, silver)
			disc.call(r * 0.2, 0.004, silver)
		_:  # black steel, a little chrome cap
			disc.call(r * 0.78, 0.0, Color(0.07, 0.07, 0.075))
			disc.call(r * 0.22, 0.003, Color(0.70, 0.71, 0.73))


static func _face_tri(out: Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, both: bool) -> void:
	_tri(out, a, b, c, n, color)
	if both:
		_tri(out, a, b, c, -n, color.darkened(0.3))


## Each car's signature parts, with the damage at which each one goes.
func _build_parts(stats: CarStats, _w: float, l: float) -> void:
	match stats.style:
		"minivan":
			# Hubcaps one by one, then the sliding door (passenger side).
			for i in _wheel_spinners.size():
				var cap := Node3D.new()
				var side := -1.0 if _wheel_spinners[i].get_parent().position.x < 0.0 else 1.0
				var out := [PackedVector3Array(), PackedColorArray()]
				_wheel_face(out, "turbine", stats.wheel_radius, side, TIRE_WIDTH / 2.0 + 0.012, true)
				cap.add_child(_mesh_of(out, _trim))
				_wheel_spinners[i].add_child(cap)
				_parts.append({"node": cap, "at": _wheel_spinners[i].get_parent().position, "threshold": 0.12 + 0.12 * i,
					"kind": "fly", "state": "on"})
			var door := _door()
			_body.add_child(door)
			_parts.append({"node": door, "at": door.position, "threshold": 0.55, "kind": "fly", "state": "on"})
		"compact":
			# Mirrors, then the bumpers.
			for side: float in [-1.0, 1.0]:
				var m: Array = _shape.mirror
				var mirror := Node3D.new()
				mirror.position = Vector3(side * (_half(_pieces.cabin, ground_y(stats) + float(m[1]), -l / 2.0 + float(m[0])) + 0.1),
					ground_y(stats) + float(m[1]), -l / 2.0 + float(m[0]))
				var out := _new_surfaces()
				_mirror(out, side)
				_add_surfaces(mirror, out)
				_body.add_child(mirror)
				_parts.append({"node": mirror, "at": mirror.position, "threshold": 0.15 if side < 0 else 0.28,
					"kind": "fly", "state": "on"})
			# The bumpers are the gray plastic drawn on the body; one that comes off flies as
			# a piece that size, and where it was goes dark.
			var g := ground_y(stats)
			var colors: PackedColorArray = _colors.trim
			var verts: PackedVector3Array = _rest.trim
			for end: float in [-1.0, 1.0]:
				var mine := PackedInt32Array()
				for i in colors.size():
					if colors[i].is_equal_approx(KINDS.plastic[1]) and signf(verts[i].z) == end:
						mine.append(i)
				var y0 := g + 0.27
				var y1 := g + 0.485
				var bumper := Node3D.new()
				var b := [PackedVector3Array(), PackedColorArray()]
				var half := _half(_pieces.body, (y0 + y1) / 2.0, end * (l / 2.0 - 0.3))
				_box(b, Vector3(half * 2.0, y1 - y0, 0.16), Vector3.ZERO, KINDS.plastic[1])
				bumper.add_child(_mesh_of(b, _trim))
				bumper.position = Vector3(0, (y0 + y1) / 2.0, end * (l / 2.0 - 0.06))
				bumper.visible = false  # (drawn on the body till it goes)
				_body.add_child(bumper)
				_parts.append({"node": bumper, "at": bumper.position, "threshold": 0.45 if end < 0 else 0.62,
					"kind": "fly", "state": "on", "recolor": mine})
		"sedan":
			# The hood and trunk lid pop open; much later the hood tears off.
			_parts.append(_lid(true, 0.35, deg_to_rad(38.0)))
			_parts.append(_lid(false, 0.55, deg_to_rad(-55.0)))
			var hood_off: Dictionary = _parts[0].duplicate()
			hood_off.threshold = 0.85
			hood_off.kind = "fly"
			hood_off.state = "on"
			hood_off.after = _parts[0]
			_parts.append(hood_off)


## The Windstar's sliding door: the side of the body over the doorway (its window,
## handle and rubbing strip on it), standing just off it. Under it the doorway's dark.
func _door() -> Node3D:
	var d: Array = _shape.door
	var g := ground_y(_stats)
	var z0 := -_stats.body_size.z / 2.0
	var side := float(d[4])
	var rect := _rect(z0 + float(d[0]), g + float(d[2]), z0 + float(d[1]), g + float(d[3]))
	var out := _new_surfaces()
	for name: String in ["body", "cabin"]:
		_emit_side(out, _pieces[name], side, rect, PATCH_OFFSET, ["bay"])
	_marks(out, rect, side)
	var node := Node3D.new()
	var mid := Vector2(z0 + (float(d[0]) + float(d[1])) / 2.0, g + (float(d[2]) + float(d[3])) / 2.0)
	node.position = Vector3(side * _half(_pieces.body, mid.y, mid.x), mid.y, mid.x)
	_add_surfaces(node, out, true)
	return node


## The Legend's hood (or trunk lid): the body's top over the bay, just above it, hinged at
## the windshield (the back glass for the trunk).
func _lid(hood: bool, threshold: float, open_angle: float) -> Dictionary:
	var p: Dictionary = _pieces.body
	var points: PackedVector2Array = p.points
	var mine := func(i: int) -> bool:
		var mid := (points[i] + points[(i + 1) % points.size()]) / 2.0
		return p.kinds[i] == "bay" and (mid.x < 0.0) == hood
	var lo := INF
	var hi := -INF
	var hinge_y := 0.0
	for i in points.size():
		if mine.call(i):  # (the outline might run either way round)
			for q: Vector2 in [points[i], points[(i + 1) % points.size()]]:
				lo = minf(lo, q.x)
				hi = maxf(hi, q.x)
	for i in points.size():
		if absf(points[i].x - (hi if hood else lo)) < 0.001:
			hinge_y = points[i].y
	var out := _new_surfaces()
	_emit_strips(out, p, mine, PATCH_OFFSET, "paint")
	var pivot := Node3D.new()
	pivot.position = Vector3(0, hinge_y + PATCH_OFFSET, hi if hood else lo)
	_add_surfaces(pivot, out, true)
	_body.add_child(pivot)
	return {"node": pivot, "at": Vector3(0, hinge_y, (lo + hi) / 2.0), "threshold": threshold, "kind": "hinge", "state": "on",
		"open_angle": open_angle}


## Meshes for a part's surfaces, around `node` (made relative to its position). `backs`
## gives it a dark back, for a panel you might see the inside of.
func _add_surfaces(node: Node3D, surfaces: Dictionary, backs := false) -> void:
	for s: String in surfaces:
		var verts: PackedVector3Array = surfaces[s][0]
		for i in verts.size():
			verts[i] -= node.position
		surfaces[s][0] = verts
	if backs:
		var front: PackedVector3Array = surfaces.body[0]
		var verts: PackedVector3Array = surfaces.trim[0]
		var colors: PackedColorArray = surfaces.trim[1]
		for t in range(0, front.size(), 3):
			verts.append_array([front[t], front[t + 2], front[t + 1]])
			colors.append_array([BAY, BAY, BAY])
		surfaces.trim[0] = verts
		surfaces.trim[1] = colors
	for s: String in surfaces:
		if not (surfaces[s][0] as PackedVector3Array).is_empty():
			node.add_child(_mesh_of(surfaces[s], _material_for(s)))


func _mesh_of(out: Array, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _array_mesh(out)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Flat-shaded triangles ([vertices, colors]) as a mesh.
static func _array_mesh(out: Array) -> ArrayMesh:
	var verts: PackedVector3Array = out[0]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, verts.size(), 3):
		var n := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
		normals[t] = n
		normals[t + 1] = n
		normals[t + 2] = n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = out[1]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A part gives: a lid pops open, anything else flies off as a physics body.
func _break(part: Dictionary) -> void:
	if part.has("after"):
		part.after.state = "gone"  # the open hood it was is tearing off
	if part.kind == "hinge":
		part.state = "open"
		return
	part.state = "gone"
	var node: Node3D = part.node
	if part.has("recolor"):  # it was drawn on the body: what's behind it is dark
		var colors: PackedColorArray = _colors.trim
		for i: int in part.recolor:
			colors[i] = BAY
		_colors.trim = colors
		_rebuild_body()
		node.visible = true
	var xf := node.global_transform
	var body := RigidBody3D.new()
	body.mass = 8.0
	# Nothing it can hit but the ground: not even the car it came off.
	body.collision_layer = 0
	body.collision_mask = 1 << (Car.WORLD_LAYER - 1)
	body.set_meta("car_part", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = box
	body.add_child(shape)
	var car := get_parent() as RigidBody3D
	var scene := get_tree().current_scene
	scene.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	node.reparent(body)
	var outward := (xf.origin - global_position)
	outward.y = 0.0
	body.linear_velocity = (car.linear_velocity if car else Vector3.ZERO) * 0.9 \
		+ outward.normalized() * 4.0 + Vector3.UP * 3.0
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	part_lost.emit(body)


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	return m


func _make_smoke(length: float) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 24
	smoke.lifetime = 1.6
	smoke.position = Vector3(0, 0.3, -length * 0.38)  # from under the hood
	smoke.direction = Vector3.UP
	smoke.spread = 25.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.2
	var puff := QuadMesh.new()
	puff.size = Vector2(0.8, 0.8)
	smoke.mesh = puff
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.25, 0.25, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke.material_override = m
	return smoke


## Cones pointing backward from the tailpipe, orange round a hot core (scaled along
## their length as they flicker).
func _make_flame() -> MeshInstance3D:
	var flame := _flame_cone(0.2, Color(1.0, 0.45, 0.08))
	var core := _flame_cone(0.09, Color(1.0, 0.92, 0.6))
	core.scale = Vector3(1.0, 0.6, 1.0)
	core.position = Vector3(0, -0.2, 0)
	flame.add_child(core)
	flame.rotation = Vector3(PI / 2.0, 0.0, 0.0)  # the cones' tips (+Y) point back (+Z)
	flame.visible = false
	return flame


func _flame_cone(radius: float, color: Color) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	cone.material = m
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _shadow_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.55))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
