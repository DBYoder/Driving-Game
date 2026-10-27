class_name SceneryMeshes
extends RefCounted
## Unit-sized low-poly models for Scenery, scaled per instance: x by the footprint's
## length, z by its width, y by its height; trees by crown diameter and height. Each sits
## on y = 0, centered on x/z.
##
## A building is drawn in two stretches that the shader fits to each one
## (shaders/scenery.gdshader): its walls, y 0 to 1 here, from the ground to the eaves, and
## its roof, y 1 to 2, from the eaves to the ridge. So one model takes every building's
## own roof pitch, from the lidar (a flat roof when the eaves are the ridge). UV.x says
## which part a face is, plus a house's windows' row: they're built for a two-story house,
## and on a one-story one (low eaves) the shader moves the lower row (LOWER_ROW) to the
## middle of the wall and makes it taller, drops the upper row (UPPER_ROW) and brings the
## door and porch (DOOR_ROW) up to suit:
##   WALLS      walls and gable ends; the instance's color tints them
##   ROOF       the roof; the instance's roof color (UV.y a shade), and UV2 the slope as
##              built here (run, rise) for the shader to light it at its real pitch
##   ROOF_TRIM  fascia, barge boards, chimneys, cupolas: fitted with the roof, in their
##              own color (UV2.x, UV2.y, UV.y), not tinted
##   WALL_TRIM  corner boards, door trim, wainscots: fitted with the walls, their own color
## Vertex alpha says what a face is: 0 plain, 1/3 a window (glows at night), 2/3 a lamp,
## 1 leaves (the season's color).

const WALLS := 0.0
const ROOF := 1.0
const ROOF_TRIM := 2.0
const WALL_TRIM := 3.0
const LOWER_ROW := 10.0
const UPPER_ROW := 20.0
const DOOR_ROW := 30.0

const WALL := Color(1.0, 1.0, 1.0, 0.0)
const PLAIN := Color(1.0, 1.0, 1.0, 0.0)  ## trim's vertex color: its color is in the UVs
const TRIM := Color(0.92, 0.92, 0.9, 0.0)
const ROOF_STEEL := Color(0.78, 0.79, 0.80, 0.0)
const WINDOW := Color(0.10, 0.13, 0.22, 0.33)
const LAMP := Color(0.85, 0.85, 0.80, 0.66)
const POLE := Color(0.42, 0.36, 0.28, 0.0)
const DOOR := Color(0.22, 0.20, 0.19, 0.0)
const TRUNK := Color(0.30, 0.22, 0.15, 0.0)
const WHITE := Color(0.93, 0.93, 0.91)
const SOFFIT := Color(0.80, 0.80, 0.78)
const BRICK := Color(0.42, 0.20, 0.15)
const PORCH_ROOF := Color(0.30, 0.29, 0.28)
const WAINSCOT := Color(0.32, 0.31, 0.30)
const SHED_TRIM := Color(0.86, 0.86, 0.85)

## Roof profiles, from the eaves on the +z side up to the ridge (z, y).
const GABLE: Array[Vector2] = [Vector2(0.5, 1.0), Vector2(0.0, 2.0)]
const GAMBREL: Array[Vector2] = [Vector2(0.5, 1.0), Vector2(0.37, 1.6), Vector2(0.0, 2.0)]


static func build(kind: String, lod: int) -> ArrayMesh:
	var st := MeshKit.begin()
	_part(st, WALLS)  # (every vertex has UVs: set before the first one)
	if kind != "tree" and kind != "conifer":
		st.set_smooth_group(-1)  # flat faces: crisp corners (leaves are smoothed: softer)
	match kind:
		"house":
			_house(st, lod)
		"barn":
			_barn(st, lod)
		"shed":
			_shed(st, lod)
		"bin":
			_bin(st, lod)
		"elevator":  # a co-op's leg and headhouse: a tall box, a smaller one on top
			MeshKit.box(st, Vector3(1.0, 0.86, 1.0), Vector3(0, 0.43, 0), WALL)
			MeshKit.box(st, Vector3(0.55, 0.14, 0.7), Vector3(0.1, 0.93, 0), WALL)
			MeshKit.box(st, Vector3(0.58, 0.02, 0.73), Vector3(0.1, 0.99, 0), ROOF_STEEL)
			if lod == 0:
				for y: float in [0.25, 0.5, 0.75]:
					MeshKit.box(st, Vector3(1.01, 0.012, 1.01), Vector3(0, y, 0), TRIM)  # the seams of the slip-formed walls
				_patch(st, Vector3(0.5, 0.06, 0.2), Vector2(0.3, 0.12), Vector3(1, 0, 0), DOOR)
		"tree":
			if lod == 0:
				_prism(st, 0.045, 0.0, 0.42, 3, TRUNK)
				_crown(st, Vector3(0, 0.6, 0), Vector3(0.5, 0.39, 0.5), 6)
			else:
				_blob(st, Vector3(0, 0.6, 0), Vector3(0.5, 0.4, 0.5), 4, 0.125)
		"yard_light":  # a farm's pole light; the instance is 1 x height x 1
			if lod == 0:
				_prism(st, 0.11, 0.0, 1.0, 4, POLE)
				MeshKit.box(st, Vector3(0.7, 0.04, 0.06), Vector3(0.3, 0.97, 0), POLE)
				MeshKit.box(st, Vector3(0.3, 0.12, 0.3), Vector3(0.6, 0.92, 0), LAMP)
			else:  # far off: the pole and the lamp (it glows at night)
				_prism(st, 0.11, 0.0, 0.95, 3, POLE)
				_prism(st, 0.17, 0.88, 0.96, 3, LAMP)
		"conifer":
			if lod == 0:
				_prism(st, 0.05, 0.0, 0.16, 4, TRUNK)
				_cone(st, 0.1, 0.62, 0.5, 6, 0.36)
				_cone(st, 0.45, 1.0, 0.34, 6, 0.30)
			else:
				_cone(st, 0.05, 1.0, 0.45, 4, 0.32)
	return MeshKit.finish(st)


## A farmhouse: gable roof with a little overhang, a chimney, windows (one row or two,
## by the eaves' height), a front door under a porch roof.
static func _house(st: SurfaceTool, lod: int) -> void:
	_walls(st)
	_roof(st, GABLE, 0.05, 0.03, lod == 0, WHITE)
	if lod != 0:
		return
	_corners(st, 0.012, WHITE)
	_part(st, ROOF_TRIM, BRICK)
	MeshKit.box(st, Vector3(0.06, 1.0, 0.09), Vector3(0.31, 1.75, -0.16), PLAIN)  # its foot down in the roof
	# Two rows of windows (one, on a one-story house: see the top), the door and its porch.
	for row: float in [LOWER_ROW, UPPER_ROW]:
		var y := 0.27 if row == LOWER_ROW else 0.72
		_part(st, WALLS + row)
		for x: float in [-0.34, -0.1, 0.12, 0.34]:
			for side: float in [-1.0, 1.0]:
				_patch(st, Vector3(x, y, side * 0.5), Vector2(0.07, 0.22), Vector3(0, 0, side), WINDOW)
		for end: float in [-1.0, 1.0]:
			_patch(st, Vector3(end * 0.5, y, 0.18), Vector2(0.1, 0.22), Vector3(end, 0, 0), WINDOW)
	var porch := 0.4  # the porch roof's height at the wall
	_part(st, WALLS + DOOR_ROW)
	_patch(st, Vector3(-0.22, porch * 0.42, 0.5), Vector2(0.075, porch * 0.84), Vector3(0, 0, 1), DOOR)
	_part(st, WALL_TRIM + DOOR_ROW, PORCH_ROOF)
	var a := Vector3(-0.42, porch, 0.5)
	var b := Vector3(0.0, porch, 0.5)
	var drop := Vector3(0, -porch * 0.12, 0.17)
	MeshKit.quad(st, a, b, b + drop, a + drop, Vector3(0, 1, 0.3), PLAIN)
	MeshKit.quad(st, a, b, b + drop, a + drop, Vector3(0, -1, 0), PLAIN)  # (seen from under it)
	_part(st, WALL_TRIM + DOOR_ROW, WHITE)
	for x: float in [-0.41, -0.01]:
		_prism(st, 0.008, 0.0, porch * 0.88, 4, PLAIN, Vector3(x, 0, 0.66))
	# The gable ends' attic windows (fitted with the roof: none on a flat one).
	_part(st, WALLS)
	for end: float in [-1.0, 1.0]:
		_patch(st, Vector3(end * 0.5, 1.32, 0.0), Vector2(0.08, 0.26), Vector3(end, 0, 0), WINDOW)


## A barn: low walls under a gambrel roof, white trim, big doors in both ends with a hay
## door over one, a cupola on the ridge.
static func _barn(st: SurfaceTool, lod: int) -> void:
	_walls(st)
	_roof(st, GAMBREL, 0.03, 0.02, lod == 0, WHITE)
	if lod != 0:
		_patch(st, Vector3(0.5, 0.36, 0.0), Vector2(0.38, 0.72), Vector3(1, 0, 0), DOOR)
		return
	_corners(st, 0.01, WHITE)
	for end: float in [-1.0, 1.0]:
		var n := Vector3(end, 0, 0)
		_part(st, WALLS)
		_patch(st, Vector3(end * 0.5, 0.38, 0.0), Vector2(0.38, 0.76), n, Color(0.7, 0.7, 0.7, 0.0))
		_part(st, WALL_TRIM, WHITE)
		_frame(st, Vector3(end * 0.5, 0.38, 0.0), Vector2(0.38, 0.76), n, 0.022, true)
	_part(st, WALLS)
	_patch(st, Vector3(0.5, 1.28, 0.0), Vector2(0.16, 0.3), Vector3(1, 0, 0), DOOR)
	_part(st, ROOF_TRIM, WHITE)
	_frame(st, Vector3(0.5, 1.28, 0.0), Vector2(0.16, 0.3), Vector3(1, 0, 0), 0.02, false)
	_part(st, WALLS)
	for x: float in [-0.36, -0.12, 0.12, 0.36]:
		for side: float in [-1.0, 1.0]:
			_patch(st, Vector3(x, 0.62, side * 0.5), Vector2(0.035, 0.16), Vector3(0, 0, side), WINDOW)
	# The cupola: a little white box with a roof, astride the ridge.
	_part(st, ROOF_TRIM, WHITE)
	MeshKit.box(st, Vector3(0.05, 0.4, 0.11), Vector3(0, 2.05, 0), PLAIN)
	_part(st, ROOF_TRIM, Color(0.35, 0.36, 0.37))
	MeshKit.box(st, Vector3(0.065, 0.05, 0.14), Vector3(0, 2.27, 0), PLAIN)
	_part(st, ROOF_TRIM, Color(0.12, 0.12, 0.13))
	for side: float in [-1.0, 1.0]:
		_patch(st, Vector3(0, 2.12, side * 0.055), Vector2(0.03, 0.14), Vector3(0, 0, side), PLAIN)


## A steel machine shed: low-pitch roof, a dark wainscot, a big sliding door on the long
## side, an overhead door in the end, a walk door.
static func _shed(st: SurfaceTool, lod: int) -> void:
	_walls(st)
	_roof(st, GABLE, 0.02, 0.015, lod == 0, SHED_TRIM)
	_part(st, WALLS)
	_patch(st, Vector3(-0.05, 0.42, 0.5), Vector2(0.32, 0.84), Vector3(0, 0, 1), Color(0.8, 0.8, 0.8, 0.0))
	if lod != 0:
		return
	_patch(st, Vector3(0.5, 0.38, 0.0), Vector2(0.42, 0.74), Vector3(1, 0, 0), Color(0.86, 0.86, 0.86, 0.0))
	_patch(st, Vector3(0.32, 0.25, 0.5), Vector2(0.04, 0.5), Vector3(0, 0, 1), DOOR)
	_part(st, WALL_TRIM, WAINSCOT)
	for side: float in [-1.0, 1.0]:
		_band(st, Vector3(0, 0, side), 0.0, 0.16, 0.002)
		_band(st, Vector3(side, 0, 0), 0.0, 0.16, 0.002)
	_part(st, WALL_TRIM, SHED_TRIM)
	_frame(st, Vector3(-0.05, 0.42, 0.5), Vector2(0.32, 0.84), Vector3(0, 0, 1), 0.012, false)
	_frame(st, Vector3(0.5, 0.38, 0.0), Vector2(0.42, 0.74), Vector3(1, 0, 0), 0.012, false)
	_corners(st, 0.008, SHED_TRIM)


## A round steel grain bin with a cone roof: ring seams, a concrete footing, the vent on
## top. (All under y = 1: a bin has no roof stretch.)
static func _bin(st: SurfaceTool, lod: int) -> void:
	var sides := 14 if lod == 0 else 8
	var wall := 0.78
	var rings := 4 if lod == 0 else 1
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.5
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.5
		var out := (p0 + p1).normalized()
		st.set_smooth_group(1)  # the round wall smooth, apart from the roof
		for r in rings:
			var y0 := wall * r / rings
			var y1 := wall * (r + 1) / rings
			var shade := (0.8 if i % 2 == 0 else 0.74) - 0.03 * float(r % 2)
			MeshKit.quad(st, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1,
				out, Color(shade, shade + 0.01, shade + 0.02, 0.0))
		st.set_smooth_group(2)
		MeshKit.tri(st, p0 + Vector3.UP * wall, p1 + Vector3.UP * wall, Vector3(0, 0.95, 0),
			out + Vector3.UP * 0.6, ROOF_STEEL)
		st.set_smooth_group(-1)
		if lod == 0:
			MeshKit.quad(st, p0 * 1.04, p1 * 1.04, p1 * 1.04 + Vector3.UP * 0.03, p0 * 1.04 + Vector3.UP * 0.03,
				out, Color(0.6, 0.59, 0.57, 0.0))  # the footing
	if lod == 0:
		_prism(st, 0.07, 0.92, 0.975, 6, Color(0.7, 0.71, 0.72, 0.0))
		for i in 6:  # its cap
			var p0 := Vector3(cos(TAU * i / 6.0), 0, sin(TAU * i / 6.0)) * 0.09 + Vector3.UP * 0.975
			var p1 := Vector3(cos(TAU * (i + 1) / 6.0), 0, sin(TAU * (i + 1) / 6.0)) * 0.09 + Vector3.UP * 0.975
			MeshKit.tri(st, p0, p1, Vector3(0, 1.0, 0), (p0 + p1) * Vector3(1, 0, 1) + Vector3.UP * 0.3, ROOF_STEEL)


## The four walls, the ground to the eaves (no top: the roof covers it; no bottom).
static func _walls(st: SurfaceTool) -> void:
	_part(st, WALLS)
	for side: float in [-1.0, 1.0]:
		MeshKit.quad(st, Vector3(-0.5, 0, side * 0.5), Vector3(0.5, 0, side * 0.5), Vector3(0.5, 1, side * 0.5),
			Vector3(-0.5, 1, side * 0.5), Vector3(0, 0, side), WALL)
		MeshKit.quad(st, Vector3(side * 0.5, 0, -0.5), Vector3(side * 0.5, 0, 0.5), Vector3(side * 0.5, 1, 0.5),
			Vector3(side * 0.5, 1, -0.5), Vector3(side, 0, 0), WALL)


## A roof along x of `profile` both sides of the ridge, out past the walls by `eaves`
## (z) and `ends` (x), the gable ends' walls under it, and with `trim` a fascia along the
## eaves, a soffit under them and barge boards up the ends.
static func _roof(st: SurfaceTool, profile: Array[Vector2], eaves: float, ends: float, trim: bool, trim_color: Color) -> void:
	var thick := 0.06  # the fascia's and barge boards' depth, in the roof's height
	var x0 := -0.5 - ends
	var x1 := 0.5 + ends
	for side: float in [-1.0, 1.0]:
		for i in profile.size() - 1:
			var a := profile[i]
			var b := profile[i + 1]
			if i == 0:  # out over the eaves, on down the same slope
				a += (a - b) * (eaves / (a.x - b.x))
			var out := Vector3(0, a.x - b.x, side * (b.y - a.y)).normalized()
			_part(st, ROOF, Color(1, 1, 1), Vector2(a.x - b.x, b.y - a.y))
			MeshKit.quad(st, Vector3(x0, a.y, side * a.x), Vector3(x1, a.y, side * a.x), Vector3(x1, b.y, side * b.x),
				Vector3(x0, b.y, side * b.x), out, WALL)
			if trim:
				_part(st, ROOF_TRIM, trim_color)
				for end: float in [-1.0, 1.0]:
					var x := end * (0.5 + ends)
					MeshKit.quad(st, Vector3(x, a.y, side * a.x), Vector3(x, b.y, side * b.x), Vector3(x, b.y - thick, side * b.x),
						Vector3(x, a.y - thick, side * a.x), Vector3(end, 0, 0), PLAIN)
				if i == 0:
					MeshKit.quad(st, Vector3(x0, a.y, side * a.x), Vector3(x1, a.y, side * a.x), Vector3(x1, a.y - thick, side * a.x),
						Vector3(x0, a.y - thick, side * a.x), Vector3(0, 0, side), PLAIN)
					_part(st, ROOF_TRIM, SOFFIT)
					MeshKit.quad(st, Vector3(x0, a.y - thick, side * a.x), Vector3(x1, a.y - thick, side * a.x),
						Vector3(x1, a.y - thick, side * 0.5), Vector3(x0, a.y - thick, side * 0.5), Vector3.DOWN, PLAIN)
		# The gable end walls, up under the roof.
		_part(st, WALLS)
		for end: float in [-1.0, 1.0]:
			for i in profile.size() - 1:
				var a := profile[i]
				var b := profile[i + 1]
				MeshKit.tri(st, Vector3(end * 0.5, 1.0, 0.0), Vector3(end * 0.5, a.y, side * a.x), Vector3(end * 0.5, b.y, side * b.x),
					Vector3(end, 0, 0), WALL)
	_part(st, WALLS)


## White boards up the four corners.
static func _corners(st: SurfaceTool, w: float, color: Color) -> void:
	_part(st, WALL_TRIM, color)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * 0.5, 0.5, sz * 0.5)
			_patch(st, c + Vector3(-sx * w / 2.0, 0, 0), Vector2(w, 1.0), Vector3(0, 0, sz), PLAIN)
			_patch(st, c + Vector3(0, 0, -sz * w / 2.0), Vector2(w, 1.0), Vector3(sx, 0, 0), PLAIN)
	_part(st, WALLS)


## A frame of boards around a door (and an X across it, for a barn's).
static func _frame(st: SurfaceTool, center: Vector3, size: Vector2, normal: Vector3, w: float, cross: bool) -> void:
	var across := Vector3.UP.cross(normal).normalized()
	var c := center + normal * 0.002
	for s: float in [-1.0, 1.0]:
		_patch(st, c + across * s * (size.x / 2.0), Vector2(w, size.y + w), normal, PLAIN)
		_patch(st, c + Vector3.UP * s * (size.y / 2.0), Vector2(size.x + w, w * 1.4), normal, PLAIN)
	if not cross:
		return
	var p := c + normal * 0.006  # (over the frame, which is over the door)
	for s: float in [-1.0, 1.0]:
		var a := p - across * (size.x / 2.0) - Vector3.UP * s * (size.y / 2.0)
		var b := p + across * (size.x / 2.0) + Vector3.UP * s * (size.y / 2.0)
		var side := (b - a).cross(normal).normalized() * w / 2.0
		MeshKit.quad(st, a - side, b - side, b + side, a + side, normal, PLAIN)


## A band around a wall from y0 to y1 (a wainscot), just proud of it.
static func _band(st: SurfaceTool, normal: Vector3, y0: float, y1: float, proud: float) -> void:
	var across := Vector3.UP.cross(normal).normalized()
	var c := normal * (0.5 + proud)
	MeshKit.quad(st, c - across * 0.5 + Vector3.UP * y0, c + across * 0.5 + Vector3.UP * y0, c + across * 0.5 + Vector3.UP * y1,
		c - across * 0.5 + Vector3.UP * y1, normal, PLAIN)


## What the vertices after this are (see the top): the part, and its color or shade
## (`color.b` and UV2 = (color.r, color.g) for trim, `color.r` for a roof, with the
## slope in `slope`).
static func _part(st: SurfaceTool, part: float, color := Color.WHITE, slope := Vector2.ZERO) -> void:
	var trim := fmod(part, 10.0) >= ROOF_TRIM
	st.set_uv(Vector2(part, color.b if trim else color.r))
	st.set_uv2(Vector2(color.r, color.g) if trim else slope)


## An upright n-sided prism (a trunk, a post), open at the ends.
static func _prism(st: SurfaceTool, radius: float, y0: float, y1: float, sides: int, color: Color,
		at := Vector3.ZERO) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius
		MeshKit.quad(st, at + p0 + Vector3.UP * y0, at + p1 + Vector3.UP * y0, at + p1 + Vector3.UP * y1,
			at + p0 + Vector3.UP * y1, (p0 + p1).normalized(), color)


## A faceted crown: a ring of `sides` points around the middle, a point on top and one
## below. Face shades vary a little so it reads as leaves, not plastic; lighter on top.
static func _blob(st: SurfaceTool, center: Vector3, half: Vector3, sides: int, turn: float) -> void:
	var top := center + Vector3(0, half.y, 0)
	var bottom := center - Vector3(0, half.y * 0.9, 0)
	for i in sides:
		var a0 := TAU * (i + turn) / sides
		var a1 := TAU * (i + 1 + turn) / sides
		var r0 := center + Vector3(cos(a0) * half.x, 0.1 * half.y * (i % 2), sin(a0) * half.z)
		var r1 := center + Vector3(cos(a1) * half.x, 0.1 * half.y * ((i + 1) % 2), sin(a1) * half.z)
		var out := ((r0 + r1) / 2.0 - center).normalized()
		var g := 0.40 + 0.05 * float(i % 3)
		MeshKit.tri(st, r0, r1, top, out + Vector3.UP, Color(g, g, g, 1.0))
		MeshKit.tri(st, r0, r1, bottom, out - Vector3.UP, Color(g * 0.72, g * 0.72, g * 0.72, 1.0))


## A rounded crown: a ring around its widest, a smaller one up toward the top (turned
## half a step, so the facets interleave), a low dome on top and a shallow one below.
## Lighter up top, darker underneath, a little lumpy.
static func _crown(st: SurfaceTool, center: Vector3, half: Vector3, sides: int) -> void:
	var mid: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 0.5) / sides
		var lump := 1.0 - 0.1 * float(i % 3 == 1)
		mid.append(center + Vector3(cos(a) * half.x * lump, -0.1 * half.y + 0.08 * half.y * (i % 2), sin(a) * half.z * lump))
		upper.append(center + Vector3(cos(b) * half.x * 0.74, 0.55 * half.y, sin(b) * half.z * 0.74))
	var top := center + Vector3(0, half.y, 0)
	var bottom := center - Vector3(0, half.y * 0.55, 0)
	for i in sides:
		var j := (i + 1) % sides
		var g := 0.42 + 0.04 * float(i % 3)
		var out := (mid[i] + mid[j]) / 2.0 - center
		MeshKit.tri(st, upper[i], upper[j], top, out + Vector3.UP * 2.0, Color(g * 1.08, g * 1.08, g * 1.08, 1.0))
		MeshKit.tri(st, mid[i], mid[j], upper[i], out + Vector3.UP * 0.6, Color(g, g, g, 1.0))
		MeshKit.tri(st, upper[i], mid[j], upper[j], out + Vector3.UP * 0.8, Color(g, g, g, 1.0))
		MeshKit.tri(st, mid[i], mid[j], bottom, out - Vector3.UP, Color(g * 0.7, g * 0.7, g * 0.7, 1.0))


## A cone of leaves (needles) from y0 up to a point at y1 (open underneath: you can't
## see in there).
static func _cone(st: SurfaceTool, y0: float, y1: float, radius: float, sides: int, shade: float) -> void:
	var tip := Vector3(0, y1, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		var g := shade + 0.04 * float(i % 2)
		MeshKit.tri(st, p0, p1, tip, (p0 + p1) / 2.0 - Vector3(0, y0, 0) + Vector3.UP * 0.4, Color(g, g, g, 1.0))


## A flat rectangle (window, door) just proud of a wall facing `normal`.
static func _patch(st: SurfaceTool, center: Vector3, size: Vector2, normal: Vector3, color: Color) -> void:
	var c := center + normal * 0.004
	var across := Vector3.UP.cross(normal).normalized() * size.x / 2.0
	var up := Vector3.UP * size.y / 2.0
	MeshKit.quad(st, c - across - up, c + across - up, c + across + up, c - across + up, normal, color)
