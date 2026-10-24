class_name SceneryMeshes
extends RefCounted
## Unit-sized low-poly models for Scenery, scaled per instance: x by the footprint's
## length, z by its width, y by its height; trees by crown diameter and height. Each sits
## on y = 0, centered on x/z. Colors are near white where the instance tints them (walls),
## fixed where they're not (roofs stay dark, windows blue-black), and leaves have alpha 1
## (the shader gives them the season's color); windows have alpha 1/3 and lamps 2/3 (they
## glow at night).

const WALL := Color(1.0, 1.0, 1.0, 0.0)
const TRIM := Color(0.92, 0.92, 0.9, 0.0)
const ROOF_DARK := Color(0.30, 0.29, 0.29, 0.0)
const ROOF_STEEL := Color(0.78, 0.79, 0.80, 0.0)
const WINDOW := Color(0.10, 0.13, 0.22, 0.33)
const LAMP := Color(0.85, 0.85, 0.80, 0.66)
const POLE := Color(0.42, 0.36, 0.28, 0.0)
const DOOR := Color(0.22, 0.20, 0.19, 0.0)
const TRUNK := Color(0.30, 0.22, 0.15, 0.0)


static func build(kind: String, lod: int) -> ArrayMesh:
	var st := MeshKit.begin()
	match kind:
		"house":
			_gabled(st, 0.62, 0.55, ROOF_DARK)
			if lod == 0:
				for x: float in [-0.3, 0.05, 0.3]:
					for side: float in [-1.0, 1.0]:
						_patch(st, Vector3(x, 0.33, side * 0.5), Vector2(0.12, 0.16), Vector3(0, 0, side), WINDOW)
				_patch(st, Vector3(-0.12, 0.17, 0.5), Vector2(0.08, 0.3), Vector3(0, 0, 1), DOOR)
		"barn":
			_gambrel(st)
			if lod == 0:
				_patch(st, Vector3(0.5, 0.2, 0.0), Vector2(0.4, 0.38), Vector3(1, 0, 0), DOOR)
				_patch(st, Vector3(0.5, 0.62, 0.0), Vector2(0.16, 0.12), Vector3(1, 0, 0), DOOR)
		"shed":
			_gabled(st, 0.78, 0.52, ROOF_STEEL)
			if lod == 0:
				_patch(st, Vector3(0.15, 0.32, 0.5), Vector2(0.3, 0.62), Vector3(0, 0, 1), DOOR)
		"bin":
			_bin(st, 12 if lod == 0 else 8)
		"elevator":  # a co-op's leg and headhouse: a tall box, a smaller one on top
			MeshKit.box(st, Vector3(1.0, 0.86, 1.0), Vector3(0, 0.43, 0), WALL)
			MeshKit.box(st, Vector3(0.55, 0.14, 0.7), Vector3(0.1, 0.93, 0), WALL)
			MeshKit.box(st, Vector3(0.58, 0.02, 0.73), Vector3(0.1, 1.0, 0), ROOF_STEEL)
			if lod == 0:
				for y: float in [0.25, 0.5, 0.75]:
					MeshKit.box(st, Vector3(1.01, 0.012, 1.01), Vector3(0, y, 0), TRIM)  # the seams of the slip-formed walls
				_patch(st, Vector3(0.5, 0.06, 0.2), Vector2(0.3, 0.12), Vector3(1, 0, 0), DOOR)
		"tree":
			if lod == 0:
				_prism(st, 0.045, 0.0, 0.42, 4, TRUNK)
				_blob(st, Vector3(0, 0.63, 0), Vector3(0.5, 0.37, 0.5), 7)
			else:
				_blob(st, Vector3(0, 0.6, 0), Vector3(0.5, 0.4, 0.5), 4)
		"yard_light":  # a farm's pole light; the instance is 1 x height x 1
			_prism(st, 0.11, 0.0, 1.0, 4 if lod == 0 else 3, POLE)
			MeshKit.box(st, Vector3(0.7, 0.04, 0.06), Vector3(0.3, 0.97, 0), POLE)
			MeshKit.box(st, Vector3(0.3, 0.12, 0.3), Vector3(0.6, 0.92, 0), LAMP)
		"conifer":
			if lod == 0:
				_prism(st, 0.05, 0.0, 0.16, 4, TRUNK)
				_cone(st, 0.1, 0.62, 0.5, 6, 0.36)
				_cone(st, 0.45, 1.0, 0.34, 6, 0.30)
			else:
				_cone(st, 0.05, 1.0, 0.45, 4, 0.32)
	return MeshKit.finish(st)


## Walls to `eave` and a two-sided roof up to the ridge at 1, overhanging to `half_span`.
static func _gabled(st: SurfaceTool, eave: float, half_span: float, roof: Color) -> void:
	MeshKit.box(st, Vector3(1.0, eave, 1.0), Vector3(0, eave / 2.0, 0), WALL)
	var overhang := 0.52
	for side: float in [-1.0, 1.0]:
		var e := Vector3(0, eave - 0.03, side * half_span)
		var r := Vector3(0, 1.0, 0)
		MeshKit.quad(st, e + Vector3(-overhang, 0, 0), e + Vector3(overhang, 0, 0), r + Vector3(overhang, 0, 0),
			r + Vector3(-overhang, 0, 0), Vector3(0, 1.0 - eave, side * half_span).normalized(), roof)
	for end: float in [-0.5, 0.5]:
		MeshKit.tri(st, Vector3(end, eave, -0.5), Vector3(end, eave, 0.5), Vector3(end, 1.0, 0), Vector3(end, 0, 0), WALL)


## A barn: low walls and a gambrel roof (steep, then shallow) with white trim at the eaves.
static func _gambrel(st: SurfaceTool) -> void:
	var eave := 0.45
	MeshKit.box(st, Vector3(1.0, eave, 1.0), Vector3(0, eave / 2.0, 0), WALL)
	var profile: Array[Vector2] = [Vector2(-0.53, eave - 0.02), Vector2(-0.38, 0.78), Vector2(0.0, 1.0),
		Vector2(0.38, 0.78), Vector2(0.53, eave - 0.02)]
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var out := Vector3(0, b.x - a.x, -(b.y - a.y)).normalized()
		if out.y < 0.0:
			out = -out
		MeshKit.quad(st, Vector3(-0.52, a.y, a.x), Vector3(0.52, a.y, a.x), Vector3(0.52, b.y, b.x),
			Vector3(-0.52, b.y, b.x), out, ROOF_DARK)
	for end: float in [-0.5, 0.5]:
		var o := Vector3(end, 0, 0)
		for i in range(1, profile.size() - 2):
			MeshKit.tri(st, Vector3(end, eave, -0.5), Vector3(end, profile[i].y, profile[i].x),
				Vector3(end, profile[i + 1].y, profile[i + 1].x), o, WALL)
		MeshKit.tri(st, Vector3(end, eave, -0.5), Vector3(end, profile[profile.size() - 2].y, profile[profile.size() - 2].x),
			Vector3(end, eave, 0.5), o, WALL)
		MeshKit.box(st, Vector3(0.02, 0.025, 1.02), Vector3(end, eave, 0), TRIM)


## A round steel grain bin with a cone roof.
static func _bin(st: SurfaceTool, sides: int) -> void:
	var wall := 0.8
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.5
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.5
		var out := (p0 + p1).normalized()
		var shade := Color(ROOF_STEEL, 0.0) if i % 2 == 0 else Color(0.72, 0.73, 0.74, 0.0)
		MeshKit.quad(st, p0, p1, p1 + Vector3.UP * wall, p0 + Vector3.UP * wall, out, shade)
		MeshKit.tri(st, p0 + Vector3.UP * wall, p1 + Vector3.UP * wall, Vector3(0, 1.0, 0),
			out + Vector3.UP * 0.6, ROOF_STEEL)


## An upright n-sided prism (a trunk).
static func _prism(st: SurfaceTool, radius: float, y0: float, y1: float, sides: int, color: Color) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius
		MeshKit.quad(st, p0 + Vector3.UP * y0, p1 + Vector3.UP * y0, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1,
			(p0 + p1).normalized(), color)


## A faceted crown: a ring of `sides` points around the middle, a point on top and one
## below. Face shades vary a little so it reads as leaves, not plastic.
static func _blob(st: SurfaceTool, center: Vector3, half: Vector3, sides: int) -> void:
	var top := center + Vector3(0, half.y, 0)
	var bottom := center - Vector3(0, half.y, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var r0 := center + Vector3(cos(a0) * half.x, 0.1 * half.y * (i % 2), sin(a0) * half.z)
		var r1 := center + Vector3(cos(a1) * half.x, 0.1 * half.y * ((i + 1) % 2), sin(a1) * half.z)
		var out := ((r0 + r1) / 2.0 - center).normalized()
		var g := 0.38 + 0.05 * float(i % 3)
		MeshKit.tri(st, r0, r1, top, out + Vector3.UP, Color(g, g, g, 1.0))
		MeshKit.tri(st, r0, r1, bottom, out - Vector3.UP, Color(g * 0.8, g * 0.8, g * 0.8, 1.0))


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
