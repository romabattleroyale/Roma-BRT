extends SceneTree
## Mobile-focused V11 scale gate. Run with 5, 10, 20 or 40.
## External textures are counted from the portable V11 texture library rather
## than walking every material property, keeping the CI gate deterministic.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"
const MATERIAL_DIR := "res://baked_city/v11_shared_materials"
const TEXTURE_DIR := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures"
const MIN_TEXTURES := 14
const MAX_NODES_PER_BUILDING := 10

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    var count := 5
    if not args.is_empty():
        count = int(args[0])
    if count != 5 and count != 10 and count != 20 and count != 40:
        push_error("V11 MOBILE SCALE: expected 5, 10, 20 or 40")
        quit(2)
        return

    var entries := _read_entries()
    if entries.size() < count:
        push_error("V11 MOBILE SCALE: only %d entries available, need %d" % [entries.size(), count])
        quit(3)
        return

    var material_count := _count_materials()
    var texture_count := _count_textures()
    var baseline := _memory_mb()
    var root := Node3D.new()
    root.name = "V11MobileScaleValidation"
    get_root().add_child(root)

    var cache: Dictionary = {}
    var total_triangles := 0
    var max_nodes := 0

    for i in range(count):
        var path := str(entries[i]["archetype"])
        var packed := cache.get(path) as PackedScene
        if packed == null:
            packed = load(path) as PackedScene
            if packed == null:
                push_error("V11 MOBILE SCALE: cannot load %s" % path)
                quit(4)
                return
            cache[path] = packed
        var node := packed.instantiate() as Node3D
        if node == null:
            push_error("V11 MOBILE SCALE: instantiate failed for %s" % path)
            quit(5)
            return
        node.transform = entries[i]["transform"]
        root.add_child(node)
        var stats := _inspect_node(node)
        total_triangles += stats["triangles"]
        max_nodes = max(max_nodes, stats["nodes"])
        print("[V11 MOBILE SCALE] edificio=%d nodi=%d triangoli=%d texture_library=%d" % [i + 1, stats["nodes"], stats["triangles"], texture_count])
        await process_frame

    var final_memory := _memory_mb()
    var delta := final_memory - baseline
    print("=== V11 MOBILE SCALE %d ===" % count)
    print("Edifici: %d" % count)
    print("Materiali condivisi: %d" % material_count)
    print("Texture V11 esterne: %d" % texture_count)
    print("Triangoli totali: %d" % total_triangles)
    print("Nodi max per edificio: %d" % max_nodes)
    print("Memoria baseline: %.2f MB" % baseline)
    print("Memoria finale: %.2f MB" % final_memory)
    print("Memoria delta edifici: %.2f MB" % delta)

    if material_count <= 0:
        push_error("V11 MOBILE SCALE FAIL: no shared materials available")
        quit(6)
        return
    if texture_count < MIN_TEXTURES:
        push_error("V11 MOBILE SCALE FAIL: external texture count %d < %d" % [texture_count, MIN_TEXTURES])
        quit(7)
        return
    if max_nodes > MAX_NODES_PER_BUILDING:
        push_error("V11 MOBILE SCALE FAIL: node count %d > %d" % [max_nodes, MAX_NODES_PER_BUILDING])
        quit(8)
        return
    if count == 10 and delta >= 60.0:
        push_error("V11 MOBILE SCALE FAIL: 10-building delta %.2f MB >= 60 MB" % delta)
        quit(10)
        return
    if count == 20 and delta >= 130.0:
        push_error("V11 MOBILE SCALE FAIL: 20-building delta %.2f MB >= 130 MB" % delta)
        quit(11)
        return
    if count == 40 and (delta >= 250.0 or final_memory >= 250.0):
        push_error("V11 MOBILE SCALE FAIL: 40-building memory delta/final %.2f/%.2f MB exceeds 250 MB" % [delta, final_memory])
        quit(12)
        return
    quit(0)

func _count_materials() -> int:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        return 0
    var count := 0
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if not dir.current_is_dir() and name.ends_with(".tres"):
            count += 1
    dir.list_dir_end()
    return count

func _count_textures() -> int:
    var dir := DirAccess.open(TEXTURE_DIR)
    if dir == null:
        return 0
    var count := 0
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if dir.current_is_dir():
            continue
        var ext := name.get_extension().to_lower()
        if ext == "jpg" or ext == "jpeg" or ext == "png":
            count += 1
    dir.list_dir_end()
    return count

func _inspect_node(root: Node) -> Dictionary:
    var triangles := 0
    var nodes := 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        nodes += 1
        if current is MeshInstance3D:
            var mi := current as MeshInstance3D
            if mi.mesh != null:
                triangles += _mesh_triangles(mi.mesh)
        for child in current.get_children():
            stack.append(child)
    return {"triangles": triangles, "nodes": nodes}

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
