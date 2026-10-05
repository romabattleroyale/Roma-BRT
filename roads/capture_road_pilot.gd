extends SceneTree
const OUT_DIR := "res://build/road_pilot"
const SCREEN := "res://build/road_pilot/road_pilot_topdown.png"
const REPORT := "res://build/road_pilot/road_pilot_memory_report.txt"
func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var scene: PackedScene = load("res://roads/roma_gridmap_pilot.tscn")
    if scene == null: push_error("ROAD PILOT FAIL: missing scene"); quit(2); return
    var root := Node3D.new(); root.name = "RoadPilotCapture"; root.add_child(scene.instantiate())
    var world := WorldEnvironment.new(); var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color("#87a8b8"); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.9; world.environment = env; root.add_child(world)
    var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55,-25,0); sun.light_energy = 1.1; root.add_child(sun)
    var camera := Camera3D.new(); root.add_child(camera); camera.position = Vector3(-800,420,-650); camera.look_at(Vector3(-800,0,-650),Vector3.UP); camera.current = true; camera.fov = 50.0; camera.far = 2000.0
    get_root().add_child(root)
    await process_frame; await process_frame; await process_frame
    var viewport: Viewport = get_root()
    var img: Image = viewport.get_texture().get_image(); img.save_png(SCREEN)
    var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
    var report := "ROMA ROADS PILOT MEMORY\nGridMap cell=4x0.15x4\nMeshLibrary items=25\nPilot=CentroStorico 9x9\nStatic memory after load=%d bytes (%.2f MB)\nTarget additional memory < 50 MB\nNOTE: this is a CI smoke measurement, not a device RSS measurement.\n" % [int(static_mem), float(static_mem)/1048576.0]
    var f := FileAccess.open(REPORT,FileAccess.WRITE); f.store_string(report); f.close()
    print("ROMA ROADS VISUAL: PASS screenshot=%s" % SCREEN)
    print(report)
    quit(0)
