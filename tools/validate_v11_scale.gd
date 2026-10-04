extends SceneTree
## Headless validation for the optimized V11 archetype set.
## Run with a user argument: 5, 10, 20 or 40.

const BAKED_SCENE: String = "res://baked_city/roma_city_587.tscn"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var args: PackedStringArray = get_cmdline_user_args()
    var count: int = 5
    if not args.is_empty():
        count = int(args[0])
    if count != 5 and count != 10 and count != 20 and count != 40:
        push_error("V11 SCALE: expected 5, 10, 20 or 40")
        quit(2)
        return

    var entries: Array[Dictionary] = _read_entries()
    if entries.size() < count:
        push_error("V11 SCALE: only %d entries available, need %d" % [entries.size(), count])
        quit(3)
        return

    var baseline: float = _memory_mb()
    var root: Node3D = Node3D.new()
    root.name = "V11ScaleValidation"
    get_root().add_child(root)

    var cache: Dictionary = {}
    var total_triangles: int = 0
    var max_nodes: int = 0
    var textures: Dictionary = {}

    for i in range(count):
        var path: String = str(entries[i]["archetype"])
        var packed: PackedScene = cache.get(path) as PackedScene
        if packed == null:
            packed = load(path) as PackedScene
            if packed == null:
                push_error("V11 SCALE: cannot load %s" % path)
                quit(4)
                return
            cache[path] = packed
        var node: Node3D = packed.instantiate() as Node3D
        if node == null:
            push_error("V11 SCALE: instantiate failed for %s" % path)
            quit(5)
            return
        node.transform = entries[i]["transform"]
        root.add_child(node)
        var stats: Dictionary = _inspect_node(node, textures)
        total_triangles += int(stats["triangles"])
        max_nodes = max(max_nodes, int(stats["nodes"]))
        await process_frame

    var final_memory: float = _memory_mb()
    var delta: float = final_memory - baseline
    print("=== V11 SCALE %d ===" % count)
    print("Edifici: %d" % count)
    print("Triangoli totali: %d" % total_triangles)
    print("Nodi max per edificio: %d" % max_nodes)
    print("Texture uniche: %d" % textures.size())
    for key in textures.keys():
        print("Texture path: %s" % str(key))
    print("Memoria baseline: %.2f MB" % baseline)
    print("Memoria finale: %.2f MB" % final_memory)
    print("Memoria delta: %.2f MB" % delta)
    print("Media delta/edificio: %.2f MB" % (delta / float(count)))

    # The hard node/texture checks are structural. Memory is reported rather than
    # made a hard CI gate because the Terrain3D/editor process is part of the same
    # allocator and is not a device-equivalent Android measurement.
    if max_nodes >= 10:
        push_error("V11 SCALE FAIL: node count %d >= 10" % max_nodes)
        quit(6)
        return
    if textures.is_empty():
        push_error("V11 SCALE FAIL: no textures discovered through materials/shaders")
        quit(7)
        return
    quit(0)

func _read_entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var f: FileAccess = FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        return out
    var text: String = f.get_as_text()
    f.close()
    var lines: PackedStringArray = text.split("\n")
    var ext_paths: Dictionary = {}
    for raw_line in lines:
        var line: String = raw_line.strip_edges()
        if line.begins_with("[ext_resource") and line.contains("type=\"PackedScene\""):
            var path: String = _between(line, "path=\"", "\" id=\"")
            var ext_id: String = _between(line, "id=\"", "\"]")
            if not path.is_empty() and not ext_id.is_empty():
                ext_paths[ext_id] = path
    for i in range(lines.size() - 1):
        var line: String = lines[i].strip_edges()
        if not line.begins_with("[node name=\"building_") or not line.contains("instance=ExtResource(\""):
            continue
        var ext_id: String = _between(line, "instance=ExtResource(\"", "\")")
        var path: String = str(ext_paths.get(ext_id, ""))
        if path.is_empty():
            continue
        var transform_line: String = lines[i + 1].strip_edges()
        if not transform_line.begins_with("transform = Transform3D("):
            continue
        out.append({"archetype": path, "transform": _parse_transform(transform_line)})
    return out

func _between(line: String, left: String, right: String) -> String:
    var a: int = line.find(left)
    if a < 0:
        return ""
    a += left.length()
    var b: int = line.find(right, a)
    if b < 0:
        return ""
    return line.substr(a, b - a)

func _parse_transform(line: String) -> Transform3D:
    var body: String = line.trim_prefix("transform = Transform3D(").trim_suffix(")")
    var parts: PackedStringArray = body.split(",")
    if parts.size() < 12:
        return Transform3D.IDENTITY
    var v: Array[float] = []
    for i in range(12):
        v.append(float(parts[i].strip_edges()))
    var basis: Basis = Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
    return Transform3D(basis, Vector3(v[9], v[10], v[11]))

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

func _inspect_node(root: Node, textures: Dictionary) -> Dictionary:
    var triangles: int = 0
    var nodes: int = 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        nodes += 1
        for child in current.get_children():
            stack.append(child)
        if current is MeshInstance3D:
            var mi: MeshInstance3D = current as MeshInstance3D
            if mi.mesh != null:
                triangles += _mesh_triangles(mi.mesh)
                for s in range(mi.mesh.get_surface_count()):
                    _collect_material_textures(mi.mesh.surface_get_material(s), textures)
            for s in range(mi.get_surface_override_material_count()):
                _collect_material_textures(mi.get_surface_override_material(s), textures)
    return {"triangles": triangles, "nodes": nodes}

func _mesh_triangles(mesh: Mesh) -> int:
    var triangles: int = 0
    for s in range(mesh.get_surface_count()):
        var arrays: Array = mesh.surface_get_arrays(s)
        if arrays.is_empty():
            continue
        var indices = arrays[Mesh.ARRAY_INDEX]
        if indices is PackedInt32Array and indices.size() > 0:
            triangles += int(indices.size() / 3)
        else:
            var vertices = arrays[Mesh.ARRAY_VERTEX]
            if vertices is PackedVector3Array:
                triangles += int(vertices.size() / 3)
    return triangles

func _collect_material_textures(material: Material, textures: Dictionary) -> void:
    if material == null:
        return
    for prop in material.get_property_list():
        var value = material.get(str(prop.get("name", "")))
        if value is Texture2D:
            var path: String = value.resource_path
            textures[path if not path.is_empty() else "<embedded/subresource>"] = true
    if material is ShaderMaterial:
        var shader_material: ShaderMaterial = material as ShaderMaterial
        var shader: Shader = shader_material.shader
        if shader != null:
            for uniform in shader.get_shader_uniform_list():
                var uniform_name: String = str(uniform.get("name", ""))
                var value = shader_material.get_shader_parameter(uniform_name)
                if value is Texture2D:
                    var path: String = value.resource_path
                    textures[path if not path.is_empty() else "<embedded/subresource>"] = true
