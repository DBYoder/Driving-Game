class_name CarFeel
extends Node
## What you hear and feel from your car, besides the engine: crashes (louder the harder),
## mailboxes, fence rails and hay bales, landing a jump, the tires squealing (or the
## gravel crunching) in a slide, a car whooshing by on a near miss, and the horn. The
## controller rumbles along (if the setting's on): crashes, smashes, landings, near
## misses and the boost.

const SQUEAL_RATE := 22050.0
const SMASH_SOUNDS := {"Mailbox": "clang", "Fence": "crack", "Hay bale": "thud"}
const WHOOSH_FOR := ["Near miss", "Close pass"]

var car: Car
var run: Run
var horn_stream := ""  ## which car's horn is loaded
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _horn: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _squeal_playback: AudioStreamGeneratorPlayback
var _squeal_level := 0.0
var _gravel_level := 0.0
var _phase := 0.0
var _low := 0.0
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
	_horn.volume_db = -4.0
	add_child(_horn)
	_squeal = AudioStreamPlayer.new()
	_squeal.bus = "Effects"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SQUEAL_RATE
	gen.buffer_length = 0.1
	_squeal.stream = gen
	_squeal.volume_db = -8.0
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
		return  # its own sound comes with the points (_on_scored)
	play("crunch", 0.3 + damage / 40.0)
	Settings.rumble_pad(0.4 + damage / 30.0, damage / 20.0, 0.15 + damage / 60.0)


func _on_scored(label: String, _points: int) -> void:
	if SMASH_SOUNDS.has(label):
		play(SMASH_SOUNDS[label], 0.8)
	elif label in WHOOSH_FOR:
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
	# Tires: squeal sliding on the asphalt, crunch on gravel and grass.
	var squeal := 0.0
	var gravel := 0.0
	if car.linear_velocity.length() > 3.0:
		for w: Car.Wheel in car.wheels:
			if not w.grounded:
				continue
			if w.surface == "asphalt":
				squeal = maxf(squeal, smoothstep(2.5, 7.0, w.slide))
			else:
				gravel = maxf(gravel, smoothstep(1.5, 5.0, w.slide))
	_squeal_level = move_toward(_squeal_level, squeal, delta * 6.0)
	_gravel_level = move_toward(_gravel_level, gravel, delta * 6.0)
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


func _process(_delta: float) -> void:
	if _squeal_playback == null:
		return
	for i in _squeal_playback.get_frames_available():
		var white := _rng.randf() * 2.0 - 1.0
		# A rubbery squeal that wobbles in pitch, over a gravelly hiss.
		_phase = fmod(_phase + (980.0 + 120.0 * white) / SQUEAL_RATE, 1.0)
		_low = _low * 0.7 + white * 0.3
		var s := sin(TAU * _phase) * 0.45 * _squeal_level + _low * 0.5 * _gravel_level
		_squeal_playback.push_frame(Vector2(s, s))
