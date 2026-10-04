extends SceneTree

const FACTORY_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/modular_house_factory.gd"
const SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var factory_script := load(FACTORY_SCRIPT) as Script
    var system_script := load(SYSTEM_SCRIPT) as Script
    if factory_script == null or system_script == null:
        push_error("ORANGE DIAGNOSTIC: factory/system missing")
        quit(10)
        return
    var factory = factory_script.new()
    if not factory.initialize():
        push_error("ORANGE DIAGNOSTIC: factory initialize failed")
        quit(11)
        return
    var catalog: Array[Dictionary] = factory.get_catalog()
    if catalog.is_empty():
        push_error("ORANGE DIAGNOSTIC: catalog empty")
        quit(12)
        return

    var entry: Dictionary = catalog[0].duplicate(true)
    entry["floors"] = 3
    entry["id"] = "__orange_visual_diagnostic"
    var system = system_script.new()
    system.setup_materials()
    var prototype := system.build(entry, 0) as Node3D
    if prototype == null:
        push_error("ORANGE DIAGNOSTIC: build failed")
        quit(13)
        return
    prototype = factory._merge_mobile_geometry(prototype, 3)
    if prototype == null:
        push_error("ORANGE DIAGNOSTIC: mobile merge failed")
        quit(14)
        return

    var orange := StandardMaterial3D.new()
    orange.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
    orange.albedo_texture = null
    orange.normal_enabled = false
    orange.normal_texture = null
    orange.roughness_texture = null
    orange.roughness = 0.85
    orange.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(prototype, meshes)
    var surfaces := 0
    for mi in meshes:
        if mi.mesh == null:
            continue
        for s in range(mi.mesh.get_surface_count()):
            mi.set_surface_override_material(s, orange)
            surfaces += 1

    var root := Node3D.new()
    root.name = "OrangeFacadeDiagnostic"
    get_root().add_child(root)
    root.add_child(prototype)
    prototype.position = Vector3.ZERO

    var camera := Camera3D.new()
    camera.name = "DiagnosticCamera"
    root.add_child(camera)
    camera.current = true
    camera.fov = 48.0

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
    light.light_energy = 1.5
    root.add_child(light)

    var fill := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.18, 0.22, 0.28)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.65, 0.68, 0.72)
    env.ambient_light_energy = 0.9
    fill.environment = env
    root.add_child(fill)

    var box := _combined_aabb(prototype)
    var center := box.position + box.size * 0.5
    var radius: float = maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5
    radius = maxf(radius, 2.0)
    camera.position = center + Vector3(radius * 1.8, radius * 1.25, radius * 1.8)
    camera.look_at(center, Vector3.UP)

    print("ORANGE DIAGNOSTIC: surfaces=", surfaces, " aabb=", box, " center=", center)
    await process_frame
    await process_frame
    await process_frame
    var image := get_root().get_viewport().get_texture().get_image()
    image.flip_y()
    var path := "build/linux_runtime/orange_facade_test.png"
    var err := image.save_png(path)
    print("ORANGE DIAGNOSTIC: screenshot=", path, " err=", err)
    quit(0 if err == OK else 15)

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func _combined_aabb(root: Node3D) -> AABB:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var first := true
    var result := AABB()
    for mi in meshes:
        if mi.mesh == null:
            continue
        var local_box := mi.get_aabb()
        var corners := [
            local_box.position,
            local_box.position + Vector3(local_box.size.x, 0, 0),
            local_box.position + Vector3(0, local_box.size.y, 0),
            local_box.position + Vector3(0, 0, local_box.size.z),
            local_box.position + Vector3(local_box.size.x, local_box.size.y, 0),
            local_box.position + Vector3(local_box.size.x, 0, local_box.size.z),
            local_box.position + Vector3(0, local_box.size.y, local_box.size.z),
            local_box.position + local_box.size
        ]
        for c in corners:
            var p: Vector3 = mi.transform * c
            if first:
                result = AABB(p, Vector3.ZERO)
                first = false
            else:
                result = result.expand(p)
    return result
