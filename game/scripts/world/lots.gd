class_name Lots
extends Node3D
## The parking lots and paved yards round the stores in town (tools/bake_lots.py, the
## route's lots.json): each its outline off the 2015 aerial photos and their color,
## draped over the ground just above it, cut into CELL-sized pieces so they follow the
## terrain's slopes. One mesh per BLOCK of town, out to DRAW_RANGE.

const CELL := 4.0
const LIFT := 0.04  ## over the ground (the car drives on the ground: you don't see the difference)
const BLOCK := 512.0
const DRAW_RANGE := 1300.0
## A photo's color to the pavement's own (as for the roofs: hazy and bright from up there).
const PHOTO_GAMMA := 1.4
const PHOTO_GAIN := 0.85

var route: RouteData
var material: ShaderMaterial
var triangle_count := 0


func setup(r: RouteData) -> void:
	route = r
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/lot.gdshader")
	var by_block := {}
	for lot: Dictionary in r.lots:
		var flat: Array = lot.outline
		var outline := PackedVector2Array()
		for i in flat.size() / 2:
			outline.append(Vector2(flat[i * 2], flat[i * 2 + 1]))
		if outline.size() < 3:
			continue
		var c: Array = lot.color
		var color := Color(pow(float(c[0]) / 255.0, PHOTO_GAMMA), pow(float(c[1]) / 255.0, PHOTO_GAMMA),
			pow(float(c[2]) / 255.0, PHOTO_GAMMA)) * PHOTO_GAIN
		var key := Vector2i(floori(outline[0].x / BLOCK), floori(outline[0].y / BLOCK))
		if not by_block.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_block[key] = st
		_drape(by_block[key], outline, color)
	for key: Vector2i in by_block:
		var st: SurfaceTool = by_block[key]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = DRAW_RANGE
		add_child(node)


## The condition's look: the asphalt's color (wet, snowy) shades every lot's.
func set_look(asphalt: Color, snow: float) -> void:
	material.set_shader_parameter("asphalt", asphalt)
	material.set_shader_parameter("snow", snow)


## A lot's outline cut into cells, each piece laid on the ground.
func _drape(st: SurfaceTool, outline: PackedVector2Array, color: Color) -> void:
	var box := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		box = box.expand(p)
	for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
		for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
			var x0 := cx * CELL
			var z0 := cz * CELL
			var square := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + CELL, z0), Vector2(x0 + CELL, z0 + CELL),
				Vector2(x0, z0 + CELL)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(square, outline):
				var tris := Geometry2D.triangulate_polygon(piece)
				for i in range(0, tris.size(), 3):
					var a := _ground(piece[tris[i]])
					var b := _ground(piece[tris[i + 1]])
					var c := _ground(piece[tris[i + 2]])
					if is_nan(a.y) or is_nan(b.y) or is_nan(c.y):
						continue
					if (b - a).cross(c - a).y > 0.0:  # (facing up: Godot's front faces wind clockwise)
						var t := b
						b = c
						c = t
					for p: Vector3 in [a, b, c]:
						st.set_color(color)
						st.set_normal(Vector3.UP)
						st.add_vertex(p)
					triangle_count += 1


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, route.terrain.height_at(p.x, p.y) + LIFT, p.y)
