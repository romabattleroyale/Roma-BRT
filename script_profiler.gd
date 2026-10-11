extends Node
## Safe per-script _process profiler. Never invokes another node's _process().
var timings: Dictionary = {}
var _frame_counter: int = 0

func record_process(script_name: String, elapsed_usec: int) -> void:
    timings[script_name] = maxi(int(timings.get(script_name, 0)), elapsed_usec)

func _process(_delta: float) -> void:
    _frame_counter += 1
    if _frame_counter < 60 or _frame_counter % 60 != 0 or timings.is_empty():
        return
    var names: Array = timings.keys()
    names.sort_custom(Callable(self, "_compare_timing_names"))
    print("[PROCESS TOP] --- measured _process() costs (max sample in last window) ---")
    for i in range(mini(5, names.size())):
        var script_name: String = str(names[i])
        var elapsed_ms: float = float(timings[script_name]) / 1000.0
        print("[PROCESS] ", script_name, ": ", "%.3f" % elapsed_ms, " ms")
    timings.clear()

func _compare_timing_names(a: Variant, b: Variant) -> bool:
    return int(timings[a]) > int(timings[b])
