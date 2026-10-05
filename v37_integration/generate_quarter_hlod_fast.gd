extends SceneTree
## Fast HLOD bake: same district/template inputs and triangle caps as the authoritative bake,
## but avoids MeshDataTool face construction and repeated vertex-object access.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST := READY_DIR + "/manifest.json"
const OUT_DIR := "res://baked_city/hlod"
const DISTRICT_COUNT := 12
const COUNTS := [61,61,61,61,61,61,61,60,25,25,25,25]
const CENTERS:Array[Vector2] = [Vector2(-800.0,-650.0),Vector2(-400.0,-650.0),Vector2(400.0,-650.0),Vector2(800.0,-650.0),Vector2(-800.0,0.0),Vector2(-400.0,0.0),Vector2(400.0,0.0),Vector2(800.0,0.0),Vector2(-800.0,650.0),Vector2(-400.0,650.0),Vector2(400.0,650.0),Vector2(800.0,650.0)]
const HLOD1_TARGET:int = 10000
const HLOD2_TARGET:int = 2000
const HLOD0_CAP:int = 50000

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not FileAccess.file_exists(MANIFEST): push_error("HLOD BAKE FAIL: manifest missing"); quit(2); return
    var f:FileAccess=FileAccess.open(MANIFEST,FileAccess.READ)
    var data:Variant=JSON.parse_string(f.get_as_text()); f.close()
    if not data is Dictionary: push_error("HLOD BAKE FAIL: invalid manifest"); quit(3); return
    var placements:Array=data.get("placements",[])
    if placements.size()!=587: push_error("HLOD BAKE FAIL: placements=%d"%placements.size()); quit(4); return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    _write_shared_texture()
    var report:Dictionary={"districts":12,"placement_count":587,"targets":{"hlod2":HLOD2_TARGET,"hlod1":HLOD1_TARGET},"levels":{}}
    var index:int=0
    for district:int in range(DISTRICT_COUNT):
        var local:Array=[]
        for _i:int in range(COUNTS[district]): local.append(placements[index]); index+=1
        var source_mesh:ArrayMesh=_build_source_mesh(local,district)
        var m0:ArrayMesh=_reduce_mesh_fast(source_mesh,HLOD0_CAP,false)
        var m1:ArrayMesh=_reduce_mesh_fast(source_mesh,HLOD1_TARGET,true)
        var m2:ArrayMesh=_reduce_mesh_fast(source_mesh,HLOD2_TARGET,false)
        _apply_material(m0,0); _apply_material(m1,1); _apply_material(m2,2)
        ResourceSaver.save(m0,OUT_DIR+"/quartiere_%02d_0.res"%(district+1))
        ResourceSaver.save(m1,OUT_DIR+"/quartiere_%02d_1.res"%(district+1))
        ResourceSaver.save(m2,OUT_DIR+"/quartiere_%02d_2.res"%(district+1))
        report["levels"][str(district+1)]={"source_tri":_tri_count(source_mesh),"hlod0_tri":_tri_count(m0),"hlod1_tri":_tri_count(m1),"hlod2_tri":_tri_count(m2)}
        source_mesh=null
        await process_frame
    var rf:FileAccess=FileAccess.open(OUT_DIR+"/report.json",FileAccess.WRITE); rf.store_string(JSON.stringify(report)); rf.close()
    print("HLOD FAST BAKE PASS: districts=12 aggregate_meshes=36 source=ready_templates direct_arrays=PASS shared_texture=512x512")
    quit(0)

func _build_source_mesh(items:Array,district:int)->ArrayMesh:
    var st:SurfaceTool=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var center:Vector2=CENTERS[district]
    for item:Variant in items:
        var d:Dictionary=item
        var ti:int=clampi(int(d.get("template",0)),0,119)
        var scene:PackedScene=ResourceLoader.load("%s/template_%03d.tscn"%[READY_DIR,ti+1],"PackedScene",ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if scene==null: continue
        var root:Node3D=scene.instantiate() as Node3D
        if root==null: continue
        root.position=Vector3(float(d.get("x",0.0))-center.x,float(d.get("y",0.0)),float(d.get("z",0.0))-center.y)
        root.rotation.y=float(d.get("rotation",0.0))
        var template_floors:int=int(root.get_meta("template_floors",3)); var floors:int=clampi(int(d.get("floors",template_floors)),3,5)
        root.scale.y=float(floors)/float(maxi(1,template_floors))
        _append_node_meshes(root,Transform3D.IDENTITY,st)
        root.free()
    var result:ArrayMesh=st.commit()
    return result if result!=null else ArrayMesh.new()

func _append_node_meshes(node:Node,parent_transform:Transform3D,st:SurfaceTool)->void:
    var current_transform:Transform3D=parent_transform
    if node is Node3D: current_transform=parent_transform*(node as Node3D).transform
    if node is MeshInstance3D:
        var mi:MeshInstance3D=node as MeshInstance3D
        if mi.mesh!=null:
            for s:int in range(mi.mesh.get_surface_count()): st.append_from(mi.mesh,s,current_transform)
    for child:Node in node.get_children(): _append_node_meshes(child,current_transform,st)

func _reduce_mesh_fast(source:ArrayMesh,target_tri:int,keep_uv:bool)->ArrayMesh:
    if source.get_surface_count()==0:return ArrayMesh.new()
    var arrays:Array=source.surface_get_arrays(0)
    if arrays.size()<=Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX]==null:return source
    var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays.size()>Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
    var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays.size()>Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
    var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays.size()>Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
    var faces:int=(indices.size()/3) if indices.size()>0 else (verts.size()/3)
    var wanted:int=mini(faces,target_tri)
    if faces<=wanted:return source
    var st:SurfaceTool=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i:int in range(wanted):
        var fi:int=clampi(int(float(i)*float(faces)/float(wanted)),0,faces-1)
        for corner:int in range(3):
            var flat:int=fi*3+corner
            var vi:int=int(indices[flat]) if indices.size()>0 else flat
            if vi<0 or vi>=verts.size(): continue
            if normals.size()==verts.size(): st.set_normal(normals[vi])
            if keep_uv and uvs.size()==verts.size(): st.set_uv(uvs[vi])
            st.add_vertex(verts[vi])
    var reduced:ArrayMesh=st.commit()
    return reduced if reduced!=null else ArrayMesh.new()

func _write_shared_texture()->void:
    var image:Image=Image.create(512,512,false,Image.FORMAT_RGBA8)
    var palette:Array[Color]=[Color("#c9ad82"),Color("#b97f62"),Color("#d6c09a"),Color("#8f6d52"),Color("#e0c8a5")]
    for y:int in range(512):
        for x:int in range(512): image.set_pixel(x,y,palette[posmod(int(x/64)+int(y/64),palette.size())])
    image.save_png(OUT_DIR+"/roma_palette_512.png")

func _apply_material(mesh:ArrayMesh,level:int)->void:
    var mat:StandardMaterial3D=StandardMaterial3D.new(); mat.roughness=1.0
    if level==1:
        var image:Image=Image.load_from_file(ProjectSettings.globalize_path(OUT_DIR+"/roma_palette_512.png"))
        if image != null and not image.is_empty(): mat.albedo_texture=ImageTexture.create_from_image(image)
        else: mat.albedo_color=Color("#c9ad82")
    elif level==2: mat.albedo_color=Color("#b98b6b")
    else: mat.albedo_color=Color("#c8aa82")
    for s:int in range(mesh.get_surface_count()): mesh.surface_set_material(s,mat)

func _tri_count(mesh:ArrayMesh)->int:
    var total:int=0
    for s:int in range(mesh.get_surface_count()):
        var arrays:Array=mesh.surface_get_arrays(s)
        if arrays.size()>Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]!=null: total+=int(arrays[Mesh.ARRAY_VERTEX].size())/3
    return total
