class_name Challenge
extends RefCounted
## The daily challenge: one run a day, the same for everyone. The day (UTC) picks the
## route, the car and its paint, the condition, and the seed that places the speed traps
## and the deer and starts the traffic, the same on every try. It has its own top tens on
## the shared leaderboard.
##
## server/app.py picks the route, car and condition the same way (challenge_for), to check
## a posted run is the day's: change the picking here and there together.

const ROUTES := ["highway1", "highway22", "highway1_south", "highway22_east"]  ## (in this order: the server's lists are the same)
const CARS := ["windstar", "tercel", "legend"]
const CONDITIONS := ["summer", "harvest", "night", "storm", "winter"]
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December"]
const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var date := ""  ## YYYY-MM-DD (UTC)
var route := ""
var car := ""
var paint := 0  ## which of the car's paints (modulo how many it has)
var condition := ""
var seed_value := 1


## Today, UTC: the same day for everyone.
static func today() -> String:
	return Time.get_date_string_from_system(true)


static func for_date(day: String) -> Challenge:
	var c := Challenge.new()
	c.date = day
	var h := _fnv(day)
	h = _next(h)
	c.route = ROUTES[(h >> 16) % ROUTES.size()]
	h = _next(h)
	c.car = CARS[(h >> 16) % CARS.size()]
	h = _next(h)
	c.condition = CONDITIONS[(h >> 16) % CONDITIONS.size()]
	h = _next(h)
	c.paint = h >> 16
	h = _next(h)
	c.seed_value = (h >> 8) + 1
	return c


## "Saturday, October 31"
static func describe_date(day: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(day + "T12:00:00"))
	return "%s, %s %d" % [DAYS[int(t.weekday)], MONTHS[int(t.month) - 1], int(t.day)]


## The car, painted (a fresh CarStats).
func car_stats() -> CarStats:
	var stats := CarStats.preset(car)
	stats.body_color = stats.paints[paint % stats.paints.size()][1]
	return stats


func paint_name() -> String:
	var paints := CarStats.preset(car).paints
	return String(paints[paint % paints.size()][0])


## FNV-1a, 32 bits, over the text's UTF-8.
static func _fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xffffffff
	return h


## The next number from a 32-bit LCG (its high bits are the good ones).
static func _next(h: int) -> int:
	return (h * 1103515245 + 12345) & 0xffffffff
