extends SceneTree
## Visual/runtime smoke test for the full GridMap road set.
const FULL_DIR := "res://roads/generated"
const CENTERS := [Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)]

func _initialize() -> void:
    var vp := SubViewport.new()
    vp.size = Vector2i(1280,720)
    vp.world_3d = World3D.new()
    vp.render_target_update_mode = SubViewport.UPDATE_ONCE
    root.add_child(vp)
    var world := Node3D.new()
    vp.add_child(world)
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color("#91a9c4")
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color("#ffffff")
    e.ambient_light_energy = 0.7
    env.environment = e
    world.add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55,-35,0)
    sun.light_energy = 1.1
    world.add_child(sun)
    var holder := Node3D.new()
    holder.position = Vector3(-400,0,-650)
    world.add_child(holder)
    for i in [0,1,4,5,6,7]:
        var scene: PackedScene = load("%s/district_%02d_roads.tscn" % [FULL_DIR,i+1])
        if scene:
            var n := scene.instantiate()
            holder.add_child(n)
    var camera := Camera3D.new()
    camera.position = Vector3(0,420,420)
    camera.look_at(Vector3(0,0,0),Vector3(0,0,-1))
    holder.add_child(camera)
    camera.current = true
    await process_frame
    await process_frame
    var img := vp.get_texture().get_image()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/road_full"))
    img.save_png(ProjectSettings.globalize_path("res://build/road_full/road_full_overview.png"))
    print("ROMA ROADS FULL VISUAL: PASS screenshot=res://build/road_full/road_full_overview.png")
    quit(0)
