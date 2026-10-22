class_name Sfx
extends RefCounted
## Sound effects made from scratch (no audio files): built once, the first time each is
## asked for, as 16-bit mono WAV streams.
##   crunch  a car crash: a low thump, crumpling noise, ringing metal, bits falling
##   thud    a hay bale, or landing a jump
##   clang   a mailbox
##   crack   a fence rail splintering
##   whoosh  a car going by close (a near miss)
##   horn_*  each car's horn, two notes, looped while you hold it

const RATE := 22050
const HORNS := {"windstar": [340.0, 428.0], "tercel": [520.0, 618.0], "legend": [400.0, 500.0]}

static var _cache := {}


static func get_stream(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _make(id)
	return _cache[id]


static func _make(id: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var samples := PackedFloat32Array()
	match id:
		"crunch":
			samples = _crunch(rng)
		"thud":
			samples = _thud(rng)
		"clang":
			samples = _clang(rng)
		"crack":
			samples = _crack(rng)
		"whoosh":
			samples = _whoosh(rng)
		_:
			if id.begins_with("horn_"):
				var notes: Array = HORNS.get(id.trim_prefix("horn_"), HORNS.legend)
				return _wav(_horn(notes[0], notes[1]), true)
	return _wav(samples, false)


static func _crunch(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(RATE * 0.7)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 7.0)
		low = low * 0.5 + (rng.randf() * 2.0 - 1.0) * 0.5
		# Pitched up out of the sub-bass so laptop speakers play it too.
		var thump := sin(TAU * (100.0 - 40.0 * t) * t) * exp(-t * 13.0)
		var metal := (sin(TAU * 730.0 * t) + 0.7 * sin(TAU * 1130.0 * t + 1.0) + 0.5 * sin(TAU * 1710.0 * t + 2.0)) \
			* exp(-t * 15.0) * 0.3
		var bits := (rng.randf() * 2.0 - 1.0) * 0.7 * env if rng.randf() < 0.04 * env + 0.004 else 0.0
		out.append(thump * 0.6 + low * env * 1.1 + metal + bits)
	return out


static func _thud(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var low := 0.0
	for i in int(RATE * 0.35):
		var t := float(i) / RATE
		low = low * 0.7 + (rng.randf() * 2.0 - 1.0) * 0.3
		out.append(sin(TAU * (125.0 - 70.0 * t) * t) * exp(-t * 11.0) + low * exp(-t * 20.0) * 0.9)
	return out


static func _clang(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var partials := [[520.0, 6.0, 0.5], [1310.0, 9.0, 0.35], [2210.0, 12.0, 0.25], [3020.0, 16.0, 0.15]]
	for i in int(RATE * 0.8):
		var t := float(i) / RATE
		var s := 0.0
		for p: Array in partials:
			s += sin(TAU * p[0] * t) * exp(-t * p[1]) * p[2]
		if t < 0.006:
			s += (rng.randf() * 2.0 - 1.0) * 0.8
		out.append(s)
	return out


static func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var a := 0.0
	var b := 0.0
	for i in int(RATE * 0.3):
		var t := float(i) / RATE
		var white := rng.randf() * 2.0 - 1.0
		a = a * 0.55 + white * 0.45
		b = b * 0.92 + white * 0.08
		var band := a - b  # a splintery middle band
		var env := exp(-t * 45.0) + 0.6 * exp(-maxf(t - 0.07, 0.0) * 55.0) * float(t > 0.07)
		out.append(band * env * 1.6)
	return out


static func _whoosh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var length := 0.6
	var low := 0.0
	for i in int(RATE * length):
		var t := float(i) / RATE
		var x := t / length
		var cutoff := 0.04 + 0.5 * sin(PI * x) ** 2  # opens up as it goes by
		low += (rng.randf() * 2.0 - 1.0 - low) * cutoff
		out.append(low * sin(PI * x) ** 2 * 1.4)
	return out


## Two buzzy notes together; half a second, so both notes loop cleanly (whole cycles).
static func _horn(f1: float, f2: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(RATE * 0.5):
		var t := float(i) / RATE
		var s := clampf(sin(TAU * f1 * t) * 2.2, -1.0, 1.0) + clampf(sin(TAU * f2 * t) * 2.2, -1.0, 1.0)
		out.append(s * 0.32)
	return out


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := minf(1.0, 0.9 / peak)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(int(samples[i] * gain * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
