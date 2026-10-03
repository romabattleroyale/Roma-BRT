@tool
extends SceneTree
## FIXED 587 bake runner.
## Supports both headless CI and editor invocation through the same bake body.
## Does not change Terrain3D, Tevere, roads, or V11 aesthetics.

const EDITOR_SYSTEM_SCRIPT := "res://city_library/buildings/houses/roma_architecture_library_v11/scripts/editor_library_building_system.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const OUTPUT_SCENE := "res://baked_city/roma_city_587.tscn"
const TERRAIN_NAME := "Terrain3D_HEIGHTMAP_2000x2000"
const MAX_SLOPE_DELTA := 2.0
const SUBSOIL_LIMIT := -5.0
const SAFETY_CORRIDOR := 2.0
const GRID_SETBACK := 10.0

func _init() -> void:
    if not Engine.is_editor_hint():
        call_deferred("_headless_run")

func _headless_run() -> void:
    var packed_main: PackedScene = load("res://main.tscn") as PackedScene
    if packed_main == null:
        push_error("BAKE 587 FINAL: main.tscn non caricabile")
        quit(1)
        return
    var root := packed_main.instantiate()
    if root == null:
        push_error("BAKE 587 FINAL: impossibile istanziare main.tscn")
        quit(1)
        return
    get_root().add_child(root)
    await process_frame
    _run_with_root(root)
    root.queue_free()
    quit(0)

func _run() -> void:
    var root := EditorInterface.get_edited_scene_root()
    if root == null or root.scene_file_path != "res://main.tscn":
        EditorInterface.open_scene_from_path("res://main.tscn")
        root = EditorInterface.get_edited_scene_root()
    if root == null:
        push_error("BAKE 587 FIXED: impossibile aprire res://main.tscn")
        return
    _run_with_root(root)

func _run_with_root(root: Node) -> void:
    print("BAKE 587 FINAL - avvio")
    var terrain := _find_terrain3d(root)
    if terrain == null:
        push_error("BAKE 587 FINAL: Terrain3D non trovato nella scena aperta")
        return
    var terrain_data = terrain.get("data")
    if terrain_data == null:
        push_error("BAKE 587 FINAL: Terrain3D trovato ma data non pronta")
        return
    if not terrain_data.has_method("get_height") and not terrain.has_method("get_height"):
        push_error("BAKE 587 FINAL: Terrain3D non espone get_height")
        return
    var variation_script: Script = load(VARIATION_SCRIPT) as Script
    var positions_script: Script = load(POSITIONS_SCRIPT) as Script
    var system_script: Script = load(EDITOR_SYSTEM_SCRIPT) as Script
    if variation_script == null or positions_script == null or system_script == null:
        push_error("BAKE 587 FINAL: dipendenze mancanti")
        return
    var system = system_script.new()
    if system == null:
        push_error("BAKE 587 FINAL: impossibile creare editor-safe V11 system")
        return
    system.setup_materials()
    var catalog: Array = _load_catalog()
    var source: Array = positions_script.get_buildings()
    print("BAKE 587 FINAL - Terrain3D: ", terrain.name)
    print("BAKE 587 FINAL - sorgente: ", source.size(), " | catalogo V11: ", catalog.size())
    if source.size() != 587:
        push_error("BAKE 587 FINAL: sorgente V37 attesa 587, trovata %d" % source.size())
        return
    if catalog.is_empty():
        push_error("BAKE 587 FINAL: catalogo V11 vuoto")
        return
    var city := Node3D.new()
    city.name = "RomaCity_BAKED_587"
    var placed := 0
    var rejected := 0
    var used_seeds := {}
    var placed_rects: Array = []
    for i in range(source.size()):
        var d: Dictionary = source[i]
        var x := float(d.get("x", 0.0))
        var z := float(d.get("z", 0.0))
        if not is_finite(x) or not is_finite(z):
            rejected += 1
            continue
        var source_w := maxf(6.0, float(d.get("sx", 10.0)))
        var source_d := maxf(6.0, float(d.get("sz", 10.0)))
        var block := _find_block(x, z, root)
        if block.is_empty():
            rejected += 1
            continue
        var block_index := int(block.get("index", 0))
        var variation: Dictionary = variation_script.call("variation_for", i, block_index)
        var seed := int(variation.get("seed", i))
        if used_seeds.has(seed):
            rejected += 1
            continue
        var ai := posmod(int(variation.get("archetype_index", i)), catalog.size())
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
        var h := _terrain_height(terrain, terrain_data, x, z)
        var hs := _corner_heights(terrain, terrain_data, center, width, depth)
        if hs.size() != 4:
            rejected += 1
            continue
        var mn := float(hs[0])
        var mx := mn
        var sum := 0.0
        for value in hs:
            var fv := float(value)
            mn = minf(mn, fv)
            mx = maxf(mx, fv)
            sum += fv
        if not is_finite(h) or not is_finite(mn) or not is_finite(mx):
            rejected += 1
            continue
        if mx - mn > MAX_SLOPE_DELTA or sum / 4.0 < SUBSOIL_LIMIT:
            rejected += 1
            continue
        var building: Node3D = system.build(entry, i) as Node3D
        if building == null:
            rejected += 1
            continue
        building.name = str(d.get("id", "building_%d" % (i + 1)))
        building.position = Vector3(x, h, z)
        building.rotation.y = 0.0
        building.set_meta("v37_source_id", building.name)
        building.set_meta("v37_source_position", building.position)
        building.set_meta("v11_catalog_id", str(entry.get("id", "")))
        building.set_meta("v11_seed", seed)
        building.set_meta("v11_variation", variation)
        building.set_meta("baked_v37", true)
        city.add_child(building)
        building.owner = city
        used_seeds[seed] = true
        placed_rects.append({"center": center, "width": width, "depth": depth})
        placed += 1
        if placed % 25 == 0:
            print("BAKE 587 FINAL - progress: ", placed, "/", source.size())
    var packed := PackedScene.new()
    var pack_error := packed.pack(city)
    if pack_error != OK:
        push_error("BAKE 587 FINAL: PackedScene.pack fallito: %s" % pack_error)
        city.free()
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://baked_city"))
    var save_error := ResourceSaver.save(packed, OUTPUT_SCENE)
    if save_error != OK:
        push_error("BAKE 587 FINAL: salvataggio fallito: %s" % save_error)
        city.free()
        return
    city.free()
    print("BAKE 587 FINAL - COMPLETATO")
    print("BAKE 587 FINAL - sorgente: ", source.size())
    print("BAKE 587 FINAL - piazzati: ", placed)
    print("BAKE 587 FINAL - scartati: ", rejected)
    print("BAKE 587 FINAL - scena: ", OUTPUT_SCENE)

func _find_terrain3d(root: Node) -> Node:
    var named := root.find_child(TERRAIN_NAME, true, false)
    if named != null and named.get_class() == "Terrain3D":
        return named
    return _find_terrain3d_recursive(root)

func _find_terrain3d_recursive(node: Node) -> Node:
    for child in node.get_children():
        if child.get_class() == "Terrain3D":
            return child
        var nested := _find_terrain3d_recursive(child)
        if nested != null:
            return nested
    return null

func _load_catalog() -> Array:
    const path := "res://city_library/buildings/houses/roma_architecture_library_v11/data/building_catalog.json"
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return []
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    return parsed if parsed is Array else []

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

func _corner_heights(terrain: Node, data, c: Vector3, w: float, d: float) -> Array:
    var points := [Vector3(c.x - w * 0.5, 0.0, c.z - d * 0.5), Vector3(c.x + w * 0.5, 0.0, c.z - d * 0.5), Vector3(c.x - w * 0.5, 0.0, c.z + d * 0.5), Vector3(c.x + w * 0.5, 0.0, c.z + d * 0.5)]
    var result: Array = []
    for p in points:
        result.append(_terrain_height(terrain, data, p.x, p.z))
    return result

func _find_block(x: float, z: float, root: Node) -> Dictionary:
    var grid := root.get_node_or_null("Urban_Grid")
    if grid != null and grid.has_meta("lot_rects"):
        var rects = grid.get_meta("lot_rects")
        for i in range(rects.size()):
            var r = rects[i]
            if x >= float(r["min_x"]) and x <= float(r["max_x"]) and z >= float(r["min_z"]) and z <= float(r["max_z"]):
                var copy = r.duplicate(true)
                copy["index"] = i
                return copy
    return {}

func _inside_block(c: Vector3, w: float, d: float, r: Dictionary) -> bool:
    return c.x >= float(r["min_x"]) + GRID_SETBACK + w * 0.5 and c.x <= float(r["max_x"]) - GRID_SETBACK - w * 0.5 and c.z >= float(r["min_z"]) + GRID_SETBACK + d * 0.5 and c.z <= float(r["max_z"]) - GRID_SETBACK - d * 0.5

func _overlaps(c: Vector3, w: float, d: float, rects: Array) -> bool:
    for r in rects:
        var o: Vector3 = r["center"]
        var xgap := absf(c.x - o.x) - (w + float(r["width"])) * 0.5
        var zgap := absf(c.z - o.z) - (d + float(r["depth"])) * 0.5
        if xgap < SAFETY_CORRIDOR and zgap < SAFETY_CORRIDOR:
            return true
    return false
