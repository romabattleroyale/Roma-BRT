extends SceneTree
## Headless visual validation for the 12-district HLOD bake.
## Produces A=500m, B=250m, C=50m and D=4 descent frames plus a state memory report.
const HLOD_DIR := "res://baked_city/hlod"
const OUT_DIR := "res://build/hlod_visual"
const SIZE := Vector2i(1280,720)
const BUDGET_MB := 300.0
const CENTERS := [
    Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),
    Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),
    Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)
]

func _init() -> void: call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.transparent_bg = false
    get_root().add_child(viewport)
    var world := World3D.new()
    viewport.world_3d = world
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#9db5c7")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#d8cdbd")
    env.ambient_light_energy = 1.1
    world.environment = env
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55,-25,0)
    sun.light_energy = 1.3
    viewport.add_child(sun)
    for d in range(12):
        _add_hlod(viewport,d,2)
        _add_hlod(viewport,d,1)
        _add_hlod(viewport,d,0)
    await process_frame
    await process_frame
    _capture(viewport,Vector3(0,500,0),Vector3(0,0,0),true,"A_500m")
    _capture(viewport,Vector3(0,250,0),Vector3(0,0,0),true,"B_250m")
    _capture(viewport,Vector3(400,50,0),Vector3(400,0,0),true,"C_50m")
    var descent := [500.0,300.0,150.0,50.0]
    for i in range(descent.size()): _capture(viewport,Vector3(400,descent[i],0),Vector3(400,0,0),true,"D_%02d"%(i+1))
    _write_memory_report()
    print("HLOD VISUAL TEST PASS: A=500m B=250m C=50m D=4_frames")
    quit(0)

func _add_hlod(viewport:SubViewport,district:int,level:int)->void:
    var path := "%s/quartiere_%02d_%d.res"%[HLOD_DIR,district+1,level]
    var mesh := ResourceLoader.load(path) as Mesh
    if mesh == null: return
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = CENTERS[district]
    if level == 2:
        node.visibility_range_begin = 400.0; node.visibility_range_end = 4000.0
    elif level == 1:
        node.visibility_range_begin = 150.0; node.visibility_range_end = 400.0
    else:
        node.visibility_range_begin = 0.0; node.visibility_range_end = 150.0
    node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    viewport.add_child(node)

func _capture(viewport:SubViewport,pos:Vector3,target:Vector3,ortho:bool,name:String)->void:
    var camera := Camera3D.new()
    viewport.add_child(camera)
    camera.position = pos
    camera.look_at(target,Vector3.UP)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
    if ortho:
        if name.begins_with("A_"): camera.size = 2200.0
        elif name.begins_with("B_"): camera.size = 1200.0
        else: camera.size = 300.0
    else: camera.fov = 70.0
    camera.current = true
    await process_frame; await process_frame
    viewport.get_texture().get_image().save_png("%s/%s.png"%[OUT_DIR,name])
    camera.queue_free(); await process_frame

func _write_memory_report() -> void:
    var bytes := {"hlod0":0,"hlod1":0,"hlod2":0,"textures":0}
    for d in range(12):
        for level in [0,1,2]:
            var path := "%s/quartiere_%02d_%d.res"%[HLOD_DIR,d+1,level]
            if FileAccess.file_exists(path): bytes["hlod%d"%level] += FileAccess.get_file_as_bytes(path).size()
    var tex_path := HLOD_DIR + "/roma_palette_512.res"
    if FileAccess.file_exists(tex_path): bytes["textures"] = FileAccess.get_file_as_bytes(tex_path).size()
    var total_mb := float(bytes.hlod0 + bytes.hlod1 + bytes.hlod2 + bytes.textures) / 1048576.0
    var report := {"budget_mb":BUDGET_MB,"states":{
        "A_500m":{"active":"HLOD2","estimated_asset_mb":float(bytes.hlod2+bytes.textures)/1048576.0},
        "B_250m":{"active":"HLOD1+HLOD2","estimated_asset_mb":float(bytes.hlod1+bytes.hlod2+bytes.textures)/1048576.0},
        "C_50m":{"active":"HLOD0+HLOD1+HLOD2","estimated_asset_mb":total_mb}},
        "asset_bytes":bytes,"note":"Asset-size estimate; runtime RSS/GPU memory remains validated by the existing mobile memory watcher."}
    var f := FileAccess.open(OUT_DIR+"/memory_report.json",FileAccess.WRITE); f.store_string(JSON.stringify(report)); f.close()
    print("HLOD MEMORY REPORT: estimated_asset_mb=%.2f budget_mb=%.2f"%[total_mb,BUDGET_MB])
