extends Node3D
## V11 diagnostic only. Loads first 5 baked buildings regardless of camera position.
const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"
const MAX_BUILDINGS_TO_LOAD := 5
var _entries: Array[Dictionary] = []
var _active: Dictionary = {}
var _archetype_cache: Dictionary = {}
var _diagnostic_triangles: int = 0
var _diagnostic_textures: int = 0

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

func _ready() -> void:
    call_deferred("_build_index")

func _between(line: String, left: String, right: String) -> String:
    var a: int = line.find(left)
    if a < 0:
        return ""
    a += left.length()
    var b: int = line.find(right, a)
    if b < 0:
        return ""
    return line.substr(a, b - a)

func _build_index() -> void:
    print("=== PRE-LOAD LIBRERIA ===")
    print("Memoria usata: %.2f MB" % _memory_mb())
    if not FileAccess.file_exists(BAKED_SCENE):
        push_error("BAKED CITY: scena non trovata")
        return
    var f: FileAccess = FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        push_error("BAKED CITY: impossibile leggere scena")
        return
    var text: String = f.get_as_text()
    f.close()
    var lines: PackedStringArray = text.split("\n")
    var ext_paths: Dictionary = {}
    var loadable_paths: Dictionary = {}
    for raw_line in lines:
        var line: String = raw_line.strip_edges()
        if not line.begins_with("[ext_resource") or not line.contains("type=\"PackedScene\""):
            continue
        var path: String = _between(line, "path=\"", "\" id=\"")
        var ext_id: String = _between(line, "id=\"", "\"]")
        if not path.is_empty() and not ext_id.is_empty():
            ext_paths[ext_id] = path
            var lower: String = path.to_lower()
            if lower.ends_with(".tscn") or lower.ends_with(".glb"):
                loadable_paths[path] = true
    print("File .tscn/.glb da caricare: %d" % loadable_paths.size())
    for i in range(lines.size() - 1):
        var line: String = lines[i].strip_edges()
        if not line.begins_with("[node name=\"building_") or not line.contains("instance=ExtResource(\""):
            continue
        var name: String = _between(line, "name=\"", "\"")
        var ext_id: String = _between(line, "instance=ExtResource(\"", "\")")
        var archetype_path: String = ext_paths.get(ext_id, "")
        if name.is_empty() or archetype_path.is_empty():
            continue
        var transform_line: String = lines[i + 1].strip_edges()
        if not transform_line.begins_with("transform = Transform3D("):
            continue
        var t: Transform3D = _parse_transform(transform_line)
        _entries.append({"name": name, "transform": t, "position": t.origin, "archetype": archetype_path})
    print("BAKED CITY DEBUG — indice pronto: %d/%d edifici" % [_entries.size(), 587])
    if _entries.is_empty():
        push_error("BAKED CITY DEBUG: indice vuoto dopo parsing")
        return
    call_deferred("_run_diagnostic")

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

func _run_diagnostic() -> void:
    var count: int = min(MAX_BUILDINGS_TO_LOAD, _entries.size())
    for i in range(count):
        await _instantiate_entry_diagnostic(_entries[i], i + 1)
    print("=== REPORT FINALE ===")
    print("Edifici caricati: %d / %d" % [_active.size(), MAX_BUILDINGS_TO_LOAD])
    print("Triangoli totali: %d" % _diagnostic_triangles)
    print("Memoria totale: %.2f MB" % _memory_mb())

func _instantiate_entry_diagnostic(entry: Dictionary, building_number: int) -> void:
    var name: String = entry["name"]
    var path: String = entry["archetype"]
    print("[EDIFICIO #%d] Nome=%s, path=%s" % [building_number, name, path])
    var packed: PackedScene = _archetype_cache.get(path) as PackedScene
    if packed == null:
        packed = load(path) as PackedScene
        if packed == null:
            print("[EDIFICIO #%d] ERRORE: PackedScene non caricabile" % building_number)
            return
        _archetype_cache[path] = packed
    var pre_stats: Dictionary = _inspect_packed_scene(packed)
    print("[EDIFICIO #%d] Triangoli mesh: %d" % [building_number, pre_stats["triangles"]])
    print("[EDIFICIO #%d] Texture: %d (formato: %s)" % [building_number, pre_stats["textures"], pre_stats["texture_format"]])
    print("[EDIFICIO #%d] Nodi figli: %d" % [building_number, pre_stats["nodes"]])
    var node: Node3D = packed.instantiate() as Node3D
    if node == null:
        print("[EDIFICIO #%d] ERRORE: instantiate() null" % building_number)
        return
    node.name = name
    node.transform = entry["transform"]
    node.set_meta("baked_v37", true)
    node.set_meta("v37_source_position", entry["position"])
    add_child(node)
    _active[name] = node
    var post_stats: Dictionary = _inspect_node(node)
    _diagnostic_triangles += int(post_stats["triangles"])
    _diagnostic_textures += int(post_stats["textures"])
    print("[EDIFICIO #%d] Memoria dopo istanziazione: %.2f MB" % [building_number, _memory_mb()])
    print("[EDIFICIO #%d] Verifica runtime: triangoli=%d texture=%d nodi=%d" % [building_number, post_stats["triangles"], post_stats["textures"], post_stats["nodes"]])
    await get_tree().process_frame

func _inspect_packed_scene(packed: PackedScene) -> Dictionary:
    var result: Dictionary = {"triangles": 0, "textures": 0, "nodes": 0, "texture_format": "n/d"}
    var state: SceneState = packed.get_state()
    if state == null:
        return result
    result["nodes"] = state.get_node_count()
    var formats: Dictionary = {}
    for n in range(state.get_node_count()):
        for p in range(state.get_node_property_count(n)):
            var value = state.get_node_property_value(n, p)
            if value is Mesh:
                result["triangles"] = int(result["triangles"]) + _mesh_triangles(value)
            elif value is Texture2D:
                result["textures"] = int(result["textures"]) + 1
                formats[_texture_format(value)] = true
            elif value is Material:
                var ms: Dictionary = _inspect_material(value)
                result["textures"] = int(result["textures"]) + int(ms["textures"])
                for fmt in ms["formats"].keys():
                    formats[fmt] = true
    if formats.size() > 0:
        result["texture_format"] = ", ".join(formats.keys())
    return result

func _inspect_node(root: Node) -> Dictionary:
    var result: Dictionary = {"triangles": 0, "textures": 0, "nodes": 0}
    var ids: Dictionary = {}
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        result["nodes"] = int(result["nodes"]) + 1
        for child in current.get_children():
            stack.append(child)
        for prop in current.get_property_list():
            var prop_name: String = str(prop.get("name", ""))
            if prop_name.is_empty():
                continue
            var value = current.get(prop_name)
            if value is Texture2D:
                var texture_id: int = value.get_instance_id()
                ids[texture_id] = true
            elif value is Material:
                _collect_material_textures(value, ids)
        if current is MeshInstance3D:
            var mi: MeshInstance3D = current as MeshInstance3D
            if mi.mesh:
                result["triangles"] = int(result["triangles"]) + _mesh_triangles(mi.mesh)
                for s in range(mi.mesh.get_surface_count()):
                    _collect_material_textures(mi.mesh.surface_get_material(s), ids)
            for s in range(mi.get_surface_override_material_count()):
                _collect_material_textures(mi.get_surface_override_material(s), ids)
    result["textures"] = ids.size()
    return result

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

func _inspect_material(material: Material) -> Dictionary:
    var ids: Dictionary = {}
    var formats: Dictionary = {}
    _collect_material_textures(material, ids, formats)
    return {"textures": ids.size(), "formats": formats}

func _collect_material_textures(material: Material, ids: Dictionary, formats: Dictionary = {}) -> void:
    if material == null:
        return
    for prop in material.get_property_list():
        var prop_name: String = str(prop.get("name", ""))
        if not prop_name.to_lower().contains("texture"):
            continue
        var value = material.get(prop_name)
        if value is Texture2D:
            var id: int = value.get_instance_id()
            ids[id] = true
            formats[_texture_format(value)] = true

func _texture_format(texture: Texture2D) -> String:
    var path: String = texture.resource_path
    if path.is_empty():
        return texture.get_class()
    return "%s/%s" % [texture.get_class(), path.get_extension().to_lower()]

func get_active_building_count() -> int:
    return _active.size()
