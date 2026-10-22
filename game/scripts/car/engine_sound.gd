class_name EngineSound
extends AudioStreamPlayer
## A synthesized engine note: a fake 4-speed automatic picks the RPM from road speed,
## and the throttle sets how hard it growls. Boosting adds a rushing roar on top.
## No audio files needed.
##
## Each cycle of the engine comes from a wavetable of harmonics built for the car (two
## of them: off the throttle, mellow; on it, bright and buzzy), so the sound has plenty
## in the 200 Hz–2 kHz range that laptop and TV speakers can play. (The first version
## was mostly a 30–140 Hz hum, too low for small speakers to reproduce, and ~20 dB
## under the horn.)

const MIX_RATE := 22050.0
const GEAR_TOP_SPEEDS := [12.0, 22.0, 34.0, 60.0]  ## m/s at which each gear tops out
const TABLE_SIZE := 512
const IDLE_HZ := 40.0  ## firing frequency at idle and at redline, times the car's engine_note
const REDLINE_HZ := 270.0
const LEVEL_IDLE := 0.22  ## loudness off the throttle and flat out
const LEVEL_FULL := 0.6
const VOLUME_DB := -3.0

var car: Car
var _phase := 0.0
var _rpm := 0.2  ## 0 = idle, 1 = redline
var _load := 0.0
var _boost := 0.0  ## 0..1, the roar of the boost
var _roar := 0.0  ## low-passed noise for it
var _hiss := 0.0  ## intake noise, band-passed
var _hiss_low := 0.0
var _soft := PackedFloat32Array()  ## one cycle off the throttle
var _hard := PackedFloat32Array()  ## and on it
var _tables_for := ""  ## which car's tables these are
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.1
	stream = generator
	volume_db = VOLUME_DB
	bus = "Effects"
	_start()


func _start() -> void:
	play()
	_playback = get_stream_playback()


func _process(delta: float) -> void:
	if car == null or car.stats == null:
		return
	if not playing:  # stopped by something (it never should be): start it again
		_start()
	update(delta, absf(car.forward_speed()), car.throttle, car.boost.active)
	var n := _playback.get_frames_available()
	if n > 0:
		_playback.push_buffer(synth(n))


## Follow the car: RPM from road speed (and a little from the throttle), load from the
## throttle, and the boost's roar.
func update(delta: float, speed: float, throttle: float, boosting: bool) -> void:
	_build_tables()
	_rpm = lerpf(_rpm, maxf(rpm_for(speed), 0.15 + throttle * 0.1), 1.0 - exp(-delta * 8.0))
	_load = lerpf(_load, maxf(throttle, 1.0 if boosting else 0.0), 1.0 - exp(-delta * 6.0))
	_boost = move_toward(_boost, 1.0 if boosting else 0.0, delta * (4.0 if boosting else 1.5))


## RPM (0 idle .. 1 redline) at a road speed, through the gears.
static func rpm_for(speed: float) -> float:
	var low := 0.0
	for top: float in GEAR_TOP_SPEEDS:
		if speed <= top:
			return lerpf(0.25, 1.0, (speed - low) / (top - low))
		low = top
	return 1.0


## How hard the engine's revving: 0.15 idling .. 1 at the redline (the tachometer).
func rpm_fraction() -> float:
	return _rpm


## The firing frequency (Hz) now.
func frequency() -> float:
	return (IDLE_HZ + _rpm * (REDLINE_HZ - IDLE_HZ)) * car.stats.engine_note


## The next `n` stereo frames.
func synth(n: int) -> PackedVector2Array:
	_build_tables()
	var out := PackedVector2Array()
	out.resize(n)
	var step := frequency() / MIX_RATE * TABLE_SIZE
	var level := lerpf(LEVEL_IDLE, LEVEL_FULL, _load)
	var hiss_level := 0.05 + 0.12 * _load * _rpm
	var phase := _phase
	for i in n:
		phase += step
		if phase >= TABLE_SIZE:
			phase -= TABLE_SIZE
		var k := int(phase)
		var f := phase - k
		var k1 := (k + 1) % TABLE_SIZE
		var soft := _soft[k] + (_soft[k1] - _soft[k]) * f
		var hard := _hard[k] + (_hard[k1] - _hard[k]) * f
		var white := randf() * 2.0 - 1.0
		# Intake hiss: noise between two one-pole filters, a few hundred Hz to ~3 kHz.
		_hiss += (white - _hiss) * 0.6
		_hiss_low += (_hiss - _hiss_low) * 0.08
		_roar = _roar * 0.85 + white * 0.15
		var s := (soft + (hard - soft) * _load) * level + (_hiss - _hiss_low) * hiss_level + _roar * 0.6 * _boost
		out[i] = Vector2(s, s)
	_phase = phase
	return out


## Wavetables for this car: harmonics with fixed random phases (so the wave isn't one
## sharp spike), falling off gently on the throttle and steeply off it. A raspy engine
## gets more of the upper odd harmonics. No DC, peak 1.
func _build_tables() -> void:
	if _tables_for == car.stats.id:
		return
	_tables_for = car.stats.id
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(car.stats.id)
	var phases := PackedFloat32Array()
	for h in 24:
		phases.append(rng.randf() * TAU)
	var rasp := car.stats.engine_rasp
	_soft = _table(phases, func(h: int) -> float: return 1.0 / pow(h, 1.6) if h <= 8 else 0.0)
	_hard = _table(phases, func(h: int) -> float:
		var w := 1.0 / pow(h, 0.75)
		if h >= 3 and h % 2 == 1:
			w *= 1.0 + rasp * 1.5
		return w * (1.0 if h <= 6 else exp(-(h - 6) * (0.35 - rasp * 0.2))))


func _table(phases: PackedFloat32Array, weight: Callable) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	var peak := 0.0001
	for i in TABLE_SIZE:
		var x := TAU * i / TABLE_SIZE
		var v := 0.0
		for h in range(1, phases.size() + 1):
			var w: float = weight.call(h)
			if w > 0.0:
				v += w * sin(h * x + phases[h - 1])
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in TABLE_SIZE:
		t[i] /= peak
	return t
