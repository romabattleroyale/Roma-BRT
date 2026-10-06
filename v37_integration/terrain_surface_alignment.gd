extends Node3D
## Runtime-only terrain surface alignment.
## Reads Terrain3D height data and lifts roads/buildings to the real terrain Y.
## Does not modify Terrain3D, the Tevere, persisted road scenes, manifests or meshes.

const ROAD_LIFT_Y := 0.08
const RETRY_FRAMES := 600

var _terrain_data: Object
var _aligned_lod1 := false
var _aligned_roads := false
var _aligned_lod0: Dictionary = {}

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    for _i in range(RETRY_FRAMES):
        var terrain := get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
        var bridge := get_tree().current_scene.get_node_or_null("V11BuildingBridge")
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
    var p := Vector3(x, 0.0, z)
    var h := float(_terrain_data.call("get_height", p))
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
                global_pos.y = h
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
        pos.y = h
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
    var aligned := 0
    var min_y := INF
    var max_y := -INF
    for child in roads_root.get_children():
        if not (child is Node3D):
            continue
        var road := child as Node3D
        var pos := road.global_position
        var h := _terrain_y(pos.x, pos.z)
        if is_nan(h):
            continue
        pos.y = h + ROAD_LIFT_Y
        road.global_position = pos
        aligned += 1
        min_y = minf(min_y, h)
        max_y = maxf(max_y, h)
    if aligned >= 16:
        _aligned_roads = true
        print("TERRAIN SURFACE ALIGN: roads aligned=" + str(aligned) + " terrain_y=" + str(snappedf(min_y, 0.01)) + ".." + str(snappedf(max_y, 0.01)) + " lift=" + str(ROAD_LIFT_Y))
