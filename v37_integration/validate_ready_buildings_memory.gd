extends SceneTree
## Progressive CI validation of the pre-generated ready-building assets.

const READY_DIR := "res://baked_city/ready_buildings"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var count := 587
    var args := OS.get_cmdline_args()
    if not args.is_empty():
        var last := str(args[args.size() - 1])
        if last.is_valid_int():
            count = int(last)
    count = clampi(count, 1, 587)

    var baseline := _memory_mb()
    var nodes: Array[Node3D] = []
    for i in range(count):
        var path := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        var packed := load(path) as PackedScene
        if packed == null:
            push_error("READY TEST: missing/unloadable %s" % path)
            quit(1)
            return
        var node := packed.instantiate() as Node3D
        if node == null:
            push_error("READY TEST: instantiate failed %s" % path)
            quit(1)
            return
        add_child(node)
        nodes.append(node)
        if (i + 1) % 10 == 0:
            await get_tree().process_frame

    await get_tree().process_frame
    var total := _memory_mb()
    var delta := total - baseline
    print("READY TEST %d OK: baseline=%.2f MB total=%.2f MB delta=%.2f MB" % [count, baseline, total, delta])

    if count == 40 and delta >= 250.0:
        push_error("READY TEST 40 FAILED: delta %.2f MB >= 250 MB" % delta)
        quit(1)
        return
    if count == 587 and delta >= 500.0:
        push_error("READY TEST 587 FAILED: delta %.2f MB >= 500 MB" % delta)
        quit(1)
        return

    for node in nodes:
        node.queue_free()
    await get_tree().process_frame
    quit(0)

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
