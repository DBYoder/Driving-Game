extends Node
## The shared leaderboard (autoload `Leaderboard`; the server is server/app.py): the top
## ten times and the top ten scores on each route, from everyone's runs.
##
## In the browser it's the site the game came from. A desktop build posts there too once
## the project setting highway/leaderboard_url is set to the site's address; until then
## (and in tests) it's off and nothing's sent.

signal posted(result: Dictionary)  ## {ok, error, time_rank, points_rank} (ranks 1-10, or 0: not in the top ten)
signal fetched(route_id: String, board: Dictionary)  ## {ok, error, times: [...], points: [...]}

const TIMEOUT := 10.0
const NAME_LENGTH := 16

var base_url := ""  ## "" = no leaderboard


func _ready() -> void:
	if OS.has_feature("web"):
		base_url = str(JavaScriptBridge.eval("window.location.origin", true))
	else:
		base_url = str(ProjectSettings.get_setting("highway/leaderboard_url", ""))
	base_url = base_url.trim_suffix("/")


func enabled() -> bool:
	return base_url != ""


## Post a run that ended (finished or wrecked): the reply comes as `posted`.
func post_run(body: Dictionary) -> void:
	if not enabled():
		return
	_send("/api/runs", HTTPClient.METHOD_POST, JSON.stringify(body), func(ok: bool, data: Dictionary, error: String):
		posted.emit({"ok": ok, "error": error, "time_rank": int(data.get("time_rank", 0) if data.get("time_rank") != null else 0),
			"points_rank": int(data.get("points_rank", 0) if data.get("points_rank") != null else 0)}))


## Ask for a route's top tens: they come as `fetched`.
func fetch(route_id: String) -> void:
	if not enabled():
		fetched.emit(route_id, {"ok": false, "error": "no leaderboard here", "times": [], "points": []})
		return
	_send("/api/leaderboard?route=" + route_id.uri_encode(), HTTPClient.METHOD_GET, "", func(ok: bool, data: Dictionary, error: String):
		fetched.emit(route_id, {"ok": ok, "error": error, "times": data.get("times", []), "points": data.get("points", [])}))


## What gets posted for a run: the server checks it all again.
static func run_body(route_id: String, player: String, points: int, seconds: float, car_id: String,
		condition_id: String, version: String) -> Dictionary:
	return {"route": route_id, "name": tidy_name(player), "points": maxi(points, 0),
		"seconds": snappedf(seconds, 0.01) if seconds > 0.0 else null, "car": car_id,
		"condition": condition_id, "version": version}


## A name as the leaderboard keeps it: letters, numbers, spaces and . ' _ -, at most 16.
static func tidy_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in " .'_-":
			out += ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().left(NAME_LENGTH).strip_edges()


## "1st", "2nd", "3rd", "4th"...
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


## One line on the results screen for where a run placed.
static func placing(result: Dictionary, route_title: String) -> String:
	if not result.get("ok", false):
		var why := str(result.get("error", ""))
		if why in ["", "no connection", "couldn't send"] or why.begins_with("error "):
			return "Couldn't reach the leaderboard"
		return "Not on the leaderboard: " + why
	var parts: Array[String] = []
	if int(result.time_rank) > 0:
		parts.append("%s fastest" % ordinal(int(result.time_rank)))
	if int(result.points_rank) > 0:
		parts.append("%s best score" % ordinal(int(result.points_rank)))
	if parts.is_empty():
		return "Not in %s's top ten this time" % route_title
	return "%s on %s!" % [" and ".join(parts), route_title]


func _send(path: String, method: int, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray):
		http.queue_free()
		var data = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		var reply: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
		if result != HTTPRequest.RESULT_SUCCESS:
			done.call(false, {}, "no connection")
		elif code != 200:
			done.call(false, reply, str(reply.get("error", "error %d" % code)))
		else:
			done.call(true, reply, ""))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if http.request(base_url + path, headers, method, body) != OK:
		http.queue_free()
		done.call(false, {}, "couldn't send")
