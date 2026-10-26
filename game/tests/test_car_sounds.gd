extends "res://tests/test_case.gd"
## The engine and the tires have to be heard over a laptop's or a TV's speakers, which
## play next to nothing below ~250 Hz. Levels are compared with the horn's, in that range.

const SMALL_SPEAKER_HZ := 250.0


## RMS (dB) of a mono signal above SMALL_SPEAKER_HZ, after the player's volume.
static func audible_db(samples: PackedFloat32Array, rate: float, volume_db: float) -> float:
	var rc := 1.0 / (TAU * SMALL_SPEAKER_HZ)
	var a := rc / (rc + 1.0 / rate)
	var y := 0.0
	var prev := 0.0
	var sum := 0.0
	for x in samples:
		y = a * (y + x - prev)
		prev = x
		sum += y * y
	return linear_to_db(sqrt(sum / maxf(samples.size(), 1))) + volume_db


static func left(frames: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in frames:
		out.append(f.x)
	return out


func _horn_db(car_id: String) -> float:
	var wav := Sfx.get_stream("horn_" + car_id)
	var samples := PackedFloat32Array()
	for i in range(0, wav.data.size(), 2):
		samples.append(wav.data.decode_s16(i) / 32768.0)
	return audible_db(samples, Sfx.RATE, CarFeel.HORN_DB)


func _engine(car_id: String) -> EngineSound:
	var car := Car.new()
	car.stats = CarStats.preset(car_id)
	var e := EngineSound.new()
	e.car = car
	return e


func _engine_db(e: EngineSound, speed: float, throttle: float) -> float:
	for i in 120:
		e.update(1.0 / 60.0, speed, throttle, false)
	return audible_db(left(e.synth(int(EngineSound.MIX_RATE))), EngineSound.MIX_RATE, EngineSound.VOLUME_DB)


func test_the_engine_is_heard_on_small_speakers() -> void:
	for id: String in CarStats.CARS:
		var horn := _horn_db(id)
		var e := _engine(id)
		var flat_out := _engine_db(e, 25.0, 1.0)
		check(flat_out > horn - 10.0 and flat_out < horn, "%s flat out: %.1f dB, the horn %.1f dB" % [id, flat_out, horn])
		var idle := _engine_db(e, 0.0, 0.0)
		check(idle < flat_out - 6.0 and idle > horn - 24.0, "%s idling: %.1f dB, quieter but there" % [id, idle])
		var frames := left(e.synth(22050))
		var mean := 0.0
		var peak := 0.0
		for x in frames:
			mean += x
			peak = maxf(peak, absf(x))
		check(absf(mean / frames.size()) < 0.01 and peak <= 1.0, "%s: no DC, no clipping (peak %.2f)" % [id, peak])
		e.car.free()
		e.free()


func test_the_engine_revs_up() -> void:
	var e := _engine("legend")
	e.update(10.0, 2.0, 1.0, false)
	var low := e.frequency()
	e.update(10.0, 11.0, 1.0, false)
	var high := e.frequency()
	check(high > low * 2.0, "the note climbs through first gear (%.0f -> %.0f Hz)" % [low, high])
	check(EngineSound.rpm_for(12.5) < EngineSound.rpm_for(11.5), "and drops when it shifts up")
	var tercel := _engine("tercel")
	tercel.update(10.0, 11.0, 1.0, false)
	check(tercel.frequency() > high, "the Tercel's little four buzzes higher than the Legend's V6")
	e.car.free()
	e.free()
	tercel.car.free()
	tercel.free()


func test_the_tires_are_heard() -> void:
	var feel := CarFeel.new()
	var horn := _horn_db("legend")
	feel.set_tire_levels(0.0, 0.0, 0.0, 0.0, 1.0)
	var quiet := audible_db(left(feel.synth_tires(11025)), CarFeel.SQUEAL_RATE, CarFeel.TIRES_DB)
	check(quiet < -80.0, "parked: no tire noise (%.0f dB)" % quiet)
	feel.set_tire_levels(1.0, 0.0, 0.0, 0.0, 1.0)
	var screech := audible_db(left(feel.synth_tires(22050)), CarFeel.SQUEAL_RATE, CarFeel.TIRES_DB)
	check(screech > horn - 8.0, "a full slide screeches nearly as loud as the horn (%.1f vs %.1f dB)" % [screech, horn])
	feel.set_tire_levels(0.0, 0.0, 1.0, 1.0, 1.0)
	var cruising := audible_db(left(feel.synth_tires(22050)), CarFeel.SQUEAL_RATE, CarFeel.TIRES_DB)
	check(cruising > horn - 26.0 and cruising < screech - 6.0, "road and wind at speed: there, under the screech (%.1f dB)" % cruising)
	feel.set_tire_levels(0.0, 1.0, 0.0, 0.0, 1.0)
	var gravel := audible_db(left(feel.synth_tires(22050)), CarFeel.SQUEAL_RATE, CarFeel.TIRES_DB)
	check(gravel > horn - 20.0, "gravel crunches (%.1f dB)" % gravel)
	feel.free()


## The buffer Godot's web build mixes into for `latency_ms` at `rate` (a power of two).
static func _web_buffer_ms(latency_ms: int, rate: int) -> float:
	var x := latency_ms * rate / 1000
	var up := 1
	while up < x:
		up <<= 1
	var down := up >> 1
	return float(down if up - x > x - down else up) * 1000.0 / rate


func test_a_phone_browser_has_sound_ready_for_a_slow_frame() -> void:
	# In a browser there's one thread: the sound's mixed between frames into a buffer the web
	# output latency sizes. Godot's 50 ms made it 43 ms at a phone's 48 kHz, and a phone's
	# frames often take longer than that: the sound stuttered.
	var latency_ms: int = ProjectSettings.get_setting("audio/driver/output_latency.web")
	for rate: int in [44100, 48000]:
		var ms := _web_buffer_ms(latency_ms, rate)
		check(ms >= 80.0, "at %d Hz the browser holds %.0f ms of sound (want 80+)" % [rate, ms])
	# And the generated sounds keep at least that much ready to mix.
	var engine := EngineSound.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(engine)
	var ready_ms := (engine.stream as AudioStreamGenerator).buffer_length * 1000.0
	check(ready_ms >= _web_buffer_ms(latency_ms, 44100), "the engine keeps %.0f ms ready" % ready_ms)
	engine.free()
