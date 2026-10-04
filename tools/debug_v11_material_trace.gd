extends SceneTree
## DEBUG ONLY — no material/mesh/terrain changes.
## Traces the V11 mobile facade material before assignment, after assignment,
## after factory return, and inspects final per-surface materials + UVs.

const FACTORY_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/modular_house_factory.gd"
const SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"
const MATERIAL_DIR := "res://baked_city/v11_shared_materials"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    print("=== V11 MATERIAL DEBUG — START ===")
    print("RENDERER project.rendering_method=", ProjectSettings.get_setting("renderer/rendering_method", "<unset>"))
    print("RENDERER project.rendering_method.mobile=", ProjectSettings.get_setting("renderer/rendering_method.mobile", "<unset>"))
    if RenderingServer.has_method("get_rendering_method"):
        print("RENDERER runtime.method=", RenderingServer.call("get_rendering_method"))
    if RenderingServer.has_method("get_video_adapter_name"):
        print("RENDERER adapter=", RenderingServer.call("get_video_adapter_name"))

    var factory_script := load(FACTORY_SCRIPT) as Script
    if factory_script == null:
        push_error("DEBUG TRACE: factory script missing")
        quit(10)
        return
    var factory = factory_script.new()
    if not factory.initialize():
        push_error("DEBUG TRACE: factory initialize failed")
        quit(11)
        return

    var catalog: Array[Dictionary] = factory.get_catalog()
    if catalog.is_empty():
        push_error("DEBUG TRACE: catalog empty")
        quit(12)
        return

    var entry: Dictionary = catalog[0]
    var id := str(entry.get("id", ""))
    var floors := 3
    var roof_variant := 0
    print("FACTORY INPUT id=", id, " floors=", floors, " roof_variant=", roof_variant)

    var system = load(SYSTEM_SCRIPT).new()
    system.setup_materials()
    var source: Dictionary = entry.duplicate(true)
    source["floors"] = floors
    source["id"] = "__debug_material_trace"
    var prototype: Node3D = system.build(source, roof_variant) as Node3D
    if prototype == null:
        push_error("DEBUG TRACE: system.build failed")
        quit(13)
        return

    prototype = factory._merge_mobile_geometry(prototype, floors)
    if prototype == null:
        push_error("DEBUG TRACE: mobile merge failed")
        quit(14)
        return

    print("LIFECYCLE A — AFTER FACTORY MERGE, BEFORE MOBILE VISUAL VARIATION")
    _inspect_root(prototype, "BEFORE_ASSIGNMENT")

    var visual = factory.visual_variation
    if visual == null:
        push_error("DEBUG TRACE: visual variation script not initialized")
        quit(15)
        return

    print("LIFECYCLE B — CALL mobile_visual_variation.apply()")
    visual.apply(prototype, 0, floors)

    print("LIFECYCLE C — AFTER mobile_visual_variation.apply()")
    _inspect_root(prototype, "AFTER_ASSIGNMENT")

    print("LIFECYCLE D — FACTORY build_mobile_by_id() FINAL RETURN")
    var final_root: Node3D = factory.build_mobile_by_id(id, 0) as Node3D
    if final_root == null:
        push_error("DEBUG TRACE: factory build_mobile_by_id failed")
        quit(16)
        return
    _inspect_root(final_root, "FACTORY_FINAL")

    print("LIFECYCLE E — SHARED MATERIAL RESOURCE INSPECTION")
    _inspect_shared_materials()

    print("LIFECYCLE F — SIMPLE ALBEDO-ONLY COMPATIBILITY MATERIAL (TEMPORARY, NOT SAVED)")
    var simple := StandardMaterial3D.new()
    simple.albedo_color = Color(0.8, 0.5, 0.3, 1.0)
    simple.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    print("SIMPLE albedo_color=", simple.albedo_color.to_html(false), " texture=<null>")
    print("SIMPLE shading_mode=", simple.shading_mode, " vertex_color_use_as_albedo=", simple.vertex_color_use_as_albedo)

    prototype.free()
    final_root.free()
    print("=== V11 MATERIAL DEBUG — END ===")
    quit(0)

func _inspect_root(root: Node3D, label: String) -> void:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    print(label, " mesh_nodes=", meshes.size())
    for mi in meshes:
        if mi.mesh == null:
            print(label, " NODE=", mi.name, " mesh=<null>")
            continue
        var mesh := mi.mesh
        var surface_count := mesh.get_surface_count()
        print(label, " NODE=", mi.name, " surface_count=", surface_count, " material_override=", _material_desc(mi.material_override))
        for s in range(surface_count):
            var arrays := mesh.surface_get_arrays(s)
            var uv_desc := "<none>"
            if not arrays.is_empty() and arrays.size() > Mesh.ARRAY_TEX_UV:
                var uv = arrays[Mesh.ARRAY_TEX_UV]
                if uv is PackedVector2Array:
                    var p: PackedVector2Array = uv
                    uv_desc = "count=%d first=%s" % [p.size(), str(p[0]) if p.size() > 0 else "<empty>"]
            var override := mi.get_surface_override_material(s)
            var active := mi.get_active_material(s)
            var mesh_mat := mesh.surface_get_material(s)
            print(label, " SURFACE=", s, " override=", _material_desc(override), " active=", _material_desc(active), " mesh_material=", _material_desc(mesh_mat), " UV=", uv_desc)

func _inspect_shared_materials() -> void:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        print("SHARED materials directory missing")
        return
    var files := dir.get_files()
    files.sort()
    var count := 0
    for file_name in files:
        if not file_name.ends_with(".tres"):
            continue
        var mat := load("%s/%s" % [MATERIAL_DIR, file_name]) as StandardMaterial3D
        if mat == null:
            continue
        var tex_path := "<null>"
        if mat.albedo_texture != null:
            tex_path = mat.albedo_texture.resource_path
        print("SHARED ", file_name, " resource_name=", mat.resource_name, " albedo=", mat.albedo_color.to_html(false), " texture=", tex_path, " normal_enabled=", mat.normal_enabled, " roughness=", mat.roughness, " shading_mode=", mat.shading_mode, " vertex_color_use_as_albedo=", mat.vertex_color_use_as_albedo)
        count += 1
        if count >= 40:
            print("SHARED inspection truncated at 40 materials")
            break

func _material_desc(material: Material) -> String:
    if material == null:
        return "<null>"
    if material is StandardMaterial3D:
        var m := material as StandardMaterial3D
        var tex_path := "<null>"
        if m.albedo_texture != null:
            tex_path = m.albedo_texture.resource_path
        return "StandardMaterial3D color=%s tex=%s normal=%s rough=%.2f shading=%d vtx_albedo=%s" % [m.albedo_color.to_html(false), tex_path, str(m.normal_enabled), m.roughness, m.shading_mode, str(m.vertex_color_use_as_albedo)]
    return material.get_class()

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)
