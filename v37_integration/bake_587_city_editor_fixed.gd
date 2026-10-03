@tool
extends EditorScript

## FIXED one-time bake: 587 V37 source positions -> existing V11 modular library.
## Does not modify Terrain3D, Tevere, roads or the V11 library itself.

const ADAPTER_SCRIPT := "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const MAX_SLOPE_DELTA := 2.0
const SUBSOIL_LIMIT := -5.0
const SAFETY_CORRIDOR := 2.0
const GRID_SETBACK := 10.0

func _run() -> void:
    print("BAKE 587 FIXED - avvio")
    var scene_root := get_scene()
    if scene_root == null:
        push_error("BAKE 587: aprire main.tscn")
        return
    var grid = scene_root.get_node_or_null("Urban_Grid")
    var terrain = scene_root.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
    if terrain == null:
        terrain = scene_root.find_child("Terrain3D", true, false)
    if terrain == null:
        push_error("BAKE 587: Terrain3D non trovato")
        return
    var adapter_script: Script = load(ADAPTER_SCRIPT)
    var variation_script: Script = load(VARIATION_SCRIPT)
    var positions_script: Script = load(POSITIONS_SCRIPT)
    if adapter_script == null or variation_script == null or positions_script == null:
        push_error("BAKE 587: risorsa necessaria mancante")
        return
    var adapter = adapter_script.new()
    if not adapter.initialize():
        push_error("BAKE 587: inizializzazione V11 fallita")
        return
    var catalog: Array = adapter.factory.get_catalog()
    var source: Array = positions_script.get_buildings()
    print("BAKE 587 FIXED - sorgente: ", source.size(), " | catalogo: ", catalog.size())

    var city := Node3D.new()
    city.name = "RomaCity_BAKED_587"
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

    var packed := PackedScene.new()
    var pack_error := packed.pack(city)
    if pack_error != OK:
        push_error("BAKE 587: pack fallito: %s" % pack_error)
        city.queue_free()
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked_city"))
    var save_error := ResourceSaver.save(packed, OUTPUT_SCENE)
    if save_error != OK:
        push_error("BAKE 587: save fallito: %s" % save_error)
        city.queue_free()
        return
    city.queue_free()
    print("BAKE 587 FIXED - COMPLETATO | sorgente=", source.size(), " piazzati=", placed, " scartati=", rejected)
    print("BAKE 587 FIXED - scena: ", OUTPUT_SCENE)

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
        if not is_finite(h): return []
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
