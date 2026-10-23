class_name ScoreKeeper
extends RefCounted
## Points and combos. Each scoring event goes into the combo pot and bumps the multiplier
## (x1, x2 ... x5). If nothing else scores within COMBO_WINDOW seconds, the pot is banked
## at its multiplier. A hard hit, a tow or a wreck throws the unbanked pot away; banked
## points are safe. Reaching Iowa City banks everything, multiplies the lot by 1.5 and
## adds a bonus for every second under par. Every point scored is first multiplied by
## the car's multiplier (harder cars score more).

signal scored(label: String, points: int)  ## an event added to the pot
signal combo_banked(points: int)
signal combo_lost(points: int)

const COMBO_WINDOW := 4.0
const MAX_MULTIPLIER := 5
const FINISH_MULTIPLIER := 1.5
const PAR_SECONDS := 900.0  ## 15 minutes: Highway 1's par (each route has its own: Routes.INFO)
const BONUS_PER_SECOND := 20

var par_seconds := PAR_SECONDS  ## a finish faster than this earns the time bonus
var car_multiplier := 1.0
var banked := 0
var pot := 0  ## combo points not yet banked (before the multiplier)
var multiplier := 0  ## 0 = no combo running
var combo_time_left := 0.0
var finish_bonus := 0  ## extra from the x1.5
var time_bonus := 0
var totals := {}  ## label -> points banked, for the results screen
var counts := {}  ## label -> how many times it scored (banked or not), for the run's title
var raw := {}  ## label -> points before any multiplier (corn: 5 a meter; airtime: 100 a half second)
var _pot_by_label := {}


func reset() -> void:
	banked = 0
	pot = 0
	multiplier = 0
	combo_time_left = 0.0
	finish_bonus = 0
	time_bonus = 0
	totals.clear()
	counts.clear()
	raw.clear()
	_pot_by_label.clear()


## Score something. `event` = false adds points without bumping the multiplier
## (for continuous things like plowing corn), but still keeps the combo alive.
func add(label: String, points: int, event := true) -> void:
	counts[label] = counts.get(label, 0) + 1
	raw[label] = raw.get(label, 0) + points
	points = roundi(points * car_multiplier)
	if points <= 0:
		return
	pot += points
	_pot_by_label[label] = _pot_by_label.get(label, 0) + points
	if event or multiplier == 0:
		multiplier = mini(multiplier + 1, MAX_MULTIPLIER)
	combo_time_left = COMBO_WINDOW
	scored.emit(label, points)


func update(delta: float) -> void:
	if multiplier == 0:
		return
	combo_time_left -= delta
	if combo_time_left <= 0.0:
		bank()


## Bank the pot at its multiplier.
func bank() -> void:
	if multiplier == 0:
		return
	var value := pot * multiplier
	banked += value
	for label in _pot_by_label:
		totals[label] = totals.get(label, 0) + _pot_by_label[label] * multiplier
	combo_banked.emit(value)
	_clear_pot()


## Lose the unbanked pot (hard hit, tow, wreck).
func break_combo() -> void:
	if multiplier == 0:
		return
	combo_lost.emit(pot * multiplier)
	_clear_pot()


func pot_value() -> int:
	return pot * multiplier


## Made it to the finish: bank the pot, then x1.5 on everything plus the time bonus.
func finish(run_seconds: float) -> void:
	bank()
	finish_bonus = int(round(banked * (FINISH_MULTIPLIER - 1.0)))
	time_bonus = maxi(0, int(par_seconds - run_seconds)) * BONUS_PER_SECOND
	banked += finish_bonus + time_bonus


func _clear_pot() -> void:
	pot = 0
	multiplier = 0
	combo_time_left = 0.0
	_pot_by_label.clear()
