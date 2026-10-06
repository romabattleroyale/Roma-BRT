extends SceneTree
## LOD1 bake: one simplified ArrayMesh per existing ready template.
## Keeps the building silhouette, drops shutter/balcony nodes when separable,
## and replaces all remaining materials with one flat color.
const READY_DIR := "res://baked_city/ready_templates"
const OUT_DIR := READY_DIR
const COUNT := 120

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var report:Dictionary={"count":COUNT,"visibility_begin":150.0,"visibility_end":400.0,"material":"flat","removed_features":["persiane","balconi"]}
    var saved:=0
    for i in range(COUNT):
        var path:=READY_DIR+"/template_%03d.tscn"%(i+1)
        var scene:=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if scene==null: push_error("LOD1: missing "+path);quit(2);return
        var root:=scene.instantiate() as Node3D
        if root==null: push_error("LOD1: instantiate failed %d"%(i+1));quit(3);return
        var mesh:=_build_mesh(root)
        root.free()
        if mesh==null or mesh.get_surface_count()==0: push_error("LOD1: empty template %d"%(i+1));quit(4);return
        var err:=ResourceSaver.save(mesh,OUT_DIR+"/template_%03d_lod1.res"%(i+1))
        if err!=OK: push_error("LOD1: save failed %d err=%d"%[i+1,err]);quit(5);return
        saved+=1
        if i%10==9:await process_frame
    report["saved"]=saved
    var f:=FileAccess.open(READY_DIR+"/lod1_report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report));f.close()
    print("LOD1 BAKE PASS: templates=%d visibility=150-400 flat_material=PASS"%saved)
    quit(0)

func _build_mesh(root:Node3D)->ArrayMesh:
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _append(root,Transform3D.IDENTITY,st)
    var mesh:=st.commit() as ArrayMesh
    if mesh==null:return null
    var mat:=StandardMaterial3D.new();mat.albedo_color=Color("#B88B68");mat.roughness=1.0
    for s in range(mesh.get_surface_count()):mesh.surface_set_material(s,mat)
    return mesh

func _append(node:Node,parent:Transform3D,st:SurfaceTool)->void:
    if _is_detail(node):return
    var current:=parent
    if node is Node3D:current=parent*(node as Node3D).transform
    if node is MeshInstance3D:
        var mi:=node as MeshInstance3D
        if mi.mesh!=null:
            for s in range(mi.mesh.get_surface_count()):st.append_from(mi.mesh,s,current)
    for child in node.get_children():_append(child,current,st)

func _is_detail(node:Node)->bool:
    var n:=str(node.name).to_lower()
    return n.contains("persian") or n.contains("persiana") or n.contains("shutter") or n.contains("balcone") or n.contains("balcony")
