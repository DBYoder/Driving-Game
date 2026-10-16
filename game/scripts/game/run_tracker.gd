class_name RunTracker
extends RefCounted
## Times a run: the clock starts when the car crosses the Kalona start line and stops
## at the US 218 finish. Keeps the best time per car in a small save file.

enum State { READY, RUNNING, FINISHED }

const SAVE_PATH := "user://records.cfg"

var start_station: float
var finish_station: float
var car_name: String
var save_path: String
var state := State.READY
var elapsed := 0.0
var best_time := 0.0  ## 0 = no record yet
var new_best := false


func _init(start: float, finish: float, name_of_car: String, path := SAVE_PATH) -> void:
	start_station = start
	finish_station = finish
	car_name = name_of_car
	save_path = path
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		best_time = cfg.get_value("best_times", car_name, 0.0)


func reset() -> void:
	state = State.READY
	elapsed = 0.0
	new_best = false


## Call every physics tick with the car's station.
func update(station: float, delta: float) -> void:
	match state:
		State.READY:
			if station >= start_station:
				state = State.RUNNING
				elapsed = 0.0
		State.RUNNING:
			elapsed += delta
			if station >= finish_station:
				state = State.FINISHED
				if best_time <= 0.0 or elapsed < best_time:
					best_time = elapsed
					new_best = true
					_save()


func _save() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("best_times", car_name, best_time)
	cfg.save(save_path)


static func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%d:%04.1f" % [minutes, seconds - minutes * 60.0]
