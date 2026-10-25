class_name CarFeel
extends Node
## What you hear and feel from your car, besides the engine: crashes (louder the harder),
## mailboxes, fence rails and hay bales, landing a jump, a car whooshing by on a near
## miss, and the horn. And the tires, all the time: a screech in a slide, a hard stop or
## a hard launch on the asphalt, the crunch of gravel, the roar of the road and the wind
## rising with speed. The controller rumbles along (if the setting's on): crashes,
## smashes, landings, near misses and the boost.

const SQUEAL_RATE := 22050.0
const SMASH_SOUNDS := {"Mailbox": "clang", "Fence": "crack", "Hay bale": "thud"}
const WHOOSH_FOR := ["Near miss", "Close pass"]
const HORN_DB := -4.0
const TIRES_DB := -2.0

var car: Car
var run: Run
var horn_stream := ""  ## which car's horn is loaded
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _horn: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _squeal_playback: AudioStreamGeneratorPlayback
var squeal_level := 0.0  ## 0..1, how loud each tire sound is now
var gravel_level := 0.0
var road_level := 0.0
var wind_level := 0.0
var _phase := 0.0
var _phase2 := 0.0
var _low := 0.0
var _crunch := 0.0
var _road := 0.0
var _road_low := 0.0
var _wind := 0.0
var _wind_low := 0.0
var _air := 0.0
var _fall_speed := 0.0
var _boost_buzz := 0.0
var _rng := RandomNumberGenerator.new()


func setup(c: Car, game_run: Run) -> void:
	car = c
	run = game_run
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_players.append(p)
	_horn = AudioStreamPlayer.new()
	_horn.bus = "Effects"
	_horn.volume_db = HORN_DB
	add_child(_horn)
	_squeal = AudioStreamPlayer.new()
	_squeal.bus = "Effects"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SQUEAL_RATE
	gen.buffer_length = 0.1
	_squeal.stream = gen
	_squeal.volume_db = TIRES_DB
	add_child(_squeal)
	_squeal.play()
	_squeal_playback = _squeal.get_stream_playback()
	car.hit.connect(_on_hit)
	run.score.scored.connect(_on_scored)
	for id: String in ["crunch", "thud", "clang", "crack", "whoosh"]:
		Sfx.get_stream(id)  # build them now, not mid-crash


## Play a sound effect, `loudness` 0..1, pitched a little differently each time.
func play(id: String, loudness := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = Sfx.get_stream(id)
	p.volume_db = linear_to_db(clampf(loudness, 0.05, 1.0))
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	p.play()


func _on_hit(damage: float, smash: bool) -> void:
	if smash:
		Settings.rumble_pad(0.35, 0.1, 0.12)
		return  # its own sound comes from what it was (on_smash)
	play("crunch", 0.3 + damage / 40.0)
	Settings.rumble_pad(0.4 + damage / 30.0, damage / 20.0, 0.15 + damage / 60.0)


## Smashed a prop (PropField.smashed): a clang for a mailbox, a crack for a fence rail, a
## thud for a hay bale.
func on_smash(label: String) -> void:
	if SMASH_SOUNDS.has(label):
		play(SMASH_SOUNDS[label], 0.8)


func _on_scored(label: String, _points: int) -> void:
	if label in WHOOSH_FOR:
		play("whoosh", 0.9)
		Settings.rumble_pad(0.5, 0.0, 0.1)


func _physics_process(delta: float) -> void:
	if car == null or car.stats == null:
		return
	# Landing a jump.
	if car.grounded_wheels() == 0:
		_air += delta
		_fall_speed = maxf(_fall_speed, -car.linear_velocity.y)
	else:
		if _air > 0.25:
			var hard := clampf(_fall_speed / 8.0, 0.2, 1.0)
			play("thud", hard)
			Settings.rumble_pad(0.3, hard * 0.8, 0.2)
		_air = 0.0
		_fall_speed = 0.0
	_tire_levels(delta)
	# The horn, for as long as it's held.
	if car.horn and not _horn.playing:
		var id := "horn_" + car.stats.id
		if horn_stream != id:
			_horn.stream = Sfx.get_stream(id)
			horn_stream = id
		_horn.play()
	elif not car.horn and _horn.playing:
		_horn.stop()
	# A low buzz in the hands while boosting.
	if car.boost.active:
		_boost_buzz -= delta
		if _boost_buzz <= 0.0:
			Settings.rumble_pad(0.3, 0.05, 0.25)
			_boost_buzz = 0.2


## How loud each tire sound should be, from what the wheels are doing.
func _tire_levels(delta: float) -> void:
	var speed := car.linear_velocity.length()
	var squeal := 0.0
	var gravel := 0.0
	var on_asphalt := false
	for w: Car.Wheel in car.wheels:
		if not w.grounded:
			continue
		if w.surface == "asphalt":
			on_asphalt = true
			squeal = maxf(squeal, smoothstep(2.0, 6.0, w.slide))
		else:
			gravel = maxf(gravel, smoothstep(1.0, 4.0, w.slide) + smoothstep(2.0, 20.0, speed) * 0.6)
	if on_asphalt:
		# A hard stop from speed, or flooring it from a standstill, chirps the tires too.
		squeal = maxf(squeal, car.brake * smoothstep(8.0, 18.0, car.forward_speed()) * 0.7)
		squeal = maxf(squeal, car.throttle * (1.0 - smoothstep(1.0, 6.0, speed)) * 0.45 * float(car.throttle > 0.9))
	var road := smoothstep(2.0, 40.0, speed) * (1.0 if on_asphalt else 0.5)
	set_tire_levels(squeal, minf(gravel, 1.0), road, smoothstep(18.0, 50.0, speed), delta)


## Ease the tire sounds toward these levels (0..1).
func set_tire_levels(squeal: float, gravel: float, road: float, wind: float, delta: float) -> void:
	squeal_level = move_toward(squeal_level, squeal, delta * 8.0)
	gravel_level = move_toward(gravel_level, gravel, delta * 6.0)
	road_level = move_toward(road_level, road, delta * 3.0)
	wind_level = move_toward(wind_level, wind, delta * 2.0)


func _process(_delta: float) -> void:
	if _squeal_playback == null:
		return
	if not _squeal.playing:  # stopped by something (it never should be): start it again
		_squeal.play()
		_squeal_playback = _squeal.get_stream_playback()
	var n := _squeal_playback.get_frames_available()
	if n > 0:
		_squeal_playback.push_buffer(synth_tires(n))


## The next `n` frames of tire noise at the current levels.
func synth_tires(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var white := _rng.randf() * 2.0 - 1.0
		# The screech: two rubbery partials that wobble in pitch, a little noise on top.
		_phase = fmod(_phase + (880.0 + 140.0 * white) / SQUEAL_RATE, 1.0)
		_phase2 = fmod(_phase2 + (1330.0 + 90.0 * white) / SQUEAL_RATE, 1.0)
		var screech := sin(TAU * _phase) * 0.55 + sin(TAU * _phase2) * 0.3 + white * 0.08
		# Gravel: low rumble with stones popping.
		_low = _low * 0.7 + white * 0.3
		_crunch = white * 0.9 if _rng.randf() < 0.02 else _crunch * 0.6
		# The road: a band of noise (a few hundred Hz); the wind: a hiss above it.
		_road += (white - _road) * 0.25
		_road_low += (_road - _road_low) * 0.03
		_wind += (white - _wind) * 0.7
		_wind_low += (_wind - _wind_low) * 0.2
		var s := screech * 0.6 * squeal_level + (_low * 0.55 + _crunch * 0.35) * gravel_level \
			+ (_road - _road_low) * 0.35 * road_level + (_wind - _wind_low) * 0.22 * wind_level
		out[i] = Vector2(s, s)
	return out
