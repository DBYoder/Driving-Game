class_name Gauges
extends Control
## The instrument cluster and the radio's display, drawn each frame into the Cockpit's
## texture (a SubViewport): needles, ticks and numbers, warning lights, the odometer and
## the gear. The left part (CLUSTER) goes on the dash in front of the driver; the right
## part (RADIO) on the center stack.
##
## Each car has its own layout, like the real ones: the Legend has a big tachometer and a
## 150 mph speedometer with fuel, temperature and oil pressure; the Windstar a wide
## minivan cluster; the base Tercel no tachometer at all.

const SIZE := Vector2(1280, 320)
const CLUSTER := Rect2(0, 0, 900, 320)
const RADIO := Rect2(920, 20, 340, 150)
const FACE := Color(0.05, 0.05, 0.06)
const MARK := Color(0.92, 0.93, 0.95)
const NEEDLE := Color(1.0, 0.42, 0.12)
const DIM := Color(0.45, 0.47, 0.5)
const RED := Color(0.9, 0.15, 0.12)
const LCD := Color(0.45, 0.95, 0.75)

## Dials per car: kind, center (a small dial's needle pivots at the bottom of its
## fan), radius, and for the big ones their range and the step between numbers. Then
## where the warning lights go: the top of their stack, and how many columns.
const LAYOUTS := {
	"legend": {
		"dials": [
			{"kind": "tach", "at": Vector2(190, 152), "r": 128, "max": 8.0, "major": 1.0, "red": 6.8},
			{"kind": "speed", "at": Vector2(495, 152), "r": 128, "max": 160.0, "major": 20.0},
			{"kind": "fuel", "at": Vector2(770, 90), "r": 70},
			{"kind": "temp", "at": Vector2(770, 194), "r": 70},
			{"kind": "oil", "at": Vector2(770, 298), "r": 70},
		],
		"lights": Vector2(190, 194), "columns": 1,
	},
	"windstar": {
		"dials": [
			{"kind": "tach", "at": Vector2(175, 158), "r": 112, "max": 6.0, "major": 1.0, "red": 5.5},
			{"kind": "speed", "at": Vector2(465, 152), "r": 135, "max": 120.0, "major": 20.0},
			{"kind": "fuel", "at": Vector2(765, 104), "r": 80},
			{"kind": "temp", "at": Vector2(765, 222), "r": 80},
		],
		"lights": Vector2(765, 256), "columns": 3,
	},
	"tercel": {
		"dials": [
			{"kind": "fuel", "at": Vector2(185, 190), "r": 85},
			{"kind": "speed", "at": Vector2(450, 152), "r": 140, "max": 110.0, "major": 20.0},
			{"kind": "temp", "at": Vector2(715, 190), "r": 85},
		],
		"lights": Vector2(185, 226), "columns": 2,
	},
}

var car_id := "legend"
## What the gauges show (Cockpit fills it in every frame).
var speed_mph := 0.0
var rpm := 800.0
var fuel := 0.9  ## 0 empty .. 1 full
var temp := 0.2  ## 0 cold .. 1 overheating
var oil := 0.5
var odometer := 0.0  ## miles
var trip := 0.0
var gear := "D"
var clock := "4:12"
var radio := "FM 94.1"
var lights := {"check": false, "brake": false, "beam": false, "boost": false, "fuel": false}


func _ready() -> void:
	size = SIZE


func _draw() -> void:
	var font := get_theme_default_font()
	var layout: Dictionary = LAYOUTS.get(car_id, LAYOUTS.legend)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.02, 0.02, 0.025))
	draw_rect(CLUSTER.grow(-6), FACE)
	for dial: Dictionary in layout.dials:
		match dial.kind:
			"speed":
				_big_dial(font, dial, speed_mph, "MPH")
				_odometer(font, dial.at + Vector2(0, dial.r * 0.25))
			"tach":
				_big_dial(font, dial, rpm / 1000.0, "x1000 r/min")
			"fuel":
				_small_dial(font, dial, fuel, "E", "F", "FUEL", 0.0, 0.12)
			"temp":
				_small_dial(font, dial, temp, "C", "H", "TEMP", 0.85, 1.0)
			"oil":
				_small_dial(font, dial, oil, "0", "80", "OIL", -1.0, 0.0)
	_warning_lights(font, layout.lights, layout.columns)
	_radio(font)


## A big round dial: 270 degrees, from the lower left round to the lower right. A number
## every `major`, a tick between; the scale runs on past the last number to `max`.
func _big_dial(font: Font, dial: Dictionary, value: float, unit: String) -> void:
	var c: Vector2 = dial.at
	var r: float = dial.r
	var top: float = dial.max
	var major: float = dial.major
	draw_circle(c, r + 6, Color(0.18, 0.18, 0.2))
	draw_circle(c, r, FACE)
	if dial.has("red"):
		_arc_band(c, r - 10, _angle(dial.red / top), _angle(1.0), 8, RED)
	var fs := 26 if r > 120 else 22
	var steps := floori(top / major + 0.001)
	for i in steps + 1:
		var a := _angle(i * major / top)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 22), c + dir * (r - 4), MARK, 4.0)
		var label := str(roundi(i * major))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + dir * (r - 46) + Vector2(-w / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MARK)
	var half := major / 2.0
	var tick := half
	while tick <= top + 0.001:
		if fmod(tick, major) > 0.01:
			var mdir := Vector2(cos(_angle(tick / top)), sin(_angle(tick / top)))
			draw_line(c + mdir * (r - 13), c + mdir * (r - 4), MARK, 2.0)
		tick += half
	var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, c + Vector2(-uw / 2.0, -r * 0.2), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
	_needle(c, r - 14, _angle(clampf(value / top, 0.0, 1.03)))


## A small dial: a fan above its needle's pivot, a quarter turn from `lo` to `hi`, with a
## red zone between red_from and red_to.
func _small_dial(font: Font, dial: Dictionary, value: float, lo: String, hi: String, title: String,
		red_from: float, red_to: float) -> void:
	var c: Vector2 = dial.at
	var r: float = dial.r
	var box := Rect2(c.x - r * 0.95, c.y - r - 12.0, r * 1.9, r + 22.0)
	draw_rect(box, Color(0.18, 0.18, 0.2))
	draw_rect(box.grow(-3), FACE)
	var a0 := deg_to_rad(225.0)
	var a1 := deg_to_rad(315.0)
	if red_to > red_from:
		_arc_band(c, r - 6, lerpf(a0, a1, maxf(red_from, 0.0)), lerpf(a0, a1, red_to), 7, RED)
	for i in 5:
		var a := lerpf(a0, a1, i / 4.0)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 16), c + dir * (r - 2), MARK, 3.0 if i % 2 == 0 else 1.5)
	for pair: Array in [[lo, a0, -1.0], [hi, a1, 1.0]]:
		var dir := Vector2(cos(pair[1]), sin(pair[1]))
		var w := font.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, c + dir * (r - 32) + Vector2(-w / 2.0, 8), pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MARK)
	draw_string(font, Vector2(box.position.x + 10, c.y + 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
	_needle(c, r - 8, lerpf(a0, a1, clampf(value, 0.0, 1.0)), 4.0, 8.0)


## Screen angle for a dial fraction 0..1: 0 at the lower left, 1 at the lower right.
static func _angle(f: float) -> float:
	return deg_to_rad(135.0 + 270.0 * f)


func _needle(c: Vector2, length: float, a: float, width := 5.0, hub := 11.0) -> void:
	var dir := Vector2(cos(a), sin(a))
	draw_line(c - dir * 14, c + dir * length, NEEDLE, width, true)
	draw_circle(c, hub, Color(0.25, 0.25, 0.27))
	draw_circle(c, hub * 0.45, NEEDLE)


func _arc_band(c: Vector2, r: float, a0: float, a1: float, width: float, color: Color) -> void:
	draw_arc(c, r, a0, a1, 24, color, width, true)


## The odometer, the trip meter under it, and the gear, in the gap at the bottom of
## the speedometer.
func _odometer(font: Font, at: Vector2) -> void:
	var odo := "%06d" % int(odometer)
	var w := font.get_string_size(odo, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var box := Rect2(at - Vector2(w / 2.0 + 6, 12), Vector2(w + 12, 24))
	draw_rect(box, Color(0.01, 0.01, 0.01))
	draw_string(font, Vector2(at.x - w / 2.0, at.y + 7), odo, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, MARK)
	var t := "TRIP %.1f" % trip
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(at.x - tw / 2.0, at.y + 30), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
	var gears := ["P", "R", "N", "D", "2", "1"]
	var x := at.x - gears.size() * 8.0
	for g: String in gears:
		draw_string(font, Vector2(x + 2, at.y + 52), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, NEEDLE if g == gear else DIM)
		x += 16.0


## The warning lights, lit or not, in a stack `columns` wide from `top` down.
func _warning_lights(font: Font, top: Vector2, columns: int) -> void:
	var defs := [["check", "CHECK", Color(1.0, 0.6, 0.1)], ["brake", "BRAKE", RED], ["beam", "HIGH", Color(0.3, 0.55, 1.0)],
		["fuel", "FUEL", Color(1.0, 0.6, 0.1)], ["boost", "BOOST", Color(0.3, 1.0, 0.4)]]
	for i in defs.size():
		var d: Array = defs[i]
		var col := i % columns
		var row := i / columns
		var at := top + Vector2((col - (columns - 1) / 2.0) * 64.0, row * 17.0)
		var lit: bool = lights.get(d[0], false)
		var w := font.get_string_size(d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, at + Vector2(-w / 2.0, 5), d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, d[2] if lit else Color(0.16, 0.16, 0.17))


## The radio's display: the dash clock and what's playing.
func _radio(font: Font) -> void:
	draw_rect(RADIO, Color(0.08, 0.08, 0.09))
	var screen := RADIO.grow(-14)
	draw_rect(screen, Color(0.02, 0.05, 0.04))
	draw_string(font, screen.position + Vector2(12, 48), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, LCD)
	var text := radio
	if text.length() > 22:
		var shift := int(Time.get_ticks_msec() / 300.0) % (text.length() + 4)
		text = (text + "    " + text).substr(shift, 22)
	draw_string(font, screen.position + Vector2(12, 100), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, LCD)
