extends SceneTree
## CI bake validator/finalizer.
## Builds the authoritative 587 V11 buildings on the real RAW terrain, but
## stores each catalog archetype once and the city as lightweight scene instances.
## This avoids embedding 587 copies of procedural Mesh resources in one .tscn.

const EDITOR_SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const ARCHETYPE_DIR := "res://baked_city/archetypes_587"
const RAW_PATH := "res://assets/heightmap.raw"
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const BYTES_PER_SAMPLE := 2
const TERRAIN_NAME := "CI_Terrain3D_Heightmap"

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

    var terrain := await _build_ci_terrain()
    if terrain == null:
        quit(1)
        return
    var terrain_data = terrain.get("data")
    if terrain_data == null:
        push_error("CI BAKE 587: Terrain3D data non pronta")
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

    # Build and save each V11 catalog entry exactly once.
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
        var h := _terrain_height(terrain, terrain_data, x, z)
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
        # Only the scene-instance root belongs to the city. Its geometry remains
        # owned by the reusable archetype PackedScene and is not duplicated here.
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

    print("CI BAKE 587 OK: source=587 placed=587 terrain=REAL_RAW reusable_archetypes=", catalog.size(), " scene=", OUTPUT_SCENE)
    city.queue_free()
    terrain.queue_free()
    quit(0)

func _set_owner_recursive(node: Node, owner: Node) -> void:
    node.owner = owner
    for child in node.get_children():
        _set_owner_recursive(child, owner)

func _build_ci_terrain() -> Node3D:
    if not ClassDB.class_exists("Terrain3D"):
        push_error("CI BAKE 587: Terrain3D class non disponibile")
        return null

    var terrain = Terrain3D.new()
    terrain.name = TERRAIN_NAME
    # Avoid static Terrain3D enum references here: the CI script can be parsed
    # before the GDExtension registers its GDScript classes. The property accepts
    # the documented SIZE_512 enum value (512).
    terrain.region_size = 512
    terrain.vertex_spacing = MAP_SIZE_M / 1080.0
    terrain.mesh_lods = 7
    terrain.show_checkered = false
    terrain.show_colormap = false
    terrain.show_grey = false
    get_root().add_child(terrain, true)
    await process_frame

    var data = terrain.get("data")
    if data == null:
        push_error("CI BAKE 587: Terrain3D Data non inizializzato")
        terrain.queue_free()
        return null

    var f := FileAccess.open(RAW_PATH, FileAccess.READ)
    if f == null:
        push_error("CI BAKE 587: RAW non apribile: %s" % RAW_PATH)
        terrain.queue_free()
        return null
    var bytes := f.get_buffer(f.get_length())
    f.close()
    if bytes.size() == 0 or bytes.size() % BYTES_PER_SAMPLE != 0:
        push_error("CI BAKE 587: RAW non valido, bytes=%d" % bytes.size())
        terrain.queue_free()
        return null

    var samples := bytes.size() / BYTES_PER_SAMPLE
    var side := int(sqrt(float(samples)))
    if side * side != samples:
        push_error("CI BAKE 587: RAW non quadrato, samples=%d" % samples)
        terrain.queue_free()
        return null

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

    var img := Image.create_from_data(side, side, false, Image.FORMAT_RF, values.to_byte_array())
    if img == null:
        push_error("CI BAKE 587: impossibile creare height Image")
        terrain.queue_free()
        return null

    # Terrain3DRegion.TYPE_MAX is 3 (HEIGHT, CONTROL, COLOR) and TYPE_HEIGHT is 0.
    # Use the documented enum values directly so the script remains parse-safe in CI.
    var maps: Array[Image]
    maps.resize(3)
    maps[0] = img
    data.import_images(maps, Vector3.ZERO, 0.0, HEIGHT_SCALE_M)
    data.calc_height_range(true)
    await process_frame

    print("CI TERRAIN OK: RAW=", side, "x", side, " min/max=", min_u, "/", max_u, " height_scale=", HEIGHT_SCALE_M)
    return terrain

func _terrain_height(terrain: Node, data, x: float, z: float) -> float:
    var p := Vector3(x, 0.0, z)
    if terrain.has_method("get_height"):
        var h := float(terrain.get_height(p))
        if is_finite(h):
            return h
    if data != null and data.has_method("get_height"):
        var h2 := float(data.get_height(p))
        if is_finite(h2):
            return h2
    return NAN

func _load_catalog() -> Array:
    var f := FileAccess.open("res://city_library/buildings/houses/roma_architecture_library_v11/data/building_catalog.json", FileAccess.READ)
    if f == null:
        return []
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    return parsed if parsed is Array else []