class_name Routes
extends RefCounted
## The routes you can drive, each baked by the tools (tools/config.py ROUTES) into
## data/routes/<id>/, and which one is on. Highway 1 north from the 4-way stop in Kalona to
## Iowa City, Highway 22 west from it to Wellman, and each the other way, back to Kalona:
## the same baked road and world, the other way along it (RouteData.reverse). The garage
## picks one (and remembers it); the world is rebuilt for it (Main.change_route).

const IDS := ["highway1", "highway1_south", "highway22", "highway22_east"]
const DEFAULT := "highway1"
## What the game needs to know about each route that isn't in its baked data:
##   title, from, to   for the menus and the HUD ("HIGHWAY 1  ·  Kalona → Iowa City")
##   number, heading   the route markers along the road (NORTH over IOWA 1)
##   data, reversed    which baked route it drives (data/routes/<data>/), and whether the
##                     other way along it (back to Kalona)
##   start             what the start is: "4way" (the 4-way stop in Kalona, Junction),
##                     "light" (traffic lights) or "stop" (the cross street stops for us)
##   start_stop_line   the start line is this far short of the middle of that
##                     intersection, m (tools/config.py start_stop_line_m): Highway 1 at
##                     the stop line coming up from the south, Highway 22 past the middle,
##                     pointed west straight out of it; the ways back past the middle too
##   finish            what the finish is (like start)
##   finish_stop_line  the finish line is this far short of the middle of the
##                     intersection, m (tools/config.py finish_stop_line_m)
##   section_corner    a crossroad on the section lines both ways, where the patchwork of
##                     fields lines up (Fields)
##   traps             speed traps per county (Cops)
##   par_seconds       a finish faster than this earns a time bonus (ScoreKeeper)
##   min_miles, min_buildings, min_trees, landmark   what the smoke test expects
const INFO := {
	"highway1": {
		"title": "HIGHWAY 1",
		"from": "Kalona",
		"to": "Iowa City",
		"number": "1",
		"heading": "NORTH",
		"tagline": "15 miles north to Iowa City's first stop light, over the county line.",
		"data": "highway1",
		"reversed": false,
		"start": "4way",
		"start_stop_line": 12.0,
		"finish": "light",
		"finish_stop_line": 12.0,
		"section_corner": "540th St SW",
		"traps": {"Washington": 1, "Johnson": 3},
		"par_seconds": 900.0,
		"min_miles": 14.5,
		"min_buildings": 500,
		"min_trees": 5000,
		"landmark": true,
	},
	"highway1_south": {
		"title": "HIGHWAY 1 SOUTH",
		"from": "Iowa City",
		"to": "Kalona",
		"number": "1",
		"heading": "SOUTH",
		"tagline": "15 miles south from Mormon Trek, back over the county line to the 4-way stop in Kalona.",
		"data": "highway1",
		"reversed": true,
		"start": "light",
		"start_stop_line": -12.0,
		"finish": "4way",
		"finish_stop_line": 12.0,
		"section_corner": "540th St SW",
		"traps": {"Washington": 1, "Johnson": 3},
		"par_seconds": 900.0,
		"min_miles": 14.5,
		"min_buildings": 500,
		"min_trees": 5000,
		"landmark": true,
	},
	"highway22": {
		"title": "HIGHWAY 22",
		"from": "Kalona",
		"to": "Wellman",
		"number": "22",
		"heading": "WEST",
		"tagline": "7 miles west to downtown Wellman, over the English River.",
		"data": "highway22",
		"reversed": false,
		"start": "4way",
		"start_stop_line": -12.0,
		"finish": "stop",
		"finish_stop_line": 8.0,
		"section_corner": "Kiwi Ave",
		"traps": {"Washington": 2},
		"par_seconds": 400.0,
		"min_miles": 6.5,
		"min_buildings": 1000,
		"min_trees": 30000,
		"landmark": true,
	},
	"highway22_east": {
		"title": "HIGHWAY 22 EAST",
		"from": "Wellman",
		"to": "Kalona",
		"number": "22",
		"heading": "EAST",
		"tagline": "7 miles east from downtown Wellman, over the English River to the 4-way stop in Kalona.",
		"data": "highway22",
		"reversed": true,
		"start": "stop",
		"start_stop_line": -8.0,
		"finish": "4way",
		"finish_stop_line": 12.0,
		"section_corner": "Kiwi Ave",
		"traps": {"Washington": 2},
		"par_seconds": 400.0,
		"min_miles": 6.5,
		"min_buildings": 1000,
		"min_trees": 30000,
		"landmark": true,
	},
}

static var current := DEFAULT


## The route's details (INFO), the one on now if `id` is "".
static func info(id := "") -> Dictionary:
	return INFO.get(current if id.is_empty() else id, INFO[DEFAULT])


## Where its baked data is (the way back shares the way out's).
static func dir(id: String) -> String:
	return "res://data/routes".path_join(String(info(id).get("data", id)) if INFO.has(id) else id)


## "HIGHWAY 22  ·  Kalona → Wellman"
static func headline(id := "") -> String:
	var i := info(id)
	return "%s  ·  %s → %s" % [i.title, i.from, i.to]


## Records are kept per route. Highway 1's keep the keys they had before there were
## routes; the others' are prefixed with the route.
static func records_key(key: String, id := "") -> String:
	var route := current if id.is_empty() else id
	return key if route == DEFAULT else "%s|%s" % [route, key]


## The route last picked in the garage (saved in its section of the save file).
static func saved(path: String) -> String:
	var cfg := ConfigFile.new()
	if path.is_empty() or cfg.load(path) != OK:
		return DEFAULT
	var id: String = cfg.get_value("garage", "route", DEFAULT)
	return id if id in IDS else DEFAULT
