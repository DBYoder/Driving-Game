class_name Boost
extends RefCounted
## The boost meter. Near misses fill it: an oncoming car whistling past your mirror, or
## squeezing past something in your lane with almost no room. Hold the boost button to
## burn it: a hard shove forward and a higher top speed, more than any deputy's cruiser
## can match. Two full burns lose a deputy in any of the cars.

const BURN_SECONDS := 4.0  ## a full meter lasts this long
const THRUST := 7.0  ## m/s² of extra push while burning
const EXTRA_TOP_SPEED := 25.0  ## m/s (56 mph) the car keeps pulling past its usual top speed...
const MAX_SPEED := 75.0  ## m/s (168 mph) ...up to this
const NEAR_MISS := 0.4  ## of a full meter, for an oncoming near miss
const CLOSE_PASS := 0.25  ## for squeezing past something going your way

signal filled(amount: float)

var meter := 0.0  ## 0..1
var active := false  ## burning right now


func reset() -> void:
	meter = 0.0
	active = false


func fill(amount: float) -> void:
	var before := meter
	meter = minf(meter + amount, 1.0)
	if meter > before:
		filled.emit(meter - before)


## One tick: burn while `held` and there's some left. Returns whether it's burning.
func update(held: bool, delta: float) -> bool:
	active = held and meter > 0.0
	if active:
		meter = maxf(meter - delta / BURN_SECONDS, 0.0)
	return active


## How fast a car whose usual top speed is `car_top_speed` goes while boosting.
static func top_speed(car_top_speed: float) -> float:
	return minf(car_top_speed + EXTRA_TOP_SPEED, maxf(MAX_SPEED, car_top_speed))


func full() -> bool:
	return meter >= 1.0
