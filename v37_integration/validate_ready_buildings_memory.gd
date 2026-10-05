extends SceneTree
## Progressive CI validation of the pre-generated ready-building assets.
## Mirrors the runtime bridge's important memory behavior: repeated ready
## signatures share one MultiMesh, while each placement keeps its lightweight
## root/collision. This avoids measuring the intentionally-removed per-instance
## MeshInstance3D duplication used only by the validator.

const READY_DIR := "res://baked_city/ready_buildings"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var count := 587
    var args := OS.get_cmdline_user_args()
    for arg in args:
        var value := str(arg).strip_edges()
        if value.is_valid_int():
            count = int(value)
            break
    count = clampi(count, 1, 587)

    var baseline := _memory_mb()
    var scene_root: Node = get_root()
    var roots: Array[Node3D] = []
    var groups: Dictionary = {}

    for i in range(count):
        var path := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if packed == null:
            push_error("READY TEST: missing/unloadable %s" % path)
            quit(1)
            return

        var node := packed.instantiate() as Node3D
        if node == null:
            push_error("READY TEST: instantiate failed %s" % path)
            quit(1)
            return
        scene_root.add_child(node)
        roots.append(node)

        var signature := str(node.get_meta("ready_signature", ""))
        var mesh_node := _find_mesh_node(node)
        if signature.is_empty() or mesh_node == null or mesh_node.mesh == null:
            push_error("READY TEST: invalid ready asset %s signature/mesh" % path)
            quit(1)
            return

        var group: Dictionary = groups.get(signature, {})
        if group.is_empty():
            groups[signature] = {
                "mesh": mesh_node.mesh,
                "mmi": null,
                "multimesh": null,
                "roots": [node]
            }
        else:
            var mm := group.get("multimesh") as MultiMesh
            var mmi := group.get("mmi") as MultiMeshInstance3D
            if mm == null or mmi == null:
                var first_root := group["roots"][0] as Node3D
                var first_mesh := _find_mesh_node(first_root)
                if first_mesh == null:
                    push_error("READY TEST: first grouped mesh missing for %s" % signature)
                    quit(1)
                    return
                mm = MultiMesh.new()
                mm.transform_format = MultiMesh.TRANSFORM_3D
                mm.use_colors = false
                mm.mesh = group["mesh"] as Mesh
                mm.instance_count = 2
                mm.set_instance_transform(0, first_root.transform)
                mm.set_instance_transform(1, node.transform)
                mmi = MultiMeshInstance3D.new()
                mmi.name = "ReadyTestMultiMesh_%s" % signature
                mmi.multimesh = mm
                scene_root.add_child(mmi)
                first_mesh.queue_free()
                mesh_node.queue_free()
                group["multimesh"] = mm
                group["mmi"] = mmi
                group["roots"].append(node)
                groups[signature] = group
            else:
                var new_count := mm.instance_count + 1
                mm.instance_count = new_count
                mm.set_instance_transform(new_count - 1, node.transform)
                mesh_node.queue_free()
                group["roots"].append(node)
                groups[signature] = group

        if (i + 1) % 10 == 0:
            await process_frame

    await process_frame
    var total := _memory_mb()
    var delta := total - baseline
    print("READY TEST %d OK: baseline=%.2f MB total=%.2f MB delta=%.2f MB groups=%d" % [count, baseline, total, delta, groups.size()])

    if count == 40 and delta >= 250.0:
        push_error("READY TEST 40 FAILED: delta %.2f MB >= 250 MB" % delta)
        quit(1)
        return
    if count == 587 and delta >= 500.0:
        push_error("READY TEST 587 FAILED: delta %.2f MB >= 500 MB" % delta)
        quit(1)
        return

    for node in roots:
        node.queue_free()
    for signature in groups:
        var group: Dictionary = groups[signature]
        var mmi := group.get("mmi") as Node
        if mmi != null:
            mmi.queue_free()
    await process_frame
    quit(0)

func _find_mesh_node(root: Node) -> MeshInstance3D:
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is MeshInstance3D:
            return current as MeshInstance3D
        for child in current.get_children():
            stack.append(child)
    return null

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
