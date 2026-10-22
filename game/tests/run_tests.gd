extends SceneTree
## Headless test runner:
##   godot --headless --path game -s res://tests/run_tests.gd
## Runs every test_* method in res://tests/test_*.gd and exits non-zero on any failure.


func _initialize() -> void:
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String): return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()

	var total := 0
	var failed := 0
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("  FAIL  %s does not compile (see errors above)" % file)
			continue
		var suite = script.new()
		for method in script.get_script_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			suite.failures.clear()
			suite.call(method.name)
			if suite.failures.is_empty():
				print("  ok    %s.%s" % [file.get_basename(), method.name])
			else:
				failed += 1
				print("  FAIL  %s.%s" % [file.get_basename(), method.name])
				for f in suite.failures:
					print("          " + f)

	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
