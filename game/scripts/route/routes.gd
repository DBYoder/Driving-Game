class_name Routes
extends RefCounted
## The routes you can drive, each baked by the tools (tools/config.py ROUTES) into
## data/routes/<id>/, and which one is on. Both start at the 4-way stop in Kalona: Highway 1
## north to Iowa City, Highway 22 west to Wellman. The garage picks one (and remembers it);
## the world is rebuilt for it (Main.change_route).

const IDS := ["highway1", "highway22"]
const DEFAULT := "highway1"
## What the game needs to know about each route that isn't in its baked data:
##   title, from, to   for the menus and the HUD ("HIGHWAY 1  ·  Kalona → Iowa City")
##   number, heading   the route markers along the road (NORTH over IOWA 1)
##   start_stop_line   the start line is this far short of the middle of the 4-way stop,
##                     m (tools/config.py start_stop_line_m): Highway 1 at the stop line
##                     coming up from the south, Highway 22 past the middle, pointed west
##                     straight out of it
##   finish            "light": traffic lights at the finish; "stop": the cross street
##                     stops for us (Intersections)
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
	"highway22": {
		"title": "HIGHWAY 22",
		"from": "Kalona",
		"to": "Wellman",
		"number": "22",
		"heading": "WEST",
		"tagline": "7 miles west to downtown Wellman, over the English River.",
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
}

static var current := DEFAULT


## The route's details (INFO), the one on now if `id` is "".
static func info(id := "") -> Dictionary:
	return INFO.get(current if id.is_empty() else id, INFO[DEFAULT])


static func dir(id: String) -> String:
	return "res://data/routes".path_join(id)


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
