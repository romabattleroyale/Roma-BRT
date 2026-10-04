extends Node3D
## Android-safe V11 building loader with targeted crash diagnostics.
## DIAGNOSTIC ONLY: no mesh/texture optimization is performed here.
## Loads a maximum of 5 buildings and prints detailed information before/after
## each instantiation so the first problematic V11 archetype can be identified.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"
const MAX_BUILDINGS_TO_LOAD := 5

@export var load_radius := 420.0
@export var unload_radius := 560.0
@export var update_interval := 0.35
@export var max_loads_per_frame := 1
@export var max_unloads_per_frame := 3

var _entries: Array[Dictionary] = []
var _active: Dictionary = {}
var _archetype_cache: Dictionary = {}
var _queued_load: Dictionary = {}
var _queued_unload: Dictionary = {}
var _viewer: Node3D
var _elapsed := 0.0
var _index_ready := false
var _queue_busy := false
var _diagnostic_finished := false
var _diagnostic_triangles := 0
var _diagnostic_textures := 0

func _memory_mb() -> float:
    return float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0

func _ready() -> void:
    _viewer = get_node_or_null("../Viewer") as Node3D
    if _viewer == null:
        push_error("BAKED CITY DEBUG: Viewer non trovato")
        return
    call_deferred("_build_index")

func _build_index() -> void:
    print("=== PRE-LOAD LIBRERIA ===")
    print("Memoria usata: %.2f MB" % _memory_mb())
    print("File .tscn/.glb da caricare: calcolo indice V11...")

    if not FileAccess.file_exists(BAKED_SCENE):
        push_warning("BAKED CITY: %s non trovata." % BAKED_SCENE)
        return

    var f := FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        push_error("BAKED CITY DEBUG: impossibile leggere %s" % BAKED_SCENE)
        return
    var text := f.get_as_text()
    f.close()

    var ext_paths: Dictionary = {}
    var ext_re := RegEx.new()
    ext_re.compile('^\\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\\]$')
    for raw_line in text.split("\\n"):
        var line := raw_line.strip_edges()
        var ext_match := ext_re.search(line)
        if ext_match:
            ext_paths[ext_match.get_string(2)] = ext_match.get_string(1)

    var loadable_paths: Dictionary = {}
    for path_variant in ext_paths.values():
        var path: String = path_variant
        var lower := path.to_lower()
        if lower.ends_with(".tscn") or lower.ends_with(".glb"):
            loadable_paths[path] = true
    print("File .tscn/.glb da caricare: %d" % loadable_paths.size())

    var node_re := RegEx.new()
    node_re.compile('^\\[node name="(building_[^"]+)"[^\\]]*instance=ExtResource\\("([^"]+)"\\)\\]$')
    var lines := text.split("\\n")
    for i in range(lines.size() - 1):
        var line := lines[i].strip_edges()
        var node_match := node_re.search(line)
        if node_match == null:
            continue
        var ext_id := node_match.get_string(2)
        var archetype_path: String = ext_paths.get(ext_id, "")
        if archetype_path.is_empty():
            continue
        var transform_line := lines[i + 1].strip_edges()
        if not transform_line.begins_with("transform = Transform3D("):
            continue
        var t := _parse_transform(transform_line)
        _entries.append({
            "name": node_match.get_string(1),
            "transform": t,
            "position": t.origin,
            "archetype": archetype_path
        })

    _index_ready = _entries.size() > 0
    print("BAKED CITY DEBUG — indice pronto: %d/%d edifici" % [_entries.size(), 587])
    if _index_ready:
        _refresh_stream(true)

func _parse_transform(line: String) -> Transform3D:
    var body := line.trim_prefix("transform = Transform3D(").trim_suffix(")")
    var parts := body.split(",")
    if parts.size() < 12:
        return Transform3D.IDENTITY
    var v: Array[float] = []
    for i in range(12):
        v.append(float(parts[i].strip_edges()))
    var basis := Basis(
        Vector3(v[0], v[1], v[2]),
        Vector3(v[3], v[4], v[5]),
        Vector3(v[6], v[7], v[8])
    )
    return Transform3D(basis, Vector3(v[9], v[10], v[11]))

func _process(delta: float) -> void:
    if not _index_ready or _viewer == null or _queue_busy:
        return
    _elapsed += delta
    if _elapsed < update_interval:
        return
    _elapsed = 0.0
    _refresh_stream(false)
    _process_queues()

func _refresh_stream(force: bool) -> void:
    var center := _viewer.global_position
    for entry in _entries:
        if _active.size() + _queued_load.size() >= MAX_BUILDINGS_TO_LOAD:
            break
        var name: String = entry["name"]
        var pos: Vector3 = entry["position"]
        var dist_sq := center.distance_squared_to(pos)
        if dist_sq <= load_radius * load_radius:
            if not _active.has(name) and not _queued_load.has(name):
                _queued_load[name] = entry
            if _queued_unload.has(name):
                _queued_unload.erase(name)
        elif not force and dist_sq >= unload_radius * unload_radius:
            if _active.has(name) and not _queued_unload.has(name):
                _queued_unload[name] = true

func _process_queues() -> void:
    _queue_busy = true

    var load_count := 0
    for name in _queued_load.keys():
        if load_count >= max_loads_per_frame or _active.size() >= MAX_BUILDINGS_TO_LOAD:
            break
        var entry: Dictionary = _queued_load[name]
        _queued_load.erase(name)
        if not _active.has(name):
            await _instantiate_entry_diagnostic(entry)
        load_count += 1

    var unload_count := 0
    for name in _queued_unload.keys():
        if unload_count >= max_unloads_per_frame:
            break
        _queued_unload.erase(name)
        var node: Node3D = _active.get(name) as Node3D
        if node:
            node.queue_free()
        _active.erase(name)
        unload_count += 1

    _queue_busy = false

    if not _diagnostic_finished and _active.size() >= MAX_BUILDINGS_TO_LOAD:
        _diagnostic_finished = true
        print("=== REPORT FINALE ===")
        print("Edifici caricati: %d / %d" % [_active.size(), MAX_BUILDINGS_TO_LOAD])
        print("Triangoli totali: %d" % _diagnostic_triangles)
        print("Memoria totale: %.2f MB" % _memory_mb())

func _instantiate_entry_diagnostic(entry: Dictionary) -> void:
    var name: String = entry["name"]
    var path: String = entry["archetype"]
    var building_number := _active.size() + 1

    print("[EDIFICIO #%d] Nome=%s, path=%s" % [building_number, name, path])

    var packed: PackedScene = _archetype_cache.get(path) as PackedScene
    if packed == null:
        packed = load(path) as PackedScene
        if packed == null:
            push_warning("BAKED CITY DEBUG: archetype non caricabile: %s" % path)
            print("[EDIFICIO #%d] ERRORE: PackedScene non caricabile" % building_number)
            return
        _archetype_cache[path] = packed

    var pre_stats := _inspect_packed_scene(packed)
    print("[EDIFICIO #%d] Triangoli mesh: %d" % [building_number, pre_stats["triangles"]])
    print("[EDIFICIO #%d] Texture: %d (formato: %s)" % [building_number, pre_stats["textures"], pre_stats["texture_format"]])
    print("[EDIFICIO #%d] Nodi figli: %d" % [building_number, pre_stats["nodes"]])

    var node := packed.instantiate() as Node3D
    if node == null:
        print("[EDIFICIO #%d] ERRORE: instantiate() ha restituito null" % building_number)
        return
    node.name = name
    node.transform = entry["transform"]
    node.set_meta("baked_v37", true)
    node.set_meta("v37_source_position", entry["position"])
    add_child(node)
    _active[name] = node

    var post_stats := _inspect_node(node)
    _diagnostic_triangles += post_stats["triangles"]
    _diagnostic_textures += post_stats["textures"]
    print("[EDIFICIO #%d] Memoria dopo istanziazione: %.2f MB" % [building_number, _memory_mb()])
    print("[EDIFICIO #%d] Verifica runtime: triangoli=%d texture=%d nodi=%d" % [building_number, post_stats["triangles"], post_stats["textures"], post_stats["nodes"]])

    await get_tree().process_frame

func _inspect_packed_scene(packed: PackedScene) -> Dictionary:
    var result := {"triangles": 0, "textures": 0, "nodes": 0, "texture_format": "n/d"}
    var state := packed.get_state()
    if state == null:
        return result

    result["nodes"] = state.get_node_count()
    var texture_formats: Dictionary = {}
    for node_index in range(state.get_node_count()):
        var property_count := state.get_node_property_count(node_index)
        for property_index in range(property_count):
            var value = state.get_node_property_value(node_index, property_index)
            if value is Mesh:
                result["triangles"] += _mesh_triangles(value)
            elif value is Texture2D:
                result["textures"] += 1
                texture_formats[_texture_format(value)] = true
            elif value is Material:
                var material_stats := _inspect_material(value)
                result["triangles"] += material_stats["triangles"]
                result["textures"] += material_stats["textures"]
                for fmt in material_stats["formats"].keys():
                    texture_formats[fmt] = true

    if texture_formats.size() > 0:
        result["texture_format"] = ", ".join(texture_formats.keys())
    return result

func _inspect_node(root: Node) -> Dictionary:
    var result := {"triangles": 0, "textures": 0, "nodes": 0}
    var texture_ids: Dictionary = {}
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        result["nodes"] += 1
        for child in current.get_children():
            stack.append(child)
        if current is MeshInstance3D:
            var mi := current as MeshInstance3D
            if mi.mesh:
                result["triangles"] += _mesh_triangles(mi.mesh)
            for surface in range(mi.get_surface_override_material_count()):
                var mat := mi.get_surface_override_material(surface)
                _collect_material_textures(mat, texture_ids)
            if mi.mesh:
                for surface in range(mi.mesh.get_surface_count()):
                    _collect_material_textures(mi.mesh.surface_get_material(surface), texture_ids)
    result["textures"] = texture_ids.size()
    return result

func _mesh_triangles(mesh: Mesh) -> int:
    var triangles := 0
    for surface in range(mesh.get_surface_count()):
        var arrays := mesh.surface_get_arrays(surface)
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
    var result := {"triangles": 0, "textures": 0, "formats": {}}
    var ids: Dictionary = {}
    _collect_material_textures(material, ids, result["formats"])
    result["textures"] = ids.size()
    return result

func _collect_material_textures(material: Material, ids: Dictionary, formats: Dictionary = {}) -> void:
    if material == null:
        return
    for prop in material.get_property_list():
        var prop_name: String = prop.get("name", "")
        if not prop_name.to_lower().contains("texture"):
            continue
        var value = material.get(prop_name)
        if value is Texture2D:
            var id: int = value.get_instance_id()
            ids[id] = true
            if formats != null:
                formats[_texture_format(value)] = true

func _texture_format(texture: Texture2D) -> String:
    var path := texture.resource_path
    var type_name := texture.get_class()
    if path.is_empty():
        return type_name
    var ext := path.get_extension().to_lower()
    return "%s/%s" % [type_name, ext]

func get_active_building_count() -> int:
    return _active.size()
