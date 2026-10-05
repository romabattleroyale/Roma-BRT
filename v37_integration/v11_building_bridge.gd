extends Node3D
## V11 ready-bake bridge.
## Runtime never calls the procedural V11 factory. Every building is loaded from
## res://baked_city/ready_buildings/ with one threaded resource request at a time.
## Exact repeated baked signatures are batched into MultiMeshInstance3D; the
## simplified BoxShape3D collision remains per placement.

const READY_DIR := "res://baked_city/ready_buildings"
const EXPECTED_COUNT := 587
const START_DELAY_FRAMES := 30

var built := false
var _city_root: Node3D
var _loaded := 0
var _groups: Dictionary = {}

func _ready() -> void:
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null:
            # Disable the legacy procedural building path before V37 creates its world.
            # Runtime buildings must come exclusively from the persisted ready bake.
            v37.set("enable_buildings", false)
            if v37.get("city_root") != null:
                _city_root = v37.get("city_root") as Node3D
                await _yield_frames(START_DELAY_FRAMES)
                await _load_ready_city()
                return
        await get_tree().create_timer(0.1).timeout
    push_error("V11 READY BAKE: V37 world non pronto entro 60 secondi")

func _load_ready_city() -> void:
    if built or _city_root == null:
        return
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(READY_DIR)):
        push_error("V11 READY BAKE: cartella mancante: %s" % READY_DIR)
        return
    print("V11 READY BAKE: caricamento pre-generato, count target=", EXPECTED_COUNT)
    for i in range(EXPECTED_COUNT):
        var path := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        if not FileAccess.file_exists(path):
            push_error("V11 READY BAKE: asset mancante %s" % path)
            return
        var request_err := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
        if request_err != OK:
            push_error("V11 READY BAKE: threaded request failed %s err=%s" % [path, request_err])
            return
        var progress: Array = []
        while true:
            var status := ResourceLoader.load_threaded_get_status(path, progress)
            if status == ResourceLoader.THREAD_LOAD_LOADED:
                break
            if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
                push_error("V11 READY BAKE: threaded load failed %s status=%s" % [path, status])
                return
            await get_tree().process_frame
        var packed := ResourceLoader.load_threaded_get(path) as PackedScene
        if packed == null:
            push_error("V11 READY BAKE: PackedScene null %s" % path)
            return
        var root := packed.instantiate() as Node3D
        if root == null:
            push_error("V11 READY BAKE: instantiate failed %s" % path)
            return
        _attach_baked_instance(root)
        _loaded += 1
        if _loaded % 25 == 0:
            print("V11 READY BAKE: loaded=", _loaded, "/", EXPECTED_COUNT)
        await get_tree().process_frame
    built = true
    print("V11 READY BAKE: COMPLETE loaded=", _loaded, " multimesh_groups=", _groups.size())

func _attach_baked_instance(root: Node3D) -> void:
    var signature := str(root.get_meta("ready_signature", ""))
    var mesh_node := _find_mesh_node(root)
    _city_root.add_child(root)
    if mesh_node == null or mesh_node.mesh == null or signature.is_empty():
        return

    var group: Dictionary = _groups.get(signature, {})
    if group.is_empty():
        _groups[signature] = {
            "mesh": mesh_node.mesh,
            "multimesh": null,
            "mmi": null,
            "roots": [root]
        }
        return

    var mmi := group.get("mmi") as MultiMeshInstance3D
    var mm := group.get("multimesh") as MultiMesh
    if mmi == null or mm == null:
        var first_root: Node3D = group["roots"][0] as Node3D
        var first_mesh_node := _find_mesh_node(first_root)
        if first_mesh_node == null:
            return
        mm = MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.use_colors = false
        mm.mesh = group["mesh"] as Mesh
        mm.instance_count = 2
        mm.set_instance_transform(0, first_root.transform)
        mm.set_instance_transform(1, root.transform)
        mmi = MultiMeshInstance3D.new()
        mmi.name = "ReadyBakeMultiMesh_%s" % signature
        mmi.multimesh = mm
        _city_root.add_child(mmi)
        first_mesh_node.queue_free()
        mesh_node.queue_free()
        group["multimesh"] = mm
        group["mmi"] = mmi
        group["roots"].append(root)
        _groups[signature] = group
        return

    var new_count := mm.instance_count + 1
    mm.instance_count = new_count
    mm.set_instance_transform(new_count - 1, root.transform)
    mesh_node.queue_free()
    group["roots"].append(root)
    _groups[signature] = group

func _find_mesh_node(root: Node) -> MeshInstance3D:
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is MeshInstance3D:
            return current as MeshInstance3D
        for child in current.get_children():
            stack.append(child)
    return null

func _yield_frames(frames: int) -> void:
    for _i in range(maxi(1, frames)):
        await get_tree().process_frame
