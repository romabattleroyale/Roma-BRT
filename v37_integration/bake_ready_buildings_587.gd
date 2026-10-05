extends SceneTree
## One-time CI bake: 587 V11 buildings, merged mobile geometry, Roman materials,
## shared imported textures and one simplified BoxShape3D collision per building.
## CI trigger marker: run the complete ready-building bake and progressive memory gates.

const FACTORY_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/modular_house_factory.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const READY_DIR := "res://baked_city/ready_buildings"
const MATERIAL_DIR := READY_DIR + "/materials"
const RAW_PATH := "res://assets/heightmap.raw"
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIAL_DIR))
    var factory_script: Script = load(FACTORY_SCRIPT) as Script
    var positions_script: Script = load(POSITIONS_SCRIPT) as Script
    var variation_script: Script = load(VARIATION_SCRIPT) as Script
    if factory_script == null or positions_script == null or variation_script == null:
        push_error("READY BAKE: dependency load failed")
        quit(1)
        return
    var factory = factory_script.new()
    if factory == null or not factory.initialize():
        push_error("READY BAKE: factory initialize failed")
        quit(1)
        return
    var source: Array = positions_script.get_buildings()
    var catalog: Array[Dictionary] = factory.get_catalog()
    if source.size() != 587 or catalog.size() != 27:
        push_error("READY BAKE: source=%d catalog=%d" % [source.size(), catalog.size()])
        quit(1)
        return
    var heightmap := _load_raw_heightmap()
    if heightmap.is_empty():
        quit(1)
        return
    var side: int = int(heightmap["side"])
    var heights: PackedFloat32Array = heightmap["values"]
    _write_shared_materials()
    var material_cache: Dictionary = _load_shared_materials()
    var baked := 0
    for i in range(source.size()):
        var d: Dictionary = source[i]
        var variation: Dictionary = variation_script.call("variation_for", i, int(i / 4))
        var ai: int = posmod(int(variation.get("archetype_index", i)), catalog.size())
        var entry: Dictionary = catalog[ai]
        var id: String = str(entry.get("id", ""))
        var root: Node3D = factory.build_mobile_by_id(id, i) as Node3D
        if root == null:
            push_error("READY BAKE: build failed index=%d id=%s" % [i, id])
            quit(1)
            return
        root.name = str(d.get("id", "building_%03d" % (i + 1)))
        root.set_meta("ready_bake", true)
        root.set_meta("ready_index", i)
        root.set_meta("v11_catalog_id", id)
        root.set_meta("v11_seed", int(variation.get("seed", i)))
        root.set_meta("v11_facade_color", str(variation.get("facade_color", "")))
        var floors: int = int(variation.get("height_floors", 3))
        root.set_meta("v11_height_floors", floors)
        var facade_index := posmod(i * 7 + 1, 6)
        var roof_index := posmod(i * 5 + 2, 3)
        var roof_variant := int(i / 10) * 10
        if posmod(i, 2) == 1:
            roof_variant += 7
        root.set_meta("ready_signature", "%s|f%d|r%d|c%d|rc%d" % [id, floors, roof_variant, facade_index, roof_index])
        var x := float(d.get("x", 0.0))
        var z := float(d.get("z", 0.0))
        var h := _sample_height(heights, side, x, z)
        if not is_finite(h):
            push_error("READY BAKE: invalid height index=%d" % i)
            root.free()
            quit(1)
            return
        root.position = Vector3(x, h, z)
        _apply_shared_materials(root, i, material_cache)
        _optimize_mobile_meshes(root)
        _remove_factory_collisions(root)
        _add_box_collision(root, float(entry.get("w", 10.0)), float(entry.get("d", 10.0)), floors)
        _set_owner_recursive(root, root)
        var packed := PackedScene.new()
        var err := packed.pack(root)
        root.free()
        if err != OK:
            push_error("READY BAKE: pack failed index=%d err=%s" % [i, err])
            quit(1)
            return
        var out := "%s/building_%03d.tscn" % [READY_DIR, i + 1]
        err = ResourceSaver.save(packed, out)
        if err != OK:
            push_error("READY BAKE: save failed index=%d err=%s" % [i, err])
            quit(1)
            return
        baked += 1
        if baked % 25 == 0:
            print("READY BAKE: ", baked, "/587")
    print("READY BAKE OK: pre_generated=", baked, " dir=", READY_DIR)
    quit(0)

func _write_shared_materials() -> void:
    var facade_colors := [Color("#B97845"), Color("#D3A63A"), Color("#B96F73"), Color("#C7AA83"), Color("#A9573B"), Color("#A99A7E")]
    var roof_colors := [Color("#B84D32"), Color("#C9783F"), Color("#8F6B4E")]
    var albedo := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_albedo.jpg") as Texture2D
    var normal := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_normal.jpg") as Texture2D
    var rough := load("res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/roman_plaster_weathered_roughness.jpg") as Texture2D
    for i in range(facade_colors.size()):
        var m := StandardMaterial3D.new()
        m.albedo_color = facade_colors[i]
        m.albedo_texture = albedo
        m.normal_enabled = normal != null
        m.normal_texture = normal
        m.normal_scale = 0.58
        m.roughness_texture = rough
        m.roughness = 0.88
        m.uv1_scale = Vector3(3.6, 3.6, 3.6)
        m.texture_repeat = true
        ResourceSaver.save(m, "%s/facade_%d.tres" % [MATERIAL_DIR, i])
    for i in range(roof_colors.size()):
        var m := StandardMaterial3D.new()
        m.albedo_color = roof_colors[i]
        m.roughness = 0.90
        ResourceSaver.save(m, "%s/roof_%d.tres" % [MATERIAL_DIR, i])

func _load_shared_materials() -> Dictionary:
    var c := {}
    for i in range(6):
        c["f%d" % i] = load("%s/facade_%d.tres" % [MATERIAL_DIR, i])
    for i in range(3):
        c["r%d" % i] = load("%s/roof_%d.tres" % [MATERIAL_DIR, i])
    return c

func _apply_shared_materials(root: Node3D, variant: int, cache: Dictionary) -> void:
    var facade_index := posmod(variant * 7 + 1, 6)
    var roof_index := posmod(variant * 5 + 2, 3)
    for node in _mesh_nodes(root):
        if not bool(node.get_meta("mobile_merged", false)) or node.mesh == null:
            continue
        var mesh := node.mesh as ArrayMesh
        if mesh == null:
            continue
        var roles: Array = mesh.get_meta("surface_roles", []) as Array
        for s in range(mesh.get_surface_count()):
            var role := str(roles[s]) if s < roles.size() else "other"
            if role == "facade":
                mesh.surface_set_material(s, cache["f%d" % facade_index])
            elif role == "roof":
                mesh.surface_set_material(s, cache["r%d" % roof_index])
        for s in range(mesh.get_surface_count()):
            node.set_surface_override_material(s, null)

func _optimize_mobile_meshes(root: Node3D) -> void:
    ## Godot 4.7.2-compatible storage optimization: reuse the merged ArrayMesh
    ## and avoid unsupported ARRAY_COMPRESS_DEFAULT API calls.
    ## The factory already produces the mobile merged mesh; keeping that resource
    ## intact avoids an additional full mesh allocation during the bake.
    for node in _mesh_nodes(root):
        if not bool(node.get_meta("mobile_merged", false)) or node.mesh == null:
            continue
        var source := node.mesh as ArrayMesh
        if source == null:
            continue
        source.resource_name = "ReadyMobile_%s" % source.resource_name

func _remove_factory_collisions(root: Node3D) -> void:
    _strip_collision_nodes(root)

func _strip_collision_nodes(node: Node) -> void:
    for child in node.get_children():
        if child is StaticBody3D or child is CollisionShape3D or child is CollisionPolygon3D:
            child.free()
        else:
            _strip_collision_nodes(child)

func _add_box_collision(root: Node3D, width: float, depth: float, floors: int) -> void:
    var body := StaticBody3D.new()
    body.name = "Collision"
    var shape := CollisionShape3D.new()
    shape.name = "BoxCollision"
    var box := BoxShape3D.new()
    box.size = Vector3(maxf(width, 2.0), maxf(2.0, float(floors) * 3.2), maxf(depth, 2.0))
    shape.shape = box
    shape.position.y = box.size.y * 0.5
    body.add_child(shape)
    root.add_child(body)

func _mesh_nodes(root: Node3D) -> Array[MeshInstance3D]:
    var result: Array[MeshInstance3D] = []
    _collect(root, result)
    return result

func _collect(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect(child, result)

func _set_owner_recursive(node: Node, owner: Node) -> void:
    if node != owner:
        node.owner = owner
    for child in node.get_children():
        _set_owner_recursive(child, owner)

func _load_raw_heightmap() -> Dictionary:
    var f := FileAccess.open(RAW_PATH, FileAccess.READ)
    if f == null:
        push_error("READY BAKE: RAW heightmap missing")
        return {}
    var bytes := f.get_buffer(f.get_length())
    f.close()
    if bytes.size() == 0 or bytes.size() % 2 != 0:
        push_error("READY BAKE: invalid RAW bytes=%d" % bytes.size())
        return {}
    var samples := bytes.size() / 2
    var side := int(sqrt(float(samples)))
    if side * side != samples:
        push_error("READY BAKE: RAW not square samples=%d" % samples)
        return {}
    var values := PackedFloat32Array()
    values.resize(samples)
    var min_u := 65535
    var max_u := 0
    for i in range(samples):
        var u := (int(bytes[i * 2]) << 8) | int(bytes[i * 2 + 1])
        values[i] = float(u)
        min_u = mini(min_u, u)
        max_u = maxi(max_u, u)
    var source_range := maxf(1.0, float(max_u - min_u))
    for i in range(samples):
        values[i] = clampf((values[i] - float(min_u)) / source_range, 0.0, 1.0)
    return {"side": side, "values": values}

func _sample_height(values: PackedFloat32Array, side: int, x: float, z: float) -> float:
    var fx := clampf(x / MAP_SIZE_M * float(side - 1), 0.0, float(side - 1))
    var fz := clampf(z / MAP_SIZE_M * float(side - 1), 0.0, float(side - 1))
    var x0 := int(floor(fx))
    var z0 := int(floor(fz))
    var x1 := mini(x0 + 1, side - 1)
    var z1 := mini(z0 + 1, side - 1)
    var tx := fx - float(x0)
    var tz := fz - float(z0)
    var h00 := values[z0 * side + x0]
    var h10 := values[z0 * side + x1]
    var h01 := values[z1 * side + x0]
    var h11 := values[z1 * side + x1]
    return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz) * HEIGHT_SCALE_M
