extends SceneTree
## DIAGNOSTIC ONLY — runtime city alignment investigation.
## No project assets are saved or permanently modified by this script.

const MAIN_SCENE := "res://main.tscn"
const FACADE_TEXTURE_PATH := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_albedo.jpg"
const IMPORT_PATH := FACADE_TEXTURE_PATH + ".import"
const TARGET_COLOR := Color(0.827451, 0.65098, 0.227451, 1.0) # #D3A63A

func _initialize() -> void:
    print("=== LINUX CITY ALIGNMENT DIAGNOSTICS — START ===")
    print("DIAG renderer=", ProjectSettings.get_setting("renderer/rendering_method", "<unset>"))
    scene_changed.connect(_on_scene_changed)
    var err: Error = change_scene_to_file(MAIN_SCENE)
    print("DIAG change_scene_to_file error=", err)
    await create_timer(15.0).timeout
    _run_diagnostics("T+15s")
    await create_timer(8.0).timeout
    _run_diagnostics("T+23s")
    print("=== LINUX CITY ALIGNMENT DIAGNOSTICS — END ===")
    quit(0)

func _on_scene_changed() -> void:
    print("CITY_CAMERA scene_changed")
    _focus_city_camera()

func _focus_city_camera() -> void:
    var root: Node = current_scene
    if root == null:
        print("CITY_CAMERA WARNING: current_scene null")
        return
    var cameras: Array[Camera3D] = []
    _collect_cameras(root, cameras)
    print("CITY_CAMERA candidates=", cameras.size())
    if cameras.is_empty():
        print("CITY_CAMERA WARNING: no Camera3D found")
        return
    var camera: Camera3D = cameras[0]
    camera.global_position = Vector3(1000.0, 650.0, 1000.0)
    camera.global_rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    camera.current = true
    camera.fov = 70.0
    print("CITY_CAMERA focused position=", camera.global_position, " rotation=", camera.global_rotation_degrees, " current=", camera.current)

func _run_diagnostics(label: String) -> void:
    print("--- CITY ALIGNMENT DIAGNOSTICS ", label, " ---")
    var root: Node = current_scene
    if root == null:
        print("DIAG scene=<null>")
        return
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    print("DIAG mesh_nodes=", meshes.size())
    var building_nodes: int = 0
    var y_min: float = INF
    var y_max: float = -INF
    for node in root.find_children("*", "Node3D", true, false):
        var n: Node3D = node as Node3D
        if n == null:
            continue
        var lower: String = n.name.to_lower()
        if lower.contains("building") or lower.contains("edificio") or lower.contains("template"):
            building_nodes += 1
            y_min = min(y_min, n.global_position.y)
            y_max = max(y_max, n.global_position.y)
    print("CITY_BUILDING_NODE_COUNT=", building_nodes, " y_min=", y_min, " y_max=", y_max)
    print("CITY_SCENE_NODE_COUNT=", root.get_child_count())

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func _collect_cameras(node: Node, result: Array[Camera3D]) -> void:
    if node is Camera3D:
        result.append(node as Camera3D)
    for child in node.get_children():
        _collect_cameras(child, result)
