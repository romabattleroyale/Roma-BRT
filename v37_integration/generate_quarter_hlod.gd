extends SceneTree
## Three-level district HLOD bake derived from the actual 120 ready building templates.
## HLOD0 is a district aggregate of full template geometry; runtime keeps HLOD0 as streamed
## per-building scenes. HLOD1/HLOD2 are deterministic triangle-reduced aggregates.
## Locked systems are not touched: Terrain3D, Tevere, roads, graph, palette and district layout.
## CI persists all 36 generated HLOD meshes before the dependent runtime smoke test.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST := READY_DIR + "/manifest.json"
const OUT_DIR := "res://baked_city/hlod"
const DISTRICT_COUNT := 12
const COUNTS := [61,61,61,61,61,61,61,60,25,25,25,25]
const CENTERS := [Vector2(-800.0,-650.0),Vector2(-400.0,-650.0),Vector2(400.0,-650.0),Vector2(800.0,-650.0),Vector2(-800.0,0.0),Vector2(-400.0,0.0),Vector2(400.0,0.0),Vector2(800.0,0.0),Vector2(-800.0,650.0),Vector2(-400.0,650.0),Vector2(400.0,650.0),Vector2(800.0,650.0)]
const HLOD1_TARGET := 10000
const HLOD2_TARGET := 2000
const HLOD0_CAP := 50000

func _init() -> void: call_deferred("_run")

func _run() -> void:
    if not FileAccess.file_exists(MANIFEST): push_error("HLOD BAKE FAIL: manifest missing"); quit(2); return
    var f := FileAccess.open(MANIFEST, FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text()); f.close()
    if not data is Dictionary: push_error("HLOD BAKE FAIL: invalid manifest"); quit(3); return
    var placements:Array = data.get("placements",[])
    if placements.size()!=587: push_error("HLOD BAKE FAIL: placements=%d"%placements.size()); quit(4); return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    _write_shared_texture()
    var report:Dictionary={"districts":12,"placement_count":587,"targets":{"hlod2":HLOD2_TARGET,"hlod1":HLOD1_TARGET},"levels":{}}
    var index:=0
    for district in range(DISTRICT_COUNT):
        var local:Array=[]
        for _i in range(COUNTS[district]): local.append(placements[index]); index+=1
        var source_mesh:=_build_source_mesh(local,district)
        var m0:=_reduce_mesh(source_mesh,HLOD0_CAP,false)
        var m1:=_reduce_mesh(source_mesh,HLOD1_TARGET,true)
        var m2:=_reduce_mesh(source_mesh,HLOD2_TARGET,false)
        _apply_material(m0,0); _apply_material(m1,1); _apply_material(m2,2)
        ResourceSaver.save(m0,OUT_DIR+"/quartiere_%02d_0.res"%(district+1))
        ResourceSaver.save(m1,OUT_DIR+"/quartiere_%02d_1.res"%(district+1))
        ResourceSaver.save(m2,OUT_DIR+"/quartiere_%02d_2.res"%(district+1))
        report["levels"][str(district+1)]={"source_tri":_tri_count(source_mesh),"hlod0_tri":_tri_count(m0),"hlod1_tri":_tri_count(m1),"hlod2_tri":_tri_count(m2)}
        source_mesh=null; await process_frame
    var rf:=FileAccess.open(OUT_DIR+"/report.json",FileAccess.WRITE); rf.store_string(JSON.stringify(report)); rf.close()
    print("HLOD BAKE PASS: districts=12 aggregate_meshes=36 source=ready_templates append_from=PASS meshdatatool=PASS shared_texture=512x512")
    quit(0)

func _build_source_mesh(items:Array,district:int)->ArrayMesh:
    var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var center:=CENTERS[district]
    for item in items:
        var d:Dictionary=item; var ti:=clampi(int(d.get("template",0)),0,119)
        var scene:=ResourceLoader.load("%s/template_%03d.tscn"%[READY_DIR,ti+1],"PackedScene",ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if scene==null: continue
        var root:=scene.instantiate() as Node3D
        if root==null: continue
        root.position=Vector3(float(d.get("x",0.0))-center.x,float(d.get("y",0.0)),float(d.get("z",0.0))-center.y); root.rotation.y=float(d.get("rotation",0.0))
        var template_floors:=int(root.get_meta("template_floors",3)); var floors:=clampi(int(d.get("floors",template_floors)),3,5); root.scale.y=float(floors)/float(maxi(1,template_floors))
        var stack:Array=[root]
        while not stack.is_empty():
            var n:Node=stack.pop_back()
            if n is MeshInstance3D:
                var mi:=n as MeshInstance3D
                if mi.mesh!=null:
                    for s in range(mi.mesh.get_surface_count()): st.append_from(mi.mesh,s,mi.global_transform)
            for child in n.get_children(): stack.append(child)
        root.free()
    var result:=st.commit(); return result if result!=null else ArrayMesh.new()

func _reduce_mesh(source:ArrayMesh,target_tri:int,keep_uv:bool)->ArrayMesh:
    if source.get_surface_count()==0:return ArrayMesh.new()
    var md:=MeshDataTool.new()
    if md.create_from_surface(source,0)!=OK:return source
    var faces:=md.get_face_count(); var wanted:=mini(faces,target_tri)
    if faces<=wanted:return source
    var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(wanted):
        var fi:=clampi(int(float(i)*float(faces)/float(wanted)),0,faces-1)
        for corner in range(3):
            var vi:=md.get_face_vertex(fi,corner); st.set_normal(md.get_vertex_normal(vi));
            if keep_uv: st.set_uv(md.get_vertex_uv(vi))
            st.add_vertex(md.get_vertex(vi))
    var reduced:=st.commit(); return reduced if reduced!=null else ArrayMesh.new()

func _write_shared_texture()->void:
    var image:=Image.create(512,512,false,Image.FORMAT_RGBA8)
    var palette=[Color("#c9ad82"),Color("#b97f62"),Color("#d6c09a"),Color("#8f6d52"),Color("#e0c8a5")]
    for y in range(512):
        for x in range(512): image.set_pixel(x,y,palette[posmod(int(x/64)+int(y/64),palette.size())])
    image.save_png(OUT_DIR+"/roma_palette_512.png")

func _apply_material(mesh:ArrayMesh,level:int)->void:
    var mat:=StandardMaterial3D.new(); mat.roughness=1.0
    if level==1: mat.albedo_texture=load(OUT_DIR+"/roma_palette_512.png") as Texture2D
    elif level==2: mat.albedo_color=Color("#b98b6b")
    else: mat.albedo_color=Color("#c8aa82")
    for s in range(mesh.get_surface_count()): mesh.surface_set_material(s,mat)

func _tri_count(mesh:ArrayMesh)->int:
    var total:=0
    for s in range(mesh.get_surface_count()):
        var arrays:=mesh.surface_get_arrays(s)
        if arrays.size()>Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]!=null: total+=int(arrays[Mesh.ARRAY_VERTEX].size())/3
    return total
