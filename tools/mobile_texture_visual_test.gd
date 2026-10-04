extends Node3D
## Dedicated Android visual/texture smoke test.
## Instantiates one optimized V11 archetype, prints the Texture2D resources
## actually resolved on Android, and renders the facade for an adb screenshot.

const ARCHETYPE := "res://baked_city/archetypes_587/archetype_00.tscn"

func _ready() -> void:
    var building_scene: PackedScene = load(ARCHETYPE) as PackedScene
    if building_scene == null:
        push_error("ANDROID TEXTURE TEST FAIL: cannot load archetype_00")
        get_tree().quit(2)
        return
    var building: Node3D = building_scene.instantiate() as Node3D
    if building == null:
        push_error("ANDROID TEXTURE TEST FAIL: instantiate failed")
        get_tree().quit(3)
        return
    add_child(building)

    var aabb := _visual_aabb(building)
    var center: Vector3 = aabb.position + aabb.size * 0.5
    var camera := Camera3D.new()
    camera.current = true
    var span: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
    camera.position = center + Vector3(span * 1.25, span * 0.70, span * 1.25)
    camera.look_at(center, Vector3.UP)
    add_child(camera)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_energy = 1.2
    add_child(sun)

    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.08, 0.10, 0.14)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.55, 0.55, 0.55)
    environment.ambient_light_energy = 0.8
    env.environment = environment
    add_child(env)

    await get_tree().process_frame
    await get_tree().process_frame
    var texture_paths: Dictionary = _collect_texture_paths(building)
    var material_report: Dictionary = _collect_material_report(building)
    print("=== ANDROID TEXTURE TEST ===")
    print("Archetipo: %s" % ARCHETYPE)
    print("Texture2D risolte su Android: %d" % texture_paths.size())
    for path in texture_paths.keys():
        print("ANDROID_TEXTURE: %s" % path)
    print("MATERIAL_REPORT: %s" % JSON.stringify(material_report))
    if not bool(material_report.get("muro_romano_used", false)):
        push_error("ANDROID ART TEST FAIL: Muro_Romano is not assigned to any visible surface")
        get_tree().quit(4)
        return
    if not bool(material_report.get("muro_romano_terracotta", false)):
        push_error("ANDROID ART TEST FAIL: Muro_Romano is not using terracotta albedo")
        get_tree().quit(5)
        return
    if not bool(material_report.get("muro_romano_pbr", false)):
        push_error("ANDROID ART TEST FAIL: Muro_Romano missing normal/roughness")
        get_tree().quit(6)
        return
    print("ANDROID_ART_TEST PASS: Muro_Romano terracotta + normal + roughness assigned")
    print("ANDROID_TEXTURE_TEST PASS: texture resources resolved")
    await get_tree().create_timer(3.0).timeout
    get_tree().quit(0)

func _collect_texture_paths(root: Node) -> Dictionary:
    var out: Dictionary = {}
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is MeshInstance3D:
            var mi: MeshInstance3D = current as MeshInstance3D
            if mi.mesh != null:
                for s in range(mi.mesh.get_surface_count()):
                    _collect_material_textures(mi.mesh.get_surface_material(s), out)
                for s in range(mi.get_surface_override_material_count()):
                    _collect_material_textures(mi.get_surface_override_material(s), out)
        for child in current.get_children():
            stack.append(child)
    return out

func _collect_material_report(root: Node) -> Dictionary:
    var report: Dictionary = {
        "muro_romano_used": false,
        "muro_romano_terracotta": false,
        "muro_romano_pbr": false,
        "material_usage": {},
        "detail_nodes": []
    }
    var usage: Dictionary = report["material_usage"] as Dictionary
    var detail_nodes: Array[String] = report["detail_nodes"] as Array[String]
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        var lower_name: String = current.name.to_lower()
        if lower_name.contains("balcon") or lower_name.contains("persian") or lower_name.contains("shutter") or lower_name.contains("cornic") or lower_name.contains("travert"):
            detail_nodes.append(str(current.name))
        if current is MeshInstance3D:
            var mi: MeshInstance3D = current as MeshInstance3D
            if mi.mesh != null:
                for s in range(mi.mesh.get_surface_count()):
                    _inspect_material(mi.mesh.get_surface_material(s), report, usage)
                for s in range(mi.get_surface_override_material_count()):
                    _inspect_material(mi.get_surface_override_material(s), report, usage)
        for child in current.get_children():
            stack.append(child)
    detail_nodes.sort()
    return report

func _inspect_material(material: Material, report: Dictionary, usage: Dictionary) -> void:
    if material == null:
        return
    var path: String = material.resource_path
    if path.is_empty():
        path = "<embedded>"
    usage[path] = int(usage.get(path, 0)) + 1
    if material.resource_name != "Muro_Romano":
        return
    report["muro_romano_used"] = true
    var albedo: Variant = material.get("albedo_texture")
    var normal: Variant = material.get("normal_texture")
    var roughness: Variant = material.get("roughness_texture")
    if albedo is Texture2D and (albedo as Texture2D).resource_path.contains("roman_plaster_terracotta"):
        report["muro_romano_terracotta"] = true
    if normal is Texture2D and roughness is Texture2D:
        report["muro_romano_pbr"] = true

func _collect_material_textures(material: Material, out: Dictionary) -> void:
    if material == null:
        return
    for prop in material.get_property_list():
        var prop_name: String = str(prop.get("name", ""))
        var value: Variant = material.get(prop_name)
        if value is Texture2D:
            var texture: Texture2D = value as Texture2D
            var path: String = texture.resource_path
            if path.is_empty():
                path = "<embedded>"
            out[path] = true
    if material is ShaderMaterial:
        var shader_material: ShaderMaterial = material as ShaderMaterial
        var shader: Shader = shader_material.shader
        if shader != null:
            for uniform in shader.get_shader_uniform_list():
                var uniform_name: String = str(uniform.get("name", ""))
                var shader_value: Variant = shader_material.get_shader_parameter(uniform_name)
                if shader_value is Texture2D:
                    var texture: Texture2D = shader_value as Texture2D
                    var path: String = texture.resource_path
                    if path.is_empty():
                        path = "<embedded>"
                    out[path] = true

func _visual_aabb(root: Node3D) -> AABB:
    var first: bool = true
    var out := AABB()
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is MeshInstance3D:
            var mi: MeshInstance3D = current as MeshInstance3D
            if mi.mesh != null:
                var tr: Transform3D = _local_transform_to_root(mi, root)
                for s in range(mi.mesh.get_surface_count()):
                    var arrays: Array = mi.mesh.surface_get_arrays(s)
                    if arrays.is_empty():
                        continue
                    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
                    if vertices != null:
                        for v: Vector3 in vertices:
                            var p: Vector3 = tr * v
                            if first:
                                out = AABB(p, Vector3.ZERO)
                                first = false
                            else:
                                out = out.expand(p)
        for child in current.get_children():
            stack.append(child)
    return out

func _local_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current: Node = node
    while current != root:
        var n: Node3D = current as Node3D
        if n == null:
            break
        result = n.transform * result
        current = n.get_parent()
    return result
