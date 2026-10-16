class_name TerrainTiles
extends RefCounted
## Heightmap tiles covering the corridor around the road.
##
## Tile (ix, iz) spans x in [ix * size, (ix + 1) * size] and z likewise. Each tile is a
## grid x grid block of heights, row-major with rows along z. Neighboring tiles share
## their edge vertices, so meshes line up without seams.

var size: float
var grid: int
var step: float
var coords: Array[Vector2i] = []
var stations := PackedFloat32Array()  ## station of the road point nearest each tile
var heights := PackedFloat32Array()
var road_distance := PackedByteArray()  ## meters from the centerline, per vertex
var _by_coord := {}
var _indices := {}  ## vertices per side -> PackedInt32Array


static func load_from(dir: String, desc: Dictionary) -> TerrainTiles:
	var t := TerrainTiles.new()
	t.size = desc.tile_size_m
	t.grid = int(desc.grid)
	t.step = t.size / (t.grid - 1)
	for tile in desc.tiles:
		var c := Vector2i(int(tile[0]), int(tile[1]))
		t._by_coord[c] = t.coords.size()
		t.coords.append(c)
		t.stations.append(tile[2])
	t.heights = FileAccess.get_file_as_bytes(dir.path_join(desc.file)).to_float32_array()
	t.road_distance = FileAccess.get_file_as_bytes(dir.path_join(desc.distance_file))
	var expected := t.coords.size() * t.grid * t.grid
	if t.heights.size() != expected or t.road_distance.size() != expected:
		push_error("terrain data has %d heights, expected %d" % [t.heights.size(), expected])
		return null
	return t


func count() -> int:
	return coords.size()


func tile_center(i: int) -> Vector3:
	return Vector3((coords[i].x + 0.5) * size, 0.0, (coords[i].y + 0.5) * size)


## Height of the rendered ground at (x, z), or NAN outside the corridor.
## Follows the same triangle split as build_mesh, so it matches what you see exactly.
func height_at(x: float, z: float) -> float:
	var c := Vector2i(floori(x / size), floori(z / size))
	if not _by_coord.has(c):
		return NAN
	var base: int = _by_coord[c] * grid * grid
	var fx := (x - c.x * size) / step
	var fz := (z - c.y * size) / step
	var col := mini(int(fx), grid - 2)
	var row := mini(int(fz), grid - 2)
	fx -= col
	fz -= row
	var k := base + row * grid + col
	var h00 := heights[k]
	var h01 := heights[k + 1]
	var h10 := heights[k + grid]
	var h11 := heights[k + grid + 1]
	if fx >= fz:
		return h00 + fx * (h01 - h00) + fz * (h11 - h01)
	return h00 + fz * (h10 - h00) + fx * (h11 - h10)


## Meters from the road centerline at (x, z), to the nearest 8 m grid point
## (255 = far away or outside the corridor).
func road_distance_at(x: float, z: float) -> float:
	var c := Vector2i(floori(x / size), floori(z / size))
	if not _by_coord.has(c):
		return 255.0
	var col := roundi((x - c.x * size) / step)
	var row := roundi((z - c.y * size) / step)
	return road_distance[_by_coord[c] * grid * grid + row * grid + col]


## A tile's mesh. `lod` 1 is the far-away version: every other vertex, each lowered to
## the lowest of its neighbors so it stays under the detailed ground (and the road)
## everywhere. Gaps where it meets a detailed tile show the horizon ground under it,
## which looks the same.
func build_mesh(i: int, lod := 0) -> ArrayMesh:
	var skip := 1 << lod
	var n := (grid - 1) / skip + 1
	var base := i * grid * grid
	var ox := coords[i].x * size
	var oz := coords[i].y * size
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	uvs.resize(n * n)
	for row in n:
		for col in n:
			var fr := row * skip
			var fc := col * skip
			var h := heights[base + fr * grid + fc]
			if lod > 0:
				for dr in range(maxi(fr - skip, 0), mini(fr + skip + 1, grid)):
					for dc in range(maxi(fc - skip, 0), mini(fc + skip + 1, grid)):
						h = minf(h, heights[base + dr * grid + dc])
			verts[row * n + col] = Vector3(ox + fc * step, h, oz + fr * step)
			uvs[row * n + col] = Vector2(road_distance[base + fr * grid + fc], 0.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _grid_indices(n)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Two clockwise triangles per cell, split along the (row, col) -> (row+1, col+1) diagonal.
func _grid_indices(n: int) -> PackedInt32Array:
	if not _indices.has(n):
		var indices := PackedInt32Array()
		for row in n - 1:
			for col in n - 1:
				var a := row * n + col
				var b := a + 1
				var c := a + n
				var d := c + 1
				indices.append_array([a, b, d, a, d, c])
		_indices[n] = indices
	return _indices[n]
