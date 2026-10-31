class_name Ghost
extends Node3D
## Your best run, driven again beside you: a see-through copy of your car where it was at
## the same moment of the run that set your best time on this route, in this car and
## condition (Condition.records_key). No collision: you drive through it.
##
## Recorded while a run that counts is on (RATE samples a second: the clock, how far
## along the road, the car's place and heading) and kept in user://ghosts/ when it's a new
## best. The HUD shows how far ahead or behind it you are (gap_at).

const RATE := 10.0
const FIELDS := 9  ## a sample: seconds, station, x, y, z, rotation (quaternion x, y, z, w)
const COLOR := Color(0.5, 0.78, 1.0, 0.46)

var dir := "user://ghosts"  ## "" = never saved or loaded (tests)
var samples := PackedFloat32Array()  ## the best run's
var key := ""
var _recording := PackedFloat32Array()
var _next := 0.0
var _model: CarModel
var _stats: CarStats
var _material: StandardMaterial3D
var _cursor := 0  ## where gap_at() last looked


## For this records key and car: its best run's ghost, if there is one, and the model.
func prepare(records_key: String, stats: CarStats) -> void:
	key = records_key
	samples = _load()
	if _stats != stats:
		_stats = stats
		_build_model()
	visible = false


func has_run() -> bool:
	return samples.size() >= FIELDS * 2


func duration() -> float:
	return samples[samples.size() - FIELDS] if has_run() else 0.0


func start_recording() -> void:
	_recording = PackedFloat32Array()
	_next = 0.0
	_cursor = 0


## While a run that counts is on, every physics tick: a sample every 1/RATE s.
func record(seconds: float, station: float, xf: Transform3D) -> void:
	if seconds < _next:
		return
	_next = seconds + 1.0 / RATE
	var q := xf.basis.get_rotation_quaternion()
	_recording.append_array([seconds, station, xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])


## A new best time: this run's the ghost now (saved for next time too).
func keep(seconds: float, station: float, xf: Transform3D) -> void:
	_next = 0.0
	record(seconds, station, xf)  # (the finish line itself)
	samples = _recording
	if dir.is_empty() or key.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_buffer(samples.to_byte_array())


## Show it where it was `seconds` into its run (not before the start or past its finish).
func show_at(seconds: float, shown: bool) -> void:
	visible = shown and has_run() and _model != null and seconds <= duration()
	if visible:
		global_transform = transform_at(seconds)


## Where the ghost's car was `seconds` into its run.
func transform_at(seconds: float) -> Transform3D:
	var n := samples.size() / FIELDS
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:  # the last sample at or before `seconds`
		var mid := (lo + hi) / 2
		if samples[mid * FIELDS] <= seconds:
			lo = mid
		else:
			hi = mid
	var a := lo * FIELDS
	var b := hi * FIELDS
	var span := samples[b] - samples[a]
	var f := clampf((seconds - samples[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var pa := Vector3(samples[a + 2], samples[a + 3], samples[a + 4])
	var pb := Vector3(samples[b + 2], samples[b + 3], samples[b + 4])
	var qa := Quaternion(samples[a + 5], samples[a + 6], samples[a + 7], samples[a + 8])
	var qb := Quaternion(samples[b + 5], samples[b + 6], samples[b + 7], samples[b + 8])
	return Transform3D(Basis(qa.slerp(qb, f)), pa.lerp(pb, f))


## Seconds you're behind the ghost (negative: ahead) at `station`, `seconds` into your
## run: your clock less the ghost's when it got there. NAN without a ghost, or before it.
func gap_at(station: float, seconds: float) -> float:
	var n := samples.size() / FIELDS
	if n < 2 or station < samples[1]:
		return NAN
	# (Walk on from where it last looked: you only ever drive on, mostly.)
	_cursor = clampi(_cursor, 0, n - 2)
	while _cursor > 0 and samples[_cursor * FIELDS + 1] > station:
		_cursor -= 1
	while _cursor < n - 2 and samples[(_cursor + 1) * FIELDS + 1] <= station:
		_cursor += 1
	var a := _cursor * FIELDS
	var b := a + FIELDS
	if station > samples[b + 1]:
		return NAN  # past where the ghost got
	var span := samples[b + 1] - samples[a + 1]
	var f := (station - samples[a + 1]) / span if span > 0.0 else 0.0
	return seconds - lerpf(samples[a], samples[b], f)


func _path() -> String:
	var safe := ""
	for ch in key:
		safe += ch if ch.is_valid_identifier() or ch.is_valid_int() else "_"
	return "%s/%s.ghost" % [dir, safe]


func _load() -> PackedFloat32Array:
	if dir.is_empty() or key.is_empty() or not FileAccess.file_exists(_path()):
		return PackedFloat32Array()
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var out := f.get_buffer(f.get_length()).to_float32_array()
	return out if out.size() % FIELDS == 0 else PackedFloat32Array()


## The car's model, every surface see-through and pale blue, its wheels at rest.
func _build_model() -> void:
	if _model:
		_model.free()
	_model = CarModel.new()
	add_child(_model)
	var wheels := []
	for z: float in [-_stats.wheelbase / 2.0, _stats.wheelbase / 2.0]:
		for x: float in [-_stats.track / 2.0, _stats.track / 2.0]:
			var w := Car.Wheel.new()
			w.mount = Vector3(x, _stats.mount_y, z)
			w.front = z < 0.0
			w.left = x < 0.0
			w.spring_length = _stats.rest_length
			wheels.append(w)
	_model.build(_stats, wheels)
	_model.update(wheels, 0.0, Vector3.ZERO, 0.0, 0.0)  # (no wheel on the ground: no shadow either)
	_model.set_headlights(false)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.albedo_color = COLOR
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.cull_mode = BaseMaterial3D.CULL_BACK
	_paint(_model)


func _paint(node: Node) -> void:
	for c in node.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).material_override = _material
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paint(c)
