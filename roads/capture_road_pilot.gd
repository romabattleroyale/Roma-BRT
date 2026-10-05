extends SceneTree

const OUT_DIR := "res://build/road_pilot"
const SCREEN := "res://build/road_pilot/road_pilot_topdown.png"
const REPORT := "res://build/road_pilot/road_pilot_memory_report.txt"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var scene: PackedScene = load("res://roads/roma_gridmap_pilot.tscn")
    if scene == null:
        push_error("ROAD PILOT FAIL: missing scene")
        quit(2)
        return

    var window: Window = get_root()
    window.size = Vector2i(WIDTH, HEIGHT)
    window.visible = true

    var root := Node3D.new()
    root.name = "RoadPilotCapture"
    window.add_child(root)

    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#87a8b8")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    env.ambient_light_energy = 0.9
    world.environment = env
    root.add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
    sun.light_energy = 1.1
    root.add_child(sun)

    var pilot := scene.instantiate()
    root.add_child(pilot)

    var camera := Camera3D.new()
    camera.name = "TopDownCamera"
    camera.position = Vector3(-800.0, 420.0, -650.0)
    root.add_child(camera)
    camera.look_at_from_position(camera.position, Vector3(-800.0, 0.0, -650.0), Vector3.UP)
    camera.fov = 50.0
    camera.far = 2000.0
    camera.current = true

    await process_frame
    await process_frame
    await process_frame
    await process_frame
    await process_frame

    var image: Image = window.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("ROAD PILOT FAIL: rendered image is empty")
        quit(3)
        return

    var save_error := image.save_png(SCREEN)
    if save_error != OK:
        push_error("ROAD PILOT FAIL: PNG save error %s" % save_error)
        quit(4)
        return

    var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
    var report := "ROMA ROADS PILOT MEMORY\nGridMap cell=4x0.15x4\nMeshLibrary items=25\nPilot=CentroStorico 9x9\nStatic memory after load=%d bytes (%.2f MB)\nTarget additional memory < 50 MB\nNOTE: this is a CI smoke measurement, not a device RSS measurement.\n" % [int(static_mem), float(static_mem) / 1048576.0]
    var file := FileAccess.open(REPORT, FileAccess.WRITE)
    if file == null:
        push_error("ROAD PILOT FAIL: cannot open memory report")
        quit(5)
        return
    file.store_string(report)
    file.close()

    print("ROMA ROADS VISUAL: PASS screenshot=%s" % SCREEN)
    print(report)
    quit(0)
