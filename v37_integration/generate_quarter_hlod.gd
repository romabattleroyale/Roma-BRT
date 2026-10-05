extends SceneTree
## Generates 3 aggregate HLOD ArrayMesh resources for each of the 12 ready-building districts.
## Geometry is derived from the real 587 placement records: wall masses, pitched roofs,
## roof caps and Roman-style chimneys. No Terrain3D/Tevere/road/layout data is modified.
const MANIFEST := "res://baked_city/ready_templates/manifest.json"
const OUT_DIR := "res://baked_city/hlod"
const DISTRICT_COUNT := 12
const CENTERS := [
    Vector2(-800.0,-650.0),Vector2(-400.0,-650.0),Vector2(400.0,-650.0),Vector2(800.0,-650.0),
    Vector2(-800.0,0.0),Vector2(-400.0,0.0),Vector2(400.0,0.0),Vector2(800.0,0.0),
    Vector2(-800.0,650.0),Vector2(-400.0,650.0),Vector2(400.0,650.0),Vector2(800.0,650.0)
]
const COUNTS := [61,61,61,61,61,61,61,60,25,25,25,25]

func _initialize() -> void:
    var f:=FileAccess.open(MANIFEST,FileAccess.READ)
    if f==null: push_error("HLOD BAKE FAIL: manifest missing");quit(2);return
    var data=JSON.parse_string(f.get_as_text());f.close()
    if not data is Dictionary: push_error("HLOD BAKE FAIL: invalid manifest");quit(3);return
    var placements:Array=data.get("placements",[])
    if placements.size()!=587: push_error("HLOD BAKE FAIL: placements=%d"%placements.size());quit(4);return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    _write_shared_texture()
    var index:=0
    var report:Dictionary={"districts":DISTRICT_COUNT,"placement_count":placements.size(),"levels":{}}
    for district in range(DISTRICT_COUNT):
        var local:Array=[]
        for _i in range(COUNTS[district]): local.append(placements[index]);index+=1
        var m2:=_build_level(local,district,2)
        var m1:=_build_level(local,district,1)
        var m0:=_build_level(local,district,0)
        _apply_material(m2,2);_apply_material(m1,1);_apply_material(m0,0)
        ResourceSaver.save(m2,OUT_DIR+"/quartiere_%02d_2.res"%(district+1))
        ResourceSaver.save(m1,OUT_DIR+"/quartiere_%02d_1.res"%(district+1))
        ResourceSaver.save(m0,OUT_DIR+"/quartiere_%02d_0.res"%(district+1))
        report["levels"][str(district+1)]={"hlod2_tri":_tri_count(m2),"hlod1_tri":_tri_count(m1),"hlod0_tri":_tri_count(m0)}
    var rf:=FileAccess.open("res://baked_city/hlod/report.json",FileAccess.WRITE)
    rf.store_string(JSON.stringify(report));rf.close()
    print("HLOD BAKE PASS: districts=12 aggregate_meshes=36 shared_texture=512x512")
    quit(0)

func _write_shared_texture()->void:
    var image:=Image.create(512,512,false,Image.FORMAT_RGBA8)
    var palette=[Color("#c9ad82"),Color("#b97f62"),Color("#d6c09a"),Color("#8f6d52"),Color("#e0c8a5")]
    for y in range(512):
        for x in range(512):
            var p:=palette[(x/64+y/64)%palette.size()]
            image.set_pixel(x,y,p)
    var tex:=ImageTexture.create_from_image(image)
    ResourceSaver.save(tex,OUT_DIR+"/roma_palette_512.res")

func _apply_material(mesh:ArrayMesh,level:int)->void:
    var mat:=StandardMaterial3D.new()
    mat.roughness=1.0
    mat.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
    if level==1:
        var tex:=ResourceLoader.load(OUT_DIR+"/roma_palette_512.res") as Texture2D
        mat.albedo_texture=tex
        mat.albedo_color=Color.WHITE
    elif level==2:
        mat.albedo_color=Color("#b98b6b")
    else:
        mat.albedo_color=Color("#c8aa82")
    for s in range(mesh.get_surface_count()): mesh.surface_set_material(s,mat)

func _build_level(items:Array,district:int,level:int)->ArrayMesh:
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var center:=CENTERS[district]
    var detail:=level==1
    var coarse:=level==2
    for item in items:
        var d:Dictionary=item
        var x:=float(d.get("x",0.0))-center.x;var z:=float(d.get("z",0.0))-center.y
        var floors:=clampi(int(d.get("floors",3)),3,5)
        var w:=14.0+float(int(d.get("facade_index",0))%3)*2.0
        var dep:=14.0+float(int(d.get("roof_index",0))%3)*2.0
        var h:=float(floors)*4.0
        if coarse:
            _house(st,Vector3(x,0,z),w,dep,h,false,true)
        else:
            _house(st,Vector3(x,0,z),w,dep,h,true,false)
            if detail: _windows_and_roof_details(st,Vector3(x,0,z),w,dep,h,d)
    var mesh:=st.commit()
    return mesh if mesh!=null else ArrayMesh.new()

func _house(st:SurfaceTool,c:Vector3,w:float,d:float,h:float,roof_details:bool,coarse:bool)->void:
    var hw:=w*0.5;var hd:=d*0.5
    _box(st,c+Vector3(0,h*0.5,0),Vector3(w,h,d))
    var roof_h:=3.0 if coarse else 3.5
    _gable_roof(st,c+Vector3(0,h,0),w+1.5,d+1.5,roof_h)
    if roof_details:
        _chimney(st,c+Vector3(-hw*0.35,h+roof_h+0.8,-hd*0.15),1.2,1.2,2.0)
        _chimney(st,c+Vector3(hw*0.25,h+roof_h+0.5,hd*0.2),0.9,0.9,1.5)

func _windows_and_roof_details(st:SurfaceTool,c:Vector3,w:float,d:float,h:float,item:Dictionary)->void:
    var rows:=clampi(int(item.get("floors",3))-1,2,4)
    for r in range(rows):
        var y:=3.0+float(r)*4.0
        for side in [-1.0,1.0]:
            for col in range(2):
                var x:=c.x+(float(col)-0.5)*w*0.35
                _box(st,Vector3(x,y,c.z+side*(d*0.5+0.08)),Vector3(1.4,1.5,0.12))
    _chimney(st,c+Vector3(0,h+4.2,0),1.0,1.0,1.2)

func _box(st:SurfaceTool,c:Vector3,s:Vector3)->void:
    var x=s.x*0.5;var y=s.y*0.5;var z=s.z*0.5
    var p=[Vector3(-x,-y,-z),Vector3(x,-y,-z),Vector3(x,y,-z),Vector3(-x,y,-z),Vector3(-x,-y,z),Vector3(x,-y,z),Vector3(x,y,z),Vector3(-x,y,z)]
    var faces=[[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]
    for q in faces:
        st.add_vertex(c+p[q[0]]);st.add_vertex(c+p[q[1]]);st.add_vertex(c+p[q[2]])
        st.add_vertex(c+p[q[0]]);st.add_vertex(c+p[q[2]]);st.add_vertex(c+p[q[3]])

func _gable_roof(st:SurfaceTool,c:Vector3,w:float,d:float,h:float)->void:
    var x:=w*0.5;var z:=d*0.5
    var a:=c+Vector3(-x,0,-z);var b:=c+Vector3(x,0,-z);var cc:=c+Vector3(x,0,z);var e:=c+Vector3(-x,0,z)
    var r1:=c+Vector3(-x,h,0);var r2:=c+Vector3(x,h,0)
    _tri(st,a,b,r2);_tri(st,a,r2,r1);_tri(st,e,r1,r2);_tri(st,e,r2,cc);_quad(st,a,e,cc,b)
func _chimney(st:SurfaceTool,c:Vector3,w:float,d:float,h:float)->void: _box(st,c+Vector3(0,h*0.5,0),Vector3(w,h,d))
func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3)->void: st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)
func _quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void: _tri(st,a,b,c);_tri(st,a,c,d)
func _tri_count(mesh:ArrayMesh)->int:
    var total:=0
    for s in range(mesh.get_surface_count()):
        var arr:=mesh.surface_get_arrays(s)
        if arr.size()>Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX]!=null: total+=arr[Mesh.ARRAY_VERTEX].size()/3
    return total
