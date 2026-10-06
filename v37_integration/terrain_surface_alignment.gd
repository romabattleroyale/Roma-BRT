extends Node3D
## Runtime-only terrain surface alignment.
## Buildings use the Terrain3D height at their own X/Z.
## Road GridMap cells are re-sampled individually so the road follows terrain
## instead of applying one Y to an entire district. Persisted assets are untouched.

const ROAD_CELL_Y_STEP := 0.01
const ROAD_LIFT_Y := 0.02
const RETRY_FRAMES := 600

var _terrain_data: Object
var _aligned_lod1 := false
var _aligned_roads := false
var _aligned_lod0: Dictionary = {}

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
                print("TERRAIN SURFACE ALIGN: PASS buildings_lod1=true roads=" + str(_aligned_roads))
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
    var city_root := bridge.get("city_root") as Node3D
    if city_root == null:
        return

    if not _aligned_lod1:
        var lod1_count := 0
        var lod1_instances := 0
        var min_y := INF
        var max_y := -INF
        for child in city_root.get_children():
            if not (child is MultiMeshInstance3D):
                continue
            var mmi := child as MultiMeshInstance3D
            if not str(mmi.name).begins_with("V11_LOD1_Template_"):
                continue
            var mm := mmi.multimesh
            if mm == null:
                continue
            lod1_count += 1
            for j in range(mm.instance_count):
                var t := mm.get_instance_transform(j)
                var global_pos := mmi.to_global(t.origin)
                var h := _terrain_y(global_pos.x, global_pos.z)
                if is_nan(h):
                    continue
                global_pos.y = h + 0.03
                t.origin = mmi.to_local(global_pos)
                mm.set_instance_transform(j, t)
                min_y = minf(min_y, h)
                max_y = maxf(max_y, h)
                lod1_instances += 1
        _aligned_lod1 = true
        print("TERRAIN SURFACE ALIGN: LOD1 nodes=" + str(lod1_count) + " instances=" + str(lod1_instances) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)))

    var lod0_count := 0
    for child in city_root.get_children():
        if not (child is Node3D):
            continue
        var root := child as Node3D
        if not root.has_meta("runtime_placement"):
            continue
        var idx := int(root.get_meta("runtime_placement"))
        if _aligned_lod0.has(idx):
            continue
        var pos := root.global_position
        var h := _terrain_y(pos.x, pos.z)
        if is_nan(h):
            continue
        pos.y = h + 0.03
        root.global_position = pos
        _aligned_lod0[idx] = true
        lod0_count += 1
    if lod0_count > 0:
        print("TERRAIN SURFACE ALIGN: LOD0 newly_aligned=" + str(lod0_count) + " total=" + str(_aligned_lod0.size()))

func _align_roads() -> void:
    if _aligned_roads:
        return
    var roads_root := get_tree().current_scene.get_node_or_null("RomaRoadsGridMap")
    if roads_root == null:
        return

    var aligned_roots := 0
    var aligned_cells := 0
    var skipped_cells := 0
    var min_y := INF
    var max_y := -INF

    for child in roads_root.get_children():
        for node in child.find_children("*", "GridMap", true, false):
            var grid := node as GridMap
            if grid == null or grid.mesh_library == null:
                continue

            var original_cells:Array[Vector3i] = grid.get_used_cells()
            if original_cells.is_empty():
                continue

            # Keep X/Z authored positions exactly. Only replace the Y sampling
            # with a 1 cm runtime vertical grid, using the real Terrain3D height.
            var root_pos := grid.global_position
            root_pos.y = 0.0
            grid.global_position = root_pos
            grid.cell_size = Vector3(grid.cell_size.x, ROAD_CELL_Y_STEP, grid.cell_size.z)

            var changed := 0
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

                var y_index := roundi((h - grid.global_position.y) / ROAD_CELL_Y_STEP)
                if grid.cell_center_y:
                    y_index = roundi((h - grid.global_position.y) / ROAD_CELL_Y_STEP - 0.5)
                var target := Vector3i(cell.x, y_index, cell.z)
                if target != cell:
                    grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
                    grid.set_cell_item(target, item, orientation)
                changed += 1
                min_y = minf(min_y, h)
                max_y = maxf(max_y, h)

            aligned_cells += changed
            aligned_roots += 1

    if aligned_roots > 0:
        _aligned_roads = true
        print("TERRAIN SURFACE ALIGN: road_gridmaps=" + str(aligned_roots) + " cells=" + str(aligned_cells) + " skipped=" + str(skipped_cells) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)) + " step=" + str(ROAD_CELL_Y_STEP))
