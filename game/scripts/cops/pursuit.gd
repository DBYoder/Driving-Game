class_name Pursuit
extends RefCounted
## The rules of a police chase, apart from the driving: what the radar flags, when
## you're busted, when you've lost the cop, and when the cop has to give up because
## you've left their county.

enum Outcome { NONE, BUSTED, LOST, JURISDICTION, GAVE_UP }

const TRIGGER_SPEED := 32.2  ## m/s (72 mph) on a 55 road: what gets a deputy's attention
const RADAR_RANGE := 130.0  ## m
const BUST_GAP := 15.0  ## m: the cop's right there...
const BUST_SPEED := 4.5  ## m/s (10 mph): ...you're barely moving...
const BUST_SECONDS := 3.0  ## ...for this long: busted
const LOST_GAP := 600.0  ## m: this far ahead of the cop...
const LOST_SECONDS := 4.0  ## ...for this long: you've lost them
const MAX_SECONDS := 150.0  ## then the deputy gives up anyway

var county: String  ## whose deputy it is
var time := 0.0
var bust_timer := 0.0  ## how long you've been stopped next to the cop
var lost_timer := 0.0


func _init(cop_county: String) -> void:
	county = cop_county


## Does a parked deputy's radar flag a car `distance` away doing `speed`?
static func spotted(distance: float, speed: float) -> bool:
	return distance <= RADAR_RANGE and speed > TRIGGER_SPEED


## One tick of the chase: `gap` between the cars, how fast the player is going, which
## county they're in now, and whether the cruiser is wrecked. NONE while it goes on.
func update(delta: float, gap: float, player_speed: float, player_county: String, cop_wrecked: bool) -> Outcome:
	time += delta
	if player_county != county:
		return Outcome.JURISDICTION
	if cop_wrecked:
		return Outcome.LOST
	bust_timer = bust_timer + delta if gap < BUST_GAP and player_speed < BUST_SPEED else 0.0
	if bust_timer >= BUST_SECONDS:
		return Outcome.BUSTED
	lost_timer = lost_timer + delta if gap > LOST_GAP else 0.0
	if lost_timer >= LOST_SECONDS:
		return Outcome.LOST
	if time >= MAX_SECONDS:
		return Outcome.GAVE_UP
	return Outcome.NONE
