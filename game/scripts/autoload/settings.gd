extends Node
## The player's settings (autoload `Settings`): graphics, sound and rumble, saved to
## user://settings.cfg. Main loads them (unless it's a test run) and applies the graphics
## ones to the world; the volumes go straight to the audio buses.
##
## A graphics preset sets everything at once; the resolution and scenery can then be
## changed on their own (the preset keeps the anti-aliasing, model detail and particles).
## (No sun shadows: in the Compatibility renderer they wash out the lighting, and the cars
## already have their blob shadows.)

signal changed

const SAVE_PATH := "user://settings.cfg"
const OLD_SAVE_PATH := "user://records.cfg"  ## the scenery setting lived here before v0.6
const PRESETS := ["low", "medium", "high"]
const PRESET_NAMES := {"low": "Low (slow PCs)", "medium": "Medium", "high": "High"}
## What each preset sets: 3D resolution, how much scenery, anti-aliasing, how far out
## buildings and trees get their detailed models (m), and how much rain and snow.
const PRESET_VALUES := {
	"low": {"render_scale": 0.75, "scenery": 0.5, "msaa": false, "detail": 300.0, "particles": 0.5},
	"medium": {"render_scale": 1.0, "scenery": 1.0, "msaa": false, "detail": 450.0, "particles": 1.0},
	"high": {"render_scale": 1.0, "scenery": 1.0, "msaa": true, "detail": 800.0, "particles": 1.0},
}
const RENDER_SCALES := [0.5, 0.6, 0.7, 0.75, 0.8, 0.9, 1.0]
const SCENERY_LEVELS := [1.0, 0.5, 0.0]
const SCENERY_NAMES := {1.0: "Everything", 0.5: "Half the trees", 0.0: "Off (fastest)"}
const BUSES := ["Effects", "Radio"]  ## besides Master
const SYMBOLS := "res://fonts/symbols.ttf"  ## see _add_symbols()

var preset := "medium"
var render_scale := 1.0
var scenery := 1.0
var fullscreen := false
var master_volume := 1.0
var effects_volume := 1.0
var radio_volume := 0.8
var rumble := true
var ghost := true  ## your best run's ghost car (Ghost)
var player_name := ""  ## on the shared leaderboard ("": asked after the next run)
var touch_controls := "auto"  ## see Touch: "auto", "on" or "off"
var save_path := ""  ## "" = don't save (tests)


func _init() -> void:
	_add_symbols()


func _ready() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_apply_volumes()


## The arrows and triangles in the menus and the HUD (→ ▲ ▼ ◀ ▶ ♪) aren't in Godot's own
## font. A desktop borrows them from the system's fonts, a browser has none to lend:
## fonts/symbols.ttf has just those, cut from DejaVu Sans Bold.
func _add_symbols() -> void:
	var font := ThemeDB.fallback_font
	var symbols: Font = load(SYMBOLS)
	if font and symbols and not font.fallbacks.has(symbols):
		font.fallbacks = font.fallbacks + [symbols]


func detail_distance() -> float:
	return PRESET_VALUES[preset].detail


func msaa() -> bool:
	return PRESET_VALUES[preset].msaa


func particles() -> float:
	return PRESET_VALUES[preset].particles


## Back to the defaults (Medium, full volume, rumble on), without saving. On a phone or
## tablet: Low, with the 3D drawn at about 600 lines (their screens have two or three times
## the pixels a PC's has, and much less to draw them with).
func reset() -> void:
	set_preset("medium", false)
	if handheld():
		set_preset("low", false)
		render_scale = handheld_render_scale(DisplayServer.window_get_size().y)
	fullscreen = false
	master_volume = 1.0
	effects_volume = 1.0
	radio_volume = 0.8
	rumble = true
	ghost = true
	player_name = ""
	touch_controls = "auto"
	_apply_volumes()


## A phone or a tablet (in a browser, or a mobile build). An iPad's Safari says it's a Mac:
## a "Mac" with a touch screen is an iPad (as the page's own script reckons, web/shell.html).
static func handheld() -> bool:
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		return true
	return OS.has_feature("web_macos") and int(JavaScriptBridge.eval("navigator.maxTouchPoints || 0", true)) > 1


## The resolution that draws the 3D at about 600 lines on a screen this many pixels high.
static func handheld_render_scale(screen_height: int) -> float:
	return _nearest(clampf(600.0 / maxf(screen_height, 1.0), RENDER_SCALES[0], 1.0), RENDER_SCALES)


## Read them from `path` (and remember it for saving). A first run picks up the scenery
## setting from the old records file.
func load_file(path := SAVE_PATH) -> void:
	save_path = path
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		var old := ConfigFile.new()
		if path == SAVE_PATH and old.load(OLD_SAVE_PATH) == OK:
			scenery = _nearest(float(old.get_value("settings", "scenery", 1.0)), SCENERY_LEVELS)
		return
	var p: String = cfg.get_value("graphics", "preset", "medium")
	preset = p if p in PRESETS else "medium"
	render_scale = _nearest(float(cfg.get_value("graphics", "render_scale", render_scale)), RENDER_SCALES)
	scenery = _nearest(float(cfg.get_value("graphics", "scenery", scenery)), SCENERY_LEVELS)
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
	master_volume = clampf(float(cfg.get_value("sound", "master", master_volume)), 0.0, 1.0)
	effects_volume = clampf(float(cfg.get_value("sound", "effects", effects_volume)), 0.0, 1.0)
	radio_volume = clampf(float(cfg.get_value("sound", "radio", radio_volume)), 0.0, 1.0)
	rumble = bool(cfg.get_value("controller", "rumble", true))
	ghost = bool(cfg.get_value("graphics", "ghost", true))
	player_name = str(cfg.get_value("leaderboard", "name", ""))
	var t: String = cfg.get_value("controls", "touch", "auto")
	touch_controls = t if t in ["auto", "on", "off"] else "auto"
	_apply_volumes()


func save() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "scenery", scenery)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("sound", "master", master_volume)
	cfg.set_value("sound", "effects", effects_volume)
	cfg.set_value("sound", "radio", radio_volume)
	cfg.set_value("controller", "rumble", rumble)
	cfg.set_value("graphics", "ghost", ghost)
	cfg.set_value("leaderboard", "name", player_name)
	cfg.set_value("controls", "touch", touch_controls)
	cfg.save(save_path)


## Pick a preset: it sets the resolution and scenery too.
func set_preset(id: String, notify := true) -> void:
	preset = id
	render_scale = PRESET_VALUES[id].render_scale
	scenery = PRESET_VALUES[id].scenery
	if notify:
		_changed()


## Change one setting by name (the settings screen): the next or previous choice for
## lists, ±10% for volumes, on/off for switches.
func step(setting: String, direction: int) -> void:
	match setting:
		"preset":
			set_preset(PRESETS[posmod(PRESETS.find(preset) + direction, PRESETS.size())], false)
		"render_scale":
			render_scale = RENDER_SCALES[clampi(RENDER_SCALES.find(render_scale) + direction, 0, RENDER_SCALES.size() - 1)]
		"scenery":
			scenery = SCENERY_LEVELS[posmod(SCENERY_LEVELS.find(scenery) + direction, SCENERY_LEVELS.size())]
		"fullscreen":
			fullscreen = not fullscreen
		"master_volume", "effects_volume", "radio_volume":
			set(setting, clampf(snappedf(float(get(setting)) + 0.1 * direction, 0.1), 0.0, 1.0))
		"rumble":
			rumble = not rumble
		"ghost":
			ghost = not ghost
		"player_name":
			player_name = ""  # asked again after the next run
		"touch_controls":
			var modes := ["auto", "on", "off"]
			touch_controls = modes[posmod(modes.find(touch_controls) + direction, modes.size())]
	_changed()


## How a setting reads on the settings screen.
func describe(setting: String) -> String:
	match setting:
		"preset":
			return PRESET_NAMES[preset]
		"render_scale":
			return "%d%%" % roundi(render_scale * 100.0)
		"scenery":
			return SCENERY_NAMES[scenery]
		"fullscreen":
			return "Full screen" if fullscreen else "Window"
		"master_volume", "effects_volume", "radio_volume":
			return "%d%%" % roundi(float(get(setting)) * 100.0)
		"rumble":
			return "On" if rumble else "Off"
		"ghost":
			return "Your best run's" if ghost else "Off"
		"player_name":
			return player_name + "  (◀ ▶ to change)" if player_name != "" else "Asked after your next run"
		"touch_controls":
			return {"auto": "Auto (when the screen's touched)", "on": "On", "off": "Off"}[touch_controls]
	return ""


## The game window: full screen or not (nothing to do without a real display).
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## A short shake of the controller (if it's on), `weak` and `strong` motors 0..1.
func rumble_pad(weak: float, strong: float, seconds: float) -> void:
	if not rumble:
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


func _changed() -> void:
	_apply_volumes()
	apply_window()
	save()
	changed.emit()


func _apply_volumes() -> void:
	var levels := {"Master": master_volume, "Effects": effects_volume, "Radio": radio_volume}
	for bus: String in levels:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(levels[bus], 0.0001)))


static func _nearest(value: float, choices: Array) -> float:
	var best: float = choices[0]
	for c: float in choices:
		if absf(c - value) < absf(best - value):
			best = c
	return best
