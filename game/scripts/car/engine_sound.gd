class_name EngineSound
extends AudioStreamPlayer
## A synthesized engine note: a fake 4-speed automatic picks the RPM from road speed,
## and the throttle sets how hard it growls. No audio files needed.

const MIX_RATE := 22050.0
const GEAR_TOP_SPEEDS := [12.0, 22.0, 34.0, 60.0]  ## m/s at which each gear tops out

var car: Car
var _phase := 0.0
var _rpm := 0.2  ## 0 = idle, 1 = redline
var _load := 0.0
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.1
	stream = generator
	volume_db = -10.0
	play()
	_playback = get_stream_playback()


func _process(delta: float) -> void:
	if car == null or _playback == null:
		return
	var speed := absf(car.forward_speed())
	var low := 0.0
	var target := 0.15
	for top in GEAR_TOP_SPEEDS:
		if speed <= top:
			target = lerpf(0.25, 1.0, (speed - low) / (top - low))
			break
		low = top
	_rpm = lerpf(_rpm, maxf(target, 0.15 + car.throttle * 0.1), 1.0 - exp(-delta * 8.0))
	_load = lerpf(_load, car.throttle, 1.0 - exp(-delta * 6.0))

	var freq := (28.0 + _rpm * 110.0) * car.stats.engine_note  # firing frequency, roughly
	var amp := 0.18 + 0.22 * _load
	var rasp := car.stats.engine_rasp
	for i in _playback.get_frames_available():
		_phase = fmod(_phase + freq / MIX_RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var pulse := 1.0 if _phase < 0.15 + 0.3 * (1.0 - rasp) else -0.4
		var sample := (saw * (1.0 - rasp * 0.5) + pulse * (0.2 + rasp * 0.5)) * amp \
			+ randf_range(-0.03, 0.03) * _load * (0.5 + rasp)
		_playback.push_frame(Vector2(sample, sample))
