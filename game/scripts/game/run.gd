class_name Run
extends Node
## The rules of a run: starts the clock and the scoring at the Kalona line, awards
## airtime, ends the run when the car is totaled (except the Tercel, whose engine never
## dies), rolled, or something else wrecks it (a buggy, a head-on), and handles the
## tow-truck penalty.

const ROLLED_SECONDS := 3.0
const TOW_PENALTY := 500
const MIN_AIR_SECONDS := 0.5
const AIR_POINTS_PER_HALF_SECOND := 100
const HARD_HIT_DAMAGE := 8.0  ## crashes at least this bad break the combo

signal wrecked(reason: String)
signal finished

var car: Car
var tracker: RunTracker
var score := ScoreKeeper.new()
var _air_time := 0.0
var _rolled_time := 0.0


func setup(c: Car, t: RunTracker) -> void:
	car = c
	tracker = t
	car.hit.connect(_on_car_hit)
	car_changed()


## After the car has been swapped for another (the car-select screen).
func car_changed() -> void:
	score.car_multiplier = car.stats.score_multiplier
	tracker.set_car(car.stats.display_name)


func restart() -> void:
	tracker.reset()
	score.reset()
	_air_time = 0.0
	_rolled_time = 0.0


func _physics_process(delta: float) -> void:
	var was := tracker.state
	tracker.update(car.station, delta)
	if was == RunTracker.State.READY and tracker.running():
		score.reset()
	if was == RunTracker.State.RUNNING and tracker.state == RunTracker.State.FINISHED:
		score.finish(tracker.elapsed)
		tracker.record_score(score.banked)
		finished.emit()
	if not tracker.running():
		return

	score.update(delta)
	_track_air(delta)
	if car.health <= 0.0 and car.stats.can_total:
		wreck("Totaled")
	_rolled_time = _rolled_time + delta if car.global_transform.basis.y.y < 0.3 else 0.0
	if _rolled_time > ROLLED_SECONDS:
		wreck("Rolled it")


## End the run. Banked points count; the combo pot and the finish bonus are lost.
func wreck(reason: String) -> void:
	if not tracker.running():
		return
	score.break_combo()
	tracker.wreck(reason)
	tracker.record_score(score.banked)
	wrecked.emit(reason)


## The tow truck: back on the road for a price.
func tow() -> void:
	if not tracker.running():
		return
	score.break_combo()
	score.banked = maxi(0, score.banked - TOW_PENALTY)
	score.totals["Tow truck"] = score.totals.get("Tow truck", 0) - TOW_PENALTY
	_air_time = 0.0


func _track_air(delta: float) -> void:
	if car.grounded_wheels() == 0:
		_air_time += delta
		return
	if _air_time >= MIN_AIR_SECONDS:
		var halves := int(_air_time / 0.5)
		score.add("Airtime", halves * AIR_POINTS_PER_HALF_SECOND)
	_air_time = 0.0


## A real crash breaks the combo; smashing things you're meant to smash doesn't.
func _on_car_hit(damage: float, smash: bool) -> void:
	if damage >= HARD_HIT_DAMAGE and not smash and tracker.running():
		score.break_combo()
