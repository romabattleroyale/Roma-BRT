extends SceneTree
## DIAGNOSTIC ONLY — runtime facade/roof texture investigation.
## No project assets are saved or permanently modified by this script.

const MAIN_SCENE := "res://main.tscn"
const FACADE_TEXTURE_PATH := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_albedo.jpg"
const IMPORT_PATH := FACADE_TEXTURE_PATH + ".import"
const TARGET_COLOR := Color(0.827451, 0.65098, 0.227451, 1.0) # #D3A63A

var _roof_test_done: bool = false

func _initialize() -> void:
    print("=== LINUX FACADE DIAGNOSTICS — START ===")
    print("DIAG renderer=", ProjectSettings.get_setting("renderer/rendering_method", "<unset>"))
    var err: Error = change_scene_to_file(MAIN_SCENE)
    print("DIAG change_scene_to_file error=", err)
    call_deferred("_wait_for_scene")

func _wait_for_scene() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().create_timer(8.0).timeout
    _run_diagnostics("T+8s")
    await get_tree().create_timer(8.0).timeout
    _run_diagnostics("T+16s")
    await get_tree().create_timer(10.0).timeout
    print("=== LINUX FACADE DIAGNOSTICS — END ===")
    quit(0)

func _run_diagnostics(label: String) -> void:
    print("--- FACADE DIAGNOSTICS ", label, " ---")
    _inspect_import_srgb()
    var root: Node = get_tree().current_scene
    if root == null:
        print("DIAG scene=<null>")
        return
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    print("DIAG mesh_nodes=", meshes.size())

    var facade_count: int = 0
    var roof_candidates: int = 0
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
                print("FACADE UV_REPEAT raw=", sm.texture_repeat, " name=", _repeat_name(sm.texture_repeat), " UV_FILTER raw=", sm.texture_filter, " name=", _filter_name(sm.texture_filter))
                print("FACADE ALBEDO_COLOR=", sm.albedo_color.to_html(true), " expected=#D3A63AFF target_match=", sm.albedo_color.is_equal_approx(TARGET_COLOR))
                print("FACADE ALBEDO_TEXTURE=", sm.albedo_texture.resource_path if sm.albedo_texture != null else "<null>")
                if sm.texture_repeat != 1:
                    print("FACADE TEMP_TEST: setting texture_repeat=ENABLED for runtime-only diagnostic")
                    sm.texture_repeat = 1
                    print("FACADE TEMP_TEST RESULT repeat=", sm.texture_repeat, " name=", _repeat_name(sm.texture_repeat))
            if is_roof:
                roof_candidates += 1
                print("ROOF_CANDIDATE ", desc)
                if not _roof_test_done and sm.albedo_texture == null:
                    _apply_facade_texture_to_roof(sm)

    print("DIAG facade_material_surfaces=", facade_count, " roof_candidates=", roof_candidates)
    if facade_count == 0:
        print("DIAG WARNING: no facade material matched Muro_Romano/roman_plaster criteria")
    if roof_candidates == 0:
        print("DIAG WARNING: no roof/tetto/coppi/tegole material candidate found")

func _inspect_import_srgb() -> void:
    var file: FileAccess = FileAccess.open(IMPORT_PATH, FileAccess.READ)
    if file == null:
        print("IMPORT_SRGB file=<missing>")
        return
    var text: String = file.get_as_text()
    file.close()
    var has_srgb_key: bool = text.findn("srgb") >= 0
    print("IMPORT_SRGB source=", IMPORT_PATH, " key_present=", has_srgb_key)
    if has_srgb_key:
        for line in text.split("\n"):
            if line.findn("srgb") >= 0:
                print("IMPORT_SRGB line=", line.strip_edges())
    else:
        print("IMPORT_SRGB result=NO_EXPLICIT_SRGB_KEY_IN_GODOT_4_IMPORT")
        print("IMPORT_SRGB note=ResourceImporterTexture in Godot 4.7 does not expose a serialized 'srgb=true' import parameter; this diagnostic records the actual .import state without changing it.")

func _apply_facade_texture_to_roof(sm: StandardMaterial3D) -> void:
    var facade_texture: Texture2D = load(FACADE_TEXTURE_PATH) as Texture2D
    if facade_texture == null:
        print("ROOF_TEXTURE_TEST texture_load=<failed>")
        _roof_test_done = true
        return
    var before_color: String = sm.albedo_color.to_html(true)
    sm.albedo_texture = facade_texture
    sm.albedo_color = Color.WHITE
    print("ROOF_TEXTURE_TEST applied facade texture temporarily; before_color=", before_color, " texture=", facade_texture.resource_path, " repeat=", sm.texture_repeat, " filter=", sm.texture_filter)
    print("ROOF_TEXTURE_TEST RESULT roof_should_render_facade_texture_if_visible_in_capture=true")
    _roof_test_done = true

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

func _repeat_name(value: int) -> String:
    match value:
        0:
            return "DEFAULT"
        1:
            return "ENABLED"
        2:
            return "DISABLED"
        _:
            return "UNKNOWN"

func _filter_name(value: int) -> String:
    match value:
        0:
            return "DEFAULT"
        1:
            return "NEAREST"
        2:
            return "LINEAR"
        3:
            return "NEAREST_MIPMAP"
        4:
            return "LINEAR_MIPMAP"
        5:
            return "NEAREST_MIPMAP_ANISOTROPIC"
        6:
            return "LINEAR_MIPMAP_ANISOTROPIC"
        _:
            return "UNKNOWN"

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)
