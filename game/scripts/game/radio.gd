class_name Radio
extends Node
## The car radio plays your own music: any .mp3 or .ogg in a radio/ folder next to the
## game (PLAN.md §4.7), shuffled. N / D-pad right skips, B / D-pad left turns it off and on.
## No folder or no songs: it stays quiet. In a browser there's no folder: no radio.

signal now_playing(title: String)

const VOLUME_DB := -8.0

var folder := ""
var songs: PackedStringArray = []
var on := true
var _order: Array[int] = []
var _player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps playing on the pause screen
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.bus = "Radio"
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_next)
	add_child(_player)
	if OS.has_feature("web"):
		on = false
		return
	folder = default_folder()
	songs = find_songs(folder)


## Next to the .exe in a build; next to the project folder when run from the editor.
static func default_folder() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../radio").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("radio")


static func find_songs(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		var ext := file.get_extension().to_lower()
		if ext == "mp3" or ext == "ogg":
			out.append(dir_path.path_join(file))
	out.sort()
	return out


## The song's title from its file name: "03 - Some Song.mp3" -> "Some Song".
static func title_of(path: String) -> String:
	var name := path.get_file().get_basename()
	var parts := name.split(" - ", false, 1)
	if parts.size() == 2 and parts[0].strip_edges().is_valid_int():
		name = parts[1]
	return name.replace("_", " ").strip_edges()


static func load_song(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			return mp3 if not mp3.data.is_empty() else null
	return null


## Start playing (if there's anything to play).
func start() -> void:
	if on and not songs.is_empty() and not _player.playing:
		_next()


func _unhandled_input(event: InputEvent) -> void:
	if songs.is_empty():
		return
	if event.is_action_pressed("radio_next"):
		on = true
		_next()
	elif event.is_action_pressed("radio_power"):
		on = not on
		if on:
			_next()
		else:
			_player.stop()
			now_playing.emit("Radio off")
	else:
		return
	get_viewport().set_input_as_handled()


func _next() -> void:
	if not on or songs.is_empty():
		return
	for attempt in songs.size():
		if _order.is_empty():
			for i in songs.size():
				_order.append(i)
			# Shuffle (Fisher-Yates) with our own generator.
			for i in range(_order.size() - 1, 0, -1):
				var j := _rng.randi_range(0, i)
				var t := _order[i]
				_order[i] = _order[j]
				_order[j] = t
		var path := songs[_order.pop_back()]
		var stream := load_song(path)
		if stream == null:
			continue  # not a readable song; try the next
		_player.stream = stream
		_player.play()
		now_playing.emit("♪  " + title_of(path))
		return
