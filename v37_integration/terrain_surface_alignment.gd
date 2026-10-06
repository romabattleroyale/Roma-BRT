extends Node3D
## Runtime-only terrain surface alignment.
## Every native building root uses the Terrain3D height at its own X/Z.
## Road GridMap cells are re-sampled individually so roads follow terrain.
## Persisted terrain, river, road and placement assets remain untouched.

const ROAD_CELL_Y_STEP := 0.01
const ROAD_LIFT_Y := 0.06
const RETRY_FRAMES := 600

var _terrain_data: Object
var _aligned_buildings := false
var _aligned_roads := false
var _aligned_buildings_map: Dictionary = {}

func _ready() -> void:
    call_deferred("_run")

func _process(_delta: float) -> void:
    if _terrain_data == null:
        return
    var scene := get_tree().current_scene
    if scene == null:
        return
    var bridge := scene.get_node_or_null("V11BuildingBridge")
    if bridge == null or not bool(bridge.get("built")):
        return
    _align_city(bridge)
    if not _aligned_roads:
        _align_roads()

func _run() -> void:
    for _i in range(RETRY_FRAMES):
        var scene := get_tree().current_scene
        if scene == null:
            await get_tree().process_frame
            continue
        var terrain := scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
        var bridge := scene.get_node_or_null("V11BuildingBridge")
        if terrain != null and bridge != null and bool(bridge.get("built")):
            _terrain_data = terrain.get("data") as Object
            if _terrain_data != null:
                await get_tree().physics_frame
                _align_city(bridge)
                _align_roads()
                print("TERRAIN SURFACE ALIGN: PASS buildings=true roads=" + str(_aligned_roads))
                return
        await get_tree().process_frame
    push_warning("TERRAIN SURFACE ALIGN: timeout waiting for Terrain3D/V11")

func _terrain_y(x: float, z: float) -> float:
    if _terrain_data == null:
        return NAN
    var h := float(_terrain_data.call("get_height", Vector3(x, 0.0, z)))
    if is_nan(h) or is_inf(h):
        return NAN
    return h

func _align_city(bridge: Node) -> void:
    if _aligned_buildings:
        return
    var city_root := bridge.get("city_root") as Node3D
    if city_root == null:
        return

    var building_count := 0
    var min_y := INF
    var max_y := -INF
    for child in city_root.get_children():
        if not (child is Node3D):
            continue
        var root := child as Node3D
        if not root.has_meta("runtime_placement"):
            continue
        var idx := int(root.get_meta("runtime_placement"))
        var h := _terrain_y(root.global_position.x, root.global_position.z)
        if is_nan(h):
            continue
        var pos := root.global_position
        pos.y = h + 0.03
        root.global_position = pos
        _aligned_buildings_map[idx] = true
        building_count += 1
        min_y = minf(min_y, h)
        max_y = maxf(max_y, h)

    if building_count >= 587:
        _aligned_buildings = true
    print("TERRAIN SURFACE ALIGN: BUILDINGS aligned=" + str(building_count) + "/587 terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)))

func _is_bridge_node(node: Node) -> bool:
    var n := node
    while n != null and n.name != "RomaRoadsGridMap":
        var lower := str(n.name).to_lower()
        if lower.contains("ponte") or lower.contains("bridge"):
            return true
        n = n.get_parent()
    return false

func _align_roads() -> void:
    if _aligned_roads:
        return
    var roads_root := get_tree().current_scene.get_node_or_null("RomaRoadsGridMap")
    if roads_root == null:
        return

    var aligned_roots := 0
    var aligned_cells := 0
    var skipped_cells := 0
    var skipped_bridges := 0
    var min_y := INF
    var max_y := -INF

    for child in roads_root.get_children():
        for node in child.find_children("*", "GridMap", true, false):
            var grid := node as GridMap
            if grid == null or grid.mesh_library == null:
                continue
            if _is_bridge_node(grid):
                skipped_bridges += 1
                continue

            var original_cells:Array[Vector3i] = grid.get_used_cells()
            if original_cells.is_empty():
                continue

            var root_pos := grid.global_position
            root_pos.y = 0.0
            grid.global_position = root_pos
            grid.cell_size = Vector3(grid.cell_size.x, ROAD_CELL_Y_STEP, grid.cell_size.z)

            var placements:Array[Dictionary] = []
            for cell:Vector3i in original_cells:
                var item := grid.get_cell_item(cell)
                if item < 0:
                    continue
                var orientation := grid.get_cell_item_orientation(cell)
                var sample_local := grid.map_to_local(Vector3i(cell.x, 0, cell.z))
                var sample_global := grid.to_global(sample_local)
                var h := _terrain_y(sample_global.x, sample_global.z)
                if is_nan(h):
                    skipped_cells += 1
                    continue

                var y_index := roundi((h + ROAD_LIFT_Y - grid.global_position.y) / ROAD_CELL_Y_STEP)
                if grid.cell_center_y:
                    y_index = roundi((h + ROAD_LIFT_Y - grid.global_position.y) / ROAD_CELL_Y_STEP - 0.5)
                placements.append({"cell": cell, "item": item, "orientation": orientation, "y": y_index})
                min_y = minf(min_y, h)
                max_y = maxf(max_y, h)

            grid.clear()
            for p:Dictionary in placements:
                var source:Vector3i = p["cell"]
                var target := Vector3i(source.x, int(p["y"]), source.z)
                grid.set_cell_item(target, int(p["item"]), int(p["orientation"]))

            aligned_cells += placements.size()
            aligned_roots += 1

    if aligned_roots > 0:
        _aligned_roads = true
        print("TERRAIN SURFACE ALIGN: road_gridmaps=" + str(aligned_roots) + " cells=" + str(aligned_cells) + " skipped=" + str(skipped_cells) + " bridges_skipped=" + str(skipped_bridges) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)) + " step=" + str(ROAD_CELL_Y_STEP))
