@tool
extends EditorScript

## FIXED one-time bake: 587 V37 source positions -> existing V11 modular library.
## Does not modify Terrain3D, Tevere, roads or the V11 library itself.
## The runtime TerrainBootstrap is not used: this script creates a temporary
## Terrain3D and imports the existing RAW in-memory only for height sampling.

const ADAPTER_SCRIPT := "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const RAW_PATH := "res://assets/heightmap.raw"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const MAP_SIZE_M := 2000.0
const HEIGHT_SCALE_M := 48.0
const MAX_SLOPE_DELTA := 2.0
const SUBSOIL_LIMIT := -5.0
const SAFETY_CORRIDOR := 2.0
const GRID_SETBACK := 10.0

func _run() -> void:
    print("BAKE 587 FIXED - avvio")
    var scene_root = EditorInterface.get_edited_scene_root()
    if scene_root == null:
        push_error("BAKE 587: aprire main.tscn")
        return

    var grid = scene_root.get_node_or_null("Urban_Grid")
    var terrain = await _create_editor_terrain()
    if terrain == null:
        return

    var adapter_script: Script = load(ADAPTER_SCRIPT)
    var variation_script: Script = load(VARIATION_SCRIPT)
    var positions_script: Script = load(POSITIONS_SCRIPT)
    if adapter_script == null or variation_script == null or positions_script == null:
        push_error("BAKE 587: risorsa necessaria mancante")
        terrain.queue_free()
        return

    var adapter = adapter_script.new()
    if not adapter.initialize():
        push_error("BAKE 587: inizializzazione V11 fallita")
        terrain.queue_free()
        return

    var catalog: Array = adapter.factory.get_catalog()
    var source: Array = positions_script.get_buildings()
    print("BAKE 587 FIXED - sorgente: ", source.size(), " | catalogo: ", catalog.size())

    var city := Node3D.new()
    city.name = "RomaCity_BAKED_587"
    scene_root.add_child(city)

    var placed := 0
    var rejected := 0
    var used_seeds := {}
    var placed_rects: Array = []

    for i in range(source.size()):
        var d: Dictionary = source[i]
        var x := float(d.get("x", NAN))
        var z := float(d.get("z", NAN))
        if not is_finite(x) or not is_finite(z):
            rejected += 1
            continue

        var block := _find_block(x, z, grid)
        if block.is_empty():
            rejected += 1
            continue

        var variation: Dictionary = variation_script.call("variation_for", i, int(block["index"]))
        var seed := int(variation.get("seed", i))
        if used_seeds.has(seed):
            rejected += 1
            continue

        var ai := posmod(int(variation.get("archetype_index", i)), max(1, catalog.size()))
        var entry: Dictionary = catalog[ai]
        var w := maxf(6.0, float(entry.get("w", d.get("sx", 10.0))))
        var dep := maxf(6.0, float(entry.get("d", d.get("sz", 10.0))))
        var center := Vector3(x, 0.0, z)

        if not _inside_block(center, w, dep, block) or _overlaps(center, w, dep, placed_rects):
            rejected += 1
            continue

        var h := _terrain_height(terrain, x, z)
        var hs := _corner_heights(terrain, center, w, dep)
        if hs.size() != 4:
            rejected += 1
            continue

        var mn: float = hs[0]
        var mx: float = hs[0]
        var sum := 0.0
        for value in hs:
            mn = minf(mn, float(value))
            mx = maxf(mx, float(value))
            sum += float(value)

        if mx - mn > MAX_SLOPE_DELTA or sum / 4.0 < SUBSOIL_LIMIT:
            rejected += 1
            continue

        var building: Node3D = adapter.factory.build_and_place(str(entry["id"]), center, h, 0.0, i)
        if building == null:
            rejected += 1
            continue

        building.name = str(d.get("id", "building_%d" % (i + 1)))
        building.set_meta("v37_source_id", building.name)
        building.set_meta("v37_source_position", center)
        building.set_meta("v11_catalog_id", str(entry["id"]))
        building.set_meta("v11_seed", seed)
        building.set_meta("v11_variation", variation)
        building.set_meta("baked_v37", true)
        city.add_child(building)
        used_seeds[seed] = true
        placed_rects.append({"center": center, "width": w, "depth": dep})
        placed += 1

        if placed % 25 == 0:
            print("BAKE 587 FIXED - piazzati: ", placed)
        if i % 10 == 0:
            await get_tree().process_frame

    var packed := PackedScene.new()
    var pack_error := packed.pack(city)
    if pack_error != OK:
        push_error("BAKE 587: pack fallito: %s" % pack_error)
        city.queue_free()
        terrain.queue_free()
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked_city"))
    var save_error := ResourceSaver.save(packed, OUTPUT_SCENE)
    if save_error != OK:
        push_error("BAKE 587: save fallito: %s" % save_error)
        city.queue_free()
        terrain.queue_free()
        return

    city.queue_free()
    terrain.queue_free()
    print("BAKE 587 FIXED - COMPLETATO | sorgente=", source.size(), " piazzati=", placed, " scartati=", rejected)
    print("BAKE 587 FIXED - scena: ", OUTPUT_SCENE)

func _create_editor_terrain() -> Node:
    if not ClassDB.class_exists("Terrain3D"):
        push_error("BAKE 587: Terrain3D/GDExtension non disponibile nell'editor")
        return null

    var terrain = Terrain3D.new()
    terrain.name = "Terrain3D_BAKE_TEMP"
    terrain.region_size = 512
    terrain.vertex_spacing = MAP_SIZE_M / 1080.0
    terrain.mesh_lods = 7
    terrain.show_checkered = false
    terrain.show_colormap = false
    terrain.show_grey = false

    var assets: Terrain3DAssets = load("res://terrain_materials/terrain_assets_roman_natural.tres")
    if assets:
        terrain.assets = assets

    get_scene_root().add_child(terrain, true)
    await get_tree().process_frame

    if terrain.data == null:
        push_error("BAKE 587: Terrain3D Data non inizializzato")
        terrain.queue_free()
        return null

    var file := FileAccess.open(RAW_PATH, FileAccess.READ)
    if file == null:
        push_error("BAKE 587: RAW non trovato: " + RAW_PATH)
        terrain.queue_free()
        return null

    var bytes := file.get_buffer(file.get_length())
    file.close()
    var samples := bytes.size() / 2
    var side := int(sqrt(float(samples)))
    if side * side != samples:
        push_error("BAKE 587: RAW non quadrato")
        terrain.queue_free()
        return null

    var values := PackedFloat32Array()
    values.resize(samples)
    var min_u := 65535
    var max_u := 0
    for i in range(samples):
        var u := (int(bytes[i * 2]) << 8) | int(bytes[i * 2 + 1])
        min_u = mini(min_u, u)
        max_u = maxi(max_u, u)
        values[i] = float(u)

    var source_range := maxf(1.0, float(max_u - min_u))
    for i in range(samples):
        values[i] = clampf((values[i] - float(min_u)) / source_range, 0.0, 1.0)

    var img := Image.create_from_data(side, side, false, Image.FORMAT_RF, values.to_byte_array())
    var maps: Array[Image]
    maps.resize(Terrain3DRegion.TYPE_MAX)
    maps[Terrain3DRegion.TYPE_HEIGHT] = img
    terrain.data.import_images(maps, Vector3.ZERO, 0.0, HEIGHT_SCALE_M)
    terrain.data.calc_height_range(true)
    print("BAKE 587 FIXED - Terrain3D temporaneo pronto | height=", terrain.data.get_height_range())
    return terrain

func get_scene_root() -> Node:
    return EditorInterface.get_edited_scene_root()

func _terrain_height(terrain: Node, x: float, z: float) -> float:
    if terrain.has_method("get_height"):
        var h := float(terrain.get_height(Vector3(x, 0.0, z)))
        if is_finite(h):
            return h
    var data = terrain.get("data")
    if data != null and data.has_method("get_height"):
        var h2 := float(data.get_height(Vector3(x, 0.0, z)))
        if is_finite(h2):
            return h2
    return 0.0

func _corner_heights(terrain: Node, c: Vector3, w: float, d: float) -> Array:
    var out: Array = []
    for p in [Vector3(c.x-w*0.5,0,c.z-d*0.5), Vector3(c.x+w*0.5,0,c.z-d*0.5), Vector3(c.x-w*0.5,0,c.z+d*0.5), Vector3(c.x+w*0.5,0,c.z+d*0.5)]:
        var h := _terrain_height(terrain, p.x, p.z)
        if not is_finite(h):
            return []
        out.append(h)
    return out

func _find_block(x: float, z: float, grid: Node) -> Dictionary:
    if grid != null and grid.has_meta("lot_rects"):
        var rects: Array = grid.get_meta("lot_rects")
        for i in range(rects.size()):
            var r: Dictionary = rects[i]
            if x >= float(r["min_x"]) and x <= float(r["max_x"]) and z >= float(r["min_z"]) and z <= float(r["max_z"]):
                var copy := r.duplicate(true)
                copy["index"] = i
                return copy
    var fallback := [[520.0,900.0,420.0,760.0],[900.0,1390.0,420.0,760.0],[520.0,900.0,760.0,1080.0],[900.0,1390.0,760.0,1080.0],[520.0,900.0,1080.0,1400.0],[900.0,1390.0,1080.0,1400.0],[520.0,900.0,1400.0,1660.0],[900.0,1390.0,1400.0,1660.0]]
    for i in range(fallback.size()):
        var b: Array = fallback[i]
        if x >= b[0] and x <= b[1] and z >= b[2] and z <= b[3]:
            return {"min_x":b[0],"max_x":b[1],"min_z":b[2],"max_z":b[3],"index":i}
    return {}

func _inside_block(c: Vector3, w: float, d: float, r: Dictionary) -> bool:
    return c.x >= float(r["min_x"])+GRID_SETBACK+w*0.5 and c.x <= float(r["max_x"])-GRID_SETBACK-w*0.5 and c.z >= float(r["min_z"])+GRID_SETBACK+d*0.5 and c.z <= float(r["max_z"])-GRID_SETBACK-d*0.5

func _overlaps(c: Vector3, w: float, d: float, rects: Array) -> bool:
    for r in rects:
        var o: Vector3 = r["center"]
        var xgap := absf(c.x-o.x)-(w+float(r["width"]))*0.5
        var zgap := absf(c.z-o.z)-(d+float(r["depth"]))*0.5
        if xgap < SAFETY_CORRIDOR and zgap < SAFETY_CORRIDOR:
            return true
    return false
