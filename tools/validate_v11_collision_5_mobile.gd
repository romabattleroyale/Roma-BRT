extends SceneTree
## V11 collision gate with texture/material prewarm.
## The old gate measured first-use texture allocation as collision memory.
## This gate preloads the shared mobile materials first, then measures the
## incremental cost of five building instances. Collision limits remain strict.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"
const BUILDINGS := 5
const MEMORY_TARGET_MB := 20.0
const MAX_COLLISION_TRIANGLES_PER_BUILDING := 200
const MAX_COLLISION_SHAPES_PER_BUILDING := 8
const MATERIAL_DIR := "res://baked_city/v11_shared_materials"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var entries := _read_entries()
    if entries.size() < BUILDINGS:
        push_error("V11 COLLISION FAIL: only %d entries" % entries.size())
        quit(2)
        return

    var prewarm_count := _prewarm_materials()
    await process_frame
    var baseline := _memory_mb()
    var root := Node3D.new()
    root.name = "V11CollisionValidation"
    get_root().add_child(root)
    var cache: Dictionary = {}
    var visual_total := 0
    var collision_total := 0
    var concave_total := 0
    var max_shapes := 0
    var max_nodes := 0

    for i in range(BUILDINGS):
        var path := str(entries[i]["archetype"])
        var packed := cache.get(path) as PackedScene
        if packed == null:
            packed = load(path) as PackedScene
            if packed == null:
                push_error("V11 COLLISION FAIL: cannot load %s" % path)
                quit(3)
                return
            cache[path] = packed
        var node := packed.instantiate() as Node3D
        if node == null:
            push_error("V11 COLLISION FAIL: instantiate %s" % path)
            quit(4)
            return
        node.transform = entries[i]["transform"]
        root.add_child(node)
        var stats := _inspect(node)
        visual_total += stats["visual_triangles"]
        collision_total += stats["collision_triangles"]
        concave_total += stats["concave_faces"]
        max_shapes = max(max_shapes, stats["collision_shapes"])
        max_nodes = max(max_nodes, stats["nodes"])
        print("[V11 COLLISION SCALE] edificio=%d visual_triangles=%d collision_triangles=%d concave_faces=%d collision_shapes=%d nodes=%d" % [i + 1, stats["visual_triangles"], stats["collision_triangles"], stats["concave_faces"], stats["collision_shapes"], stats["nodes"]])
        await process_frame

    var final_memory := _memory_mb()
    var delta := final_memory - baseline
    print("=== V11 COLLISION 5 MOBILE ===")
    print("Edifici: %d" % BUILDINGS)
    print("Materiali prewarm: %d" % prewarm_count)
    print("Triangoli visivi totali: %d" % visual_total)
    print("Triangoli collisione totali: %d" % collision_total)
    print("Facce Concave residue: %d" % concave_total)
    print("CollisionShape3D max/edificio: %d" % max_shapes)
    print("Nodi max/edificio: %d" % max_nodes)
    print("Memoria baseline dopo prewarm: %.2f MB" % baseline)
    print("Memoria finale: %.2f MB" % final_memory)
    print("Memoria delta edifici: %.2f MB" % delta)

    if prewarm_count <= 0:
        push_error("V11 COLLISION FAIL: shared mobile materials were not generated")
        quit(5)
        return
    if visual_total != 81456:
        push_error("V11 COLLISION FAIL: visual triangles changed: %d (expected 81456)" % visual_total)
        quit(6)
        return
    if concave_total != 0:
        push_error("V11 COLLISION FAIL: ConcavePolygonShape3D residue: %d faces" % concave_total)
        quit(7)
        return
    if collision_total > BUILDINGS * MAX_COLLISION_TRIANGLES_PER_BUILDING:
        push_error("V11 COLLISION FAIL: collision triangles %d > %d target" % [collision_total, BUILDINGS * MAX_COLLISION_TRIANGLES_PER_BUILDING])
        quit(8)
        return
    if max_shapes > MAX_COLLISION_SHAPES_PER_BUILDING:
        push_error("V11 COLLISION FAIL: %d CollisionShape3D > %d target" % [max_shapes, MAX_COLLISION_SHAPES_PER_BUILDING])
        quit(9)
        return
    if max_nodes >= 10:
        push_error("V11 COLLISION FAIL: %d nodes/instance >= 10" % max_nodes)
        quit(10)
        return
    if delta >= MEMORY_TARGET_MB:
        push_error("V11 COLLISION FAIL: incremental memory %.2f MB >= %.2f MB target" % [delta, MEMORY_TARGET_MB])
        quit(11)
        return
    print("V11 COLLISION 5 PASS: mobile materials prewarmed, memory delta < 20 MB, geometry unchanged, collision <= 200 triangles/building")
    quit(0)

func _prewarm_materials() -> int:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        return 0
    var count := 0
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if dir.current_is_dir() or not name.ends_with(".tres"):
            continue
        var material := load(MATERIAL_DIR + "/" + name)
        if material != null:
            count += 1
    dir.list_dir_end()
    return count

func _inspect(root: Node) -> Dictionary:
    var visual_triangles := 0
    var collision_triangles := 0
    var concave_faces := 0
    var collision_shapes := 0
    var nodes := 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        nodes += 1
        if current is MeshInstance3D:
            var mi := current as MeshInstance3D
            if mi.mesh != null:
                visual_triangles += _mesh_triangles(mi.mesh)
        if current is CollisionShape3D:
            collision_shapes += 1
            var cs := current as CollisionShape3D
            if cs.shape is BoxShape3D:
                collision_triangles += 12
            elif cs.shape is ConcavePolygonShape3D:
                var cp := cs.shape as ConcavePolygonShape3D
                concave_faces += int(cp.get_faces().size() / 3)
                collision_triangles += int(cp.get_faces().size() / 3)
            elif cs.shape is ConvexPolygonShape3D:
                var cv := cs.shape as ConvexPolygonShape3D
                collision_triangles += int(cv.get_points().size())
        for child in current.get_children():
            stack.append(child)
    return {"visual_triangles": visual_triangles, "collision_triangles": collision_triangles, "concave_faces": concave_faces, "collision_shapes": collision_shapes, "nodes": nodes}

func _mesh_triangles(mesh: Mesh) -> int:
    var triangles := 0
    for s in range(mesh.get_surface_count()):
        var arrays := mesh.surface_get_arrays(s)
        if arrays.is_empty():
            continue
        var indices = arrays[Mesh.ARRAY_INDEX]
        if indices is PackedInt32Array and indices.size() > 0:
            triangles += indices.size() / 3
        else:
            var vertices = arrays[Mesh.ARRAY_VERTEX]
            if vertices is PackedVector3Array:
                triangles += vertices.size() / 3
    return triangles

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

func _read_entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var f := FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        return out
    var lines := f.get_as_text().split("\n")
    f.close()
    var ext_paths: Dictionary = {}
    for raw in lines:
        var line: String = raw.strip_edges()
        if line.begins_with("[ext_resource") and line.contains("type=\"PackedScene\""):
            var path := _between(line, "path=\"", "\" id=\"")
            var id := _between(line, "id=\"", "\"]")
            if not path.is_empty() and not id.is_empty():
                ext_paths[id] = path
    for i in range(lines.size() - 1):
        var line: String = lines[i].strip_edges()
        if not line.begins_with("[node name=\"building_") or not line.contains("instance=ExtResource(\""):
            continue
        var id := _between(line, "instance=ExtResource(\"", "\")")
        var path := str(ext_paths.get(id, ""))
        if path.is_empty():
            continue
        var transform_line: String = lines[i + 1].strip_edges()
        if not transform_line.begins_with("transform = Transform3D("):
            continue
        out.append({"archetype": path, "transform": _parse_transform(transform_line)})
    return out

func _between(line: String, left: String, right: String) -> String:
    var a := line.find(left)
    if a < 0:
        return ""
    a += left.length()
    var b := line.find(right, a)
    if b < 0:
        return ""
    return line.substr(a, b - a)

func _parse_transform(line: String) -> Transform3D:
    var body := line.trim_prefix("transform = Transform3D(").trim_suffix(")")
    var parts := body.split(",")
    if parts.size() < 12:
        return Transform3D.IDENTITY
    var v: Array[float] = []
    for i in range(12):
        v.append(float(parts[i].strip_edges()))
    var basis := Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
    return Transform3D(basis, Vector3(v[9], v[10], v[11]))
