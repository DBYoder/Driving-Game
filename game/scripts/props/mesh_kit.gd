class_name MeshKit
extends RefCounted
## Builds low-poly, vertex-colored meshes out of boxes and cylinders. One material
## (vertex colors) per mesh keeps props cheap to draw and easy to instance.
## Every triangle is oriented against an outward direction, so faces are always
## front-facing from outside (Godot's front faces wind clockwise).


static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


## `flat`: every face its own normal (crisp corners: buildings, signs, boxes); otherwise
## faces meeting at a vertex share one (soft: car bodies, animals, round bales).
static func begin(flat := false) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat:
		st.set_smooth_group(-1)
	return st


static func finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh


## A box, optionally rotated about Y.
static func box(st: SurfaceTool, size: Vector3, center: Vector3, color: Color, yaw := 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := size / 2.0
	for axis in 3:
		for side in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var face := n * h[axis]
			var du := u * h[(axis + 1) % 3]
			var dv := v * h[(axis + 2) % 3]
			var corners := [face - du - dv, face + du - dv, face + du + dv, face - du + dv]
			for i in 4:
				corners[i] = center + basis * corners[i]
			quad(st, corners[0], corners[1], corners[2], corners[3], basis * n, color)


## A cylinder along an axis (default X), flat-shaded with `sides` faces.
static func cylinder(st: SurfaceTool, radius: float, length: float, center: Vector3, color: Color,
		end_color: Color, sides := 10, axis := Vector3.RIGHT) -> void:
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.FORWARD).normalized()
	var v := a.cross(u)
	var half := a * length / 2.0
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var r0 := (u * cos(t0) + v * sin(t0)) * radius
		var r1 := (u * cos(t1) + v * sin(t1)) * radius
		var out := (r0 + r1).normalized()
		quad(st, center - half + r0, center - half + r1, center + half + r1, center + half + r0, out, color)
		tri(st, center - half, center - half + r0, center - half + r1, -a, end_color)
		tri(st, center + half, center + half + r0, center + half + r1, a, end_color)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
	tri(st, a, b, c, outward, color)
	tri(st, a, c, d, outward, color)


## One flat-shaded triangle, wound so its front faces `outward`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	# Godot front faces are clockwise from the viewer, i.e. (b-a)x(c-a) points away from them.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_color(color)
		st.add_vertex(p)
