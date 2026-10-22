class_name HorizonTerrain
extends RefCounted
## Coarse ground out to the horizon, 64 m between vertices, so the world doesn't end
## where the detailed corridor tiles do. The bake keeps it a little under the detailed
## ground and the road everywhere: where both are drawn the detail wins, and past the
## detailed tiles this takes over. Split into square chunks for streaming and culling.

var corner: Vector2  ## game x, z of vertex (0, 0)
var step: float
var cols: int
var rows: int
var chunk: int  ## cells per chunk side
var chunks_x: int
var chunks_z: int
var heights := PackedFloat32Array()  ## rows along z
var road_distance := PackedByteArray()
var _indices := PackedInt32Array()


static func load_from(dir: String, desc: Dictionary) -> HorizonTerrain:
	var h := HorizonTerrain.new()
	h.corner = Vector2(desc.corner[0], desc.corner[1])
	h.step = desc.step_m
	h.cols = int(desc.cols)
	h.rows = int(desc.rows)
	h.chunk = int(desc.chunk)
	h.chunks_x = (h.cols - 1) / h.chunk
	h.chunks_z = (h.rows - 1) / h.chunk
	h.heights = FileAccess.get_file_as_bytes(dir.path_join(desc.file)).to_float32_array()
	h.road_distance = FileAccess.get_file_as_bytes(dir.path_join(desc.distance_file))
	if h.heights.size() != h.cols * h.rows or h.road_distance.size() != h.cols * h.rows:
		push_error("horizon data has %d heights, expected %d" % [h.heights.size(), h.cols * h.rows])
		return null
	return h


func chunk_count() -> int:
	return chunks_x * chunks_z


func chunk_size() -> float:
	return chunk * step


func chunk_center(i: int) -> Vector3:
	var size := chunk_size()
	return Vector3(corner.x + (i % chunks_x + 0.5) * size, 0.0, corner.y + (i / chunks_x + 0.5) * size)


## Height of the coarse ground at (x, z), following the mesh's triangles; NAN outside it.
func height_at(x: float, z: float) -> float:
	var fx := (x - corner.x) / step
	var fz := (z - corner.y) / step
	if fx < 0.0 or fz < 0.0 or fx > cols - 1 or fz > rows - 1:
		return NAN
	var col := mini(int(fx), cols - 2)
	var row := mini(int(fz), rows - 2)
	fx -= col
	fz -= row
	var k := row * cols + col
	var h00 := heights[k]
	var h01 := heights[k + 1]
	var h10 := heights[k + cols]
	var h11 := heights[k + cols + 1]
	if fx >= fz:
		return h00 + fx * (h01 - h00) + fz * (h11 - h01)
	return h00 + fz * (h10 - h00) + fx * (h11 - h10)


func build_mesh(i: int) -> ArrayMesh:
	var n := chunk + 1
	var col0 := (i % chunks_x) * chunk
	var row0 := (i / chunks_x) * chunk
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	uvs.resize(n * n)
	for row in n:
		for col in n:
			var k := (row0 + row) * cols + col0 + col
			verts[row * n + col] = Vector3(corner.x + (col0 + col) * step, heights[k], corner.y + (row0 + row) * step)
			uvs[row * n + col] = Vector2(road_distance[k], 255.0)  # (no yards out here)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _grid_indices(n)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Same winding and diagonal as the corridor tiles.
func _grid_indices(n: int) -> PackedInt32Array:
	if _indices.is_empty():
		for row in n - 1:
			for col in n - 1:
				var a := row * n + col
				var b := a + 1
				var c := a + n
				var d := c + 1
				_indices.append_array([a, b, d, a, d, c])
	return _indices
