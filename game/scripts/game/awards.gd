class_name Awards
extends RefCounted
## The results screen's one-line title for a run, from the way it ended and what
## happened on the way. First match wins.


## `run`: {finished: bool, wreck: String, car: String (car id), seconds: float,
## score: int, counts: {label: n}, raw: {label: points before multipliers}, honked: int}
static func title_for(run: Dictionary) -> String:
	var counts: Dictionary = run.get("counts", {})
	var raw: Dictionary = run.get("raw", {})
	var wreck: String = run.get("wreck", "")
	match wreck:
		"You hit an Amish buggy":
			return "The horse saw that coming."
		"Busted":
			return "Should've used the boost."
		"Rolled it":
			return "Minivan gymnastics: a perfect 10." if run.get("car", "") == "windstar" else "Shiny side down."
		"Totaled":
			return "The insurance adjuster is on the way."
	if wreck.begins_with("Head-on"):
		return "Two lanes, and you picked the wrong one."
	var corn_m := int(raw.get("Corn", 0) / 5)
	if corn_m >= 300:
		return "Unlicensed combine operator: %d m of corn." % corn_m
	if counts.get("Mailbox", 0) >= 8:
		return "Federal mailbox offender (%d counts)." % counts.Mailbox
	if raw.get("Airtime", 0) >= 1500:
		return "Cleared for takeoff: %.1f s in the air." % (raw.Airtime / 200.0)
	if counts.get("Lost the cop", 0) + counts.get("Jurisdiction", 0) >= 2:
		return "The Dukes of Washington County."
	if counts.get("Near miss", 0) + counts.get("Close pass", 0) >= 8:
		return "Mirror to mirror, all the way."
	if run.get("honked", 0) >= 3:
		return "Deer whisperer (it was mostly the horn)."
	if counts.get("Deer dodged", 0) >= 4:
		return "Deer whisperer."
	if counts.get("Hay bale", 0) >= 6:
		return "Hay there."
	if counts.get("Fence", 0) >= 40:
		return "Good fences make good points."
	if run.get("finished", false):
		if run.get("seconds", 1e9) < Routes.info().par_seconds * 0.73:
			return "Hauling cheese curds."
		if run.get("score", 0) < 3000:
			return "Drove it like a rental."
		return "Made it to %s. Mom would be proud." % Routes.info().to
	return "Just another day on Highway %s." % Routes.info().number
