extends SceneTree
## CI bake validator/finalizer.
## Builds the authoritative 587 V11 buildings using the same authoritative RAW
## heightmap used by runtime Terrain3D, then stores each catalog archetype once.
## CI does not instantiate Terrain3D: the native extension is not required to
## calculate the building Y coordinates and must not block the city bake.

const EDITOR_SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const ARCHETYPE_DIR := "res://baked_city/archetypes_587"
const RAW_PATH := "res://assets/heightmap.raw"
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const BYTES_PER_SAMPLE := 2

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var variation_script: Script = load(VARIATION_SCRIPT) as Script
    var positions_script: Script = load(POSITIONS_SCRIPT) as Script
    var system_script: Script = load(EDITOR_SYSTEM_SCRIPT) as Script
    if variation_script == null or positions_script == null or system_script == null:
        push_error("CI BAKE 587: dipendenze mancanti")
        quit(1)
        return

    var heightmap := _load_raw_heightmap()
    if heightmap.is_empty():
        quit(1)
        return
    var side := int(heightmap.get("side", 0))
    var values: PackedFloat32Array = heightmap.get("values", PackedFloat32Array())
    if side < 2 or values.size() != side * side:
        push_error("CI BAKE 587: heightmap RAW non valida")
        quit(1)
        return

    var system = system_script.new()
    if system == null:
        push_error("CI BAKE 587: builder V11 non disponibile")
        quit(1)
        return
    system.setup_materials()

    var catalog := _load_catalog()
    var source: Array = positions_script.get_buildings()
    if source.size() != 587 or catalog.is_empty():
        push_error("CI BAKE 587: source=%d catalog=%d" % [source.size(), catalog.size()])
        quit(1)
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARCHETYPE_DIR))
    var archetype_scenes: Array[PackedScene] = []
    archetype_scenes.resize(catalog.size())

    for ai in range(catalog.size()):
        var archetype_path := "%s/archetype_%02d.tscn" % [ARCHETYPE_DIR, ai]
        var building: Node3D = system.build(catalog[ai], ai) as Node3D
        if building == null:
            push_error("CI BAKE 587: V11 build returned null for archetype %d" % ai)
            quit(1)
            return
        building.name = str(catalog[ai].get("id", "archetype_%02d" % ai))
        get_root().add_child(building)
        _set_owner_recursive(building, building)
        var archetype_packed := PackedScene.new()
        var archetype_err := archetype_packed.pack(building)
        if archetype_err != OK:
            push_error("CI BAKE 587: archetype pack failed %d err=%s" % [ai, archetype_err])
            building.queue_free()
            quit(1)
            return
        archetype_err = ResourceSaver.save(archetype_packed, archetype_path)
        building.queue_free()
        if archetype_err != OK:
            push_error("CI BAKE 587: archetype save failed %d err=%s" % [ai, archetype_err])
            quit(1)
            return
        archetype_scenes[ai] = load(archetype_path) as PackedScene
        if archetype_scenes[ai] == null:
            push_error("CI BAKE 587: archetype reload failed %d" % ai)
            quit(1)
            return

    var city := Node3D.new()
    city.name = "RomaCity_BAKED_587"
    get_root().add_child(city)
    var used := {}
    var placed := 0
    var missing_height := 0

    for i in range(source.size()):
        var d: Dictionary = source[i]
        var x := float(d.get("x", 0.0))
        var z := float(d.get("z", 0.0))
        var h := _sample_height(values, side, x, z)
        if not is_finite(h):
            missing_height += 1
            push_error("CI BAKE 587: height non valida at index=%d x=%f z=%f" % [i, x, z])
            city.queue_free()
            quit(1)
            return

        var variation: Dictionary = variation_script.call("variation_for", i, int(i / 4))
        var seed := int(variation.get("seed", i))
        if used.has(seed):
            push_error("CI BAKE 587: duplicate seed at %d" % i)
            city.queue_free()
            quit(1)
            return
        var ai := posmod(int(variation.get("archetype_index", i)), catalog.size())
        var entry: Dictionary = catalog[ai]
        var building_instance := archetype_scenes[ai].instantiate() as Node3D
        if building_instance == null:
            push_error("CI BAKE 587: archetype instance null at index %d" % i)
            city.queue_free()
            quit(1)
            return

        building_instance.name = str(d.get("id", "building_%d" % (i + 1)))
        building_instance.position = Vector3(x, h, z)
        building_instance.rotation.y = 0.0
        building_instance.set_meta("v37_source_id", building_instance.name)
        building_instance.set_meta("v37_source_position", building_instance.position)
        building_instance.set_meta("v11_catalog_id", str(entry.get("id", "")))
        building_instance.set_meta("v11_seed", seed)
        building_instance.set_meta("v11_variation", variation)
        building_instance.set_meta("baked_v37", true)
        city.add_child(building_instance)
        building_instance.owner = city
        used[seed] = true
        placed += 1

    if missing_height != 0 or placed != 587:
        push_error("CI BAKE 587: source=%d placed=%d missing_height=%d" % [source.size(), placed, missing_height])
        city.queue_free()
        quit(1)
        return

    var packed := PackedScene.new()
    var err := packed.pack(city)
    if err != OK:
        push_error("CI BAKE 587: pack failed %s" % err)
        city.queue_free()
        quit(1)
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked_city"))
    err = ResourceSaver.save(packed, OUTPUT_SCENE)
    if err != OK:
        push_error("CI BAKE 587: save failed %s" % err)
        city.queue_free()
        quit(1)
        return

    print("CI BAKE 587 OK: source=587 placed=587 terrain=REAL_RAW_DIRECT reusable_archetypes=", catalog.size(), " scene=", OUTPUT_SCENE)
    city.queue_free()
    quit(0)

func _load_raw_heightmap() -> Dictionary:
    var f := FileAccess.open(RAW_PATH, FileAccess.READ)
    if f == null:
        push_error("CI BAKE 587: RAW non apribile: %s" % RAW_PATH)
        return {}
    var bytes := f.get_buffer(f.get_length())
    f.close()
    if bytes.size() == 0 or bytes.size() % BYTES_PER_SAMPLE != 0:
        push_error("CI BAKE 587: RAW non valido, bytes=%d" % bytes.size())
        return {}

    var samples := bytes.size() / BYTES_PER_SAMPLE
    var side := int(sqrt(float(samples)))
    if side * side != samples:
        push_error("CI BAKE 587: RAW non quadrato, samples=%d" % samples)
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

    print("CI RAW HEIGHT OK: ", side, "x", side, " min/max=", min_u, "/", max_u, " height_scale=", HEIGHT_SCALE_M)
    return {"side": side, "values": values}

func _sample_height(values: PackedFloat32Array, side: int, x: float, z: float) -> float:
    # Same 0..MAP_SIZE_M world domain used by the existing CI Terrain3D import.
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
    var hx0 := lerpf(h00, h10, tx)
    var hx1 := lerpf(h01, h11, tx)
    return lerpf(hx0, hx1, tz) * HEIGHT_SCALE_M

func _set_owner_recursive(node: Node, owner: Node) -> void:
    node.owner = owner
    for child in node.get_children():
        _set_owner_recursive(child, owner)

func _load_catalog() -> Array:
    var f := FileAccess.open("res://city_library/buildings/houses/roma_architecture_library_v11/data/building_catalog.json", FileAccess.READ)
    if f == null:
        return []
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    return parsed if parsed is Array else []
