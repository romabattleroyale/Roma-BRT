extends SceneTree
## Hard gate for the 120-template architecture: 120 templates in memory, then 587 virtual placements with max 50 active.
const DIR := "res://baked_city/ready_templates"
const TEMPLATE_COUNT := 120
const PLACEMENT_COUNT := 587
const MAX_ACTIVE := 50

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var baseline := Performance.get_monitor(Performance.MEMORY_STATIC)
    var templates: Array[PackedScene] = []
    for i in range(TEMPLATE_COUNT):
        var p := ResourceLoader.load("%s/template_%03d.tscn" % [DIR, i + 1], "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if p == null:
            push_error("READY TEMPLATE TEST: missing template %d" % (i + 1))
            quit(1)
            return
        templates.append(p)
    await process_frame
    var template_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC) - baseline) / 1048576.0
    print("READY TEMPLATE TEST 120 OK: delta_mb=%.2f" % template_mb)
    if template_mb >= 200.0:
        push_error("READY TEMPLATE TEST: 120 templates >= 200 MB")
        quit(1)
        return

    # Measure only incremental runtime memory. The old validator measured from the
    # process baseline and then added template_mb again, double-counting templates.
    var runtime_baseline := Performance.get_monitor(Performance.MEMORY_STATIC)
    var max_runtime_delta_mb := 0.0
    var active: Array[Node3D] = []
    var runtime_root := Node3D.new()
    get_root().add_child(runtime_root)

    for i in range(PLACEMENT_COUNT):
        var template_index := posmod(i * 17 + 11, TEMPLATE_COUNT)
        var instance := templates[template_index].instantiate() as Node3D
        if instance == null:
            push_error("READY VIRTUAL TEST: instantiate failed %d" % i)
            runtime_root.queue_free()
            await process_frame
            quit(1)
            return
        instance.scale.y = [1.0, 1.333333, 1.666667][posmod(i, 3)]
        runtime_root.add_child(instance)
        active.append(instance)
        if active.size() > MAX_ACTIVE:
            var old: Node3D = active.pop_front()
            old.queue_free()
        await process_frame
        var current_delta_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC) - runtime_baseline) / 1048576.0
        max_runtime_delta_mb = maxf(max_runtime_delta_mb, current_delta_mb)

    for node in active:
        node.queue_free()
    await process_frame
    runtime_root.queue_free()
    await process_frame

    print("READY VIRTUAL TEST 587 OK: max_active=%d max_runtime_delta_mb=%.2f total_virtual=587" % [MAX_ACTIVE, max_runtime_delta_mb])
    if max_runtime_delta_mb >= 150.0:
        push_error("READY VIRTUAL TEST: runtime incremental peak >= 150 MB")
        quit(1)
        return

    var total_mb := template_mb + max_runtime_delta_mb
    print("READY FINAL MEMORY: templates_mb=%.2f runtime_incremental_mb=%.2f total_budget_mb=%.2f" % [template_mb, max_runtime_delta_mb, total_mb])
    if total_mb >= 300.0:
        push_error("READY FINAL MEMORY: total budget >= 300 MB")
        quit(1)
        return
    print("READY TEMPLATE ARCHITECTURE OK: 120 templates / 587 virtual placements / max 50 active / total < 300 MB")
    quit(0)
