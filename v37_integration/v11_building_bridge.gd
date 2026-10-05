extends Node3D
## Runtime V11 bridge: 120 shared templates, 587 virtual placements, spatial chunking.
## Detailed buildings stream near the player; one lightweight MultiMesh HLOD keeps the whole city readable.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST_PATH := READY_DIR + "/manifest.json"
const CHUNK_SIZE := 200.0
const MAX_ACTIVE := 50
const LOAD_RADIUS_CHUNKS := 1
const HLOD_NEAR := 350.0
const HLOD_WIDTH := 18.0
const HLOD_DEPTH := 18.0
const HLOD_FLOOR_HEIGHT := 4.0
const HLOD_HEIGHT_MIN := 10.0
var built := false
var _refreshing := false
var _city_root: Node3D
var _templates: Array[PackedScene] = []
var _placements: Array = []
var _active: Dictionary = {}
var _groups: Dictionary = {}
var _last_chunk := Vector2i(999999,999999)
var _variation_script: RefCounted
var _hlod_instance: MultiMeshInstance3D

func _ready() -> void:
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37=get_parent().get_node_or_null("V37Integration")
        if v37!=null:
            v37.set("enable_buildings",false)
            if v37.get("city_root")!=null:
                _city_root=v37.get("city_root") as Node3D
                await _yield_frames(2)
                if _load_manifest():
                    _build_city_hlod()
                    await _load_all_templates()
                    var player:=_find_player()
                    var p:=player.global_position if player!=null else Vector3.ZERO
                    await _refresh_chunks(p)
                    built=true
                    print("V11 READY BAKE: COMPLETE loaded=587 templates=120 active=%d hlod=587" % _active.size())
                    return
        await get_tree().create_timer(0.1).timeout
    push_error("V11 TEMPLATE CHUNKING: V37 world non pronto")

func _load_manifest()->bool:
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("V11 TEMPLATE CHUNKING: manifest mancante")
        return false
    var f:=FileAccess.open(MANIFEST_PATH,FileAccess.READ)
    var data=JSON.parse_string(f.get_as_text())
    f.close()
    if not data is Dictionary or int(data.get("template_count",0))!=120 or int(data.get("placement_count",0))!=587:
        push_error("V11 TEMPLATE CHUNKING: manifest invalido")
        return false
    _placements=data["placements"] as Array
    return _placements.size()==587

func _build_city_hlod()->void:
    if _city_root==null or _hlod_instance!=null:
        return
    var mesh:=BoxMesh.new()
    mesh.size=Vector3(HLOD_WIDTH,1.0,HLOD_DEPTH)
    var mat:=StandardMaterial3D.new()
    mat.albedo_color=Color(0.56,0.48,0.38)
    mat.roughness=1.0
    mesh.material=mat
    var mm:=MultiMesh.new()
    mm.transform_format=MultiMesh.TRANSFORM_3D
    mm.use_colors=false
    mm.mesh=mesh
    mm.instance_count=_placements.size()
    for i in range(_placements.size()):
        var d:Dictionary=_placements[i]
        var floors:=clampi(int(d.get("floors",3)),3,5)
        var h:=maxf(HLOD_HEIGHT_MIN,float(floors)*HLOD_FLOOR_HEIGHT)
        var x:=float(d.get("x",0.0))
        var y:=float(d.get("y",0.0))
        var z:=float(d.get("z",0.0))
        var rot:=float(d.get("rotation",0.0))
        var t:=Transform3D(Basis(Vector3.UP,rot),Vector3(x,y+h*0.5,z))
        t.basis=Basis(Vector3.UP,rot).scaled(Vector3(1.0,h,1.0))
        mm.set_instance_transform(i,t)
    _hlod_instance=MultiMeshInstance3D.new()
    _hlod_instance.name="V11_City_HLOD_587"
    _hlod_instance.multimesh=mm
    _hlod_instance.visibility_range_begin=HLOD_NEAR
    _hlod_instance.visibility_range_begin_margin=50.0
    _hlod_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _hlod_instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
    _hlod_instance.extra_cull_margin=2000.0
    _city_root.add_child(_hlod_instance)
    print("V11 CITY HLOD: PASS proxies=587 near=%.0fm" % HLOD_NEAR)

func _load_all_templates() -> void:
    _templates.clear()
    for i in range(120):
        var packed:=ResourceLoader.load("%s/template_%03d.tscn"%[READY_DIR,i+1],"PackedScene",ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if packed!=null:
            _templates.append(packed)
        if i % 3 == 2:
            await get_tree().process_frame
    var variation_script:Script=load("res://v37_integration/mobile_visual_variation.gd") as Script
    if variation_script!=null:
        _variation_script=variation_script.new()
    if _templates.size()!=120:
        push_error("V11 TEMPLATE CHUNKING: templates caricati=%d"%_templates.size())

func _process(_delta:float)->void:
    if not built or _refreshing:
        return
    var player:=_find_player()
    if player==null:
        return
    var p:=player.global_position
    var c:=_chunk_for(p.x,p.z)
    if c!=_last_chunk:
        _refresh_chunks(p)

func _refresh_chunks(player_pos:Vector3) -> void:
    if _refreshing:
        return
    _refreshing=true
    var center:=_chunk_for(player_pos.x,player_pos.z)
    _last_chunk=center
    var wanted={}
    for i in range(_placements.size()):
        var d:Dictionary=_placements[i]
        var c:=_chunk_for(float(d.get("x",0)),float(d.get("z",0)))
        if abs(c.x-center.x)<=LOAD_RADIUS_CHUNKS and abs(c.y-center.y)<=LOAD_RADIUS_CHUNKS:
            wanted[i]=true
    var ordered: Array = wanted.keys()
    ordered.sort_custom(func(a:int,b:int)->bool:
        var da:Dictionary=_placements[a]
        var db:Dictionary=_placements[b]
        return Vector2(float(da.get("x",0))-player_pos.x,float(da.get("z",0))-player_pos.z).length_squared()<Vector2(float(db.get("x",0))-player_pos.x,float(db.get("z",0))-player_pos.z).length_squared())
    if ordered.size()>MAX_ACTIVE:
        ordered.resize(MAX_ACTIVE)
    var keep={}
    for i in ordered:
        keep[i]=true
    var to_remove:Array[int]=[]
    for key in _active.keys():
        if not keep.has(int(key)):
            to_remove.append(int(key))
    for i in to_remove:
        _unload_placement(i)
    var added:=0
    for i in ordered:
        if not _active.has(i):
            _load_placement(i)
            added+=1
            if added % 3 == 0:
                await get_tree().process_frame
    _refreshing=false

func _load_placement(i:int)->void:
    var d:Dictionary=_placements[i]
    var ti:=clampi(int(d.get("template",0)),0,119)
    if ti>=_templates.size():
        return
    var root:=_templates[ti].instantiate() as Node3D
    if root==null:
        return
    root.position=Vector3(float(d.get("x",0)),float(d.get("y",0)),float(d.get("z",0)))
    root.rotation.y=float(d.get("rotation",0))
    var template_floors:=int(root.get_meta("template_floors",3))
    var floors:=clampi(int(d.get("floors",template_floors)),3,5)
    root.scale.y=float(floors)/float(maxi(1,template_floors))
    root.set_meta("runtime_placement",i)
    root.set_meta("ready_signature","%d|f%d|c%d|r%d"%[ti,floors,int(d.get("facade_index",0)),int(d.get("roof_index",0))])
    if _variation_script!=null:
        _variation_script.apply(root,int(d.get("seed",i)),floors)
    _city_root.add_child(root)
    _active[i]=root
    _attach_to_multimesh(i,root)

func _attach_to_multimesh(i:int,root:Node3D)->void:
    var mesh:=_find_mesh_node(root)
    if mesh==null or mesh.mesh==null:
        return
    var sig:=str(root.get_meta("ready_signature",""))
    var group:Dictionary=_groups.get(sig,{})
    if group.is_empty():
        _groups[sig]={"mesh":mesh.mesh,"roots":[i],"mmi":null,"mm":null}
        return
    var mm:=group.get("mm") as MultiMesh
    if mm==null:
        mm=MultiMesh.new()
        mm.transform_format=MultiMesh.TRANSFORM_3D
        mm.use_colors=false
        mm.mesh=group["mesh"] as Mesh
        mm.instance_count=2
        var first_root:Node3D=_active[int(group["roots"][0])]
        mm.set_instance_transform(0,first_root.transform)
        mm.set_instance_transform(1,root.transform)
        var mmi:=MultiMeshInstance3D.new()
        mmi.name="ReadyTemplateMultiMesh_%s"%sig
        mmi.multimesh=mm
        _city_root.add_child(mmi)
        var first_mesh:=_find_mesh_node(first_root)
        if first_mesh!=null:
            first_mesh.visible=false
        mesh.visible=false
        group["mm"]=mm
        group["mmi"]=mmi
        group["roots"].append(i)
        _groups[sig]=group
    else:
        mm.instance_count+=1
        mm.set_instance_transform(mm.instance_count-1,root.transform)
        mesh.visible=false
        group["roots"].append(i)
        _groups[sig]=group

func _unload_placement(i:int)->void:
    var root:=_active.get(i) as Node3D
    if root!=null:
        root.queue_free()
    _active.erase(i)
    _rebuild_groups()

func _rebuild_groups()->void:
    _groups.clear()
    if _city_root!=null:
        for child in _city_root.get_children():
            if child is MultiMeshInstance3D and str(child.name).begins_with("ReadyTemplateMultiMesh_"):
                child.queue_free()
    for i in _active.keys():
        var mesh:=_find_mesh_node(_active[i] as Node3D)
        if mesh!=null:
            mesh.visible=true
    for i in _active.keys():
        _attach_to_multimesh(int(i),_active[i] as Node3D)

func _chunk_for(x:float,z:float)->Vector2i:
    return Vector2i(floori(x/CHUNK_SIZE),floori(z/CHUNK_SIZE))

func _find_mesh_node(root:Node)->MeshInstance3D:
    var stack:Array[Node]=[root]
    while not stack.is_empty():
        var n:Node=stack.pop_back()
        if n is MeshInstance3D:
            return n as MeshInstance3D
        for c in n.get_children():
            stack.append(c)
    return null

func _find_player()->Node3D:
    var group_nodes:=get_tree().get_nodes_in_group("player")
    if not group_nodes.is_empty() and group_nodes[0] is Node3D:
        return group_nodes[0] as Node3D
    return get_tree().current_scene.get_node_or_null("Player") as Node3D

func _yield_frames(n:int)->void:
    for _i in range(n):
        await get_tree().process_frame
