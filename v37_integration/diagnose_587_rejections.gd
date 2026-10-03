extends SceneTree

const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        push_error("DIAG 587: main.tscn non caricabile")
        quit(1)
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame
    var grid := root.get_node_or_null("Urban_Grid")
    var rects = grid.get_meta("lot_rects", []) if grid != null else []
    var positions_script: Script = load(POSITIONS_SCRIPT) as Script
    var source: Array = positions_script.call("get_buildings") if positions_script != null else []
    var hits := 0
    var misses := 0
    print("DIAG 587: source=", source.size(), " grid=", grid != null, " rects=", rects.size())
    for i in range(source.size()):
        var d: Dictionary = source[i]
        var x := float(d.get("x", 0.0))
        var z := float(d.get("z", 0.0))
        var found := false
        for r in rects:
            if x >= float(r["min_x"]) and x <= float(r["max_x"]) and z >= float(r["min_z"]) and z <= float(r["max_z"]):
                found = true
                break
        if found:
            hits += 1
        else:
            misses += 1
        if i < 10:
            print("DIAG 587 #", i, " x=", x, " z=", z, " block=", found)
    print("DIAG 587: block_hits=", hits, " block_misses=", misses)
    root.queue_free()
    quit(0)
