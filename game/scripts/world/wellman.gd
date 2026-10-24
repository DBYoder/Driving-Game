class_name WellmanLandmarks
extends RefCounted
## Wellman, at Highway 22's finish, built out from the 2015 USGS aerial photo and the 2019
## lidar (data/routes/highway22/landmarks.json):
## - Downtown: the block of 8th Ave S between 3rd St and 2nd St (one-way, downhill) and the
##   storefronts north of 3rd St. Every building is at its measured spot, width, height
##   and depth (the lidar's roof heights along each side of the street): brick fronts of
##   one and two stories, plate-glass shop windows, sign bands, awnings, the upper
##   floors' windows and cornices. The signs are what a small Iowa main street has, not
##   the real shops' names (no photo of them to go by). Sidewalks, angle parking with the
##   day's cars, and lamp posts lit at night.
## - The water tower, north of IA 22: a tank 12 m across, 41 m to the top of its roof, on
##   four braced legs (the lidar's points: the tank's ring and top, the legs and their
##   struts on the side the plane saw), WELLMAN across it.
## Built with the Landmarks node's helpers and material, like its others.

## The fronts: reds and browns of brick, the buff of the newer ones, a painted one.
const BRICKS: Array[Color] = [Color(0.62, 0.25, 0.18, 0.0), Color(0.48, 0.20, 0.15, 0.0), Color(0.72, 0.58, 0.42, 0.0),
	Color(0.80, 0.71, 0.55, 0.0), Color(0.56, 0.36, 0.26, 0.0), Color(0.86, 0.84, 0.76, 0.0), Color(0.66, 0.31, 0.21, 0.0)]
const SIGN_COLORS: Array[Color] = [Color(0.10, 0.22, 0.14, 0.0), Color(0.42, 0.08, 0.08, 0.0), Color(0.10, 0.14, 0.30, 0.0),
	Color(0.08, 0.08, 0.08, 0.0), Color(0.36, 0.26, 0.14, 0.0)]
const AWNINGS: Array[Color] = [Color(0.16, 0.38, 0.22, 0.0), Color(0.60, 0.12, 0.12, 0.0), Color(0.13, 0.20, 0.38, 0.0),
	Color(0.62, 0.52, 0.36, 0.0), Color(0.12, 0.12, 0.12, 0.0)]
const SHOPS := ["CAFE", "HARDWARE", "BANK", "PHARMACY", "BARBER", "INSURANCE", "TAVERN", "FLOWERS", "ANTIQUES",
	"BAKERY", "GIFTS", "PIZZA", "LAW OFFICE", "SALON", "QUILTS", "FURNITURE", "VARIETY", "REALTY", "DINER",
	"AUTO PARTS", "LIBRARY", "CITY HALL"]
const BAY := 7.5  ## a storefront's width: 25 feet, the old lots
const SIDEWALK := 3.0
const CURB := 0.15
const STALL := 3.1  ## along the curb, for 60-degree angle parking
const LAMP_EVERY := 24.0
const POST := Color(0.10, 0.16, 0.12, 0.0)  ## the lamp posts' dark green
const STRIPE := Color(0.92, 0.92, 0.88, 0.0)
const KICK := Color(0.20, 0.20, 0.21, 0.0)  ## under the shop windows
const TOWER := Color(0.86, 0.90, 0.93, 0.0)  ## the water tower's pale blue-white
const TOWER_LETTERS := Color(0.10, 0.20, 0.42)

var lm: Landmarks


func _init(landmarks: Landmarks) -> void:
	lm = landmarks


## The storefronts, both sides, and the street between them.
func downtown(l: Dictionary) -> void:
	var n := 0
	for i in 2:
		var side: String = ["west", "east"][i]
		var front := float(l.fronts[i])
		var out := 1.0 if i == 0 else -1.0  # toward the street: east from the west side
		for seg: Array in l[side]:
			storefront(front, out, float(seg[0]), float(seg[1]), float(seg[2]), float(seg[3]), n)
			n += 1
	_street(l)


## One building: its front on the sidewalk at x = `front`, facing the street (`out`: +1
## east, -1 west), from z0 to z1, `height` tall at its front and `depth` deep. It stands on
## the sidewalk at the middle of its front (the street runs downhill), its walls running
## down to the lowest of its corners.
func storefront(front: float, out: float, z0: float, z1: float, height: float, depth: float, n: int) -> void:
	var width := z1 - z0
	var g := lm._group(Vector3(front - out * depth / 2.0, 0.0, (z0 + z1) / 2.0), Rect2(-depth / 2.0, -width / 2.0, depth, width))
	var fl := lm._ground_y(g, Vector2(out * depth / 2.0, 0.0))
	g.at.y += fl
	g.base -= fl
	var st: SurfaceTool = g.st
	var fx := out * depth / 2.0  # the front wall
	var normal := Vector3(out, 0.0, 0.0)
	var brick: Color = BRICKS[_pick(n, 1, BRICKS.size())]
	var trim := brick.darkened(0.35)
	lm._box(st, g, Vector3(-depth / 2.0, g.base, -width / 2.0), Vector3(depth / 2.0, height, width / 2.0), brick)
	# A flat roof inside the parapet, and the cornice along the top of the front.
	MeshKit.box(st, Vector3(depth - 0.7, 0.06, width - 0.7), Vector3(0.0, height + 0.02, 0.0), Landmarks.MEMBRANE)
	var cornice := 0.7 if height >= 7.0 else 0.35
	MeshKit.box(st, Vector3(0.36, cornice, width + 0.1), Vector3(fx + out * 0.14, height - cornice / 2.0, 0.0), trim)
	var bays := maxi(1, roundi(width / BAY))
	var bay := width / bays
	for b in bays + 1:  # pilasters between the shops
		var pz := -width / 2.0 + bay * b
		MeshKit.box(st, Vector3(0.14, height - cornice - g.base, 0.45), Vector3(fx + out * 0.07, (height - cornice + g.base) / 2.0, pz), trim)
	for b in bays:
		var k := n * 5 + b
		var zc := -width / 2.0 + bay * (b + 0.5)
		var door_side := 1.0 if _pick(k, 2, 2) == 0 else -1.0
		var glass := maxf(bay - 2.6, 1.2)
		var gz := zc - door_side * 0.6
		lm._window(st, Vector3(fx, 1.8, gz), Vector2(glass, 2.3), normal)
		MeshKit.box(st, Vector3(0.1, 0.6, glass), Vector3(fx + out * 0.05, 0.3, gz), KICK)
		var dz := zc + door_side * (bay / 2.0 - 0.95)
		MeshKit.quad(st, Vector3(fx + out * 0.03, 0.0, dz - 0.5), Vector3(fx + out * 0.03, 0.0, dz + 0.5),
			Vector3(fx + out * 0.03, 2.3, dz + 0.5), Vector3(fx + out * 0.03, 2.3, dz - 0.5), normal, Landmarks.WINDOW)
		# The sign band over the windows, mostly with a sign on it.
		var band: Color = SIGN_COLORS[_pick(k, 3, SIGN_COLORS.size())]
		MeshKit.box(st, Vector3(0.12, 0.85, bay - 0.6), Vector3(fx + out * 0.06, 3.65, zc), band)
		if _pick(k, 4, 6) != 0:
			lm._label(g, SHOPS[_pick(k, 5, SHOPS.size())], 40, 0.012, Vector3(fx + out * 0.14, 3.65, zc), normal, false)
		if _pick(k, 6, 5) < 2:
			_awning(st, fx, out, zc, bay - 0.8, AWNINGS[_pick(k, 7, AWNINGS.size())])
		if height >= 7.0:  # the upper floor's windows
			var count := maxi(2, roundi((bay - 1.0) / 2.3))
			var wy := minf(4.9 + (height - cornice - 4.9) / 2.0, height - cornice - 1.1)
			for w in count:
				var wz := zc - bay / 2.0 + bay * (w + 0.5) / count
				lm._window(st, Vector3(fx, wy, wz), Vector2(1.0, 1.7), normal)
	lm._finish(g)


## A shop's awning over its windows: sloping out from under the sign band, with a valance.
func _awning(st: SurfaceTool, fx: float, out: float, zc: float, width: float, color: Color) -> void:
	var top := 3.15
	var low := 2.55
	var reach := 1.5
	var a := Vector3(fx, top, zc - width / 2.0)
	var b := Vector3(fx, top, zc + width / 2.0)
	var c := Vector3(fx + out * reach, low, zc + width / 2.0)
	var d := Vector3(fx + out * reach, low, zc - width / 2.0)
	MeshKit.quad(st, a, b, c, d, Vector3(out * 0.37, 0.93, 0.0), color)
	MeshKit.quad(st, d, c, c - Vector3(0, 0.28, 0), d - Vector3(0, 0.28, 0), Vector3(out, 0, 0), color)
	for e: Array in [[a, d, -1.0], [b, c, 1.0]]:
		MeshKit.tri(st, e[0], e[1], e[1] - Vector3(0, 0.28, 0), Vector3(0, 0, e[2]), color)


## The sidewalks (a curb up from the parking), the angle parking out to the street with
## its stripes and the day's cars, and the lamp posts.
func _street(l: Dictionary) -> void:
	var sx := float(l.street_x)
	var half := float(l.street_half_width)
	var g := lm._group(Vector3(sx, 0.0, float(l.z)), Rect2(-40.0, -130.0, 80.0, 260.0))
	var st: SurfaceTool = g.st
	var street := _street_heights(sx, float(l.z) - 140.0, float(l.z) + 140.0, g)
	var cars := SurfaceTool.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 52356  # Wellman's zip code: the same cars every day
	for i in 2:
		var front := float(l.fronts[i]) - sx
		var out := 1.0 if i == 0 else -1.0
		var curb := front + out * SIDEWALK
		var edge := -out * half  # the street's own pavement starts here
		for span: Array in l.walks:
			var z0 := float(span[0]) - float(l.z)
			var z1 := float(span[1]) - float(l.z)
			_strip(st, g, front, curb, z0, z1, CURB, Landmarks.CONCRETE)
			_curb(st, g, curb, out, z0, z1)
			_strip(st, g, curb, edge + out * 0.5, z0, z1, 0.07, Landmarks.ASPHALT, street, half)
			# The stalls, 60 degrees to the curb, nosed in going downhill (south): the
			# one-way's traffic turns in.
			var z := z0 + 3.0
			while z < z1 - 3.0:
				_stripe(st, g, curb, edge, out, z)
				if rng.randf() < 0.55:
					var kind := "pickup" if rng.randf() < 0.4 else "car"
					var nose := Vector3(-out * 0.866, 0.0, 0.5)
					var spot := Vector3(curb, 0.0, z + STALL / 2.0) - nose * 2.7
					spot.y = lm._ground_y(g, Vector2(spot.x, spot.z)) + 0.08
					var turn := Basis(Vector3.UP, atan2(-nose.x, -nose.z))
					cars.append_from(TrafficModels.build(kind, rng), 0, Transform3D(turn, spot))
					var spec: Dictionary = Traffic.KINDS[kind]
					lm._solid_at(Transform3D(turn, g.at + spot + Vector3(0, 0.75, 0)),
						Vector3(float(spec.width) / 2.0, 0.75, float(spec.length) / 2.0))
				z += STALL
			var lz := z0 + LAMP_EVERY / 2.0 + (LAMP_EVERY / 2.0 if i == 1 else 0.0)
			while lz < z1:
				_lamp_post(st, g, Vector2(front + out * (SIDEWALK - 0.5), lz))
				lz += LAMP_EVERY
	lm._finish(g)
	var node := MeshInstance3D.new()
	node.mesh = cars.commit()
	node.material_override = MeshKit.material()
	node.position = g.at
	node.visibility_range_end = 900.0
	lm.add_child(node)


## The street's own surface (local y) down the middle, every couple of meters of z (local):
## [z, y] pairs, from the town street pieces running down 8th Ave.
func _street_heights(sx: float, z0: float, z1: float, g: Dictionary) -> Array:
	var out := []
	for piece: Dictionary in lm.route.streets:
		var p: PackedFloat32Array = piece.points
		for i in range(0, p.size(), 5):
			if absf(p[i] - sx) < 4.0 and p[i + 4] >= z0 and p[i + 4] <= z1:
				out.append(Vector2(p[i + 4] - float(g.at.z), p[i + 2] - float(g.at.y)))
	out.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	return out


## The street's height (local) at z (local), from those pairs; NAN without them.
static func _street_y(street: Array, z: float) -> float:
	if street.is_empty():
		return NAN
	var best: Vector2 = street[0]
	for q: Vector2 in street:
		if absf(q.x - z) < absf(best.x - z):
			best = q
	return best.y


## A strip of pavement from x0 to x1 (local), z0 to z1, `lift` over the ground. Given the
## street's heights, it stays over the grass the street's edge slopes down into (its skirt).
func _strip(st: SurfaceTool, g: Dictionary, x0: float, x1: float, z0: float, z1: float, lift: float, color: Color,
		street := [], half := 0.0) -> void:
	var a := minf(x0, x1)
	var b := maxf(x0, x1)
	var nx := maxi(1, ceili((b - a) / 1.0))  # a meter apart across, so the ground can't poke up between
	var z := z0
	while z < z1 - 0.01:
		var dz := minf(2.0, z1 - z)
		for i in nx:
			var xa := lerpf(a, b, float(i) / nx)
			var xb := lerpf(a, b, float(i + 1) / nx)
			var c: Array[Vector3] = []
			for p: Vector2 in [Vector2(xa, z), Vector2(xb, z), Vector2(xb, z + dz), Vector2(xa, z + dz)]:
				var y := lm._ground_y(g, p) + lift
				var sy := _street_y(street, p.y)
				if not is_nan(sy):  # (the skirt drops 1.4 m over 3 m out from the edge)
					y = maxf(y, sy + 0.03 - 0.45 * maxf(absf(p.x) - half, 0.0))
				c.append(Vector3(p.x, y, p.y))
			MeshKit.quad(st, c[0], c[1], c[2], c[3], Vector3.UP, color)
		z += dz


## The curb's face, down from the sidewalk to the parking.
func _curb(st: SurfaceTool, g: Dictionary, x: float, out: float, z0: float, z1: float) -> void:
	var z := z0
	while z < z1 - 0.01:
		var dz := minf(2.0, z1 - z)
		var y0 := lm._ground_y(g, Vector2(x, z))
		var y1 := lm._ground_y(g, Vector2(x, z + dz))
		MeshKit.quad(st, Vector3(x, y0 + CURB, z), Vector3(x, y1 + CURB, z + dz), Vector3(x, y1 + 0.03, z + dz),
			Vector3(x, y0 + 0.03, z), Vector3(out, 0, 0), Landmarks.CONCRETE)
		z += dz


## A stall's white line, from the curb out toward the street at 60 degrees.
func _stripe(st: SurfaceTool, g: Dictionary, curb: float, edge: float, out: float, z: float) -> void:
	var run := absf(edge - curb)
	var a := Vector2(curb, z)
	var b := Vector2(edge, z - run * 0.577)  # tan(30): out from the curb they lean uphill
	var across := Vector2(0.0, 0.06)
	var c: Array[Vector3] = []
	for p: Vector2 in [a - across, a + across, b + across, b - across]:
		c.append(Vector3(p.x, lm._ground_y(g, p) + 0.07, p.y))
	MeshKit.quad(st, c[0], c[1], c[2], c[3], Vector3.UP, STRIPE)


## A lamp post on the sidewalk: a dark green post and a globe lit at night.
func _lamp_post(st: SurfaceTool, g: Dictionary, at: Vector2) -> void:
	var foot := Vector3(at.x, lm._ground_y(g, at) + CURB, at.y)
	MeshKit.box(st, Vector3(0.4, 0.5, 0.4), foot + Vector3(0, 0.25, 0), POST)
	MeshKit.box(st, Vector3(0.16, 4.0, 0.16), foot + Vector3(0, 2.2, 0), POST)
	MeshKit.box(st, Vector3(0.5, 0.55, 0.5), foot + Vector3(0, 4.45, 0), Landmarks.LAMP)
	MeshKit.box(st, Vector3(0.62, 0.12, 0.62), foot + Vector3(0, 4.78, 0), POST)
	lm._solid(g, foot + Vector3(0, 2.2, 0), Vector3(0.12, 2.2, 0.12))


## The water tower: four legs braced every 10 m, the riser up the middle, the tank's cone
## bottom, its walk round the rim, the tank, its roof and the vent on top.
func water_tower(l: Dictionary) -> void:
	var g := lm._group(Vector3(float(l.x), 0.0, float(l.z)), Rect2(-7.0, -7.0, 14.0, 14.0))
	var st: SurfaceTool = g.st
	var foot := 4.7  # the legs' corners at the ground...
	var head := 4.1  # ...and under the tank
	var bottom := 30.0
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var leg := func(c: Vector2, y: float) -> Vector3:
		var r := lerpf(foot, head, y / bottom)
		return Vector3(c.x * r, y, c.y * r)
	for c: Vector2 in corners:
		var a: Vector3 = leg.call(c, g.base)
		var b: Vector3 = leg.call(c, bottom + 0.5)
		_beam(st, a, b, 0.55, TOWER)
		lm._solid(g, (a + b) / 2.0, Vector3(0.3, (b.y - a.y) / 2.0, 0.3))
	for i in 4:
		var c0 := corners[i]
		var c1 := corners[(i + 1) % 4]
		for y: float in [10.0, 20.0, 29.5]:
			_beam(st, leg.call(c0, y), leg.call(c1, y), 0.3, TOWER)
		for y0: float in [0.5, 10.0, 20.0]:  # X-bracing in each panel
			var y1 := y0 + 9.5 if y0 > 1.0 else 10.0
			_beam(st, leg.call(c0, y0), leg.call(c1, y1), 0.1, TOWER)
			_beam(st, leg.call(c1, y0), leg.call(c0, y1), 0.1, TOWER)
	MeshKit.cylinder(st, 0.9, bottom - g.base, Vector3(0, (bottom + g.base) / 2.0, 0), TOWER, TOWER, 10, Vector3.UP)
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = bottom - g.base
	lm._solid(g, Vector3(0, (bottom + g.base) / 2.0, 0), Vector3(0.9, (bottom - g.base) / 2.0, 0.9), shape)
	_cone(st, Vector3(0, bottom - 0.5, 0), 0.9, 6.2, 2.3, TOWER)  # the tank's bottom
	MeshKit.cylinder(st, 6.75, 0.15, Vector3(0, bottom + 1.85, 0), TOWER.darkened(0.15), TOWER.darkened(0.15), 24, Vector3.UP)
	MeshKit.cylinder(st, 6.75, 0.08, Vector3(0, bottom + 2.9, 0), TOWER.darkened(0.15), TOWER.darkened(0.15), 24, Vector3.UP)
	MeshKit.cylinder(st, 6.2, 5.8, Vector3(0, bottom + 4.7, 0), TOWER, TOWER, 24, Vector3.UP)
	_cone(st, Vector3(0, bottom + 7.6, 0), 6.2, 0.4, 2.6, TOWER)  # the roof
	MeshKit.cylinder(st, 0.35, 0.7, Vector3(0, bottom + 10.55, 0), TOWER.darkened(0.2), TOWER.darkened(0.2), 8, Vector3.UP)
	lm._finish(g)
	# WELLMAN round the tank, a letter at a time so they follow its curve: facing IA 22
	# (south) and north.
	var word := "WELLMAN"
	var step := 1.25 / 6.2  # a letter's width round the tank, as an angle
	for facing: float in [0.0, PI]:
		for i in word.length():
			var a := facing + (i - (word.length() - 1) / 2.0) * step
			var normal := Vector3(sin(a), 0.0, cos(a))
			var label := Label3D.new()
			label.text = word[i]
			label.font_size = 96
			label.pixel_size = 0.022
			label.modulate = TOWER_LETTERS
			label.outline_size = 0
			label.double_sided = false
			label.shaded = true
			label.visibility_range_end = 3000.0
			label.position = g.at + Vector3(0, bottom + 4.6, 0) + normal * 6.25
			label.rotation.y = a
			lm.add_child(label)


## A cone (or a cone's frustum) round the vertical through `base`: radius r0 there, r1
## `height` above it.
func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, height: float, color: Color) -> void:
	var sides := 24
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var a := base + Vector3(cos(t0) * r0, 0, sin(t0) * r0)
		var b := base + Vector3(cos(t1) * r0, 0, sin(t1) * r0)
		var c := base + Vector3(cos(t1) * r1, height, sin(t1) * r1)
		var d := base + Vector3(cos(t0) * r1, height, sin(t0) * r1)
		var mid := Vector3(cos((t0 + t1) / 2.0), 0, sin((t0 + t1) / 2.0))
		var slope := Vector3(mid.x * height, r0 - r1, mid.z * height).normalized()
		MeshKit.quad(st, a, b, c, d, slope, color)


## A square beam `size` thick from a to b (any direction).
func _beam(st: SurfaceTool, a: Vector3, b: Vector3, size: float, color: Color) -> void:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized() * size / 2.0
	var v := d.cross(u).normalized() * size / 2.0
	var ring: Array[Vector3] = [u + v, u - v, -u - v, -u + v]
	for i in 4:
		var p := ring[i]
		var q := ring[(i + 1) % 4]
		MeshKit.quad(st, a + p, a + q, b + q, b + p, (p + q).normalized(), color)


## A fixed pick for building `n` (0 .. count-1): the same shops every time.
static func _pick(n: int, salt: int, count: int) -> int:
	return int(Scenery._hash(n * 31 + salt * 977) * count) % count
