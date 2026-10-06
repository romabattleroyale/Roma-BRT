extends SceneTree
## LOD1 bake: one simplified ArrayMesh per existing ready template.
## Uses direct ArrayMesh surface arrays instead of SurfaceTool to avoid the
## expensive per-vertex append path. Drops separable shutter/balcony nodes
## and replaces remaining geometry with one flat material.
const READY_DIR := "res://baked_city/ready_templates"
const OUT_DIR := READY_DIR
const COUNT := 120

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var report:Dictionary={"count":COUNT,"visibility_begin":150.0,"visibility_end":400.0,"material":"flat","removed_features":["persiane","balconi"],"method":"direct_arraymesh"}
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
    print("LOD1 BAKE PASS: templates=%d visibility=150-400 flat_material=PASS method=direct_arraymesh"%saved)
    quit(0)

func _build_mesh(root:Node3D)->ArrayMesh:
    var vertices:=PackedVector3Array()
    var normals:=PackedVector3Array()
    var indices:=PackedInt32Array()
    _collect(root,Transform3D.IDENTITY,vertices,normals,indices)
    if vertices.is_empty():return null
    var arrays:=[]
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    if normals.size()==vertices.size():arrays[Mesh.ARRAY_NORMAL]=normals
    if not indices.is_empty():arrays[Mesh.ARRAY_INDEX]=indices
    var mesh:=ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var mat:=StandardMaterial3D.new();mat.albedo_color=Color("#B88B68");mat.roughness=1.0
    mesh.surface_set_material(0,mat)
    return mesh

func _collect(node:Node,parent:Transform3D,vertices:PackedVector3Array,normals:PackedVector3Array,indices:PackedInt32Array)->void:
    if _is_detail(node):return
    var current:=parent
    if node is Node3D:current=parent*(node as Node3D).transform
    if node is MeshInstance3D:
        var mi:=node as MeshInstance3D
        if mi.mesh!=null:
            for s in range(mi.mesh.get_surface_count()):
                _append_surface(mi.mesh,s,current,vertices,normals,indices)
    for child in node.get_children():_collect(child,current,vertices,normals,indices)

func _append_surface(mesh:Mesh,surface:int,xf:Transform3D,vertices:PackedVector3Array,normals:PackedVector3Array,indices:PackedInt32Array)->void:
    var a:=mesh.surface_get_arrays(surface)
    if a.is_empty():return
    var src_vertices:=a[Mesh.ARRAY_VERTEX] as PackedVector3Array
    if src_vertices==null or src_vertices.is_empty():return
    var base:=vertices.size()
    for v in src_vertices:vertices.append(xf*v)
    var src_normals:=a[Mesh.ARRAY_NORMAL] as PackedVector3Array
    var have_normals:=src_normals!=null and src_normals.size()==src_vertices.size()
    if have_normals:
        var normal_xf:=xf.basis.inverse().transposed()
        for n in src_normals:normals.append((normal_xf*n).normalized())
    else:
        for v in src_vertices:normals.append(Vector3.UP)
    var src_indices:=a[Mesh.ARRAY_INDEX] as PackedInt32Array
    if src_indices!=null and not src_indices.is_empty():
        for idx in src_indices:indices.append(base+idx)
    else:
        for idx in range(src_vertices.size()):indices.append(base+idx)

func _is_detail(node:Node)->bool:
    var n:=str(node.name).to_lower()
    return n.contains("persian") or n.contains("persiana") or n.contains("shutter") or n.contains("balcone") or n.contains("balcony")
