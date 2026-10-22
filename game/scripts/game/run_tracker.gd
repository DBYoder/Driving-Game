class_name RunTracker
extends RefCounted
## Times a run: the clock starts when the car crosses the start line (the stop line at
## the Kalona 4-way stop) and stops at the finish (the stop line at the Mormon Trek Blvd
## light in Iowa City), or when the car is wrecked. Keeps the best time and best score
## per car in a small save file.

enum State { READY, RUNNING, FINISHED, WRECKED }

const SAVE_PATH := "user://records.cfg"

var start_station: float
var finish_station: float
var car_name: String
var save_path: String
var state := State.READY
var elapsed := 0.0
var wreck_reason := ""
var best_time := 0.0  ## 0 = no record yet
var best_score := 0
var new_best := false  ## best time
var new_best_score := false
var practice := false  ## started somewhere up the road: nothing's saved


func _init(start: float, finish: float, name_of_car: String, path := SAVE_PATH) -> void:
	start_station = start
	finish_station = finish
	save_path = path
	set_car(name_of_car)


## Switch to another car's records.
func set_car(name_of_car: String) -> void:
	car_name = name_of_car
	best_time = 0.0
	best_score = 0
	var cfg := ConfigFile.new()
	if not save_path.is_empty() and cfg.load(save_path) == OK:
		best_time = cfg.get_value("best_times", car_name, 0.0)
		best_score = cfg.get_value("best_scores", car_name, 0)


func reset() -> void:
	state = State.READY
	elapsed = 0.0
	wreck_reason = ""
	new_best = false
	new_best_score = false


func running() -> bool:
	return state == State.RUNNING


func over() -> bool:
	return state == State.FINISHED or state == State.WRECKED


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
				if practice:
					return
				if best_time <= 0.0 or elapsed < best_time:
					best_time = elapsed
					new_best = true
					_save("best_times", best_time)


## The run ends here. Only counts once the clock is running.
func wreck(reason: String) -> void:
	if state == State.RUNNING:
		state = State.WRECKED
		wreck_reason = reason


## Record the final score of a finished or wrecked run.
func record_score(score: int) -> void:
	if practice:
		return
	if score > best_score:
		best_score = score
		new_best_score = true
		_save("best_scores", best_score)


func _save(section: String, value) -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value(section, car_name, value)
	cfg.save(save_path)


## The best score and time saved for a car's records key (see Condition.records_key):
## [score, seconds], zeros if there are none.
static func saved_records(path: String, key: String) -> Array:
	var cfg := ConfigFile.new()
	if path.is_empty() or cfg.load(path) != OK:
		return [0, 0.0]
	return [int(cfg.get_value("best_scores", key, 0)), float(cfg.get_value("best_times", key, 0.0))]


static func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%d:%04.1f" % [minutes, seconds - minutes * 60.0]
