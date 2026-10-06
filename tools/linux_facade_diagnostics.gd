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
    var err: Error = change_scene_to_file(MAIN_SCENE)
    print("DIAG change_scene_to_file error=", err)
    await create_timer(8.0).timeout
    _focus_city_camera()
    _run_diagnostics("T+8s")
    await create_timer(8.0).timeout
    _focus_city_camera()
    _run_diagnostics("T+16s")
    await create_timer(10.0).timeout
    print("=== LINUX CITY ALIGNMENT DIAGNOSTICS — END ===")
    quit(0)

func _focus_city_camera() -> void:
    var root: Node = current_scene
    if root == null:
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
    _inspect_import_srgb()
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
    var riverish: int = 0
    for node in root.find_children("*", "Node3D", true, false):
        var n: Node3D = node as Node3D
        if n == null:
            continue
        var lower: String = n.name.to_lower()
        if lower.contains("building") or lower.contains("edificio") or lower.contains("template"):
            building_nodes += 1
            y_min = min(y_min, n.global_position.y)
            y_max = max(y_max, n.global_position.y)
            if abs(n.global_position.x - 1000.0) < 900.0 and abs(n.global_position.z - 1000.0) < 900.0:
                riverish += 1
    print("CITY_BUILDING_NODE_COUNT=", building_nodes, " y_min=", y_min, " y_max=", y_max)
    print("CITY_BUILDING_NODE_IN_WORLD_BOUNDS=", riverish)

    var facade_count: int = 0
    var roof_candidates: int = 0
    var roof_test_done: bool = false
    for mi in meshes:
        if mi.mesh == null:
            continue
        var surface_count: int = mi.mesh.get_surface_count()
        for s in range(surface_count):
            var material: Material = mi.get_active_material(s)
            if material == null:
                material = mi.mesh.surface_get_material(s)
            if not (material is StandardMaterial3D):
                continue
            var sm: StandardMaterial3D = material as StandardMaterial3D
            var desc: String = _node_material_desc(mi, s, sm)
            var is_facade: bool = _is_facade(mi, sm)
            var is_roof: bool = _is_roof(mi, sm)
            if is_facade:
                facade_count += 1
                print("FACADE ", desc)
                print("FACADE ALBEDO_COLOR=", sm.albedo_color.to_html(true), " expected=#D3A63AFF target_match=", sm.albedo_color.is_equal_approx(TARGET_COLOR))
                print("FACADE ALBEDO_TEXTURE=", sm.albedo_texture.resource_path if sm.albedo_texture != null else "<null>")
            if is_roof:
                roof_candidates += 1
                print("ROOF_CANDIDATE ", desc)
                if not roof_test_done:
                    _apply_facade_texture_to_roof(sm)
                    roof_test_done = true

    print("DIAG facade_material_surfaces=", facade_count, " roof_candidates=", roof_candidates)
    if facade_count == 0:
        print("DIAG WARNING: no facade material matched")
    if roof_candidates == 0:
        print("DIAG WARNING: no roof candidate found")

func _inspect_import_srgb() -> void:
    var file: FileAccess = FileAccess.open(IMPORT_PATH, FileAccess.READ)
    if file == null:
        return
    var text: String = file.get_as_text()
    file.close()
    print("IMPORT_SRGB key_present=", text.findn("srgb") >= 0)

func _apply_facade_texture_to_roof(sm: StandardMaterial3D) -> void:
    var facade_texture: Texture2D = load(FACADE_TEXTURE_PATH) as Texture2D
    if facade_texture == null:
        return
    sm.albedo_texture = facade_texture
    sm.albedo_color = Color.WHITE
    print("ROOF_TEXTURE_TEST temporary facade texture applied")

func _is_facade(mi: MeshInstance3D, sm: StandardMaterial3D) -> bool:
    var node_name: String = mi.name.to_lower()
    var material_name: String = sm.resource_name.to_lower()
    var texture_path: String = sm.albedo_texture.resource_path.to_lower() if sm.albedo_texture != null else ""
    return material_name.contains("muro_romano") or texture_path.contains("roman_plaster_weathered_albedo") or node_name.contains("facade") or node_name.contains("facciata")

func _is_roof(mi: MeshInstance3D, sm: StandardMaterial3D) -> bool:
    var node_name: String = mi.name.to_lower()
    var material_name: String = sm.resource_name.to_lower()
    var texture_path: String = sm.albedo_texture.resource_path.to_lower() if sm.albedo_texture != null else ""
    return node_name.contains("roof") or node_name.contains("tetto") or node_name.contains("coppi") or node_name.contains("tegole") or material_name.contains("roof") or material_name.contains("tetto") or material_name.contains("coppi") or material_name.contains("tegole") or texture_path.contains("roof") or texture_path.contains("coppi") or texture_path.contains("tegole")

func _node_material_desc(mi: MeshInstance3D, surface: int, sm: StandardMaterial3D) -> String:
    var texture_path: String = sm.albedo_texture.resource_path if sm.albedo_texture != null else "<null>"
    return "node=%s surface=%d material=%s color=%s texture=%s" % [mi.get_path(), surface, sm.resource_name, sm.albedo_color.to_html(true), texture_path]

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
