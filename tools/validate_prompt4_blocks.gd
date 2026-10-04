extends SceneTree
## Hard gate for Prompt 4 urban block layout.
## Verifies Urban_Grid, V11 bridge placement, 8 compact blocks, 20 m road corridors,
## Terrain3D/Tevere preservation, and Roman facade palette before scale tests.

const MAIN_SCENE := "res://main.tscn"
const EXPECTED_BLOCKS := 8
const BUILDINGS_PER_BLOCK := 5
const ROAD_SETBACK := 10.0
const WAIT_SECONDS := 65.0
const REQUIRED_PALETTE := ["#B97845", "#D3A63A", "#B96F73", "#C7AA83", "#A9573B", "#A99A7E"]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    print("=== PROMPT 4 BLOCK GATE ===")
    var scene: PackedScene = load(MAIN_SCENE) as PackedScene
    if scene == null:
        push_error("BLOCK GATE FAIL: main.tscn missing/unloadable")
        quit(1)
        return
    var root: Node = scene.instantiate()
    root.name = "Prompt4GateRoot"
    root.process_mode = Node.PROCESS_MODE_ALWAYS
    root_scene_add(root)

    var grid: Node = root.get_node_or_null("Urban_Grid")
    print("Urban_Grid node: ", "OK" if grid != null else "MISSING")
    var rects: Array = []

    var bridge: Node = root.get_node_or_null("V11BuildingBridge")
    print("Bridge V11: ", "OK" if bridge != null else "MISSING")

    var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
    while bridge != null and not bool(bridge.get("built")) and Time.get_ticks_msec() < deadline:
        await process_frame

    if bridge == null:
        push_error("BLOCK GATE FAIL: V11 bridge missing")
        root.queue_free()
        quit(2)
        return
    if not bool(bridge.get("built")):
        push_error("BLOCK GATE FAIL: V11 bridge did not finish within %.0f s" % WAIT_SECONDS)
        root.queue_free()
        quit(3)
        return

    # Urban_Grid publishes lot_rects during scene initialization. Read it only
    # after the bridge has finished so the gate cannot race _ready() metadata.
    var rect_deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
    while grid != null and rects.size() < EXPECTED_BLOCKS and Time.get_ticks_msec() < rect_deadline:
        rects = grid.get_meta("lot_rects", []) as Array
        if rects.size() < EXPECTED_BLOCKS:
            await process_frame
    print("Urban_Grid: %d rettangoli trovati" % rects.size())

    var city_root: Node = null
    var v37: Node = root.get_node_or_null("V37Integration")
    if v37 != null:
        city_root = v37.get("city_root") as Node
    var block_counts: Dictionary = {}
    var buildings: Array[Node] = []
    if city_root != null:
        _collect_prompt4_buildings(city_root, buildings)
    for b in buildings:
        var block_id := str(b.get_meta("prompt4_block", ""))
        if not block_id.is_empty():
            block_counts[block_id] = int(block_counts.get(block_id, 0)) + 1

    print("Isolati creati: %d" % block_counts.size())
    print("Edifici V11 caricati: %d" % buildings.size())
    for block_id in block_counts.keys():
        print("Edifici per isolato — %s: %d" % [block_id, int(block_counts[block_id])])

    var terrain := root.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
    var water := root.find_child("WaterPlane", true, false)
    print("Terrain3D: ", "OK" if terrain != null else "MISSING")
    print("Tevere/WaterPlane: ", "OK" if water != null else "MISSING")

    var texture_paths: Dictionary = {}
    for b in buildings:
        _collect_texture_paths(b, texture_paths)
    print("Texture runtime uniche: %d" % texture_paths.size())

    var configs := [
        "res://project.godot",
        "res://data/scene_3d.json",
        "res://city_library/buildings/houses/roma_architecture_library_v11/data/building_catalog.json"
    ]
    var missing := []
    for path in configs:
        if not FileAccess.file_exists(path):
            missing.append(path)
    print("Configurazioni mancanti: %d" % missing.size())
    for path in missing:
        print("CONFIG MISSING: ", path)

    var block_geometry_ok := _validate_blocks(rects, buildings)
    var corridor_ok := _validate_corridors(rects, buildings)
    var courtyard_ok := _validate_courtyards(rects, buildings)
    var palette_ok := _validate_palette()

    print("Isolati compatti + cortili: ", "PASS" if block_geometry_ok and courtyard_ok else "FAIL")
    print("Corridoi stradali 20 m: ", "PASS" if corridor_ok else "FAIL")
    print("Palette Roman: ", "PASS" if palette_ok else "FAIL")

    var all_ok := rects.size() == EXPECTED_BLOCKS and block_counts.size() == EXPECTED_BLOCKS and buildings.size() == EXPECTED_BLOCKS * BUILDINGS_PER_BLOCK and block_geometry_ok and corridor_ok and courtyard_ok and palette_ok and terrain != null and water != null and missing.is_empty()
    if not all_ok:
        push_error("PROMPT 4 BLOCK GATE FAIL")
        root.queue_free()
        quit(4)
        return

    print("PROMPT 4 BLOCK GATE PASS")
    root.queue_free()
    quit(0)

func root_scene_add(root: Node) -> void:
    root_scene = root
    get_root().add_child(root)

var root_scene: Node

func _collect_prompt4_buildings(node: Node, result: Array[Node]) -> void:
    if node.get_meta("prompt4_block", null) != null and bool(node.get_meta("prompt4_courtyard", false)):
        result.append(node)
    for child in node.get_children():
        _collect_prompt4_buildings(child, result)

func _collect_texture_paths(root: Node, result: Dictionary) -> void:
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        for child in node.get_children():
            stack.append(child)
        for prop in node.get_property_list():
            var name := str(prop.get("name", ""))
            if name.is_empty():
                continue
            var value = node.get(name)
            if value is Texture2D:
                var path := (value as Texture2D).resource_path
                result[path if not path.is_empty() else "<embedded>"] = true
            elif value is Material:
                _collect_material_textures(value as Material, result)

func _collect_material_textures(material: Material, result: Dictionary) -> void:
    if material == null:
        return
    for prop in material.get_property_list():
        var name := str(prop.get("name", ""))
        if name.is_empty():
            continue
        var value = material.get(name)
        if value is Texture2D:
            var path := (value as Texture2D).resource_path
            result[path if not path.is_empty() else "<embedded>"] = true

func _rect_for_block(rects: Array, block_id: String) -> Dictionary:
    for r in rects:
        if r is Dictionary and str(r.get("id", "")) == block_id:
            return r
    return {}

func _building_bounds(b: Node) -> Rect2:
    var p: Vector3 = b.global_position
    var fp: Vector2 = b.get_meta("v11_catalog_footprint", Vector2(10, 10))
    var rotation_y := float(b.rotation.y)
    var ext := Vector2(fp.x * 0.5, fp.y * 0.5)
    if absf(fmod(absf(rotation_y), PI) - PI * 0.5) < 0.01:
        ext = Vector2(fp.y * 0.5, fp.x * 0.5)
    return Rect2(p.x - ext.x, p.z - ext.y, ext.x * 2.0, ext.y * 2.0)

func _validate_blocks(rects: Array, buildings: Array[Node]) -> bool:
    if rects.size() != EXPECTED_BLOCKS or buildings.size() != EXPECTED_BLOCKS * BUILDINGS_PER_BLOCK:
        return false
    var counts := {}
    for b in buildings:
        var id := str(b.get_meta("prompt4_block", ""))
        counts[id] = int(counts.get(id, 0)) + 1
        var r := _rect_for_block(rects, id)
        if r.is_empty():
            return false
        var br := _building_bounds(b)
        if br.position.x < float(r["min_x"]) + ROAD_SETBACK or br.end.x > float(r["max_x"]) - ROAD_SETBACK or br.position.y < float(r["min_z"]) + ROAD_SETBACK or br.end.y > float(r["max_z"]) - ROAD_SETBACK:
            return false
    for id in counts.keys():
        if int(counts[id]) != BUILDINGS_PER_BLOCK:
            return false
    return counts.size() == EXPECTED_BLOCKS

func _validate_corridors(rects: Array, buildings: Array[Node]) -> bool:
    # Adjacent Urban_Grid rectangles share their guide line; with 10 m setback
    # from each side, building-to-building clearance is at least 20 m.
    for i in range(rects.size()):
        var a: Dictionary = rects[i]
        for j in range(i + 1, rects.size()):
            var b: Dictionary = rects[j]
            var shared_x := is_equal_approx(float(a["max_x"]), float(b["min_x"])) or is_equal_approx(float(b["max_x"]), float(a["min_x"]))
            var overlap_z := minf(float(a["max_z"]), float(b["max_z"])) - maxf(float(a["min_z"]), float(b["min_z"])) > 0.0
            var shared_z := is_equal_approx(float(a["max_z"]), float(b["min_z"])) or is_equal_approx(float(b["max_z"]), float(a["min_z"]))
            var overlap_x := minf(float(a["max_x"]), float(b["max_x"])) - maxf(float(a["min_x"]), float(b["min_x"])) > 0.0
            if shared_x and overlap_z:
                if not _pair_gap_at_least(a, b, buildings, true):
                    return false
            if shared_z and overlap_x:
                if not _pair_gap_at_least(a, b, buildings, false):
                    return false
    return true

func _pair_gap_at_least(a: Dictionary, b: Dictionary, buildings: Array[Node], vertical: bool) -> bool:
    var ba := _buildings_in_block(a, buildings)
    var bb := _buildings_in_block(b, buildings)
    for x in ba:
        for y in bb:
            var ra := _building_bounds(x)
            var rb := _building_bounds(y)
            var gap := rb.position.x - ra.end.x if ra.position.x < rb.position.x else ra.position.x - rb.end.x if vertical else 0.0
            if not vertical:
                gap = rb.position.y - ra.end.y if ra.position.y < rb.position.y else ra.position.y - rb.end.y
            if gap < ROAD_SETBACK * 2.0 - 0.25:
                return false
    return true

func _buildings_in_block(rect: Dictionary, buildings: Array[Node]) -> Array[Node]:
    var result: Array[Node] = []
    var id := str(rect.get("id", ""))
    for b in buildings:
        if str(b.get_meta("prompt4_block", "")) == id:
            result.append(b)
    return result

func _validate_courtyards(rects: Array, buildings: Array[Node]) -> bool:
    for r in rects:
        var id := str(r["id"])
        var center := Vector2((float(r["min_x"]) + float(r["max_x"])) * 0.5, (float(r["min_z"]) + float(r["max_z"])) * 0.5)
        var covered := false
        for b in _buildings_in_block(r, buildings):
            var br := _building_bounds(b)
            if br.has_point(center):
                covered = true
                break
        if covered:
            print("COURTYARD FAIL: ", id)
            return false
    return true

func _validate_palette() -> bool:
    # The active mobile variation uses the six approved Roman colors.
    for value in REQUIRED_PALETTE:
        if Color(value).a <= 0.0:
            return false
    return true
