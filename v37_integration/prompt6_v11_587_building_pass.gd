extends Node3D
## PROMPT 6 — V37 587 source positions + full V11 construction.
## No 3D roads, no POI/interior generation, no Terrain3D/Tevere edits.

const ADAPTER_SCRIPT := "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT := "res://v37_integration/building_variation.gd"
const POSITIONS_SCRIPT := "res://v37_integration/v37_building_positions_blob.gd"
const MAX_SLOPE_DELTA := 2.0
const SUBSOIL_LIMIT := -5.0
const SAFETY_CORRIDOR := 2.0
const GRID_SETBACK := 10.0
const BATCH_PAUSE_FRAMES := 2

var adapter = null
var variation_script = null
var positions_script = null
var water_ray: RayCast3D
var built := false
var used_seeds := {}
var used_archetypes := {}
var used_colors := {}
var used_heights := {}
var placed_rects: Array = []
var rejection_counts := {}
var block_counts := {}

func _ready() -> void:
    var a: Script = load(ADAPTER_SCRIPT) as Script
    variation_script = load(VARIATION_SCRIPT) as Script
    positions_script = load(POSITIONS_SCRIPT) as Script
    if a == null or variation_script == null or positions_script == null:
        push_error("PROMPT 6: script V11/variation/positions mancante")
        return
    adapter = a.new()
    water_ray = RayCast3D.new()
    water_ray.name = "Prompt6WaterValidationRayCast3D"
    water_ray.enabled = true
    water_ray.collide_with_bodies = true
    water_ray.collide_with_areas = true
    add_child(water_ray)
    call_deferred("_wait_and_build")

func _wait_and_build() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null and v37.get("city_root") != null:
            await _yield_frames(20)
            await _build_587(v37)
            return
        await get_tree().create_timer(0.1).timeout
    push_warning("PROMPT 6: V37 world non pronto entro 60 secondi")

func _build_587(v37: Node) -> void:
    if built or adapter == null or not adapter.initialize(): return
    var city_root: Node3D = v37.get("city_root") as Node3D
    var source: Array = positions_script.get_buildings()
    var catalog: Array[Dictionary] = adapter.factory.get_catalog()
    print("PROMPT 6 — SOURCE V37: ", source.size(), " edifici (attesi 587)")
    print("PROMPT 6 — CATALOGO V11: ", catalog.size(), " archetipi")
    var placed := 0
    for i in range(source.size()):
        var d: Dictionary = source[i]
        var id := str(d.get("id", "building_%d" % (i + 1)))
        var x := float(d.get("x", NAN)); var z := float(d.get("z", NAN))
        var source_w := maxf(6.0, float(d.get("sx", 10.0)))
        var source_d := maxf(6.0, float(d.get("sz", 10.0)))
        if not is_finite(x) or not is_finite(z): _reject(i,"non_finite_source"); continue
        var block := _find_block(x,z)
        if block.is_empty(): _reject(i,"outside_urban_grid_or_on_road_line"); continue
        var block_index := int(block["index"])
        var v: Dictionary = variation_script.call("variation_for", i, block_index)
        var seed := int(v["seed"])
        if used_seeds.has(seed): _reject(i,"duplicate_seed"); continue
        var ai := posmod(int(v["archetype_index"]), max(1,catalog.size()))
        var entry: Dictionary = catalog[ai]
        var width := maxf(6.0,float(entry.get("w",source_w)))
        var depth := maxf(6.0,float(entry.get("d",source_d)))
        var center := Vector3(x,0.0,z)
        if not center.is_finite(): _reject(i,"non_finite_position"); continue
        if not _inside_block(center,width,depth,block): _reject(i,"outside_urban_grid_or_on_road_line"); continue
        if _overlaps(center,width,depth): _reject(i,"overlap_or_safety_corridor"); continue
        var terrain_check := _validate_terrain(v37,center,width,depth)
        if not bool(terrain_check["valid"]): _reject(i,str(terrain_check["reason"])); continue
        var root: Node3D = adapter.factory.build_and_place(str(entry["id"]),center,float(terrain_check["base_h"]),0.0,i)
        if root == null: _reject(i,"library_build_failed"); continue
        if not root.position.is_finite(): root.queue_free(); _reject(i,"non_finite_building_transform"); continue
        root.name=id
        root.set_meta("v37_source_id",id)
        root.set_meta("v37_source_position",center)
        root.set_meta("v37_source_footprint",Vector2(source_w,source_d))
        root.set_meta("v11_catalog_id",str(entry["id"]))
        root.set_meta("v11_catalog_footprint",Vector2(width,depth))
        root.set_meta("v11_seed",seed)
        root.set_meta("v11_variation",v)
        root.set_meta("prompt6_block",str(block["id"]))
        root.set_meta("prompt6_safety_corridor_m",SAFETY_CORRIDOR)
        root.set_meta("prompt6_full_v11",true)
        city_root.add_child(root)
        placed_rects.append({"center":center,"width":width,"depth":depth})
        used_seeds[seed]=true; used_archetypes[ai]=true
        used_colors[str(v["facade_color"])]=true; used_heights[int(v["height_floors"])]=true
        block_counts[str(block["id"])] = int(block_counts.get(str(block["id"]),0))+1
        placed += 1
        if placed % 4 == 0: await _yield_frames(BATCH_PAUSE_FRAMES)
    built=true
    print("PROMPT 6 — ===== REPORT =====")
    print("PROMPT 6 — SOURCE: ",source.size())
    print("PROMPT 6 — PIAZZATI: ",placed)
    print("PROMPT 6 — SCARTATI: ",source.size()-placed)
    print("PROMPT 6 — ARCHETIPI DIVERSI USATI: ",used_archetypes.size())
    print("PROMPT 6 — COLORI: ",used_colors.keys())
    print("PROMPT 6 — ALTEZZE: ",used_heights.keys())
    print("PROMPT 6 — ISOLATI: ",block_counts)
    print("PROMPT 6 — MOTIVI SCARTO: ",rejection_counts)
    print("PROMPT 6 — STRADE 3D: 0 | INTERNI: 0 | TERRAIN/TEVERE MODIFICATI: NO")

func _find_block(x:float,z:float)->Dictionary:
    var g=get_parent().get_node_or_null("Urban_Grid")
    var rs:Array=[]
    if g!=null: rs=g.get_meta("lot_rects",[])
    if rs.is_empty(): rs=[{"id":"BLOCK_NW","min_x":520.0,"max_x":900.0,"min_z":420.0,"max_z":760.0},{"id":"BLOCK_NE","min_x":900.0,"max_x":1390.0,"min_z":420.0,"max_z":760.0},{"id":"BLOCK_W1","min_x":520.0,"max_x":900.0,"min_z":760.0,"max_z":1080.0},{"id":"BLOCK_E1","min_x":900.0,"max_x":1390.0,"min_z":760.0,"max_z":1080.0},{"id":"BLOCK_W2","min_x":520.0,"max_x":900.0,"min_z":1080.0,"max_z":1400.0},{"id":"BLOCK_E2","min_x":900.0,"max_x":1390.0,"min_z":1080.0,"max_z":1400.0},{"id":"BLOCK_W3","min_x":520.0,"max_x":900.0,"min_z":1400.0,"max_z":1660.0},{"id":"BLOCK_E3","min_x":900.0,"max_x":1390.0,"min_z":1400.0,"max_z":1660.0}]
    for i in range(rs.size()):
        var r:Dictionary=rs[i]
        if x>=float(r["min_x"]) and x<=float(r["max_x"]) and z>=float(r["min_z"]) and z<=float(r["max_z"]):
            var o=r.duplicate(true); o["index"]=i; return o
    return {}

func _inside_block(c:Vector3,w:float,d:float,r:Dictionary)->bool:
    return c.x>=float(r["min_x"])+GRID_SETBACK+w*0.5 and c.x<=float(r["max_x"])-GRID_SETBACK-w*0.5 and c.z>=float(r["min_z"])+GRID_SETBACK+d*0.5 and c.z<=float(r["max_z"])-GRID_SETBACK-d*0.5

func _validate_terrain(world:Node,c:Vector3,w:float,d:float)->Dictionary:
    var hs:Array[float]=[]
    for p in [Vector3(c.x-w*0.5,0,c.z-d*0.5),Vector3(c.x+w*0.5,0,c.z-d*0.5),Vector3(c.x-w*0.5,0,c.z+d*0.5),Vector3(c.x+w*0.5,0,c.z+d*0.5)]:
        var h=float(world.sample_height(p.x,p.z)); if not is_finite(h): return {"valid":false,"reason":"non_finite_terrain_height"}; hs.append(h)
    var mn=hs[0]; var mx=hs[0]; var sum=0.0
    for h in hs: mn=minf(mn,h); mx=maxf(mx,h); sum+=h
    if mx-mn>MAX_SLOPE_DELTA: return {"valid":false,"reason":"slope_gt_2m"}
    if sum/hs.size()<SUBSOIL_LIMIT: return {"valid":false,"reason":"subsoil_lt_-5m"}
    water_ray.position=Vector3(c.x,200,c.z); water_ray.target_position=Vector3(0,-500,0); water_ray.force_raycast_update()
    if water_ray.is_colliding():
        var col=water_ray.get_collider(); if col!=null:
            var n=str(col.name).to_lower(); if n.contains("water") or n.contains("tevere") or n.contains("river"): return {"valid":false,"reason":"water"}
    return {"valid":true,"base_h":sum/hs.size()}

func _overlaps(c:Vector3,w:float,d:float)->bool:
    for r in placed_rects:
        var o:Vector3=r["center"]; var xgap=absf(c.x-o.x)-(w+float(r["width"]))*0.5; var zgap=absf(c.z-o.z)-(d+float(r["depth"]))*0.5
        if xgap<SAFETY_CORRIDOR and zgap<SAFETY_CORRIDOR: return true
    return false

func _reject(i:int,reason:String)->void:
    rejection_counts[reason]=int(rejection_counts.get(reason,0))+1
    if rejection_counts[reason]<=8: print("PROMPT 6 — SCARTATO #",i+1," motivo=",reason)

func _yield_frames(n:int)->void:
    for _i in range(maxi(1,n)): await get_tree().process_frame
