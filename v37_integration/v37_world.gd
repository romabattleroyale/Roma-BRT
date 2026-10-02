extends Node3D
## V37 approved systems adapted to the existing Roma-BRT world.
## Terrain3D/Tevere remain authoritative. create_ground is intentionally absent.

@export var enable_buildings := true
@export var enable_pois := true
@export var enable_foliage := true
@export var enable_fire := true
@export var enable_roads := false
@export var enable_technical_camera := false

var map_data: Dictionary = {}
var city_root: Node3D
var camera: Camera3D
var fire_root: Node3D
var fire_time := 0.0
var building_materials: Dictionary = {}
var road_material: StandardMaterial3D
var sidewalk_material: StandardMaterial3D
var curb_material: StandardMaterial3D
var marking_material: StandardMaterial3D
var roof_material: StandardMaterial3D
var window_material: StandardMaterial3D
var fire_patch_material: StandardMaterial3D
var flame_material: ShaderMaterial
var smoke_material: StandardMaterial3D
var ember_material: StandardMaterial3D

const MAP_SIZE := 2000.0
const FIRE_CENTER := Vector3(1080.0, 0.0, 930.0)
const FIRE_PHASE_SCALE := [1.0, 0.78, 0.61, 0.47, 0.35, 0.25, 0.15, 0.045]
const FIRE_PHASE_TIME := [18.0, 15.0, 12.0, 10.0, 8.0, 7.0, 6.0, 0.0]
const FIRE_SOURCE_COUNT := 72
const FIRE_SEGMENT_COUNT := 72
const FIRE_NEAR_DISTANCE := 520.0

func _ready() -> void:
    call_deferred("_bootstrap_v37")

func _bootstrap_v37() -> void:
    load_map()
    create_materials()
    # TerrainBootstrap imports the existing Terrain3D asynchronously.
    for _i in range(600):
        var bootstrap := get_node_or_null("../TerrainBootstrap")
        if bootstrap != null and bootstrap.get("terrain") != null and bootstrap.terrain.get("data") != null:
            create_world()
            return
        await get_tree().create_timer(0.1).timeout
    push_warning("V37: Terrain3D non pronto entro 60 secondi; integrazione non avviata")

func _process(delta: float) -> void:
    fire_time += delta
    animate_fire()
    animate_camera(delta)

func load_map() -> void:
    var file := FileAccess.open("res://data/scene_3d.json", FileAccess.READ)
    if file == null:
        file = FileAccess.open("res://scene_3d.json", FileAccess.READ)
    if file == null:
        push_warning("V37 scene_3d.json non trovato")
        return
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary:
        map_data = parsed

func create_world() -> void:
    if city_root != null:
        return
    city_root = Node3D.new()
    city_root.name = "V37World"
    add_child(city_root)
    create_lighting()
    if enable_foliage:
        create_foliage()
    if enable_buildings:
        create_buildings()
    if enable_pois:
        create_pois()
    if enable_fire:
        create_fire_zone()
    if enable_roads:
        create_roads()
    if enable_technical_camera:
        create_camera()

func make_material(color: Color, roughness := 0.8, emission := Color(0,0,0), emission_energy := 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    if emission_energy > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = emission_energy
    return m

func create_materials() -> void:
    road_material = make_material(Color(0.055,0.060,0.065),0.92)
    sidewalk_material = make_material(Color(0.42,0.40,0.36),0.88)
    curb_material = make_material(Color(0.48,0.46,0.41),0.92)
    marking_material = make_material(Color(0.82,0.78,0.62),0.72)
    roof_material = make_material(Color(0.25,0.14,0.08),0.95)
    window_material = make_material(Color(0.045,0.09,0.11),0.25,Color(0.15,0.20,0.22),0.35)
    building_materials["historic"] = make_material(Color(0.58,0.40,0.27))
    building_materials["trastevere"] = make_material(Color(0.67,0.46,0.30))
    building_materials["monumental"] = make_material(Color(0.76,0.69,0.55))
    building_materials["rationalist"] = make_material(Color(0.53,0.53,0.49))
    building_materials["industrial"] = make_material(Color(0.34,0.35,0.33))
    building_materials["residential"] = make_material(Color(0.62,0.54,0.44))
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
void fragment(){
    vec2 uv=UV; float side=abs(uv.x-0.5)*2.0;
    float n=sin(uv.y*13.0+TIME*7.0+sin(uv.x*9.0)*2.0)*0.075+sin(uv.y*29.0-TIME*11.0+uv.x*17.0)*0.035;
    float body=(1.0-side)+n-uv.y*0.10;
    float a=smoothstep(0.03,0.20,body*(1.0-uv.y*0.72))*smoothstep(0.0,0.10,uv.y)*smoothstep(1.0,0.70,uv.y);
    float core=smoothstep(0.72,0.08,side)*smoothstep(0.90,0.16,uv.y);
    vec3 c=mix(vec3(1.0,0.035,0.002),vec3(1.0,0.28,0.015),core);
    c=mix(c,vec3(1.0,0.92,0.28),core*0.72); ALBEDO=c; EMISSION=c*(3.0+core*2.0); ALPHA=a*0.98;
}
"""
    flame_material = ShaderMaterial.new()
    flame_material.shader = shader
    smoke_material = make_material(Color(0.075,0.068,0.062,0.28),1.0)
    smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    fire_patch_material = make_material(Color(0.34,0.055,0.018,0.62),0.78,Color(0.9,0.035,0.005),1.1)
    fire_patch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    fire_patch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ember_material = make_material(Color(1.0,0.42,0.04),0.25,Color(1.0,0.16,0.01),5.0)

func sample_height(x: float, z: float) -> float:
    var terrain = get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000",true,false)
    if terrain and terrain.has_method("get_height"):
        return float(terrain.get_height(Vector3(x,0.0,z)))
    if terrain and terrain.get("data") != null and terrain.data.has_method("get_height"):
        return float(terrain.data.get_height(Vector3(x,0.0,z)))
    return 0.0

func create_lighting() -> void:
    # V37 lighting hook retained; existing main.tscn Environment/Sun are authoritative.
    return

func create_buildings() -> void:
    var buildings: Array = map_data.get("city",{}).get("buildings",[])
    print("V37 edifici: ",buildings.size())
    for i in range(buildings.size()):
        create_building(buildings[i],i)

func create_building(data: Dictionary, index: int) -> void:
    var root:=Node3D.new()
    root.name=str(data.get("id","Building"))
    var pos:Dictionary=data.get("position",{})
    var px:=float(pos.get("x",0.0)); var pz:=float(pos.get("z",0.0))
    root.position=Vector3(px,sample_height(px,pz),pz)
    city_root.add_child(root)
    var size:Dictionary=data.get("size",{})
    var width:=maxf(6.0,float(size.get("x",10.0))); var depth:=maxf(6.0,float(size.get("z",10.0)))
    var style:=str(data.get("style","residential")); var material:Material=building_materials.get(style,building_materials["residential"])
    var floors:=maxi(1,int(data.get("floors",3))); var floor_height:=3.0; var factor:=1.0
    match style:
        "historic": floor_height=3.15; factor=1.05
        "trastevere": floor_height=3.0; factor=0.98
        "monumental": floor_height=4.0; factor=1.15
        "rationalist": floor_height=3.4; factor=1.08
        "industrial": floor_height=4.2; factor=0.95
    var height:=maxf(5.0,float(floors)*floor_height*factor)
    width*=0.94+float((index*37)%13)/100.0
    depth*=0.96+float((index*19)%9)/100.0
    var base:=MeshInstance3D.new(); var base_mesh:=BoxMesh.new(); base_mesh.size=Vector3(width+0.9,0.65,depth+0.9); base.mesh=base_mesh; base.position.y=0.325; base.material_override=roof_material; root.add_child(base)
    var body:=MeshInstance3D.new(); var body_mesh:=BoxMesh.new(); body_mesh.size=Vector3(width,height,depth); body.mesh=body_mesh; body.position.y=height*0.5+0.65; body.material_override=material; root.add_child(body)
    var roof:=MeshInstance3D.new(); var roof_mesh:=BoxMesh.new(); roof_mesh.size=Vector3(width+1.4,0.9,depth+1.4); roof.mesh=roof_mesh; roof.position.y=height+1.1; roof.material_override=roof_material; root.add_child(roof)
    if style=="historic" or style=="monumental":
        var cornice:=MeshInstance3D.new(); var cm:=BoxMesh.new(); cm.size=Vector3(width+1.1,0.42,depth+1.1); cornice.mesh=cm; cornice.position.y=height*0.82+0.65; cornice.material_override=roof_material; root.add_child(cornice)
    if index%2==0: add_windows(root,width,height,depth)
    if bool(data.get("balconies",false)) and index%3==0: add_balcony(root,width,height,depth)

func add_windows(root: Node3D,width: float,height: float,depth: float) -> void:
    var rows:=clampi(int(height/5.0),1,5); var cols:=clampi(int(width/4.5),1,4)
    for row in range(rows):
        var y:=3.65+float(row)*maxf(1.0,height-4.6)/float(maxi(1,rows-1))
        for col in range(cols):
            var x:=-width*0.5+2.0+float(col)*(width-4.0)/float(maxi(1,cols-1))
            add_window(root,Vector3(x,y,depth*0.5+0.08),Vector3(1.2,1.8,0.08))
            if col==0 or col==cols-1: add_window(root,Vector3(x,y,-depth*0.5-0.08),Vector3(1.2,1.8,0.08))

func add_window(root: Node3D,p: Vector3,s: Vector3) -> void:
    var w:=MeshInstance3D.new(); var m:=BoxMesh.new(); m.size=s; w.mesh=m; w.position=p; w.material_override=window_material; root.add_child(w)

func add_balcony(root: Node3D,width: float,height: float,depth: float) -> void:
    var b:=MeshInstance3D.new(); var m:=BoxMesh.new(); m.size=Vector3(minf(5.0,width*0.7),0.22,1.1); b.mesh=m; b.position=Vector3(0,maxf(3.2,height*0.65)+0.65,depth*0.5+0.65); b.material_override=roof_material; root.add_child(b)

func create_roads() -> void:
    # Approved V37 road generator is staged. Default false so current Roma-BRT roads are untouched.
    var roads:Array=map_data.get("city",{}).get("roads",[])
    for road in roads:
        var points:Array=road.get("points",[])
        for i in range(points.size()-1):
            create_road_segment(points[i],points[i+1],float(road.get("width",12.0)),str(road.get("type","secondary")))

func create_road_segment(a: Dictionary,b: Dictionary,width: float,road_type: String) -> void:
    var ax:=float(a.get("x",0)); var az:=float(a.get("z",0)); var bx:=float(b.get("x",0)); var bz:=float(b.get("z",0))
    var start:=Vector3(ax,sample_height(ax,az)+0.06,az); var end:=Vector3(bx,sample_height(bx,bz)+0.06,bz); var length:=start.distance_to(end)
    if length<=0.1:return
    var dir:=Vector3(bx-ax,0,bz-az).normalized(); var side:=Vector3(-dir.z,0,dir.x); var rw:=maxf(width,5.0)
    var road:=MeshInstance3D.new(); var rm:=BoxMesh.new(); rm.size=Vector3(rw,0.12,length); road.mesh=rm; road.position=(start+end)*0.5; road.look_at(end,Vector3.UP); road.material_override=road_material; city_root.add_child(road)
    var sw:=2.4 if road_type=="main" else 1.9
    for sign in [-1.0,1.0]:
        var curb:=MeshInstance3D.new(); var cm:=BoxMesh.new(); cm.size=Vector3(0.22,0.18,length); curb.mesh=cm; curb.position=(start+end)*0.5+side*sign*(rw*0.5+0.11); curb.position.y+=0.10; curb.look_at(end,Vector3.UP); curb.material_override=curb_material; city_root.add_child(curb)
        var sidewalk:=MeshInstance3D.new(); var sm:=BoxMesh.new(); sm.size=Vector3(sw,0.14,length); sidewalk.mesh=sm; sidewalk.position=(start+end)*0.5+side*sign*(rw*0.5+0.22+sw*0.5); sidewalk.position.y+=0.12; sidewalk.look_at(end,Vector3.UP); sidewalk.material_override=sidewalk_material; city_root.add_child(sidewalk)

func create_pois() -> void:
    # Register positions only. Existing Exterior Library assets attach later; no POI is rebuilt here.
    var registry:=Node3D.new(); registry.name="V37_POI_Registry"; city_root.add_child(registry)
    for poi in map_data.get("city",{}).get("pois",[]):
        var marker:=Node3D.new(); marker.name=str(poi.get("name","POI")); var pos:Dictionary=poi.get("position",{}); var x:=float(pos.get("x",0)); var z:=float(pos.get("z",0)); marker.position=Vector3(x,sample_height(x,z),z); marker.set_meta("v37_poi_data",poi); registry.add_child(marker)

func create_foliage() -> void:
    var shader:=Shader.new(); shader.code="shader_type spatial; render_mode unshaded, cull_disabled; void vertex(){float h=clamp(VERTEX.y/4.8,0.0,1.0);float id=float(INSTANCE_ID);float p=fract(sin(id*17.13)*43758.5453);VERTEX.x+=sin(TIME*1.7+p*6.28+VERTEX.y*1.4)*0.055*h;VERTEX.z+=cos(TIME*1.25+p*4.7+VERTEX.y*1.9)*0.035*h;} void fragment(){ALBEDO=COLOR.rgb;ROUGHNESS=1.0;}"
    grass_material=ShaderMaterial.new(); grass_material.shader=shader
    var mesh:=create_grass_clump_mesh(); mesh.surface_set_material(0,grass_material)
    var rng:=RandomNumberGenerator.new(); rng.seed=606060
    var palettes:Array[Color]=[Color(0.20,0.40,0.075),Color(0.29,0.50,0.10),Color(0.38,0.57,0.12),Color(0.16,0.33,0.055)]
    for variant in range(palettes.size()):
        var mm:=MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.use_colors=true; mm.mesh=mesh; mm.instance_count=1800
        var root:=MultiMeshInstance3D.new(); root.name="Foliage_Procedural_%02d"%(variant+1); root.multimesh=mm; root.extra_cull_margin=16; city_root.add_child(root)
        var placed:=0; var attempts:=0
        while placed<1800 and attempts<12000:
            attempts+=1; var x:=rng.randf_range(14,MAP_SIZE-14); var z:=rng.randf_range(14,MAP_SIZE-14)
            if grass_density(x,z)<=0.025 or rng.randf()>grass_density(x,z) or is_blocked_by_city(x,z):continue
            var h:=rng.randf_range(2.8,5.0); var w:=rng.randf_range(1.15,1.85); var basis:=Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3(w,h/4.8,w)); mm.set_instance_transform(placed,Transform3D(basis,Vector3(x,sample_height(x,z),z))); var c:=palettes[variant]; var f:=rng.randf_range(0.88,1.12); mm.set_instance_color(placed,Color(clampf(c.r*f,0.08,0.75),clampf(c.g*f,0.12,0.85),clampf(c.b*f,0.02,0.30),1)); placed+=1
        mm.visible_instance_count=placed

func create_grass_clump_mesh() -> ArrayMesh:
    var v:=PackedVector3Array(); var n:=PackedVector3Array(); var c:=PackedColorArray(); var idx:=PackedInt32Array()
    for blade in range(5):
        var a:=float(blade)*TAU/5.0+0.37; var d:=Vector3(cos(a),0,sin(a)); var s:=Vector3(-sin(a),0,cos(a)); var base:=v.size(); var h:=4.8-float(blade%3)*0.45; var w:=0.34+float(blade%2)*0.10; var t:=0.11; var tip:=d*(0.18+float(blade%3)*0.055)+Vector3(0,h,0); var tw:=w*0.16; var tt:=t*0.12
        v.append_array(PackedVector3Array([-s*w-d*t,s*w-d*t,s*w+d*t,-s*w+d*t,tip-s*tw-d*tt,tip+s*tw-d*tt,tip+s*tw+d*tt,tip-s*tw+d*tt]))
        for col in [Color(0.18,0.40,0.055),Color(0.28,0.52,0.075),Color(0.28,0.52,0.075),Color(0.18,0.40,0.055),Color(0.28,0.52,0.075),Color(0.40,0.63,0.12),Color(0.40,0.63,0.12),Color(0.28,0.52,0.075)]:c.append(col);n.append(Vector3.UP)
        idx.append_array(PackedInt32Array([base,base+1,base+5,base,base+5,base+4,base+1,base+2,base+6,base+1,base+6,base+5,base+2,base+3,base+7,base+2,base+7,base+6,base+3,base,base+4,base+3,base+4,base+7,base,base+3,base+2,base,base+2,base+1]))
    var arrays:Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=v; arrays[Mesh.ARRAY_NORMAL]=n; arrays[Mesh.ARRAY_COLOR]=c; arrays[Mesh.ARRAY_INDEX]=idx; var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh

func grass_density(x:float,z:float)->float:
    var p:=Vector2(x,z); var d:=p.distance_to(Vector2(1000,1000)); var density:=smoothstep(560.0,980.0,d)*0.82
    for park in [{"p":Vector2(760,560),"r":145.0,"v":0.86},{"p":Vector2(420,1280),"r":170.0,"v":0.78},{"p":Vector2(1530,1650),"r":190.0,"v":0.88}]:
        density=maxf(density,smoothstep(float(park.r)+80.0,float(park.r)-40.0,p.distance_to(park.p))*float(park.v))
    if d<500:density*=smoothstep(470,560,d)*0.25
    return clampf(density,0,0.92)

func is_blocked_by_city(x:float,z:float)->bool:
    var city:Dictionary=map_data.get("city",{}); var p:=Vector2(x,z)
    for b in city.get("buildings",[]):
        var pos:Dictionary=b.get("position",{}); var size:Dictionary=b.get("size",{}); var bx:=float(pos.get("x",0)); var bz:=float(pos.get("z",0)); var hw:=float(size.get("x",10))*0.5+4; var hd:=float(size.get("z",10))*0.5+4
        if absf(x-bx)<hw and absf(z-bz)<hd:return true
    for poi in city.get("pois",[]):
        var pos:Dictionary=poi.get("position",{}); var q:=Vector2(float(pos.get("x",0)),float(pos.get("z",0))); if p.distance_to(q)<35:return true
    return false

func create_fire_zone() -> void:
    fire_root=Node3D.new(); fire_root.name="FireZone"; add_child(fire_root)
    for i in range(FIRE_SEGMENT_COUNT):fire_root.add_child(create_fire_patch(i))
    for i in range(FIRE_SOURCE_COUNT):fire_root.add_child(create_fire_source(i))

func get_phase_and_radius()->Dictionary:
    var total:=0.0
    for t in FIRE_PHASE_TIME:total+=float(t)
    var elapsed:=minf(fire_time,total);var phase:=0;var local:=elapsed
    for i in range(FIRE_PHASE_TIME.size()):
        var duration:=float(FIRE_PHASE_TIME[i]);
        if duration<=0:phase=i;local=0;break
        if local<duration:phase=i;break
        local-=duration;phase=min(i+1,FIRE_PHASE_SCALE.size()-1)
    var progress:=0.0
    if phase<FIRE_PHASE_TIME.size()-1 and FIRE_PHASE_TIME[phase]>0:progress=clampf(local/float(FIRE_PHASE_TIME[phase]),0,1)
    return {"phase":phase,"progress":progress}

func perimeter_point(index:int)->Vector3:
    var d:=(float(index)/float(FIRE_SOURCE_COUNT))*MAP_SIZE*4.0
    if d<MAP_SIZE:return Vector3(d,0,0)
    d-=MAP_SIZE;if d<MAP_SIZE:return Vector3(MAP_SIZE,0,d)
    d-=MAP_SIZE;if d<MAP_SIZE:return Vector3(MAP_SIZE-d,0,MAP_SIZE)
    d-=MAP_SIZE;return Vector3(0,0,MAP_SIZE-d)

func inner_front_point(index:int,front_scale:float,t:float)->Vector3:
    var a:=TAU*float(index)/float(FIRE_SOURCE_COUNT);var na:=1.0+sin(float(index)*0.51+t*0.20)*0.055;var nb:=1.0+cos(float(index)*1.13-t*0.14)*0.035;return FIRE_CENTER+Vector3(cos(a)*970*front_scale*na*nb,0,sin(a)*900*front_scale*nb)

func fire_front_point(index:int,phase:int,progress:float)->Vector3:
    var outer:=perimeter_point(index);var inner:=inner_front_point(index,float(FIRE_PHASE_SCALE[phase]),fire_time);var next:=inner
    if phase<FIRE_PHASE_SCALE.size()-1:next=inner_front_point(index,float(FIRE_PHASE_SCALE[phase+1]),fire_time)
    var edge:=1.0 if phase==0 else 0.0;if phase==0:edge=progress;return outer.lerp(inner.lerp(next,progress),edge)

func create_fire_patch(index:int)->Node3D:
    var p:=MeshInstance3D.new();p.name="BurningGround_%02d"%index;var m:=BoxMesh.new();m.size=Vector3(32,0.09,9+float(index%5));p.mesh=m;p.material_override=fire_patch_material;return p

func create_fire_source(index:int)->Node3D:
    var root:=Node3D.new();root.name="FireSource_%02d"%index
    var flames:=GPUParticles3D.new();flames.name="Flames";flames.amount=30;flames.lifetime=1.15;var pm:=ParticleProcessMaterial.new();pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;pm.emission_sphere_radius=2.2;pm.direction=Vector3.UP;pm.spread=34;pm.initial_velocity_min=1.5;pm.initial_velocity_max=4.2;pm.gravity=Vector3(0,1.05,0);pm.scale_min=0.55;pm.scale_max=1.25;pm.color=Color(1,0.35,0.04,1);flames.process_material=pm;var q:=QuadMesh.new();q.size=Vector2(7,13);q.material=flame_material;flames.draw_pass_1=q;root.add_child(flames)
    var inner:=GPUParticles3D.new();inner.name="InnerFlames";inner.amount=14;inner.lifetime=0.72;var ip:=ParticleProcessMaterial.new();ip.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;ip.emission_sphere_radius=1.4;ip.direction=Vector3.UP;ip.spread=24;ip.initial_velocity_min=1.8;ip.initial_velocity_max=4.8;ip.gravity=Vector3(0,1.35,0);ip.scale_min=0.28;ip.scale_max=0.72;ip.color=Color(1,0.82,0.16,1);inner.process_material=ip;var iq:=QuadMesh.new();iq.size=Vector2(3.5,7);iq.material=flame_material;inner.draw_pass_1=iq;root.add_child(inner)
    if index%3==0:var light:=OmniLight3D.new();light.name="FireLight";light.light_color=Color(1,0.20,0.035);light.light_energy=2.8;light.omni_range=48;root.add_child(light)
    var smoke:=GPUParticles3D.new();smoke.name="Smoke";smoke.amount=5;smoke.lifetime=3.6;var sp:=ParticleProcessMaterial.new();sp.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;sp.emission_sphere_radius=1.35;sp.direction=Vector3.UP;sp.spread=18;sp.initial_velocity_min=0.55;sp.initial_velocity_max=1.55;sp.gravity=Vector3(0.05,0.24,-0.03);sp.scale_min=0.72;sp.scale_max=1.55;sp.color=Color(0.09,0.082,0.075,0.12);smoke.process_material=sp;var sm:=SphereMesh.new();sm.radius=1.15;sm.height=2;sm.material=smoke_material;smoke.draw_pass_1=sm;root.add_child(smoke)
    var base:=MeshInstance3D.new();var bm:=CylinderMesh.new();bm.top_radius=3.8;bm.bottom_radius=4.8;bm.height=0.1;base.mesh=bm;base.position.y=0.05;base.material_override=make_material(Color(0.055,0.028,0.018),1);root.add_child(base)
    return root

func animate_fire() -> void:
    if fire_root==null:return
    var d:=get_phase_and_radius();var phase:=int(d.phase);var progress:=float(d.progress);var patch:=0;var source:=0
    for child in fire_root.get_children():
        if child.name.begins_with("BurningGround"):
            var p:=fire_front_point(patch,phase,progress);child.position=p;child.rotation.y=-TAU*float(patch)/float(FIRE_SOURCE_COUNT)+PI*0.5;patch+=1
        elif child.name.begins_with("FireSource"):
            child.position=fire_front_point(source,phase,progress)+Vector3(sin(fire_time*0.75+source)*2.5,0,cos(fire_time*0.68+source*0.7)*2.5)
            var detail:=1.0
            if camera!=null and child.global_position.distance_to(camera.global_position)>FIRE_NEAR_DISTANCE:detail=0.55
            var flames:=child.get_node_or_null("Flames") as GPUParticles3D;var inner:=child.get_node_or_null("InnerFlames") as GPUParticles3D;var smoke:=child.get_node_or_null("Smoke") as GPUParticles3D
            if flames:flames.amount=int(30*detail)
            if inner:inner.amount=int(14*detail)
            if smoke:smoke.amount=int(5*detail)
            var light:=child.get_node_or_null("FireLight") as OmniLight3D
            if light:light.light_energy=1.75+sin(fire_time*8+source)*0.65
            source+=1

func create_camera() -> void:
    camera=Camera3D.new();camera.name="V37TechnicalCamera";camera.current=false;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2200;camera.near=0.1;camera.far=5000;camera.position=Vector3(1000,2200,1000);camera.rotation=Vector3(-PI*0.5,0,0);add_child(camera)

func animate_camera(_delta:float)->void:
    return
