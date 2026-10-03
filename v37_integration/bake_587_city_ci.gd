extends SceneTree
## CI-only bake validator. It uses the authoritative V37 positions and the existing
## V11 editor-safe builder, but does not require the interactive Terrain3D RAW picker.

const EDITOR_SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"

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
    var city := Node3D.new()
    city.name = "RomaCity_BAKED_587"
    get_root().add_child(city)
    var used := {}
    var placed := 0
    for i in range(source.size()):
        var d: Dictionary = source[i]
        var variation: Dictionary = variation_script.call("variation_for", i, int(i / 4))
        var seed := int(variation.get("seed", i))
        if used.has(seed):
            push_error("CI BAKE 587: duplicate seed at %d" % i)
            city.queue_free()
            quit(1)
            return
        var ai := posmod(int(variation.get("archetype_index", i)), catalog.size())
        var entry: Dictionary = catalog[ai]
        var building: Node3D = system.build(entry, i) as Node3D
        if building == null:
            push_error("CI BAKE 587: V11 build returned null at index %d" % i)
            city.queue_free()
            quit(1)
            return
        building.name = str(d.get("id", "building_%d" % (i + 1)))
        building.position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
        building.rotation.y = 0.0
        building.set_meta("v37_source_id", building.name)
        building.set_meta("v37_source_position", building.position)
        building.set_meta("v11_catalog_id", str(entry.get("id", "")))
        building.set_meta("v11_seed", seed)
        building.set_meta("v11_variation", variation)
        building.set_meta("baked_v37", true)
        city.add_child(building)
        building.owner = city
        used[seed] = true
        placed += 1
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
    print("CI BAKE 587 OK: source=587 placed=", placed, " scene=", OUTPUT_SCENE)
    city.queue_free()
    quit(0)

func _load_catalog() -> Array:
    var f := FileAccess.open("res://city_library/buildings/houses/roma_architecture_library_v11/data/building_catalog.json", FileAccess.READ)
    if f == null:
        return []
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    return parsed if parsed is Array else []
