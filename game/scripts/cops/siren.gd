class_name Siren
extends AudioStreamPlayer3D
## A synthesized police siren (the rising and falling "wail"), coming from the cruiser
## so it gets louder as it closes in. No audio files needed.

const MIX_RATE := 22050.0
const WAIL_SECONDS := 3.2

var on := false:
	set(value):
		on = value
		if value and not playing:
			play()
			_playback = get_stream_playback()
		elif not value and playing:
			stop()
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _time := 0.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.1
	stream = generator
	unit_size = 25.0
	max_db = 3.0
	volume_db = -4.0


func _process(_delta: float) -> void:
	if not on or _playback == null:
		return
	for i in _playback.get_frames_available():
		_time += 1.0 / MIX_RATE
		var rise := 0.5 - 0.5 * cos(TAU * _time / WAIL_SECONDS)
		var freq := 650.0 + 700.0 * rise
		_phase = fmod(_phase + freq / MIX_RATE, 1.0)
		# A rounded square wave: sirens are buzzy, but not harsh.
		var sample := clampf(sin(TAU * _phase) * 3.0, -1.0, 1.0) * 0.35
		_playback.push_frame(Vector2(sample, sample))
