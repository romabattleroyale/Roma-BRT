@tool
extends EditorScript
## One-time editor bake for the V37 587 building positions using the existing V11 modular library.
## Run from Godot EditorScript. It creates res://baked_city/roma_city_587.tscn.
## Runtime must load the baked scene; it must NOT rebuild the buildings on Play.

const ADAPTER_SCRIPT := "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const MAX_SLOPE_DELTA := 2.0
const SUBSOIL_LIMIT := -5.0
const SAFETY_CORRIDOR := 2.0
const GRID_SETBACK := 10.0

func _run() -> void:
    print("BAKE 587 — avvio costruzione editor-only")
    var scene_root := get_scene()
    if scene_root == null:
        push_error("BAKE 587: aprire main.tscn prima di eseguire lo script")
        return
    var v37 := scene_root.get_node_or_null("V37Integration")
    var grid := scene_root.get_node_or_null("Urban_Grid")
    if v37 == null:
        push_error("BAKE 587: V37Integration non trovato")
        return

    var adapter_script: Script = load(ADAPTER_SCRIPT)
    var variation_script: Script = load(VARIATION_SCRIPT)
    var positions_script: Script = load(POSITIONS_SCRIPT)
    if adapter_script == null or variation_script == null or positions_script == null:
        push_error("BAKE 587: libreria/variazione/posizioni mancanti")
        return

    var adapter = adapter_script.new()
    if not adapter.initialize():
        push_error("BAKE 587: inizializzazione V11 fallita")
        return
    var catalog: Array[Dictionary] = adapter.factory.get_catalog()
    var source: Array = positions_script.get_buildings()
    print("BAKE 587 — sorgente: ", source.size(), " | catalogo V11: ", catalog.size())

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
        var source_w := maxf(6.0, float(d.get("sx", 10.0)))
        var source_d := maxf(6.0, float(d.get("sz", 10.0)))
        if not is_finite(x) or not is_finite(z):
            rejected += 1
            continue

        var block := _find_block(x, z, grid)
        if block.is_empty():
            rejected += 1
            continue
        var block_index := int(block["index"])
        var variation: Dictionary = variation_script.call("variation_for", i, block_index)
        var seed := int(variation["seed"])
        if used_seeds.has(seed):
            rejected += 1
            continue
        var ai := posmod(int(variation["archetype_index"]), max(1, catalog.size()))
        var entry: Dictionary = catalog[ai]
        var width := maxf(6.0, float(entry.get("w", source_w)))
        var depth := maxf(6.0, float(entry.get("d", source_d)))
        var center := Vector3(x, 0.0, z)
        if not _inside_block(center, width, depth, block):
            rejected += 1
            continue
        if _overlaps(center, width, depth, placed_rects):
            rejected += 1
            continue

        var h := _sample_height(v37, center.x, center.z)
        var hs := _corner_heights(v37, center, width, depth)
        if hs.size() != 4:
            rejected += 1
            continue
        var mn := hs[0]
        var mx := hs[0]
        var sum := 0.0
        for value in hs:
            mn = minf(mn, value)
            mx = maxf(mx, value)
            sum += value
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
        placed_rects.append({"center": center, "width": width, "depth": depth})
        placed += 1

    var output := PackedScene.new()
    var packed_error := output.pack(city)
    if packed_error != OK:
        push_error("BAKE 587: impossibile creare PackedScene: %s" % packed_error)
        city.queue_free()
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked_city"))
    var save_error := ResourceSaver.save(output, OUTPUT_SCENE)
    if save_error != OK:
        push_error("BAKE 587: salvataggio fallito: %s" % save_error)
        city.queue_free()
        return

    city.queue_free()
    print("BAKE 587 — COMPLETATO")
    print("BAKE 587 — sorgente: ", source.size())
    print("BAKE 587 — piazzati: ", placed)
    print("BAKE 587 — scartati: ", rejected)
    print("BAKE 587 — scena: ", OUTPUT_SCENE)
    print("BAKE 587 — ora main.tscn deve solo istanziare la scena baked; nessuna build durante Play.")

func _sample_height(world: Node, x: float, z: float) -> float:
    if world.has_method("sample_height"):
        return float(world.sample_height(x, z))
    return 0.0

func _corner_heights(world: Node, c: Vector3, w: float, d: float) -> Array:
    var result: Array = []
    for p in [Vector3(c.x-w*0.5,0,c.z-d*0.5), Vector3(c.x+w*0.5,0,c.z-d*0.5), Vector3(c.x-w*0.5,0,c.z+d*0.5), Vector3(c.x+w*0.5,0,c.z+d*0.5)]:
        var h := _sample_height(world, p.x, p.z)
        if not is_finite(h): return []
        result.append(h)
    return result

func _find_block(x: float, z: float, grid: Node) -> Dictionary:
    var rects: Array = []
    if grid != null:
        rects = grid.get_meta("lot_rects", [])
    for i in range(rects.size()):
        var r: Dictionary = rects[i]
        if x >= float(r["min_x"]) and x <= float(r["max_x"]) and z >= float(r["min_z"]) and z <= float(r["max_z"]):
            var copy := r.duplicate(true)
            copy["index"] = i
            return copy
    return {}

func _inside_block(c: Vector3, w: float, d: float, r: Dictionary) -> bool:
    return c.x >= float(r["min_x"]) + GRID_SETBACK + w*0.5 and c.x <= float(r["max_x"]) - GRID_SETBACK - w*0.5 and c.z >= float(r["min_z"]) + GRID_SETBACK + d*0.5 and c.z <= float(r["max_z"]) - GRID_SETBACK - d*0.5

func _overlaps(c: Vector3, w: float, d: float, rects: Array) -> bool:
    for r in rects:
        var o: Vector3 = r["center"]
        var xgap := absf(c.x-o.x) - (w + float(r["width"])) * 0.5
        var zgap := absf(c.z-o.z) - (d + float(r["depth"])) * 0.5
        if xgap < SAFETY_CORRIDOR and zgap < SAFETY_CORRIDOR:
            return true
    return false
