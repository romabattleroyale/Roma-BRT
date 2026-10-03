extends Node3D
## PROMPT 4: compact Roman-style urban blocks from the first 40 V11 candidates.
## Uses the real V11 catalog footprint and exact seeded catalog archetype.
## No roads, terrain, Tevere or heightmap edits.

const ADAPTER_SCRIPT = "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT = "res://v37_integration/building_variation.gd"
const TEST_COUNT = 40
const MAX_SLOPE_DELTA = 2.0
const SUBSOIL_LIMIT = -5.0
const ROAD_SETBACK = 10.0
const SAFETY_CORRIDOR = 2.0
const BATCH_PAUSE_FRAMES = 2
const TERRAIN_CLEARANCE = 0.10

var adapter = null
var variation_script = null
var built := false
var used_seeds := {}
var used_archetypes := {}
var used_colors := {}
var used_heights := {}
var rejection_counts := {}
var block_counts := {}
var placed_rects := []
var water_ray: RayCast3D

func _ready() -> void:
    var adapter_resource = load(ADAPTER_SCRIPT)
    variation_script = load(VARIATION_SCRIPT)
    if adapter_resource == null or variation_script == null:
        push_error("V11 Building Bridge: script libreria/variazione non caricabile")
        return
    adapter = adapter_resource.new()
    water_ray = RayCast3D.new()
    water_ray.name = "WaterValidationRayCast3D"
    water_ray.enabled = true
    water_ray.collide_with_bodies = true
    water_ray.collide_with_areas = true
    add_child(water_ray)
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null and v37.get("city_root") != null and not (v37.get("map_data") as Dictionary).is_empty():
            await _build_library(v37)
            return
        await get_tree().create_timer(0.1).timeout
    push_warning("V11 Building Bridge: V37 world non pronto entro 60 secondi")

func _build_library(v37: Node) -> void:
    if built or adapter == null or variation_script == null or not adapter.initialize():
        return
    var city_root = v37.get("city_root") as Node3D
    var map_data = v37.get("map_data") as Dictionary
    var source_buildings: Array = map_data.get("city", {}).get("buildings", [])
    var limit := min(TEST_COUNT, source_buildings.size())
    var catalog: Array[Dictionary] = adapter.factory.get_catalog()
    var library_archetypes := catalog.size()
    print("PROMPT 4 — V11 ARCHETIPI CARICATI: ", library_archetypes, " (attesi 24)")

    var candidates: Array = []
    for i in range(limit):
        var data: Dictionary = source_buildings[i]
        var variation: Dictionary = variation_script.call("variation_for", i, int(i / 4))
        var archetype_index := posmod(int(variation["archetype_index"]), max(1, library_archetypes))
        var entry: Dictionary = catalog[archetype_index]
        var width := maxf(6.0, float(entry.get("w", 10.0)))
        var depth := maxf(6.0, float(entry.get("d", 10.0)))
        var catalog_id := str(entry.get("id", ""))
        candidates.append({"index":i, "data":data, "variation":variation, "archetype":archetype_index, "catalog_id":catalog_id, "width":width, "depth":depth})
        print("PROMPT 4 — CANDIDATO #", i + 1, " archetype=", archetype_index, " id=", catalog_id, " footprint=", width, "x", depth, " colore=", variation["facade_color"], " altezza=", variation["height_floors"], " seed=", variation["seed"])

    var blocks := _urban_lot_rects()
    var block_count := min(blocks.size(), int(ceil(float(limit) / 5.0)))
    print("PROMPT 4 — URBAN_GRID RETTANGOLI: ", blocks.size(), " (attesi 8)")
    print("PROMPT 4 — ISOLATI UTILIZZATI: ", block_count)

    var placed := 0
    for block_index in range(block_count):
        var group: Array = []
        var first := block_index * 5
        var last := min(first + 5, candidates.size())
        for i in range(first, last):
            group.append(candidates[i])
        if group.size() < 5:
            for candidate in group:
                _reject(int(candidate["index"]), "incomplete_block")
            continue
        var rect: Dictionary = blocks[block_index]
        var block_id := str(rect.get("id", "BLOCK_%02d" % block_index))
        var layout := _make_compact_layout(group)
        var anchor := _direct_anchor(rect, layout, block_index)
        var valid_group := 0

        for item in layout:
            await _android_yield()
            var candidate: Dictionary = item["candidate"]
            var index := int(candidate["index"])
            var variation: Dictionary = candidate["variation"]
            var seed := int(variation["seed"])
            var width := float(candidate["width"])
            var depth := float(candidate["depth"])
            var center := anchor + item["offset"]
            center.y = 0.0
            var rotation_y := float(item["rotation"])
            if used_seeds.has(seed):
                _reject(index, "duplicate_seed")
                continue
            if not center.is_finite():
                _reject(index, "non_finite_position")
                continue
            if not _inside_urban_grid(center, width, depth, rotation_y):
                _reject(index, "outside_urban_grid_or_on_road_line")
                continue
            var validation := _validate_prompt4_candidate(v37, center, width, depth, rotation_y)
            if not validation["valid"]:
                _reject(index, str(validation["reason"]))
                continue
            var base_h := float(validation["base_h"])
            var building = adapter.build_by_id(str(candidate["catalog_id"]), Vector3(center.x, 0.0, center.z), base_h, rotation_y, index)
            if building == null:
                _reject(index, "library_build_failed")
                continue
            if not building.position.is_finite():
                building.queue_free()
                _reject(index, "non_finite_building_transform")
                continue
            building.name = str(candidate["data"].get("id", "V11Building_%03d" % index))
            building.set_meta("v11_seed", seed)
            building.set_meta("v11_variation", variation)
            building.set_meta("v11_catalog_id", str(candidate["catalog_id"]))
            building.set_meta("v11_catalog_footprint", Vector2(width, depth))
            building.set_meta("prompt4_block", block_id)
            building.set_meta("prompt4_slot", int(item["slot"]))
            building.set_meta("prompt4_safety_corridor_m", SAFETY_CORRIDOR)
            building.set_meta("prompt4_courtyard", true)
            building.set_meta("prompt4_terrain_base_h", base_h)
            city_root.add_child(building)
            placed_rects.append({"center":center, "width":width, "depth":depth, "rotation":rotation_y, "block":block_index})
            used_seeds[seed] = true
            used_archetypes[int(candidate["archetype"])] = true
            used_colors[str(variation["facade_color"])] = true
            used_heights[int(variation["height_floors"])] = true
            valid_group += 1
            placed += 1
            block_counts[block_id] = int(block_counts.get(block_id, 0)) + 1
            print("PROMPT 4 — PIAZZATO #", index + 1, " block=", block_id, " slot=", item["slot"], " archetype=", candidate["archetype"], " id=", candidate["catalog_id"], " colore=", variation["facade_color"], " altezza=", variation["height_floors"])
            await _android_yield()
        print("PROMPT 4 — ISOLATO ", block_id, ": ", valid_group, " / 5 edifici")

    built = true
    print("PROMPT 4 — ===== RIEPILOGO =====")
    print("PROMPT 4 — CANDIDATI TOTALI: ", limit)
    print("PROMPT 4 — PIAZZATI TOTALI: ", placed)
    print("PROMPT 4 — SCARTATI TOTALI: ", limit - placed)
    print("PROMPT 4 — ARCHETIPI V11 LIBRERIA: ", library_archetypes)
    print("PROMPT 4 — ARCHETIPI V11 REALMENTE USATI: ", used_archetypes.size())
    print("PROMPT 4 — COLORI USATI: ", used_colors.size(), " -> ", used_colors.keys())
    print("PROMPT 4 — ALTEZZE USATE: ", used_heights.size(), " -> ", used_heights.keys())
    print("PROMPT 4 — ISOLATI CREATI: ", block_counts.size(), " / target ", block_count)
    for block_id in block_counts.keys():
        print("PROMPT 4 — ", block_id, " = ", block_counts[block_id], " edifici")
    print("PROMPT 4 — MOTIVI SCARTO: ", rejection_counts)

func _android_yield() -> void:
    for _i in range(BATCH_PAUSE_FRAMES):
        await get_tree().process_frame

func _urban_lot_rects() -> Array:
    var grid = get_parent().get_node_or_null("Urban_Grid")
    if grid != null:
        var rects: Array = grid.get_meta("lot_rects", [])
        if not rects.is_empty():
            return rects
    return [{"id":"BLOCK_NW","min_x":520.0,"max_x":900.0,"min_z":420.0,"max_z":760.0},{"id":"BLOCK_NE","min_x":900.0,"max_x":1390.0,"min_z":420.0,"max_z":760.0},{"id":"BLOCK_W1","min_x":520.0,"max_x":900.0,"min_z":760.0,"max_z":1080.0},{"id":"BLOCK_E1","min_x":900.0,"max_x":1390.0,"min_z":760.0,"max_z":1080.0},{"id":"BLOCK_W2","min_x":520.0,"max_x":900.0,"min_z":1080.0,"max_z":1400.0},{"id":"BLOCK_E2","min_x":900.0,"max_x":1390.0,"min_z":1080.0,"max_z":1400.0},{"id":"BLOCK_W3","min_x":520.0,"max_x":900.0,"min_z":1400.0,"max_z":1660.0},{"id":"BLOCK_E3","min_x":900.0,"max_x":1390.0,"min_z":1400.0,"max_z":1660.0}]

func _make_compact_layout(group: Array) -> Array:
    var layout: Array = []
    if group.size() < 5:
        return layout
    var w0 := float(group[0]["width"]); var w1 := float(group[1]["width"]); var w2 := float(group[2]["width"])
    var d0 := float(group[0]["depth"]); var d1 := float(group[1]["depth"]); var d2 := float(group[2]["depth"])
    var outer_depth := maxf(d0,maxf(d1,d2))
    var x0 := -(w0+w1+w2)*0.5+w0*0.5
    var x1 := x0+w0*0.5+w1*0.5
    var x2 := x1+w1*0.5+w2*0.5
    var top_z := -outer_depth*0.5
    layout.append({"candidate":group[0],"offset":Vector3(x0,0,top_z+(outer_depth-d0)*0.5),"rotation":0.0,"slot":0})
    layout.append({"candidate":group[1],"offset":Vector3(x1,0,top_z+(outer_depth-d1)*0.5),"rotation":0.0,"slot":1})
    layout.append({"candidate":group[2],"offset":Vector3(x2,0,top_z+(outer_depth-d2)*0.5),"rotation":0.0,"slot":2})
    var lw := float(group[3]["depth"]); var ld := float(group[3]["width"]); var rw := float(group[4]["depth"]); var rd := float(group[4]["width"])
    var left_x := x0-w0*0.5-lw*0.5; var right_x := x2+w2*0.5+rw*0.5
    var side_z := top_z+outer_depth*0.5+maxf(ld,rd)*0.5
    layout.append({"candidate":group[3],"offset":Vector3(left_x,0,side_z),"rotation":PI*0.5,"slot":3})
    layout.append({"candidate":group[4],"offset":Vector3(right_x,0,side_z),"rotation":-PI*0.5,"slot":4})
    return layout

func _world_half_extents(width: float,depth: float,rotation_y: float) -> Vector2:
    if absf(fmod(absf(rotation_y),PI)-PI*0.5)<0.01:
        return Vector2(depth*0.5,width*0.5)
    return Vector2(width*0.5,depth*0.5)

func _direct_anchor(rect: Dictionary,layout: Array,block_index: int) -> Vector3:
    var min_x := float(rect.get("min_x",0.0)); var max_x := float(rect.get("max_x",0.0)); var min_z := float(rect.get("min_z",0.0)); var max_z := float(rect.get("max_z",0.0))
    var lo_x := INF; var hi_x := -INF; var lo_z := INF; var hi_z := -INF
    for item in layout:
        var c: Dictionary = item["candidate"]; var p: Vector3 = item["offset"]
        var ext := _world_half_extents(float(c["width"]),float(c["depth"]),float(item["rotation"]))
        lo_x=minf(lo_x,p.x-ext.x); hi_x=maxf(hi_x,p.x+ext.x); lo_z=minf(lo_z,p.z-ext.y); hi_z=maxf(hi_z,p.z+ext.y)
    var ax0 := min_x+ROAD_SETBACK-lo_x; var ax1 := max_x-ROAD_SETBACK-hi_x; var az0 := min_z+ROAD_SETBACK-lo_z; var az1 := max_z-ROAD_SETBACK-hi_z
    if ax1<ax0 or az1<az0:
        return Vector3(NAN,0,NAN)
    var target_x := ax1 if block_index%2==0 else ax0
    var target_z := (az0+az1)*0.5
    return Vector3(target_x,0,target_z)

func _validate_prompt4_candidate(v37: Node,center: Vector3,width: float,depth: float,rotation_y: float) -> Dictionary:
    if not _inside_urban_grid(center,width,depth,rotation_y): return {"valid":false,"reason":"outside_urban_grid_or_on_road_line"}
    if _overlaps_existing(center,width,depth,rotation_y): return {"valid":false,"reason":"footprint_overlap"}
    var hw:=width*0.5; var hd:=depth*0.5; var corners=[Vector2(-hw,-hd),Vector2(hw,-hd),Vector2(-hw,hd),Vector2(hw,hd)]; var heights=[]; var s:=sin(rotation_y); var c:=cos(rotation_y)
    for local in corners:
        var rx:=local.x*c-local.y*s; var rz:=local.x*s+local.y*c; var h:=float(v37.sample_height(center.x+rx,center.z+rz)) if v37.has_method("sample_height") else NAN
        if not is_finite(h): return {"valid":false,"reason":"non_finite_terrain_height"}
        heights.append(h)
    var min_h=heights.min(); var max_h=heights.max(); var mean_h=(heights[0]+heights[1]+heights[2]+heights[3])*0.25
    if _is_over_water(center,mean_h): return {"valid":false,"reason":"water"}
    if max_h-min_h>MAX_SLOPE_DELTA: return {"valid":false,"reason":"slope_gt_2m"}
    if mean_h<SUBSOIL_LIMIT: return {"valid":false,"reason":"subsoil_below_-5m"}
    return {"valid":true,"base_h":max_h+TERRAIN_CLEARANCE}

func _is_over_water(center: Vector3,mean_h: float) -> bool:
    var water=get_tree().current_scene.find_child("WaterPlane",true,false); var water_level:=-INF
    if water!=null: water_level=float(water.global_position.y)
    water_ray.global_position=Vector3(center.x,maxf(mean_h+100.0,100.0),center.z); water_ray.target_position=Vector3(0.0,minf(mean_h-100.0,-100.0)-water_ray.global_position.y,0.0); water_ray.force_raycast_update()
    if water_ray.is_colliding():
        var collider=water_ray.get_collider(); var hit=water_ray.get_collision_point()
        if water_level>-INF and hit.y<=water_level: return true
        if collider!=null:
            var n:=str(collider.name).to_lower()
            if n.contains("water") or n.contains("tevere") or n.contains("river"): return true
    return water_level>-INF and mean_h<=water_level

func _inside_urban_grid(center: Vector3,width: float,depth: float,rotation_y: float) -> bool:
    var grid=get_parent().get_node_or_null("Urban_Grid")
    if grid==null: return false
    var rects:Array=grid.get_meta("lot_rects",[]); if rects.is_empty(): return false
    var ext:=_world_half_extents(width,depth,rotation_y)
    for rv in rects:
        if rv is Dictionary:
            var r:Dictionary=rv; var min_x=float(r.get("min_x",INF)); var max_x=float(r.get("max_x",-INF)); var min_z=float(r.get("min_z",INF)); var max_z=float(r.get("max_z",-INF))
            if center.x-ext.x>min_x+0.5 and center.x+ext.x<max_x-0.5 and center.z-ext.y>min_z+0.5 and center.z+ext.y<max_z-0.5: return true
    return false

func _overlaps_existing(center: Vector3,width: float,depth: float,rotation_y: float) -> bool:
    var ext:=_world_half_extents(width,depth,rotation_y)
    for other in placed_rects:
        var oc:Vector3=other["center"]; var oe:=_world_half_extents(float(other["width"]),float(other["depth"]),float(other["rotation"])); if absf(center.x-oc.x)<ext.x+oe.x-0.05 and absf(center.z-oc.z)<ext.y+oe.y-0.05: return true
    return false

func _reject(index:int,reason:String)->void:
    rejection_counts[reason]=int(rejection_counts.get(reason,0))+1
    print("PROMPT 4 — SCARTATO #",index+1," motivo=",reason)
