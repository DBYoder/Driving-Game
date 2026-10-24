class_name TouchPad
extends Control
## The touch controls while driving (when `Touch` says they're up):
## - the left side is the wheel: put a thumb down anywhere there and slide it left or
##   right (further = more lock), let go to straighten up;
## - the pedals on the right, gas and brake (hold the brake to back up, like S), with the
##   boost, the handbrake and the horn above them; a thumb can slide from pedal to pedal;
## - pause, camera and the tow truck along the top right.
## Each button does just what its key does (Touch.press / release), so the car, the menus
## and everything else don't know the difference. Drawn, not textured: it's all circles.

const STEER_RANGE := 120.0  ## px of slide (virtual) for full lock
const DEAD := 0.04  ## steering this close to straight is straight
const MARGIN := 26.0
const FILL := Color(0, 0, 0, 0.32)
const LINE := Color(1, 1, 1, 0.55)
const LIT := Color(1, 1, 1, 0.3)
const GOLD := Color(1.0, 0.85, 0.3)

## The buttons: id -> {action, text, hold (held down, or a tap), center, radius}. Laid out
## by _layout() for the screen's size.
var pads := {
	"gas": {"action": "accelerate", "text": "GAS", "hold": true},
	"brake": {"action": "brake", "text": "BRAKE", "hold": true},
	"boost": {"action": "boost", "text": "BOOST", "hold": true},
	"handbrake": {"action": "handbrake", "text": "HANDBRAKE", "hold": true},
	"horn": {"action": "horn", "text": "HORN", "hold": true},
	"pause": {"action": "pause", "text": "II", "hold": false},
	"camera": {"action": "camera_next", "text": "CAM", "hold": false},
	"tow": {"action": "recover", "text": "TOW", "hold": false},
}
var driving := false:  ## up while a run's on (main says): let go of everything when not
	set(value):
		if value == driving:
			return
		driving = value
		visible = value
		if not value:
			release_all()
var boost := 0.0  ## the boost meter (0..1), shown round the BOOST button
var should_drive := Callable()  ## main's say on whether a run's being driven (checked every frame)
var meter := Callable()  ## the boost meter's level, for `boost`
var steer := 0.0  ## -1 (full left) .. 1 (full right)
var steer_origin := Vector2.ZERO  ## where the steering thumb went down
var _steer_finger := -1
var _fingers := {}  ## touch index -> pad id
var _held := {}  ## action -> how many fingers are holding it


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = driving
	get_viewport().size_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


## Let go of every pedal and button and straighten the wheel.
func release_all() -> void:
	for action: String in _held:
		if _held[action] > 0:
			Touch.release(action)
	_held.clear()
	_fingers.clear()
	_steer_finger = -1
	_set_steer(0.0, true)
	queue_redraw()


## Where everything goes on a screen this big (virtual pixels).
func _layout() -> void:
	var screen := _screen()
	var w := screen.x
	var h := screen.y
	var gas := Vector2(w - MARGIN - 80.0, h - MARGIN - 80.0)
	var brake := Vector2(gas.x - 80.0 - 26.0 - 64.0, h - MARGIN - 64.0)
	_place("gas", gas, 80.0)
	_place("brake", brake, 64.0)
	_place("boost", Vector2(gas.x, gas.y - 80.0 - 26.0 - 50.0), 50.0)
	_place("handbrake", Vector2(brake.x, brake.y - 64.0 - 26.0 - 48.0), 48.0)
	_place("horn", Vector2(brake.x - 64.0 - 24.0 - 36.0, h - MARGIN - 36.0), 36.0)
	for i in 3:
		_place(["pause", "camera", "tow"][i], Vector2(w - MARGIN - 32.0 - i * 80.0, 150.0), 32.0)
	queue_redraw()


func _place(id: String, center: Vector2, radius: float) -> void:
	pads[id].center = center
	pads[id].radius = radius


## The button under a point (a little forgiving round the edges), or "".
func pad_at(point: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id: String in pads:
		var d := point.distance_to(pads[id].center)
		if d < pads[id].radius * 1.2 and d < best_d:
			best = id
			best_d = d
	return best


## The wheel is the left of the screen, below the trip lines at the top.
func in_steering_zone(point: Vector2) -> bool:
	return point.x < _screen().x * 0.45 and point.y > _screen().y * 0.25


## The screen in the UI's own (stretched) pixels: what touches and drawing are measured in.
func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)


func _input(event: InputEvent) -> void:
	if not driving:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_down(event.index, event.position)
		else:
			touch_up(event.index)
	elif event is InputEventScreenDrag:
		touch_move(event.index, event.position)


func touch_down(finger: int, point: Vector2) -> void:
	var id := pad_at(point)
	if id != "":
		_fingers[finger] = id
		_hold(id)
	elif _steer_finger == -1 and in_steering_zone(point):
		_steer_finger = finger
		steer_origin = point
		_set_steer(0.0)
	queue_redraw()


func touch_move(finger: int, point: Vector2) -> void:
	if finger == _steer_finger:
		_set_steer(clampf((point.x - steer_origin.x) / STEER_RANGE, -1.0, 1.0))
	elif _fingers.has(finger) and _fingers[finger] in ["gas", "brake"]:
		# Slide from one pedal to the other without lifting.
		var now := pad_at(point)
		if now in ["gas", "brake"] and now != _fingers[finger]:
			_let_go(_fingers[finger])
			_fingers[finger] = now
			_hold(now)
	queue_redraw()


func touch_up(finger: int) -> void:
	if finger == _steer_finger:
		_steer_finger = -1
		_set_steer(0.0)
	elif _fingers.has(finger):
		_let_go(_fingers[finger])
		_fingers.erase(finger)
	queue_redraw()


func _hold(id: String) -> void:
	var pad: Dictionary = pads[id]
	if not pad.hold:
		Touch.tap(pad.action)
		return
	_held[pad.action] = _held.get(pad.action, 0) + 1
	if _held[pad.action] == 1:
		Touch.press(pad.action)


func _let_go(id: String) -> void:
	var pad: Dictionary = pads[id]
	if not pad.hold or _held.get(pad.action, 0) <= 0:
		return
	_held[pad.action] -= 1
	if _held[pad.action] == 0:
		Touch.release(pad.action)


func _set_steer(value: float, force := false) -> void:
	value = 0.0 if absf(value) < DEAD else value
	if value == steer and not force:
		return
	steer = value
	if value > 0.0:
		Touch.release("steer_left")
		Touch.press("steer_right", value)
	elif value < 0.0:
		Touch.release("steer_right")
		Touch.press("steer_left", -value)
	else:  # (both, whatever Input says: what's been sent may not have landed yet)
		Touch.release("steer_left")
		Touch.release("steer_right")


func held(id: String) -> bool:
	return _fingers.values().has(id)


func _process(_delta: float) -> void:
	if should_drive.is_valid():
		driving = should_drive.call()
	if driving:
		if meter.is_valid():
			boost = meter.call()
		queue_redraw()  # the boost meter fills and drains


func _draw() -> void:
	var font := get_theme_default_font()
	# The wheel: a slide bar, where the thumb went down (or waiting at the bottom left).
	var origin := steer_origin if _steer_finger != -1 else Vector2(MARGIN + STEER_RANGE + 50.0, _screen().y - MARGIN - 70.0)
	var left := origin - Vector2(STEER_RANGE, 0)
	var right := origin + Vector2(STEER_RANGE, 0)
	draw_line(left, right, Color(0, 0, 0, 0.35), 34.0)
	draw_circle(left, 17.0, Color(0, 0, 0, 0.35))
	draw_circle(right, 17.0, Color(0, 0, 0, 0.35))
	draw_line(left, right, LINE, 2.0)
	var knob := origin + Vector2(steer * STEER_RANGE, 0)
	draw_circle(knob, 36.0, LIT if _steer_finger != -1 else FILL)
	draw_arc(knob, 36.0, 0.0, TAU, 40, GOLD if _steer_finger != -1 else LINE, 3.0, true)
	_text(font, "◀", left + Vector2(-30, 0), 26, LINE)
	_text(font, "▶", right + Vector2(30, 0), 26, LINE)
	if _steer_finger == -1:
		_text(font, "STEER", origin + Vector2(0, -56), 18, LINE)
	# The buttons.
	for id: String in pads:
		var pad: Dictionary = pads[id]
		var on := held(id)
		draw_circle(pad.center, pad.radius, LIT if on else FILL)
		draw_arc(pad.center, pad.radius, 0.0, TAU, 48, GOLD if on else LINE, 3.0, true)
		if id == "boost" and boost > 0.0:
			draw_arc(pad.center, pad.radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * boost, 48, Color(1.0, 0.62, 0.15), 6.0, true)
		var size_px := 26 if pad.radius >= 60.0 else (14 if id == "handbrake" else 18)
		_text(font, pad.text, pad.center, size_px, Color.WHITE)


func _text(font: Font, text: String, center: Vector2, size_px: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, center + Vector2(-width / 2.0, size_px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
