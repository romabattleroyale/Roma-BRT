extends Node
## Runtime screenshot helper for the simple road network.
## Captures one elevated overview and one ground-level road view.

const OVERVIEW_PATH := "user://simple_roads_overview.png"
const GROUND_PATH := "user://simple_roads_ground.png"

func _ready() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    var camera := get_viewport().get_camera_3d()
    if camera == null:
        return
    camera.position = Vector3(1000.0, 850.0, 1000.0)
    camera.look_at(Vector3(1000.0, 0.0, 1000.0), Vector3.UP)
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(OVERVIEW_PATH)
    camera.position = Vector3(1000.0, 8.0, 1000.0)
    camera.look_at(Vector3(1080.0, 0.0, 1000.0), Vector3.UP)
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(GROUND_PATH)
    print("SIMPLE ROADS SCREENSHOTS: PASS overview=%s ground=%s" % [OVERVIEW_PATH, GROUND_PATH])
