class_name Fields
extends RefCounted
## What's growing where. Farmland is a patchwork of quarter-quarter sections (1/4 mile
## squares) lined up with the real section-line roads, each corn, soybeans, hay or
## pasture. terrain.gdshader paints the same patchwork with the same integer hash, so
## the game logic (corn to plow, where hay bales sit) matches what's drawn.

const FIELD_SIZE := 402.336
const CORN := "corn"
const SOYBEANS := "soybeans"
const HAY := "hay"
const PASTURE := "pasture"

var offset := Vector2.ZERO  ## world x/z of one section corner


func _init(route: RouteData) -> void:
	# IA 1 runs north on a section line, and 540th St is an east-west section line.
	for c in route.crossroads:
		if c.name == "540th St SW":
			var p := route.position_at(c.station)
			offset = Vector2(p.x, p.z)


func crop_at(x: float, z: float) -> String:
	var h := cell_hash(floori((x - offset.x) / FIELD_SIZE), floori((z - offset.y) / FIELD_SIZE))
	if h < 0.45:
		return CORN
	if h < 0.85:
		return SOYBEANS
	if h < 0.93:
		return HAY
	return PASTURE


## 32-bit integer hash of a field cell to [0, 1). Must match cell_hash() in terrain.gdshader.
static func cell_hash(cx: int, cz: int) -> float:
	var h := ((cx * 73856093) ^ (cz * 19349663)) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 0x5bd1e995) & 0xFFFFFFFF
	h ^= h >> 15
	return float(h & 0xFFFFFF) / 16777216.0
