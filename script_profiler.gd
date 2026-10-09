extends Node
## Safe per-script _process profiler. Never invokes another node's _process().
var timings: Dictionary = {}
var _frame_counter := 0

func record_process(script_name: String, elapsed_usec: int) -> void:
    timings[script_name] = maxi(int(timings.get(script_name, 0)), elapsed_usec)

func _process(_delta: float) -> void:
    _frame_counter += 1
    if _frame_counter % 60 != 0 or timings.is_empty():
        return
    var names: Array = timings.keys()
    names.sort_custom(func(a, b): return int(timings[a]) > int(timings[b]))
    print("[PROCESS TOP] --- measured _process() costs (max sample in last window) ---")
    for i in range(mini(5, names.size())):
        var name: String = str(names[i])
        print("[PROCESS] ", name, ": ", "%.3f" % (float(timings[name]) / 1000.0), " ms")
    timings.clear()
