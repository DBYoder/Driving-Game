extends "res://tests/test_case.gd"

var route := RouteData.load_from("res://data/route")


func test_every_condition_is_complete() -> void:
	for id: String in Condition.IDS:
		var c := Condition.preset(id)
		check(c.id == id, "%s: id" % id)
		check(c.display_name != "" and c.tagline != "", "%s: has a name and a tagline" % id)
		check(c.fog_end > c.fog_begin, "%s: fog thickens with distance" % id)
		check(c.grip > 0.5 and c.grip <= 1.0, "%s: grip %.2f" % [id, c.grip])
		check(c.ice_grip > 0.0 and c.ice_grip <= 1.0, "%s: ice grip" % id)
		check(c.deer_rate >= 1.0, "%s: deer rate" % id)
		for mix: Dictionary in [c.same_direction, c.oncoming]:
			for kind: String in mix:
				check(Traffic.KINDS.has(kind), "%s: unknown vehicle %s" % [id, kind])


func test_records_are_kept_per_condition() -> void:
	check(Condition.preset("summer").records_key("1993 Acura Legend") == "1993 Acura Legend",
		"summer keeps the records from before conditions")
	var keys := {}
	for id: String in Condition.IDS:
		keys[Condition.preset(id).records_key("1993 Acura Legend")] = true
	check(keys.size() == Condition.IDS.size(), "each condition has its own records")


func test_the_named_conditions_do_what_they_say() -> void:
	check(Condition.preset("night").deer_rate == 3.0, "night: deer x3")
	check(Condition.preset("storm").grip < 1.0 and Condition.preset("storm").lightning, "storm: wet, lightning")
	check(Condition.preset("winter").ice_grip < 0.5 and Condition.preset("winter").harvested == 1.0,
		"winter: black ice, the corn's all in")
	check(Condition.preset("harvest").same_direction.has("combine"), "harvest: combines")
	check(Condition.preset("winter").same_direction.has("snowplow"), "winter: snowplows")


func test_harvest_cuts_some_corn_fields() -> void:
	var fields := Fields.new(route)
	var corn := 0
	var cut := 0
	fields.harvested = 0.45
	for cx in 40:
		for cz in 40:
			var x := fields.offset.x + (cx + 0.5) * Fields.FIELD_SIZE
			var z := fields.offset.y + (cz + 0.5) * Fields.FIELD_SIZE
			var h := Fields.cell_hash(cx, cz)
			if h < 0.45:
				corn += 1
				if fields.crop_at(x, z) == Fields.STUBBLE:
					cut += 1
	check(corn > 500, "plenty of corn fields to look at (%d)" % corn)
	check(cut > corn * 0.3 and cut < corn * 0.6, "about 45%% of the corn cut (%d of %d)" % [cut, corn])
	fields.harvested = 0.0
	var x0 := fields.offset.x + 0.5 * Fields.FIELD_SIZE
	check(fields.crop_at(x0, fields.offset.y + 0.5 * Fields.FIELD_SIZE) != Fields.STUBBLE, "summer: nothing cut")


func test_traffic_mix_matches_the_old_summer_odds() -> void:
	var mix := {"tractor": 0.3, "car": 0.7}
	check(Traffic._pick(mix, 0.55, 0.5) == "tractor", "just past the buggies: a tractor")
	check(Traffic._pick(mix, 0.85, 0.5) == "car", "past the tractors: a car")
	var oncoming := {"semi": 0.2, "pickup": 0.3, "car": 0.5}
	check(Traffic._pick(oncoming, 0.1, 0.0) == "semi", "semi under 0.2")
	check(Traffic._pick(oncoming, 0.4, 0.0) == "pickup", "pickup under 0.5")
	check(Traffic._pick(oncoming, 0.99, 0.0) == "car", "car for the rest")
	check(Traffic._pick({"buggy": 0.0, "snowplow": 0.35, "car": 0.6}, 0.2, 0.15) == "snowplow", "zero shares skipped")


func test_radio_titles() -> void:
	check(Radio.title_of("/x/radio/03 - Some Song.mp3") == "Some Song", "track number dropped")
	check(Radio.title_of("/x/radio/KCJJ_ad.ogg") == "KCJJ ad", "underscores to spaces")
	check(Radio.find_songs("/nonexistent/radio").is_empty(), "no folder, no songs")
