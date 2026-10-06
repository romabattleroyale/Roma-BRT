extends Node3D
## Temporary runtime visual audit: show the actual city assets, hide debug-only HLOD/road pilot geometry.
## Does not modify Terrain3D, Tevere, persisted placement data, or road assets.

const CITY_OFFSET := Vector3(1000.0, 0.0, 1000.0)
const CITY_AABB := AABB(Vector3(-100.0, -100.0, -100.0), Vector3(2200.0, 400.0, 2200.0))

var _done := false

func _ready() -> void:
    call_deferred("_wait_and_apply")

func _wait_and_apply() -> void:
    for _i in range(600):
        var scene := get_tree().current_scene
        if scene == null:
            await get_tree().process_frame
            continue
        var bridge := scene.get_node_or_null("V11BuildingBridge")
        if bridge != null and bool(bridge.get("built")):
            _apply(scene)
            return
        await get_tree().process_frame
    push_warning("CITY VISUAL AUDIT: timeout waiting for V11BuildingBridge")

func _apply(scene: Node) -> void:
    if _done:
        return

    # V11BuildingBridge keeps city_root private; resolve the same runtime root
    # through V37Integration, exactly as the bridge itself does during bootstrap.
    var v37 := scene.get_node_or_null("V37Integration")
    var city_root := v37.get("city_root") as Node3D if v37 != null else null
    if city_root == null:
        push_warning("CITY VISUAL AUDIT: V37 city_root missing")
        return

    var hlod_hidden := 0
    var lod1_visible := 0
    var lod1_instances := 0
    for child in city_root.get_children():
        if child is MeshInstance3D and str(child.name).begins_with("V11_HLOD2_"):
            child.visible = false
            hlod_hidden += 1
        elif child is MultiMeshInstance3D and str(child.name).begins_with("V11_LOD1_Template_"):
            var mmi := child as MultiMeshInstance3D
            mmi.visible = true
            mmi.visibility_range_begin = 0.0
            mmi.visibility_range_end = 5000.0
            mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
            mmi.custom_aabb = CITY_AABB
            mmi.material_override = null
            lod1_visible += 1
            if mmi.multimesh != null:
                lod1_instances += mmi.multimesh.instance_count

    # The current GridMap road pilot is a block-test asset, not the final visual road network.
    # Hide it for this audit so it cannot mask the actual city assets.
    var roads := scene.get_node_or_null("RomaRoadsGridMap") as Node3D
    if roads != null:
        roads.visible = false

    # Put the player/camera over the authored city center so LOD0 can be inspected.
    var viewer := scene.get_node_or_null("Viewer") as Node3D
    if viewer != null:
        viewer.global_position = Vector3(CITY_OFFSET.x, 120.0, CITY_OFFSET.z)

    var debug_camera := scene.get_node_or_null("DebugTopDownCamera")
    if debug_camera != null:
        debug_camera.set("target", CITY_OFFSET)
        debug_camera.set("distance", 500.0)
        debug_camera.set("pitch", -1.08)
        if debug_camera.has_method("update_camera"):
            debug_camera.call("update_camera")

    _done = true
    print("CITY VISUAL AUDIT: PASS HLOD_hidden=%d LOD1_nodes=%d LOD1_instances=%d roads_hidden=true center=%s" % [hlod_hidden, lod1_visible, lod1_instances, CITY_OFFSET])
