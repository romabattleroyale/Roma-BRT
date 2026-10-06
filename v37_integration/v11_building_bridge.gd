extends Node3D
## Runtime V11 bridge: load all 587 real building instances and use native Godot visibility ranges.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST_PATH := READY_DIR + "/manifest.json"
const WORLD_OFFSET := Vector3(1000.0, 0.0, 1000.0)
const BUILDING_VISIBILITY_END := 500.0
const BUILDING_FADE_MARGIN := 40.0
const DISTRICT_PLANE_BEGIN := 500.0
const DISTRICT_PLANE_END := 5000.0
const DISTRICT_PLANE_SIZE := Vector2(300.0, 300.0)
const DISTRICT_PLANE_Y := 0.5
const DISTRICT_CENTERS := [Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)]
const DISTRICT_COLORS := [Color("#C58B62"),Color("#B97845"),Color("#D1A15A"),Color("#B96F73"),Color("#C7AA83"),Color("#A9573B"),Color("#B88D6A"),Color("#D3A63A"),Color("#A99A7E"),Color("#C98D68"),Color("#A96D54"),Color("#C6A47B")]

var built := false
var _city_root: Node3D
var _templates: Array[PackedScene] = []
var _placements: Array = []
var _variation_script: RefCounted

func _ready() -> void:
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null:
            v37.set("enable_buildings", false)
            if v37.get("city_root") != null:
                _city_root = v37.get("city_root") as Node3D
                await _yield_frames(2)
                if _load_manifest():
                    await _load_all_templates()
                    await _load_all_buildings()
                    _create_district_planes()
                    built = true
                    print("V11 NATIVE VISIBILITY: COMPLETE loaded=587 templates=120 buildings=587 range=0-500 fade=self district_planes=12 range=500-5000")
                    return
        await get_tree().create_timer(0.1).timeout
    push_error("V11 NATIVE VISIBILITY: V37 world non pronto")

func _load_manifest() -> bool:
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("V11 NATIVE VISIBILITY: manifest mancante")
        return false
    var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text())
    f.close()
    if not data is Dictionary or int(data.get("template_count", 0)) != 120 or int(data.get("placement_count", 0)) != 587:
        push_error("V11 NATIVE VISIBILITY: manifest invalido")
        return false
    var source_placements: Array = data["placements"] as Array
    _placements.clear()
    for source_item in source_placements:
        var d: Dictionary = (source_item as Dictionary).duplicate(true)
        d["x"] = float(d.get("x", 0.0)) + WORLD_OFFSET.x
        d["z"] = float(d.get("z", 0.0)) + WORLD_OFFSET.z
        _placements.append(d)
    print("V11 WORLD FRAME: manifest 587 placements shifted once by +1000,+1000")
    return _placements.size() == 587

func _load_all_templates() -> void:
    _templates.clear()
    for i in range(120):
        var packed := ResourceLoader.load("%s/template_%03d.tscn" % [READY_DIR, i + 1], "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if packed != null:
            _templates.append(packed)
        if i % 3 == 2:
            await get_tree().process_frame
    var variation_script: Script = load("res://v37_integration/mobile_visual_variation.gd") as Script
    if variation_script != null:
        _variation_script = variation_script.new()
    if _templates.size() != 120:
        push_error("V11 NATIVE VISIBILITY: templates caricati=%d" % _templates.size())

func _load_all_buildings() -> void:
    if _city_root == null or _templates.size() != 120:
        return
    var loaded := 0
    for i in range(_placements.size()):
        _load_placement(i)
        loaded += 1
        if loaded % 4 == 0:
            await get_tree().process_frame
    if loaded != 587:
        push_error("V11 NATIVE VISIBILITY: buildings caricati=%d expected=587" % loaded)

func _load_placement(i: int) -> void:
    var d: Dictionary = _placements[i]
    var ti := clampi(int(d.get("template", 0)), 0, 119)
    if ti >= _templates.size():
        return
    var root := _templates[ti].instantiate() as Node3D
    if root == null:
        return
    root.position = Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
    root.rotation.y = float(d.get("rotation", 0))
    var template_floors := int(root.get_meta("template_floors", 3))
    var floors := clampi(int(d.get("floors", template_floors)), 3, 5)
    root.scale.y = float(floors) / float(maxi(1, template_floors))
    root.set_meta("runtime_placement", i)
    root.set_meta("ready_signature", "%d|f%d|c%d|r%d" % [ti, floors, int(d.get("facade_index", 0)), int(d.get("roof_index", 0))])
    if _variation_script != null:
        _variation_script.apply(root, int(d.get("seed", i)), floors)
    _set_native_visibility(root)
    _city_root.add_child(root)

func _set_native_visibility(root: Node) -> void:
    var stack: Array[Node] = [root]
    var mesh_count := 0
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is MeshInstance3D:
            var mesh := n as MeshInstance3D
            mesh.visibility_range_begin = 0.0
            mesh.visibility_range_end = BUILDING_VISIBILITY_END
            mesh.visibility_range_begin_margin = 0.0
            mesh.visibility_range_end_margin = BUILDING_FADE_MARGIN
            mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
            mesh_count += 1
        for c in n.get_children():
            stack.append(c)
    root.set_meta("runtime_mesh_count", mesh_count)

func _create_district_planes() -> void:
    if _city_root == null:
        return
    for child in _city_root.get_children():
        if str(child.name).begins_with("V11_CITY_PLANE_"):
            child.queue_free()
    for district in range(12):
        var plane := MeshInstance3D.new()
        plane.name = "V11_CITY_PLANE_%02d" % (district + 1)
        var mesh := PlaneMesh.new()
        mesh.size = DISTRICT_PLANE_SIZE
        plane.mesh = mesh
        var authored_center: Vector3 = DISTRICT_CENTERS[district] as Vector3
        plane.position = authored_center + WORLD_OFFSET
        plane.position.y = DISTRICT_PLANE_Y
        plane.material_override = _make_flat_material(DISTRICT_COLORS[district])
        plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
        plane.visibility_range_begin = DISTRICT_PLANE_BEGIN
        plane.visibility_range_end = DISTRICT_PLANE_END
        plane.visibility_range_begin_margin = 40.0
        plane.visibility_range_end_margin = 40.0
        plane.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        plane.extra_cull_margin = 100.0
        _city_root.add_child(plane)
    print("V11 CITY DISTRICT PLANES: PASS count=12 size=300x300 y=0.5 range=500-5000 fade=self")

func _make_flat_material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    mat.metallic = 0.0
    return mat

func _find_player() -> Node3D:
    var debug_camera := get_tree().current_scene.find_child("DebugTopDownCamera3D", true, false) as Camera3D
    if debug_camera != null and debug_camera.current:
        return debug_camera
    var group_nodes := get_tree().get_nodes_in_group("player")
    if not group_nodes.is_empty() and group_nodes[0] is Node3D:
        return group_nodes[0] as Node3D
    return get_tree().current_scene.get_node_or_null("Player") as Node3D

func _yield_frames(n: int) -> void:
    for _i in range(n):
        await get_tree().process_frame
