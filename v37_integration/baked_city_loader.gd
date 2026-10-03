extends Node3D
## Android-safe runtime loader for the editor-baked 587-building city.
## The old loader instantiated all 587 buildings at once. On mobile this can
## spike memory/GPU resource usage and close the app. This loader reads the
## baked scene index and instantiates only buildings around the player.
## As the player moves, nearby buildings are loaded and distant ones released.

const BAKED_SCENE := "res://baked_city/roma_city_587.tscn"

@export var load_radius := 420.0
@export var unload_radius := 560.0
@export var update_interval := 0.35
@export var max_loads_per_frame := 2
@export var max_unloads_per_frame := 3

var _entries: Array[Dictionary] = []
var _active: Dictionary = {}
var _archetype_cache: Dictionary = {}
var _queued_load: Dictionary = {}
var _queued_unload: Dictionary = {}
var _viewer: Node3D
var _elapsed := 0.0
var _index_ready := false

func _ready() -> void:
    _viewer = get_node_or_null("../Viewer") as Node3D
    if _viewer == null:
        push_error("BAKED CITY STREAM: Viewer non trovato")
        return
    call_deferred("_build_index")

func _build_index() -> void:
    if not FileAccess.file_exists(BAKED_SCENE):
        push_warning("BAKED CITY: %s non trovata." % BAKED_SCENE)
        return

    var f := FileAccess.open(BAKED_SCENE, FileAccess.READ)
    if f == null:
        push_error("BAKED CITY STREAM: impossibile leggere %s" % BAKED_SCENE)
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
    print("BAKED CITY STREAM — indice pronto: %d/%d edifici" % [_entries.size(), 587])
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
    if not _index_ready or _viewer == null:
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
    var load_count := 0
    for name in _queued_load.keys():
        if load_count >= max_loads_per_frame:
            break
        var entry: Dictionary = _queued_load[name]
        _queued_load.erase(name)
        if not _active.has(name):
            _instantiate_entry(entry)
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

func _instantiate_entry(entry: Dictionary) -> void:
    var name: String = entry["name"]
    var path: String = entry["archetype"]
    var packed: PackedScene = _archetype_cache.get(path) as PackedScene
    if packed == null:
        packed = load(path) as PackedScene
        if packed == null:
            push_warning("BAKED CITY STREAM: archetype non caricabile: %s" % path)
            return
        _archetype_cache[path] = packed

    var node := packed.instantiate() as Node3D
    if node == null:
        return
    node.name = name
    node.transform = entry["transform"]
    node.set_meta("baked_v37", true)
    node.set_meta("v37_source_position", entry["position"])
    add_child(node)
    _active[name] = node

func get_active_building_count() -> int:
    return _active.size()
