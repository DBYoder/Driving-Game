class_name Benchmark
extends Node
## --benchmark: the autopilot drives at 70 mph for a while, rendering normally, then this
## prints frames per second (average and the slowest 1% of frames), draw calls and
## triangles per frame, and quits. For checking a change against the potato budget, or
## how well a friend's computer copes.

const SECONDS := 40.0
const WARM_UP := 3.0  ## skip the first frames (shader compiles, streaming settling)

var _time := 0.0
var _frame_times: Array[float] = []
var _draw_calls := 0.0
var _triangles := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_time += delta
	if _time < WARM_UP:
		return
	_frame_times.append(delta)
	_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_triangles += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if _time >= SECONDS:
		_report()


func _report() -> void:
	set_process(false)
	var n := _frame_times.size()
	var total := 0.0
	for t in _frame_times:
		total += t
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var worst_1pct: float = sorted[mini(n - 1, floori(n * 0.99))]
	print("BENCHMARK: %.0f fps average, %.0f fps 1%% low, %.0f draw calls, %.0fk triangles per frame (%d frames, %s)" % [
		n / total, 1.0 / worst_1pct, _draw_calls / n, _triangles / n / 1000.0, n,
		RenderingServer.get_video_adapter_name()])
	get_tree().quit(0)
