extends RefCounted
## Base for test scripts run by run_tests.gd. Methods named test_* are run in order;
## a test fails if it records any failure.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not absf(actual - expected) <= tolerance:
		failures.append("%s: got %.4f, expected %.4f ± %.4f" % [message, actual, expected, tolerance])
