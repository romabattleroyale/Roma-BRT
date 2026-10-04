extends SceneTree
## Headless V11 artistic/material audit.
## Audits every baked archetype without changing scene geometry, terrain, roads, or graph.
## Uses the effective material path (surface override -> material_override -> mesh surface)
## so the audit matches what the optimized runtime actually renders.

const ARCH_DIR: String = "res://baked_city/archetypes_587"
const OUT_FILE: String = "user://v11_artistic_audit.txt"

func _initialize() -> void:
    var report: FileAccess = FileAccess.open(OUT_FILE, FileAccess.WRITE)
    if report == null:
        print("V11_ART_AUDIT FAIL: cannot open report")
        quit(2)
        return

    var files: PackedStringArray = DirAccess.get_files_at(ARCH_DIR)
    files.sort()
    var archetypes: Array[String] = []
    for file_name in files:
        if file_name.begins_with("archetype_") and file_name.ends_with(".tscn"):
            archetypes.append(file_name)

    print("=== V11 ARTISTIC AUDIT ===")
    print("Archetipi trovati: %d" % archetypes.size())
    report.store_line("V11_ARTISTIC_AUDIT archetypes=%d" % archetypes.size())

    var global_materials: Dictionary = {}
    var global_textures: Dictionary = {}
    var global_uv_missing: int = 0
    var global_meshes: int = 0
    var global_nodes: int = 0
    var global_effective_overrides: int = 0
    var global_detail_nodes: int = 0
    var failures: int = 0

    for file_name in archetypes:
        var path: String = ARCH_DIR + "/" + file_name
        var packed: PackedScene = load(path) as PackedScene
        if packed == null:
            print("ARCHETYPE_FAIL %s load" % file_name)
            report.store_line("ARCHETYPE_FAIL %s load" % file_name)
            failures += 1
            continue
        var root: Node = packed.instantiate()
        if root == null:
            print("ARCHETYPE_FAIL %s instantiate" % file_name)
            report.store_line("ARCHETYPE_FAIL %s instantiate" % file_name)
            failures += 1
            continue

        var mesh_count: int = 0
        var node_count: int = 0
        var uv_missing: int = 0
        var effective_override_count: int = 0
        var detail_node_count: int = 0
        var materials: Dictionary = {}
        var textures: Dictionary = {}
        var named_nodes: Array[String] = []

        var stack: Array[Node] = [root]
        while not stack.is_empty():
            var current: Node = stack.pop_back()
            node_count += 1
            var lower_name: String = current.name.to_lower()
            if lower_name.contains("balcon") or lower_name.contains("persian") or lower_name.contains("shutter") or lower_name.contains("cornic") or lower_name.contains("travert"):
                named_nodes.append(str(current.name))
                detail_node_count += 1
            if current is MeshInstance3D:
                mesh_count += 1
                var mi: MeshInstance3D = current as MeshInstance3D
                if mi.material_override != null:
                    effective_override_count += 1
                if mi.mesh != null:
                    for s in range(mi.mesh.get_surface_count()):
                        var surface_material: Material = mi.get_surface_override_material(s)
                        if surface_material == null:
                            surface_material = mi.material_override
                        if surface_material == null:
                            surface_material = mi.mesh.get_surface_material(s)
                        _audit_material(surface_material, materials, textures)
                        if not _has_uv(mi.mesh.surface_get_arrays(s)):
                            uv_missing += 1
            for child in current.get_children():
                stack.append(child)

        for key in materials.keys():
            global_materials[key] = true
        for key in textures.keys():
            global_textures[key] = true
        global_uv_missing += uv_missing
        global_meshes += mesh_count
        global_nodes += node_count
        global_effective_overrides += effective_override_count
        global_detail_nodes += detail_node_count

        var material_list: Array[String] = []
        for key in materials.keys():
            material_list.append(str(key))
        material_list.sort()
        var texture_list: Array[String] = []
        for key in textures.keys():
            texture_list.append(str(key))
        texture_list.sort()
        var named_list: Array[String] = named_nodes.duplicate()
        named_list.sort()

        var line: String = "ARCHETYPE %s meshes=%d nodes=%d uv_missing=%d effective_material_overrides=%d materials=%s textures=%s named_detail_nodes=%s" % [file_name, mesh_count, node_count, uv_missing, effective_override_count, ";".join(material_list), ";".join(texture_list), ";".join(named_list)]
        print(line)
        report.store_line(line)
        root.free()

    report.store_line("SUMMARY archetypes=%d failures=%d meshes=%d nodes=%d uv_missing=%d effective_material_overrides=%d named_detail_nodes=%d unique_materials=%d unique_textures=%d" % [archetypes.size(), failures, global_meshes, global_nodes, global_uv_missing, global_effective_overrides, global_detail_nodes, global_materials.size(), global_textures.size()])
    print("SUMMARY archetypes=%d failures=%d meshes=%d nodes=%d uv_missing=%d effective_material_overrides=%d named_detail_nodes=%d unique_materials=%d unique_textures=%d" % [archetypes.size(), failures, global_meshes, global_nodes, global_uv_missing, global_effective_overrides, global_detail_nodes, global_materials.size(), global_textures.size()])

    if failures > 0 or global_uv_missing > 0:
        quit(1)
    quit(0)

func _has_uv(arrays: Array) -> bool:
    if arrays.is_empty():
        return false
    var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
    return uv is PackedVector2Array and not (uv as PackedVector2Array).is_empty()

func _audit_material(material: Material, materials: Dictionary, textures: Dictionary) -> void:
    if material == null:
        return
    var material_path: String = material.resource_path
    if material_path.is_empty():
        material_path = "<embedded>"
    materials[material_path] = true
    for prop in material.get_property_list():
        var prop_name: String = str(prop.get("name", ""))
        var value: Variant = material.get(prop_name)
        if value is Texture2D:
            var texture: Texture2D = value as Texture2D
            var texture_path: String = texture.resource_path
            if texture_path.is_empty():
                texture_path = "<embedded>"
            textures[texture_path] = true
