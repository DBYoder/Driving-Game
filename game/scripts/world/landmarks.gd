class_name Landmarks
extends Node3D
## The places you'd point at from the passenger seat, built by hand at their real spots
## (data/routes/highway1/landmarks.json). RouteData leaves out the lidar's own buildings and trees
## where each one stands.
##
## Kalona Cheese, at the corner of 540th St 3.9 miles up from Kalona (the Kalona Creamery
## since 2017): the red brick store right by the road, a story and a half under a steep
## gray roof with KALONA CHEESE across its gable, wrapped in a one-story front with a gray
## shingled mansard and the black KALONA CREAMERY sign over the doors. Behind it, the
## cheese plant: a concrete-block and brick wing, the old plant under its tan roof, the
## brick smokestack, steel silos and the big metal plant buildings. Sizes and heights
## are off the 2019 lidar; the look is off a photo.
##
## Drawn with the scenery's shader, so the roofs take the snow and the windows light up
## at night. Solid, like the rest of the buildings.

# Vertex alpha says what a face is (see scenery.gdshader): 0 plain, 1/3 window, 2/3 lamp.
const BRICK := Color(0.62, 0.25, 0.18, 0.0)
const BRICK_DARK := Color(0.42, 0.17, 0.13, 0.0)
const SHINGLE := Color(0.40, 0.41, 0.43, 0.0)
const TAN_ROOF := Color(0.64, 0.50, 0.34, 0.0)
const FLAT_ROOF := Color(0.30, 0.30, 0.31, 0.0)
const BLOCK := Color(0.66, 0.66, 0.64, 0.0)
const METAL := Color(0.82, 0.83, 0.84, 0.0)
const STEEL := Color(0.88, 0.89, 0.90, 0.0)
const DOOR := Color(0.36, 0.37, 0.38, 0.0)  ## roll-up doors
const SIGN_BLACK := Color(0.05, 0.05, 0.05, 0.0)
const SILL := Color(0.86, 0.85, 0.80, 0.0)
const CONCRETE := Color(0.58, 0.57, 0.55, 0.0)
const POLE := Color(0.42, 0.42, 0.44, 0.0)
const WINDOW := Color(0.07, 0.08, 0.10, 0.33)
const LAMP := Color(0.85, 0.85, 0.80, 0.66)
const LETTERS := Color(0.97, 0.95, 0.88)
# Mid-Prairie High School
const SCHOOL_BRICK := Color(0.66, 0.31, 0.21, 0.0)
const COPING := Color(0.24, 0.25, 0.27, 0.0)  ## the dark metal edge round a flat roof
const MEMBRANE := Color(0.66, 0.66, 0.64, 0.0)  ## flat roofs
const TAN_BAND := Color(0.80, 0.75, 0.62, 0.0)  ## the gym's upper walls
const PANEL := Color(0.72, 0.73, 0.74, 0.0)  ## the gray front building
const PANEL_DARK := Color(0.27, 0.28, 0.30, 0.0)
const TAN_METAL := Color(0.78, 0.74, 0.63, 0.0)
const GREENHOUSE := Color(0.74, 0.82, 0.80, 0.33)  ## glass, lit up at night (grow lights)
const FRAME := Color(0.92, 0.93, 0.92, 0.0)
const ASPHALT := Color(0.23, 0.23, 0.24, 0.0)
const FLAGPOLE := Color(0.86, 0.87, 0.89, 0.0)
const GOLD := Color(0.98, 0.76, 0.16)  ## Golden Hawks lettering
const GOLD_BALL := Color(0.85, 0.70, 0.25, 0.0)
const LABEL_RANGE := 1100.0  ## like the road signs: a pixel or two in the haze past this

var route: RouteData
var material: ShaderMaterial
var _boxes: Array = []  ## [Transform3D at the box's center, half extents]: for QA's clip probe
var _body: StaticBody3D


func setup(r: RouteData) -> void:
	route = r
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/scenery.gdshader")
	_body = StaticBody3D.new()
	_body.collision_layer = 1 << (Car.WORLD_LAYER - 1)
	_body.collision_mask = 0
	add_child(_body)
	for l: Dictionary in route.landmarks:
		match String(l.id):
			"kalona_cheese":
				_kalona_cheese(Vector3(float(l.x), 0.0, float(l.z)))
			"mid_prairie":
				_mid_prairie(Vector3(float(l.x), 0.0, float(l.z)), float(l.get("yaw", 0.0)))


## The season and the time of day, like the scenery's.
func set_look(snow: float, night: float) -> void:
	material.set_shader_parameter("snow", snow)
	material.set_shader_parameter("night", night)


## Solid boxes within `radius` of a point (QA's clip probe), as [transform, half extents].
func building_boxes(near: Vector3, radius: float) -> Array:
	return _boxes.filter(func(b: Array): return Vector2(b[0].origin.x - near.x, b[0].origin.z - near.z).length() <= radius)


func box_count() -> int:
	return _boxes.size()


## Local axes: x east, z south (the store's front faces south, onto 540th St), y up from
## the ground at the middle of each group. The origin is the middle of the store's main
## block.
func _kalona_cheese(origin: Vector3) -> void:
	# The store and the buildings joined to it.
	var g := _group(origin, Rect2(-11.5, -14.5, 44.5, 40.0))
	var st: SurfaceTool = g.st
	var base: float = g.base
	# The main block: a story and a half of brick under a steep gray roof, gable to the front.
	var eave := 5.4
	var ridge := 9.8
	_box(st, g, Vector3(-8, base, -14.5), Vector3(8, eave, 14.5), BRICK)
	_gable_z(st, -8.0, 8.0, -14.5, 14.5, eave, ridge, 0.45, 0.35, SHINGLE, BRICK)
	var front := 14.5
	for x: float in [-1.3, 1.3]:
		_window(st, Vector3(x, 7.7, front), Vector2(0.85, 1.05), Vector3.BACK)
	for x: float in [-4.6, -1.6, 1.6, 4.6]:
		_window(st, Vector3(x, 4.75, front), Vector2(0.9, 0.6), Vector3.BACK)
	_label(g, "KALONA CHEESE", 112, 0.0105, Vector3(0, 6.0, front + 0.03), Vector3.BACK, false)
	for z: float in [-11.0, -6.5, -2.0, 2.5, 7.0, 11.0]:
		_window(st, Vector3(-8.0, 4.8, z), Vector2(0.9, 0.9), Vector3.LEFT)
	for z: float in [-11.0, -6.5]:  # the west wall, ahead of the one-story wing
		_window(st, Vector3(-8.0, 1.8, z), Vector2(1.2, 1.3), Vector3.LEFT)
	for z: float in [6.0, 11.0]:  # the east wall, past the old plant
		_window(st, Vector3(8.0, 4.8, z), Vector2(0.9, 0.9), Vector3.RIGHT)
		_window(st, Vector3(8.0, 1.8, z), Vector2(1.2, 1.3), Vector3.RIGHT)
	for x: float in [-4.0, 0.0, 4.0]:
		_window(st, Vector3(x, 4.8, -14.5), Vector2(0.9, 0.9), Vector3.FORWARD)
		_window(st, Vector3(x, 1.8, -14.5), Vector2(1.2, 1.3), Vector3.FORWARD)

	# The one-story front and its wing along the road side, under the gray mansard.
	var wall := 3.0
	var top := 4.2
	_one_story(st, g, Rect2(-11.5, 14.5, 22.5, 11.0), wall, top, [true, false, false, true])
	_one_story(st, g, Rect2(-11.5, -2.5, 3.5, 17.0), wall, top, [true, false, true, false])
	var face := 25.5
	for x: float in [-7.0, 4.6, 8.0]:
		_window(st, Vector3(x, 1.75, face), Vector2(1.9, 1.7), Vector3.BACK)
	for z: float in [0.0, 4.0, 8.0, 12.0, 17.5, 22.0]:
		_window(st, Vector3(-11.5, 1.75, z), Vector2(1.5, 1.7), Vector3.LEFT)
	# Black double doors (glass: lit at night), and the sign over them.
	_box(st, g, Vector3(-1.25, 0.0, face - 0.05), Vector3(1.25, 2.55, face + 0.08), SIGN_BLACK)
	for x: float in [-0.55, 0.55]:
		_window(st, Vector3(x, 1.2, face + 0.08), Vector2(0.85, 2.0), Vector3.BACK)
	_box(st, g, Vector3(-3.2, 2.7, face + 0.2), Vector3(3.2, 4.55, face + 0.5), SIGN_BLACK)
	_label(g, "KALONA\nCREAMERY", 96, 0.0085, Vector3(0, 3.62, face + 0.52), Vector3.BACK, true)
	# A concrete walk along the front.
	_walk(st, g, -11.5, 32.0, face, face + 3.5)

	# Joined on the right: a concrete-block section, then a brick wing with a garage door.
	_box(st, g, Vector3(11, base, 9.5), Vector3(18, 4.7, 25.5), BLOCK)
	_box(st, g, Vector3(11.2, 4.7, 9.7), Vector3(17.8, 4.8, 25.3), FLAT_ROOF)
	_box(st, g, Vector3(18, base, 9.5), Vector3(32, 4.2, 25.5), BRICK)
	_box(st, g, Vector3(18.2, 4.2, 9.7), Vector3(31.8, 4.3, 25.3), FLAT_ROOF)
	_box(st, g, Vector3(23.0, 0.0, 25.5), Vector3(26.4, 3.2, 25.6), DOOR)
	_window(st, Vector3(29.0, 1.8, 25.5), Vector2(1.4, 1.2), Vector3.BACK)
	# The old plant behind, brick under a tan roof, and its smokestack.
	_box(st, g, Vector3(8, base, -11.5), Vector3(26, 5.0, 2.5), BRICK)
	_gable_x(st, 8.0, 26.0, -11.5, 2.5, 5.0, 7.6, 0.4, TAN_ROOF, BRICK)
	_window(st, Vector3(26.0, 2.0, -4.5), Vector2(1.2, 1.2), Vector3.RIGHT)
	_stack(st, g, Vector3(33.0, 0, 3.5), 0.95, 15.0)
	# A light pole out front.
	_light_pole(st, g, Vector3(-13.5, 0, 29.0))
	_finish(g)

	# The plant: steel silos and two big metal buildings.
	var p := _group(origin, Rect2(26.0, -22.5, 49.0, 37.0))
	st = p.st
	base = p.base
	_box(st, p, Vector3(26, base, -18.5), Vector3(36, 7.0, -1.5), METAL)
	_box(st, p, Vector3(26.2, 7.0, -18.3), Vector3(35.8, 7.1, -1.7), FLAT_ROOF)
	for z: float in [-15.0, -10.0, -5.0]:
		_silo(st, p, Vector3(42.0, 0, z), 2.1, 12.5)
	_box(st, p, Vector3(48, base, -22.5), Vector3(75, 10.0, -4.5), METAL)
	_box(st, p, Vector3(48.2, 10.0, -22.3), Vector3(74.8, 10.1, -4.7), FLAT_ROOF)
	_box(st, p, Vector3(48, base, -1.5), Vector3(75, 6.0, 14.5), METAL)
	_box(st, p, Vector3(48.2, 6.0, -1.3), Vector3(74.8, 6.1, 14.3), FLAT_ROOF)
	for x: float in [54.0, 62.0, 70.0]:
		_box(st, p, Vector3(x - 1.6, 0.0, 14.5), Vector3(x + 1.6, 3.4, 14.6), DOOR)
	for z: float in [-17.0, -10.0]:
		_box(st, p, Vector3(47.9, 0.0, z - 1.8), Vector3(48.0, 4.0, z + 1.8), DOOR)
	_finish(p)


# --- Mid-Prairie High School -----------------------------------------------------------

## Mid-Prairie High School (the Golden Hawks), 1634 Highway 22, a mile east of Wellman: the
## long red-brick school up the slope on the north side of the road, with a parking lot
## and a gray front building between it and the highway.
##
## The main building is turned 23 degrees off the compass, square to its lot: local x runs
## east-northeast along it, local z toward the highway. Two stories of brick with bands of
## windows across the front, a round glass-and-brick entrance between the two halves of
## it, one-story wings round the back and sides, the gym (brick, then tan above) behind
## its lobby, and the greenhouse at the east end. The site falls about 5 m toward the
## road, so each wing stands on the ground at the middle of its front. In front of it are
## the flagpole (the Stars and Stripes over Iowa's flag), the gray front building, the bus
## barn out back, the parking lots and drives down to the road, and the sign by the road.
## Footprints and heights are off the 2019 lidar; the look is off photos.
func _mid_prairie(origin: Vector3, yaw: float) -> void:
	var g := _group(origin, Rect2(-78.0, -32.0, 161.0, 91.0), yaw)
	var st: SurfaceTool = g.st
	# West wing: one story under a gabled roof, its ridge front to back.
	var fl := _ground_y(g, Vector2(-69.0, 16.0))
	_box(st, g, Vector3(-77.0, g.base, -15.0), Vector3(-61.0, fl + 4.0, 17.0), SCHOOL_BRICK)
	_gable_z(st, -77.0, -61.0, -15.0, 17.0, fl + 4.0, fl + 6.0, 0.4, 0.4, SHINGLE, SCHOOL_BRICK)
	for z: float in [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]:
		_window(st, Vector3(-77.0, fl + 1.8, z), Vector2(1.4, 1.5), Vector3.LEFT)
	for x: float in [-73.0, -69.0, -65.0]:
		_window(st, Vector3(x, fl + 1.8, 17.0), Vector2(1.4, 1.5), Vector3.BACK)
	# The two-story front, west half: bands of windows on both floors.
	fl = _wing(st, g, -61.0, -19.0, -25.0, 15.5, 8.0, SCHOOL_BRICK)
	_ribbon(st, -60.0, -26.0, fl + 1.9, 15.5, Vector3.BACK, 1.75)
	_ribbon(st, -60.0, -26.0, fl + 5.6, 15.5, Vector3.BACK, 1.75)
	_ribbon(st, -60.0, -46.0, fl + 5.6, -19.0, Vector3.FORWARD, 1.75)
	_wing(st, g, -45.0, -25.0, -24.0, -19.05, 8.0, SCHOOL_BRICK)
	# The commons behind the entrance, a little taller (its clerestory).
	_wing(st, g, -26.0, -14.0, -12.5, 10.5, 9.6, SCHOOL_BRICK)
	# The two-story front, east half.
	fl = _wing(st, g, -12.5, -12.0, 22.0, 18.5, 8.0, SCHOOL_BRICK)
	_ribbon(st, -11.0, 21.0, fl + 1.9, 18.5, Vector3.BACK, 1.75)
	_ribbon(st, -11.0, 21.0, fl + 5.6, 18.5, Vector3.BACK, 1.75)
	_ribbon_x(st, -11.0, 17.0, fl + 5.6, 22.0, Vector3.RIGHT, 1.75)
	# The round entrance between them: glass round both floors, a canopy over the doors.
	var dfl := _ground_y(g, Vector2(-19.0, 18.0))
	_drum(st, g, Vector2(-19.0, 13.0), 5.6, dfl, 8.8)
	_box(st, g, Vector3(-23.0, dfl + 3.0, 18.4), Vector3(-15.0, dfl + 3.3, 21.6), COPING, false)
	for x: float in [-22.6, -15.4]:
		_box(st, g, Vector3(x - 0.1, dfl - 0.5, 21.2), Vector3(x + 0.1, dfl + 3.0, 21.4), COPING, false)
	# One-story wings round the back and the east end.
	_wing(st, g, -61.0, -31.0, -16.0, -19.05, 4.2, SCHOOL_BRICK)
	_wing(st, g, -26.0, -25.0, 24.0, -12.05, 4.4, SCHOOL_BRICK)
	_wing(st, g, 22.05, -21.0, 57.0, 19.5, 4.3, SCHOOL_BRICK)
	fl = _wing(st, g, 57.05, -17.0, 81.0, 19.5, 5.0, SCHOOL_BRICK)
	_ribbon_x(st, -15.0, 18.0, fl + 1.9, 81.0, Vector3.RIGHT, 3.0)
	_wing(st, g, 57.1, -4.0, 73.0, 4.0, 7.2, TAN_BAND)  # a high bay above it
	# The gym, its lobby in front (glass across it), and the wing east of it.
	fl = _wing(st, g, 21.0, 19.55, 54.0, 48.0, 9.2, SCHOOL_BRICK, 5.0)
	_ribbon(st, 24.0, 51.0, fl + 7.3, 48.0, Vector3.BACK, 4.5, Vector2(2.2, 0.9))
	_ribbon_x(st, 22.0, 46.0, fl + 7.3, 21.0, Vector3.LEFT, 4.5, Vector2(2.2, 0.9))
	fl = _wing(st, g, 17.0, 48.05, 45.0, 57.5, 5.6, SCHOOL_BRICK)
	_ribbon(st, 20.0, 42.0, fl + 2.2, 57.5, Vector3.BACK, 2.2, Vector2(2.0, 3.6))
	_box(st, g, Vector3(26.0, fl + 3.6, 57.5), Vector3(36.0, fl + 3.9, 60.0), COPING, false)
	fl = _wing(st, g, 54.05, 19.55, 82.0, 47.0, 5.2, SCHOOL_BRICK)
	_ribbon_x(st, 22.0, 45.0, fl + 1.9, 82.0, Vector3.RIGHT, 3.0)
	# The greenhouse along the front of the east wing.
	fl = _ground_y(g, Vector2(69.5, 53.5))
	_box(st, g, Vector3(58.0, g.base, 47.05), Vector3(81.0, fl + 2.5, 54.0), GREENHOUSE)
	_gable_x(st, 58.0, 81.0, 47.05, 54.0, fl + 2.5, fl + 3.9, 0.15, GREENHOUSE, GREENHOUSE)
	var x := 58.0
	while x <= 81.01:
		_box(st, g, Vector3(x - 0.06, fl - 0.3, 53.98), Vector3(x + 0.06, fl + 2.5, 54.1), FRAME, false)
		x += 2.3
	_box(st, g, Vector3(57.9, fl + 2.4, 53.98), Vector3(81.1, fl + 2.55, 54.12), FRAME, false)
	# The flagpole on the lawn by the entrance.
	_flagpole(g, Vector2(-31.0, 25.0))
	_finish(g)

	# The gray front building, nearest the road: light gray panels under a dark band, a
	# taller glass entrance with a canopy.
	var f := _group(origin + Vector3(66.5, 0.0, 61.0), Rect2(-26.0, -9.0, 52.0, 20.0))
	st = f.st
	fl = _wing(st, f, -25.5, -8.0, 25.5, 8.0, 4.6, PANEL)
	_box(st, f, Vector3(-25.58, fl + 3.3, -8.08), Vector3(25.58, fl + 4.25, 8.08), PANEL_DARK, false)
	_ribbon(st, -24.0, -6.5, fl + 1.8, 8.0, Vector3.BACK, 3.4, Vector2(2.6, 1.7))
	_ribbon(st, 6.5, 24.0, fl + 1.8, 8.0, Vector3.BACK, 3.4, Vector2(2.6, 1.7))
	_ribbon_x(st, -6.0, 6.0, fl + 1.8, -25.5, Vector3.LEFT, 3.4, Vector2(2.6, 1.7))
	_wing(st, f, 12.0, -8.05, 25.55, 1.0, 5.6, PANEL)
	var ef := _wing(st, f, -5.0, -1.0, 5.0, 8.3, 7.6, PANEL)
	_ribbon(st, -4.4, 4.4, ef + 3.3, 8.3, Vector3.BACK, 2.2, Vector2(2.0, 5.4))
	_box(st, f, Vector3(-4.4, ef + 3.0, 8.3), Vector3(4.4, ef + 3.35, 10.8), PANEL_DARK, false)
	for px: float in [-4.0, 4.0]:
		_box(st, f, Vector3(px - 0.1, ef - 0.5, 10.4), Vector3(px + 0.1, ef + 3.0, 10.6), PANEL_DARK, false)
	_finish(f)

	# The bus barn out back: tan metal, roll-up doors to the south.
	var b := _group(origin + Vector3(2.0, 0.0, -76.5), Rect2(-25.0, -15.5, 50.0, 31.0))
	st = b.st
	fl = _wing(st, b, -25.0, -15.5, 25.0, 15.5, 8.0, TAN_METAL)
	for dx: float in [-17.0, -7.0, 3.0, 13.0]:
		_box(st, b, Vector3(dx - 2.0, fl, 15.5), Vector3(dx + 2.0, fl + 4.2, 15.6), DOOR, false)
	_window(st, Vector3(20.5, fl + 1.8, 15.5), Vector2(1.2, 1.2), Vector3.BACK)
	_finish(b)

	_school_grounds(origin)


## The parking lots, the drive across the front, the two entrances down to the road, the
## lot lights, cars parked for the day and the sign by the road. Square to the compass,
## relative to the school's `origin`.
func _school_grounds(origin: Vector3) -> void:
	var g := _group(origin, Rect2(-145.0, 5.0, 295.0, 110.0))
	var st: SurfaceTool = g.st
	_pave(st, g, Rect2(-60.0, 73.0, 165.0, 9.0))  # across the front
	_pave(st, g, Rect2(99.0, 10.0, 48.0, 63.0))  # the east lot
	_pave(st, g, Rect2(-143.0, 56.0, 83.0, 26.0))  # the west lot
	_entrance(st, g, 97.0, 82.0, 9.0)
	_entrance(st, g, -122.0, 82.0, 9.0)
	for at: Vector2 in [Vector2(123.0, 23.0), Vector2(123.0, 51.0), Vector2(-120.0, 69.0), Vector2(-80.0, 69.0),
			Vector2(20.0, 71.0)]:  # in the aisles
		_lot_light(st, g, at)
	_finish(g)

	# Cars and pickups in rows, nosed in (the same ones every day).
	var rng := RandomNumberGenerator.new()
	rng.seed = 1634
	var cars := SurfaceTool.new()
	var rows: Array = []
	for z: float in [16.0, 30.0, 44.0, 58.0]:  # the east lot, nosed in from the aisles
		rows.append([103.0, 143.0, z, PI if rows.size() % 2 == 0 else 0.0])
	for z: float in [61.0, 77.0]:  # the west lot
		rows.append([-140.0, -64.0, z, 0.0 if z < 70.0 else PI])
	for row: Array in rows:
		var px: float = row[0]
		while px <= float(row[1]):
			if rng.randf() < 0.62:
				var kind := "pickup" if rng.randf() < 0.45 else "car"
				var spot := Vector2(px, float(row[2]))
				var y := _ground_y(g, spot) + 0.06
				var turn := Basis(Vector3.UP, float(row[3]) + rng.randf_range(-0.05, 0.05))
				var xf := Transform3D(turn, Vector3(spot.x, y, spot.y))
				cars.append_from(TrafficModels.build(kind, rng), 0, xf)
				var spec: Dictionary = Traffic.KINDS[kind]
				var half := Vector3(float(spec.width) / 2.0, 0.75, float(spec.length) / 2.0)
				_solid_at(Transform3D(turn, g.at + Vector3(spot.x, y + 0.75, spot.y)), half)
			px += 3.0
	var node := MeshInstance3D.new()
	node.mesh = cars.commit()
	node.material_override = MeshKit.material()
	node.position = g.at
	node.visibility_range_end = 900.0
	add_child(node)

	_school_sign(origin + Vector3(88.0, 0.0, 93.5))


## A flat-roofed wing from (x0, z0) to (x1, z1) (local), `height` tall on its own floor (the
## ground at the middle of its front, toward +z): walls, a dark metal coping round the roof
## and a pale roof inside it. With `band`, the walls are tan from that high up. Returns the
## floor (local y).
func _wing(st: SurfaceTool, g: Dictionary, x0: float, z0: float, x1: float, z1: float, height: float,
		wall: Color, band := 0.0) -> float:
	var fl := _ground_y(g, Vector2((x0 + x1) / 2.0, z1 - 1.0))
	var low := INF
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		low = minf(low, _ground_y(g, c))
	var top := fl + height
	var split := fl + band if band > 0.0 else top - 0.35
	_box(st, g, Vector3(x0, low - 0.3, z0), Vector3(x1, split, z1), wall)
	if band > 0.0:
		_box(st, g, Vector3(x0, split, z0), Vector3(x1, top - 0.35, z1), TAN_BAND)
	_box(st, g, Vector3(x0 - 0.08, top - 0.35, z0 - 0.08), Vector3(x1 + 0.08, top, z1 + 0.08), COPING, false)
	_box(st, g, Vector3(x0 + 0.3, top - 0.1, z0 + 0.3), Vector3(x1 - 0.3, top + 0.04, z1 - 0.3), MEMBRANE, false)
	return fl


## A band of windows across a wall facing +z or -z (at `face`), evenly from x0 to x1.
func _ribbon(st: SurfaceTool, x0: float, x1: float, y: float, face: float, normal: Vector3, pitch: float,
		size := Vector2(1.5, 1.6)) -> void:
	var n := int((x1 - x0) / pitch) + 1
	var first := (x0 + x1) / 2.0 - (n - 1) * pitch / 2.0
	for i in n:
		_window(st, Vector3(first + i * pitch, y, face), size, normal)


## The same on a wall facing +x or -x, from z0 to z1.
func _ribbon_x(st: SurfaceTool, z0: float, z1: float, y: float, face: float, normal: Vector3, pitch: float,
		size := Vector2(1.5, 1.6)) -> void:
	var n := int((z1 - z0) / pitch) + 1
	var first := (z0 + z1) / 2.0 - (n - 1) * pitch / 2.0
	for i in n:
		_window(st, Vector3(face, y, first + i * pitch), size, normal)


## The round entrance: brick between bands of glass round both floors, a flat roof with a
## dark edge. Its back half is inside the building.
func _drum(st: SurfaceTool, g: Dictionary, center: Vector2, radius: float, fl: float, height: float) -> void:
	const SIDES := 16
	var top := fl + height
	var base: float = g.base
	var c := Vector3(center.x, 0.0, center.y)
	for i in SIDES:
		var t0 := TAU * i / SIDES
		var t1 := TAU * (i + 1) / SIDES
		var p0 := c + Vector3(cos(t0), 0.0, sin(t0)) * radius
		var p1 := c + Vector3(cos(t1), 0.0, sin(t1)) * radius
		var out := Vector3(cos((t0 + t1) / 2.0), 0.0, sin((t0 + t1) / 2.0))
		MeshKit.quad(st, p0 + Vector3.UP * base, p1 + Vector3.UP * base, p1 + Vector3.UP * top,
			p0 + Vector3.UP * top, out, SCHOOL_BRICK)
		MeshKit.tri(st, c + Vector3.UP * top, p0 + Vector3.UP * top, p1 + Vector3.UP * top, Vector3.UP, MEMBRANE)
		if out.z < -0.3:
			continue
		var mid := (p0 + p1) / 2.0 + out * 0.03
		var across := (p1 - p0) * 0.47
		for band: Vector2 in [Vector2(fl + 0.4, fl + 3.2), Vector2(fl + 4.4, fl + 7.4)]:
			MeshKit.quad(st, mid - across + Vector3.UP * band.x, mid + across + Vector3.UP * band.x,
				mid + across + Vector3.UP * band.y, mid - across + Vector3.UP * band.y, out, WINDOW)
	MeshKit.cylinder(st, radius + 0.08, 0.35, c + Vector3.UP * (top - 0.17), COPING, COPING, SIDES, Vector3.UP)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = top - base
	_solid(g, c + Vector3.UP * (top + base) / 2.0, Vector3(radius, (top - base) / 2.0, radius), shape)


## The flagpole: the Stars and Stripes over Iowa's flag, standing out a little in the breeze.
func _flagpole(g: Dictionary, at: Vector2) -> void:
	var st: SurfaceTool = g.st
	var y := _ground_y(g, at)
	var foot := Vector3(at.x, y, at.y)
	MeshKit.cylinder(st, 0.09, 12.3, foot + Vector3.UP * 6.0, FLAGPOLE, FLAGPOLE, 8, Vector3.UP)
	MeshKit.box(st, Vector3(0.24, 0.24, 0.24), foot + Vector3.UP * 12.2, GOLD_BALL)
	var pole := CylinderShape3D.new()
	pole.radius = 0.12
	pole.height = 12.3
	_solid(g, foot + Vector3.UP * 6.0, Vector3(0.12, 6.15, 0.12), pole)
	for flag: Array in [["us", 11.6, Vector2(2.4, 1.3)], ["iowa", 9.7, Vector2(1.9, 1.25)]]:
		var node := MeshInstance3D.new()
		node.mesh = _flag_mesh(flag[2])
		node.material_override = _flag_material(flag[0])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.transform = Transform3D(g.basis, g.at + g.basis * (foot + Vector3(0.1, float(flag[1]), 0.0)))
		add_child(node)


## A flag `size` (fly, hoist) hanging off the pole along +x, rippling, its top edge at y = 0.
static func _flag_mesh(size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 6
	for i in STEPS:
		var u0 := float(i) / STEPS
		var u1 := float(i + 1) / STEPS
		var a := Vector3(u0 * size.x, 0.0, sin(u0 * 7.0) * 0.12 * u0)
		var b := Vector3(u1 * size.x, 0.0, sin(u1 * 7.0) * 0.12 * u1)
		var down := Vector3(0.0, -size.y, 0.0)
		for v: Array in [[a, Vector2(u0, 0)], [b, Vector2(u1, 0)], [b + down, Vector2(u1, 1)],
				[a, Vector2(u0, 0)], [b + down, Vector2(u1, 1)], [a + down, Vector2(u0, 1)]]:
			st.set_uv(v[1])
			st.set_normal(Vector3.BACK)
			st.add_vertex(v[0])
	return st.commit()


## The two flags' pictures, drawn small: 13 stripes and a starry canton; Iowa's blue, white
## and red with the eagle's streamer across the middle.
static func _flag_material(which: String) -> StandardMaterial3D:
	var image: Image
	var red := Color(0.72, 0.10, 0.14)
	var blue := Color(0.12, 0.18, 0.42)
	if which == "us":
		image = Image.create(38, 26, false, Image.FORMAT_RGB8)
		for y in 26:
			for x in 38:
				var stripe := red if (y / 2) % 2 == 0 else Color(0.95, 0.95, 0.93)
				image.set_pixel(x, y, stripe)
		for y in 14:
			for x in 16:
				var star := (x % 3 == 1 and y % 3 == 1) or (x % 3 == 2 and y % 3 == 2 and x < 15 and y < 13)
				image.set_pixel(x, y, Color(0.95, 0.95, 0.93) if star else blue)
	else:
		image = Image.create(30, 20, false, Image.FORMAT_RGB8)
		for y in 20:
			for x in 30:
				var c := Color(0.10, 0.25, 0.60) if x < 10 else (Color(0.95, 0.95, 0.93) if x < 20 else Color(0.80, 0.12, 0.14))
				if x >= 11 and x <= 18 and y >= 7 and y <= 11:
					c = Color(0.25, 0.30, 0.55) if y < 10 else Color(0.80, 0.12, 0.14)
				image.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(image)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	return m


## Asphalt over the ground (it follows the slope) across a rectangle, local x/z.
func _pave(st: SurfaceTool, g: Dictionary, area: Rect2) -> void:
	var nx := maxi(1, ceili(area.size.x / 4.0))
	var nz := maxi(1, ceili(area.size.y / 4.0))
	for i in nx:
		for j in nz:
			var corners: Array[Vector3] = []
			for c: Vector2 in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var p := area.position + area.size * c / Vector2(nx, nz)
				corners.append(Vector3(p.x, _ground_y(g, p) + 0.07, p.y))
			MeshKit.quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.UP, ASPHALT)


## A drive `width` wide from (x, z) (local) straight south down to the highway. Across the
## ditch it's built up level with the shoulder, over a culvert, with its sides going down
## into the ditch.
func _entrance(st: SurfaceTool, g: Dictionary, x: float, z: float, width: float) -> void:
	var at: Vector3 = g.at
	var hint := route.nearest_station(at + Vector3(x, 0.0, z), 0.0, 1e9)
	var prev: Array = []
	var dz := 0.0
	while dz < 80.0:
		var row: Array = []
		var reached := false
		for side: float in [-0.5, 0.5]:
			var local := Vector2(x + side * width, z + dz)
			var world := at + Vector3(local.x, 0.0, local.y)
			var s := route.nearest_station(world, hint, 200.0)
			var road := route.position_at(s)
			var lateral := absf((world - road).dot(route.right_at(s)))
			var ground := _ground_y(g, local)
			var y := ground + 0.07
			if lateral < 13.0:  # built up across the ditch to the shoulder
				y = maxf(y, lerpf(road.y - 1.2, road.y - 0.06, clampf((13.0 - lateral) / 6.4, 0.0, 1.0)) - at.y)
			reached = reached or lateral <= RoadMesher.GRAVEL_HALF_WIDTH + 0.1
			row.append(Vector3(local.x, y, local.y))
			row.append(ground)
		if not prev.is_empty():
			MeshKit.quad(st, prev[0], prev[2], row[2], row[0], Vector3.UP, ASPHALT)
			for k: int in [0, 2]:  # the sides, down into the ditch
				var o := Vector3(-1.0 if k == 0 else 1.0, 0.0, 0.0)
				var low_a := minf(float(prev[k + 1]), prev[k].y - 0.1) - 0.3
				var low_b := minf(float(row[k + 1]), row[k].y - 0.1) - 0.3
				MeshKit.quad(st, prev[k], row[k], Vector3(row[k].x, low_b, row[k].z),
					Vector3(prev[k].x, low_a, prev[k].z), o, ASPHALT)
		prev = row
		if reached:
			break
		dz += 1.5


## A parking-lot light on the ground at (x, z): a pole and a lamp lit at night.
func _lot_light(st: SurfaceTool, g: Dictionary, at: Vector2) -> void:
	var y := _ground_y(g, at)
	var foot := Vector3(at.x, y, at.y)
	MeshKit.box(st, Vector3(0.22, 9.0, 0.22), foot + Vector3(0, 4.0, 0), POLE)
	_solid(g, foot + Vector3(0, 4.0, 0), Vector3(0.11, 4.5, 0.11))
	MeshKit.box(st, Vector3(1.2, 0.1, 0.12), foot + Vector3(0.6, 8.4, 0), POLE)
	MeshKit.box(st, Vector3(0.5, 0.18, 0.4), foot + Vector3(1.1, 8.25, 0), LAMP)


## The sign at the east entrance, square to the road so it reads both ways: brick piers,
## a black panel, MID-PRAIRIE HIGH SCHOOL and HOME OF THE GOLDEN HAWKS.
func _school_sign(at: Vector3) -> void:
	var s := route.nearest_station(at, 0.0, 1e9)
	var along := route.tangent_at(s)
	var g := {"st": MeshKit.begin(), "basis": Basis.looking_at(Vector3(along.x, 0.0, along.z), Vector3.UP)}
	g.at = at
	var h := _ground(g, Vector2.ZERO)
	g.at = Vector3(at.x, h if not is_nan(h) else route.position_at(s).y, at.z)
	g.base = -0.6
	var st: SurfaceTool = g.st
	# Local: -z along the road (westbound), x away from it (the sign's width).
	_box(st, g, Vector3(-2.6, -0.6, -0.35), Vector3(-2.0, 2.4, 0.35), SCHOOL_BRICK)
	_box(st, g, Vector3(2.0, -0.6, -0.35), Vector3(2.6, 2.4, 0.35), SCHOOL_BRICK)
	_box(st, g, Vector3(-2.0, -0.6, -0.3), Vector3(2.0, 0.5, 0.3), SCHOOL_BRICK)
	_box(st, g, Vector3(-2.0, 0.5, -0.12), Vector3(2.0, 2.2, 0.12), SIGN_BLACK)
	_box(st, g, Vector3(-2.7, 2.4, -0.42), Vector3(2.7, 2.55, 0.42), SILL, false)
	_finish(g)
	for side: float in [1.0, -1.0]:
		var n := Vector3(0, 0, side)
		_label(g, "MID-PRAIRIE\nHIGH SCHOOL", 72, 0.0072, Vector3(0, 1.62, 0.13 * side), n, false)
		var hawks := Label3D.new()
		hawks.text = "HOME OF THE GOLDEN HAWKS"
		hawks.font_size = 40
		hawks.pixel_size = 0.0058
		hawks.outline_size = 0
		hawks.modulate = GOLD
		hawks.double_sided = false
		hawks.visibility_range_end = LABEL_RANGE
		hawks.position = g.at + g.basis * Vector3(0, 0.82, 0.13 * side)
		hawks.rotation.y = g.basis.get_euler().y + atan2(n.x, n.z)
		add_child(hawks)


## A group of buildings drawn as one mesh, sat on the ground: y = 0 is the ground at the
## middle of `area` (local x/z), and walls start at `base`, below the lowest ground under
## it, so nothing floats on a slope.
## `yaw` turns the group's local axes (like rotation.y): a building that isn't square to the
## compass.
func _group(origin: Vector3, area: Rect2, yaw := 0.0) -> Dictionary:
	var g := {"st": MeshKit.begin(), "at": origin, "basis": Basis(Vector3.UP, yaw)}
	var low := INF
	for corner: Vector2 in [area.position, area.position + Vector2(area.size.x, 0), area.end,
			area.position + Vector2(0, area.size.y)]:
		var h := _ground(g, corner)
		if not is_nan(h):
			low = minf(low, h)
	var floor_y := _ground(g, area.get_center())
	if is_nan(floor_y):
		floor_y = low if not is_inf(low) else route.position_at(route.nearest_station(origin, 0.0, 1e9)).y
	if is_inf(low):
		low = floor_y
	g.at = Vector3(origin.x, floor_y, origin.z)
	g.base = low - floor_y - 0.3
	return g


## The terrain's height (world y, NaN off the map) under a group's local (x, z).
func _ground(g: Dictionary, local: Vector2) -> float:
	var p: Vector3 = g.at + g.basis * Vector3(local.x, 0.0, local.y)
	return route.terrain.height_at(p.x, p.z)


## The same, as a local y (0 where it's missing).
func _ground_y(g: Dictionary, local: Vector2) -> float:
	var h := _ground(g, local)
	return 0.0 if is_nan(h) else h - float(g.at.y)


func _finish(g: Dictionary) -> void:
	var st: SurfaceTool = g.st
	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = Transform3D(g.basis, g.at)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## An axis-aligned box from corner `a` to corner `b` (local); solid unless it's trim.
func _box(st: SurfaceTool, g: Dictionary, a: Vector3, b: Vector3, color: Color, solid := true) -> void:
	var size := (b - a).abs()
	var center := (a + b) / 2.0
	MeshKit.box(st, size, center, color)
	if solid and size.x > 0.5 and size.y > 0.5 and size.z > 0.5:
		_solid(g, center, size / 2.0)


func _solid(g: Dictionary, center: Vector3, half: Vector3, shape: Shape3D = null) -> void:
	_solid_at(Transform3D(g.basis, g.at + g.basis * center), half, shape)


func _solid_at(xf: Transform3D, half: Vector3, shape: Shape3D = null) -> void:
	var cs := CollisionShape3D.new()
	if shape == null:
		var box := BoxShape3D.new()
		box.size = half * 2.0
		shape = box
		_boxes.append([xf, half])
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


## A two-sided roof whose ridge runs north-south, over walls from x0 to x1 and z0 to z1,
## with brick gables at the ends.
func _gable_z(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, eave: float, ridge: float,
		overhang: float, end_overhang: float, roof: Color, wall: Color) -> void:
	var mid := (x0 + x1) / 2.0
	var half := (x1 - x0) / 2.0 + overhang
	var drop := (ridge - eave) * overhang / ((x1 - x0) / 2.0)
	for side: float in [-1.0, 1.0]:
		var e := Vector3(mid + side * half, eave - drop, 0)
		var r := Vector3(mid, ridge, 0)
		var out := Vector3(side * (ridge - eave), (x1 - x0) / 2.0, 0).normalized()
		MeshKit.quad(st, e + Vector3(0, 0, z0 - end_overhang), e + Vector3(0, 0, z1 + end_overhang),
			r + Vector3(0, 0, z1 + end_overhang), r + Vector3(0, 0, z0 - end_overhang), out, roof)
	for z: float in [z0, z1]:
		MeshKit.tri(st, Vector3(x0, eave, z), Vector3(x1, eave, z), Vector3(mid, ridge, z), Vector3(0, 0, signf(z - (z0 + z1) / 2.0)), wall)


## The same with the ridge running east-west.
func _gable_x(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, eave: float, ridge: float,
		overhang: float, roof: Color, wall: Color) -> void:
	var mid := (z0 + z1) / 2.0
	var half := (z1 - z0) / 2.0 + overhang
	var drop := (ridge - eave) * overhang / ((z1 - z0) / 2.0)
	for side: float in [-1.0, 1.0]:
		var e := Vector3(0, eave - drop, mid + side * half)
		var r := Vector3(0, ridge, mid)
		var out := Vector3(0, (z1 - z0) / 2.0, side * (ridge - eave)).normalized()
		MeshKit.quad(st, e + Vector3(x0 - overhang, 0, 0), e + Vector3(x1 + overhang, 0, 0),
			r + Vector3(x1 + overhang, 0, 0), r + Vector3(x0 - overhang, 0, 0), out, roof)
	for x: float in [x0, x1]:
		MeshKit.tri(st, Vector3(x, eave, z0), Vector3(x, eave, z1), Vector3(x, ridge, mid), Vector3(signf(x - (x0 + x1) / 2.0), 0, 0), wall)


## One story of brick, its roof edged with a sloping shingled mansard on the sides in
## `sides` (west, east, north, south), flat behind it.
func _one_story(st: SurfaceTool, g: Dictionary, area: Rect2, wall: float, top: float, sides: Array) -> void:
	var base: float = g.base
	_box(st, g, Vector3(area.position.x, base, area.position.y), Vector3(area.end.x, wall, area.end.y), BRICK)
	var out := 0.3  ## the mansard's foot sticks out past the wall this far...
	var inset := 1.0  ## ...and its top is this far in
	# Where the flat roof's edges are, and where the mansard's foot is, per side.
	var lo := [area.position.x, area.end.x, area.position.y, area.end.y]
	var foot := lo.duplicate()
	var crest := lo.duplicate()
	for i in 4:
		var outward := -1.0 if i % 2 == 0 else 1.0
		if sides[i]:
			foot[i] = lo[i] + outward * out
			crest[i] = lo[i] - outward * inset
	MeshKit.box(st, Vector3(crest[1] - crest[0], top - wall, crest[3] - crest[2]),
		Vector3((crest[0] + crest[1]) / 2.0, (wall + top) / 2.0, (crest[2] + crest[3]) / 2.0), FLAT_ROOF)
	var y0 := wall - 0.1
	# Corners of the foot and the crest, going round: NW, NE, SE, SW.
	var f := [Vector3(foot[0], y0, foot[2]), Vector3(foot[1], y0, foot[2]), Vector3(foot[1], y0, foot[3]), Vector3(foot[0], y0, foot[3])]
	var c := [Vector3(crest[0], top, crest[2]), Vector3(crest[1], top, crest[2]), Vector3(crest[1], top, crest[3]), Vector3(crest[0], top, crest[3])]
	# side index -> the two corners along it, and its outward normal
	var edges := {0: [3, 0, Vector3.LEFT], 1: [1, 2, Vector3.RIGHT], 2: [0, 1, Vector3.FORWARD], 3: [2, 3, Vector3.BACK]}
	for i in 4:
		if not sides[i]:
			continue
		var a: int = edges[i][0]
		var b: int = edges[i][1]
		MeshKit.quad(st, f[a], f[b], c[b], c[a], edges[i][2] + Vector3.UP * 0.8, SHINGLE)
		MeshKit.quad(st, f[a], f[b], f[b] + Vector3(0, -0.12, 0), f[a] + Vector3(0, -0.12, 0), edges[i][2], SHINGLE)


## A flat strip on the ground (a sidewalk), following it.
func _walk(st: SurfaceTool, g: Dictionary, x0: float, x1: float, z0: float, z1: float) -> void:
	var step := (x1 - x0) / ceilf((x1 - x0) / 2.0)
	var x := x0
	while x < x1 - 0.01:
		var corners: Array[Vector3] = []
		for c: Vector2 in [Vector2(x, z0), Vector2(x + step, z0), Vector2(x + step, z1), Vector2(x, z1)]:
			corners.append(Vector3(c.x, _ground_y(g, c) + 0.06, c.y))
		MeshKit.quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.UP, CONCRETE)
		x += step


## A window (dark glass that lights up at night) just proud of a wall facing `normal`,
## with a pale sill under it.
func _window(st: SurfaceTool, center: Vector3, size: Vector2, normal: Vector3) -> void:
	var c := center + normal * 0.03
	var across := Vector3.UP.cross(normal).normalized() * size.x / 2.0
	var up := Vector3.UP * size.y / 2.0
	MeshKit.quad(st, c - across - up, c + across - up, c + across + up, c - across + up, normal, WINDOW)
	MeshKit.box(st, Vector3(size.x + 0.15, 0.08, 0.12) if absf(normal.z) > 0.5 else Vector3(0.12, 0.08, size.x + 0.15),
		c - up + normal * 0.03 - Vector3(0, 0.04, 0), SILL)


## A round steel silo with a cone top.
func _silo(st: SurfaceTool, g: Dictionary, at: Vector3, radius: float, height: float) -> void:
	var base: float = g.base
	var length := height - base
	MeshKit.cylinder(st, radius, length, at + Vector3(0, base + length / 2.0, 0), STEEL, STEEL, 12, Vector3.UP)
	var tip := at + Vector3(0, height + 1.3, 0)
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		var p0 := at + Vector3(cos(a0) * radius, height, sin(a0) * radius)
		var p1 := at + Vector3(cos(a1) * radius, height, sin(a1) * radius)
		MeshKit.tri(st, p0, p1, tip, (p0 + p1) / 2.0 - at - Vector3(0, height - 1.0, 0), METAL)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = length
	_solid(g, at + Vector3(0, base + length / 2.0, 0), Vector3(radius, length / 2.0, radius), shape)


## The brick smokestack, darker at the top.
func _stack(st: SurfaceTool, g: Dictionary, at: Vector3, radius: float, height: float) -> void:
	var base: float = g.base
	var length := height - 1.2 - base
	MeshKit.cylinder(st, radius, length, at + Vector3(0, base + length / 2.0, 0), BRICK, BRICK, 10, Vector3.UP)
	MeshKit.cylinder(st, radius * 0.92, 1.2, at + Vector3(0, height - 0.6, 0), BRICK_DARK, SIGN_BLACK, 10, Vector3.UP)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height - base
	_solid(g, at + Vector3(0, (height + base) / 2.0, 0), Vector3(radius, (height - base) / 2.0, radius), shape)


## A parking-lot light: a pole with a lamp that's lit at night.
func _light_pole(st: SurfaceTool, g: Dictionary, at: Vector3) -> void:
	var pole := Vector3(0.22, 8.5 - g.base, 0.22)
	MeshKit.box(st, pole, at + Vector3(0, (8.5 + g.base) / 2.0, 0), POLE)
	_solid(g, at + Vector3(0, (8.5 + g.base) / 2.0, 0), pole / 2.0)
	MeshKit.box(st, Vector3(1.2, 0.1, 0.12), at + Vector3(0.6, 8.4, 0), POLE)
	MeshKit.box(st, Vector3(0.5, 0.18, 0.4), at + Vector3(1.1, 8.25, 0), LAMP)


## Lettering on a wall, facing `normal`. `lit` for a sign that's lit at night.
func _label(g: Dictionary, text: String, font_size: int, pixel: float, pos: Vector3, normal: Vector3, lit: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = LETTERS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.line_spacing = -8.0
	label.double_sided = false
	label.shaded = not lit
	label.visibility_range_end = LABEL_RANGE
	label.position = g.at + g.basis * pos
	label.rotation.y = g.basis.get_euler().y + atan2(normal.x, normal.z)
	add_child(label)
