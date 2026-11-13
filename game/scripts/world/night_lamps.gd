class_name NightLamps
extends Node
## The light the lamps throw on the ground at night: a pool under each street light, lot
## light and farm yard light, and the beams of the traffic's headlights down the road.
## Hundreds of real lights would cost the renderer far too much, so the ground's shaders
## draw them (shaders/ground.gdshaderinc, g_lamps): every so often this picks the lamps
## nearest the camera and the nearest vehicles' headlights and hands them over in a small
## texture (the night_lamps shader global, one column per lamp).
##
## The lamps come from the scenery (each farmhouse's yard light), the landmarks (main
## streets' lights, parking lots, Wellman's globes) and the 4-way (which has real lights
## of its own: halos only, no pools).

const MAX_LAMPS := 16  ## columns in the texture
const CELL := 128.0  ## m: the lamps are kept in a grid of these
const REACH := 170.0  ## m from the camera: lamps further off aren't drawn
const REFRESH := 0.12  ## s between picks
const BEAMS := 4  ## of the lamps, at most this many are headlights
const BEAM_REACH := 220.0
## Per kind: the pool's color and strength (linear light), and how far it reaches (m).
const KINDS := {
	"street": [Color(1.0, 0.62, 0.30), 1.1, 22.0],
	"lot": [Color(1.0, 0.66, 0.34), 1.0, 24.0],
	"globe": [Color(1.0, 0.72, 0.42), 0.8, 12.0],
	"yard": [Color(0.78, 0.80, 1.0), 0.30, 15.0],
}
const HEADLIGHT := Color(1.0, 0.92, 0.78)

var camera: Camera3D
var traffic: Traffic
var count := 0  ## lamps handed over at the last pick
var max_lamps := MAX_LAMPS  ## fewer on Low (Main)
var lit := false  ## night
var _grid := {}  ## Vector2i -> Array of [position, kind]
var _image: Image
var _texture: ImageTexture
var _wait := 0.0


func _ready() -> void:
	_image = Image.create_empty(MAX_LAMPS, 3, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("night_lamps", _texture)
	_hand_over(0)


## A lamp `kind` (KINDS) at `at`, its fixture (world).
func add(at: Vector3, kind: String) -> void:
	var c := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append([at, kind])


func add_all(points: PackedVector3Array, kind: String) -> void:
	for p in points:
		add(p, kind)


func lamp_count() -> int:
	var n := 0
	for c in _grid:
		n += _grid[c].size()
	return n


## Night or not: by day nothing's handed over (the shaders skip it all).
func set_lit(on: bool) -> void:
	lit = on
	_wait = 0.0
	if not on:
		_hand_over(0)


func _process(delta: float) -> void:
	if not lit or camera == null:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH
	pick(camera.global_position)


## The nearest lamps and headlights to `focus`, into the texture.
func pick(focus: Vector3) -> void:
	var near: Array = []  # [distance squared, position, kind]
	var r := ceili(REACH / CELL)
	var fc := Vector2i(floori(focus.x / CELL), floori(focus.z / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for lamp: Array in _grid.get(fc + Vector2i(dx, dz), []):
				var d := (lamp[0] as Vector3).distance_squared_to(focus)
				if d < REACH * REACH:
					near.append([d, lamp[0], lamp[1]])
	var beams := _beams(focus)
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for b: Array in beams.slice(0, mini(BEAMS, max_lamps)):
		_set_beam(n, b[1], b[2])
		n += 1
	for lamp: Array in near:
		if n >= max_lamps:
			break
		_set_lamp(n, lamp[1], lamp[2])
		n += 1
	_hand_over(n)


## The traffic's headlights nearest `focus`: [distance squared, front, forward].
func _beams(focus: Vector3) -> Array:
	var out: Array = []
	if traffic == null:
		return out
	for v in traffic.vehicles:
		if v.kind == "buggy" or not is_instance_valid(v.node):
			continue
		var spec: Dictionary = Traffic.KINDS[v.kind]
		var xf := v.node.global_transform
		var front := xf * Vector3(0.0, 0.8, -float(spec.length) / 2.0 + float(spec.center))
		var d := front.distance_squared_to(focus)
		if d < BEAM_REACH * BEAM_REACH:
			var fwd := -xf.basis.z
			out.append([d, front, Vector2(fwd.x, fwd.z).normalized()])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func _set_lamp(i: int, at: Vector3, kind: String) -> void:
	var k: Array = KINDS[kind]
	var c: Color = k[0]
	_image.set_pixel(i, 0, Color(at.x, at.y, at.z, k[2]))
	_image.set_pixel(i, 1, Color(c.r * k[1], c.g * k[1], c.b * k[1], 0.0))
	_image.set_pixel(i, 2, Color(0.0, 0.0, 0.0, 0.0))


func _set_beam(i: int, at: Vector3, forward: Vector2) -> void:
	_image.set_pixel(i, 0, Color(at.x, at.y, at.z, 70.0))
	_image.set_pixel(i, 1, Color(HEADLIGHT.r * 1.4, HEADLIGHT.g * 1.4, HEADLIGHT.b * 1.4, 1.0))
	_image.set_pixel(i, 2, Color(forward.x, forward.y, 0.27, 70.0))  # (spread: tan of half the beam's angle)


func _hand_over(n: int) -> void:
	count = n
	if n > 0:
		_texture.update(_image)
	RenderingServer.global_shader_parameter_set("night_lamp_count", n)
