extends Node3D
## Runtime-only terrain surface alignment.
## Buildings are aligned against Terrain3D using footprint samples and real mesh bounds.
## Roads are re-sampled individually so they follow terrain.
## Persisted terrain, river, road and placement assets remain untouched.

const ROAD_CELL_Y_STEP := 0.01
const ROAD_LIFT_Y := 0.06
const BUILDING_LIFT_Y := 0.06
const BUILDING_CLEARANCE := 0.02
const RETRY_FRAMES := 600

var _terrain_data: Object
var _aligned_buildings := false
var _aligned_roads := false
var _aligned_buildings_map: Dictionary = {}

func _ready() -> void:
    call_deferred("_run")

# Alignment is intentionally one-shot. _run() waits for Terrain3D and the
# building bridge, then performs the city/road alignment once; doing this in
# _process caused repeated full-city scans on Android.

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

func _building_meshes(root: Node) -> Array[MeshInstance3D]:
    var meshes: Array[MeshInstance3D] = []
    for node in root.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh != null and mesh.mesh != null:
            meshes.append(mesh)
    return meshes

func _building_footprint(root: Node3D) -> Array[Vector3]:
    var points: Array[Vector3] = [root.global_position]
    var meshes := _building_meshes(root)
    if meshes.is_empty():
        return points

    var bounds := AABB()
    var has_bounds := false
    for mesh: MeshInstance3D in meshes:
        var local_aabb := mesh.get_aabb()
        var corners := [
            Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.position.z),
            Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.position.z),
            Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.end.z),
            Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.end.z)
        ]
        for corner: Vector3 in corners:
            var world := mesh.global_transform * corner
            if not has_bounds:
                bounds = AABB(world, Vector3.ZERO)
                has_bounds = true
            else:
                bounds = bounds.expand(world)

    if has_bounds:
        var center := bounds.position + bounds.size * 0.5
        points = [
            Vector3(bounds.position.x, center.y, bounds.position.z),
            Vector3(bounds.end.x, center.y, bounds.position.z),
            Vector3(bounds.position.x, center.y, bounds.end.z),
            Vector3(bounds.end.x, center.y, bounds.end.z),
            Vector3(center.x, center.y, center.z)
        ]
    return points

func _building_bottom_clearance(root: Node3D, terrain_floor: float) -> float:
    var min_bottom := INF
    var found := false
    for mesh: MeshInstance3D in _building_meshes(root):
        var aabb := mesh.get_aabb()
        var y_values := [aabb.position.y, aabb.end.y]
        for y: float in y_values:
            for x: float in [aabb.position.x, aabb.end.x]:
                for z: float in [aabb.position.z, aabb.end.z]:
                    var world := mesh.global_transform * Vector3(x, y, z)
                    min_bottom = minf(min_bottom, world.y)
                    found = true
    if not found:
        return INF
    return min_bottom - terrain_floor

func _align_city(bridge: Node) -> void:
    if _aligned_buildings:
        return
    var city_root := bridge.get("city_root") as Node3D
    if city_root == null:
        return

    var building_count := 0
    var lifted_count := 0
    var max_extra_lift := 0.0
    var min_y := INF
    var max_y := -INF

    for child in city_root.get_children():
        if not (child is Node3D):
            continue
        var root := child as Node3D
        if not root.has_meta("runtime_placement"):
            continue

        var samples := _building_footprint(root)
        var terrain_floor := -INF
        for sample: Vector3 in samples:
            var h := _terrain_y(sample.x, sample.z)
            if not is_nan(h):
                terrain_floor = maxf(terrain_floor, h)
        if is_inf(terrain_floor):
            continue

        var pos := root.global_position
        pos.y = terrain_floor + BUILDING_LIFT_Y
        root.global_position = pos

        var clearance := _building_bottom_clearance(root, terrain_floor)
        if clearance < BUILDING_CLEARANCE:
            var extra := BUILDING_CLEARANCE - clearance
            pos.y += extra
            root.global_position = pos
            lifted_count += 1
            max_extra_lift = maxf(max_extra_lift, extra)

        _aligned_buildings_map[int(root.get_meta("runtime_placement"))] = true
        building_count += 1
        min_y = minf(min_y, terrain_floor)
        max_y = maxf(max_y, terrain_floor)

    if building_count >= 587:
        _aligned_buildings = true
    print("TERRAIN SURFACE ALIGN: BUILDINGS aligned=" + str(building_count) + "/587 lifted=" + str(lifted_count) + " max_extra=" + str(snappedf(max_extra_lift, 0.01)) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)))

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

            var original_cells: Array[Vector3i] = grid.get_used_cells()
            if original_cells.is_empty():
                continue

            var root_pos := grid.global_position
            root_pos.y = 0.0
            grid.global_position = root_pos
            grid.cell_size = Vector3(grid.cell_size.x, ROAD_CELL_Y_STEP, grid.cell_size.z)

            var placements: Array[Dictionary] = []
            for cell: Vector3i in original_cells:
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
            for p: Dictionary in placements:
                var source: Vector3i = p["cell"]
                var target := Vector3i(source.x, int(p["y"]), source.z)
                grid.set_cell_item(target, int(p["item"]), int(p["orientation"]))

            aligned_cells += placements.size()
            aligned_roots += 1

    if aligned_roots > 0:
        _aligned_roads = true
        print("TERRAIN SURFACE ALIGN: road_gridmaps=" + str(aligned_roots) + " cells=" + str(aligned_cells) + " skipped=" + str(skipped_cells) + " bridges_skipped=" + str(skipped_bridges) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)) + " step=" + str(ROAD_CELL_Y_STEP))
