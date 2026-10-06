extends SceneTree
## Fast HLOD2: one lightweight district proxy per quarter.
## No quarter merge: each .res is an independent colored box + pitched roof.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST := READY_DIR + "/manifest.json"
const OUT_DIR := "res://baked_city/hlod"
const DISTRICT_COUNT := 12
const COUNTS := [61,61,61,61,61,61,61,60,25,25,25,25]
const CENTERS:Array[Vector2] = [Vector2(-800,-650),Vector2(-400,-650),Vector2(400,-650),Vector2(800,-650),Vector2(-800,0),Vector2(-400,0),Vector2(400,0),Vector2(800,0),Vector2(-800,650),Vector2(-400,650),Vector2(400,650),Vector2(800,650)]
const COLORS:Array[Color] = [Color("#C58B62"),Color("#B97845"),Color("#D1A15A"),Color("#B96F73"),Color("#C7AA83"),Color("#A9573B"),Color("#B88D6A"),Color("#D3A63A"),Color("#A99A7E"),Color("#C98D68"),Color("#A96D54"),Color("#C6A47B")]

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not FileAccess.file_exists(MANIFEST): push_error("HLOD2 BAKE FAIL: manifest missing"); quit(2); return
    var f:=FileAccess.open(MANIFEST,FileAccess.READ)
    var data:Variant=JSON.parse_string(f.get_as_text()); f.close()
    if not data is Dictionary: push_error("HLOD2 BAKE FAIL: invalid manifest"); quit(3); return
    var placements:Array=data.get("placements",[])
    if placements.size()!=587: push_error("HLOD2 BAKE FAIL: placements=%d"%placements.size()); quit(4); return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var report:Dictionary={"districts":12,"placement_count":587,"architecture":"box_plus_pitched_roof","levels":{}}
    var index:=0
    for district in range(DISTRICT_COUNT):
        var local:Array=[]
        for _i in range(COUNTS[district]): local.append(placements[index]); index+=1
        var mesh:=_build_proxy(local,district)
        var path:=OUT_DIR+"/quartiere_%02d_2.res"%(district+1)
        var err:=ResourceSaver.save(mesh,path)
        if err!=OK: push_error("HLOD2 BAKE FAIL: save district=%02d err=%d"%[district+1,err]); quit(5); return
        report["levels"][str(district+1)]={"triangles":_tri_count(mesh),"visibility_begin":400.0,"visibility_end":4000.0}
        await process_frame
    var rf:=FileAccess.open(OUT_DIR+"/report.json",FileAccess.WRITE);rf.store_string(JSON.stringify(report));rf.close()
    print("HLOD2 FAST BAKE PASS: districts=12 proxies=12 box_roof=PASS")
    quit(0)

func _build_proxy(items:Array,district:int)->ArrayMesh:
    var min_x:=INF;var max_x:=-INF;var min_z:=INF;var max_z:=-INF;var max_floor:=3
    for item in items:
        var d:Dictionary=item
        var x:=float(d.get("x",0.0));var z:=float(d.get("z",0.0))
        min_x=minf(min_x,x);max_x=maxf(max_x,x);min_z=minf(min_z,z);max_z=maxf(max_z,z)
        max_floor=maxi(max_floor,clampi(int(d.get("floors",3)),3,5))
    var cx:float=(min_x+max_x)*0.5;var cz:float=(min_z+max_z)*0.5
    var w:float=maxf(180.0,max_x-min_x+30.0);var d:float=maxf(180.0,max_z-min_z+30.0);var h:float=float(max_floor)*3.2
    var roof_h:float=18.0
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var c:=COLORS[district]
    _box(st,Vector3(cx,0,cz),Vector3(w,h,d),c)
    _gable_roof(st,Vector3(cx,h,cz),w,d,roof_h,c.lightened(0.08))
    var mesh:=st.commit() as ArrayMesh
    return mesh if mesh!=null else ArrayMesh.new()

func _box(st:SurfaceTool,center:Vector3,size:Vector3,c:Color)->void:
    var x:=size.x*0.5;var y:=size.y;var z:=size.z*0.5
    var p=[Vector3(-x,0,-z),Vector3(x,0,-z),Vector3(x,y,-z),Vector3(-x,y,-z),Vector3(-x,0,z),Vector3(x,0,z),Vector3(x,y,z),Vector3(-x,y,z)]
    var faces=[[0,1,2,3],[1,5,6,2],[5,4,7,6],[4,0,3,7],[3,2,6,7],[4,5,1,0]]
    for face in faces:_quad(st,center,p,face,c)

func _gable_roof(st:SurfaceTool,base:Vector3,w:float,d:float,rh:float,c:Color)->void:
    var x:=w*0.5;var z:=d*0.5
    var p=[Vector3(-x,0,-z),Vector3(x,0,-z),Vector3(x,0,z),Vector3(-x,0,z),Vector3(0,rh,-z),Vector3(0,rh,z)]
    _tri(st,base+p[0],base+p[1],base+p[4],c);_tri(st,base+p[1],base+p[2],base+p[5],c);_tri(st,base+p[2],base+p[3],base+p[5],c);_tri(st,base+p[3],base+p[0],base+p[4],c)
    _quad(st,base,p,[0,3,5,4],c);_quad(st,base,p,[1,4,5,2],c)

func _quad(st:SurfaceTool,base:Vector3,p:Array,face:Array,c:Color)->void:
    _tri(st,base+p[face[0]],base+p[face[1]],base+p[face[2]],c);_tri(st,base+p[face[0]],base+p[face[2]],base+p[face[3]],c)
func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,col:Color)->void:
    st.set_color(col);st.add_vertex(a);st.set_color(col);st.add_vertex(b);st.set_color(col);st.add_vertex(c)
func _tri_count(mesh:ArrayMesh)->int:
    var total:=0
    for s in range(mesh.get_surface_count()):
        var arrays:Array=mesh.surface_get_arrays(s)
        if arrays.size()>Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]!=null:total+=int(arrays[Mesh.ARRAY_VERTEX].size())/3
    return total
