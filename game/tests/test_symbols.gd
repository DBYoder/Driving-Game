extends "res://tests/test_case.gd"
## Every character the game writes on screen has a glyph in its own fonts: a browser has
## no system fonts to fall back on, so anything missing shows as a box there.


func test_every_character_has_a_glyph() -> void:
	var font := ThemeDB.fallback_font
	check(font.fallbacks.has(load(Settings.SYMBOLS)), "the symbols font backs up Godot's own")
	var missing := {}
	for path in _scripts("res://scripts"):
		for ch in FileAccess.get_file_as_string(path):
			if ch.unicode_at(0) > 127 and not font.has_char(ch.unicode_at(0)):
				missing[ch] = path
	check(missing.is_empty(), "no glyphs missing: %s" % [missing])


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	return out
