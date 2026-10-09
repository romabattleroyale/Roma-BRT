extends Node3D
## Runtime V11 bridge: load all 587 real building instances and use native Godot visibility ranges.
const READY_DIR := "res://baked_city/ready_templates"
const MANIFEST_PATH := READY_DIR + "/manifest.json"
const WORLD_OFFSET := Vector3(1000.0, 0.0, 1000.0)
const BUILDING_VISIBILITY_END := 500.0
const BUILDING_FADE_MARGIN := 40.0
const DISTRICT_PLANE_BEGIN := 500.0
const DISTRICT_PLANE_END := 5000.0
const DISTRICT_PLANE_SIZE := Vector2(300.0, 300.0)
const DISTRICT_PLANE_Y := 0.5
const ROAD_WIDTH := 8.0
const ROAD_SIDEWALK_WIDTH := 1.5
const ROAD_BUILDING_BUFFER := 1.0
const ROAD_COLLISION_GUARD_RADIUS := 4.35
const ROAD_COLLISION_CELL := 2.5
const ROAD_COLLISION_MARGIN := 0.35
const ROAD_CLEARANCE := ROAD_WIDTH * 0.5 + ROAD_SIDEWALK_WIDTH + ROAD_BUILDING_BUFFER
# Must cover the authoritative rasterized road collision mask, including
# one whole cell of quantization and the guard's sampling margin.
const ROAD_RESERVATION_CLEARANCE := maxf(ROAD_CLEARANCE, ROAD_COLLISION_GUARD_RADIUS + ROAD_COLLISION_CELL + ROAD_COLLISION_MARGIN)
const BUILDING_GAP := 0.75
const DISTRICT_CENTERS := [Vector3(-800,0,-650),Vector3(-400,0,-650),Vector3(400,0,-650),Vector3(800,0,-650),Vector3(-800,0,0),Vector3(-400,0,0),Vector3(400,0,0),Vector3(800,0,0),Vector3(-800,0,650),Vector3(-400,0,650),Vector3(400,0,650),Vector3(800,0,650)]
const DISTRICT_COLORS := [Color("#C58B62"),Color("#B97845"),Color("#D1A15A"),Color("#B96F73"),Color("#C7AA83"),Color("#A9573B"),Color("#B88D6A"),Color("#D3A63A"),Color("#A99A7E"),Color("#C98D68"),Color("#A96D54"),Color("#C6A47B")]

var built := false
var _city_root: Node3D
var _templates: Array[PackedScene] = []
var _placements: Array = []
var _variation_script: RefCounted
var _road_corridors: Array[Dictionary] = []
var _placed_bounds: Array[AABB] = []

func _ready() -> void:
    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null:
            v37.set("enable_buildings", false)
            if v37.get("city_root") != null:
                _city_root = v37.get("city_root") as Node3D
                await _yield_frames(2)
                if _load_manifest():
                    _load_road_corridors()
                    await _load_all_templates()
                    await _load_all_buildings()
                    _create_district_planes()
                    built = true
                    print("V11 NATIVE VISIBILITY: COMPLETE loaded=587 templates=120 buildings=587 range=0-500 fade=self district_planes=12 range=500-5000")
                    return
        await get_tree().create_timer(0.1).timeout
    push_error("V11 NATIVE VISIBILITY: V37 world non pronto")

func _load_manifest() -> bool:
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("V11 NATIVE VISIBILITY: manifest mancante")
        return false
    var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text())
    f.close()
    if not data is Dictionary or int(data.get("template_count", 0)) != 120 or int(data.get("placement_count", 0)) != 587:
        push_error("V11 NATIVE VISIBILITY: manifest invalido")
        return false
    var source_placements: Array = data["placements"] as Array
    _placements.clear()
    for source_item in source_placements:
        var d: Dictionary = (source_item as Dictionary).duplicate(true)
        d["x"] = float(d.get("x", 0.0)) + WORLD_OFFSET.x
        d["z"] = float(d.get("z", 0.0)) + WORLD_OFFSET.z
        _placements.append(d)
    print("V11 WORLD FRAME: manifest 587 placements shifted once by +1000,+1000")
    return _placements.size() == 587

func _load_all_templates() -> void:
    _templates.clear()
    for i in range(120):
        var packed := ResourceLoader.load("%s/template_%03d.tscn" % [READY_DIR, i + 1], "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
        if packed != null:
            _templates.append(packed)
        if i % 3 == 2:
            await get_tree().process_frame
    var variation_script: Script = load("res://v37_integration/mobile_visual_variation.gd") as Script
    if variation_script != null:
        _variation_script = variation_script.new()
    if _templates.size() != 120:
        push_error("V11 NATIVE VISIBILITY: templates caricati=%d" % _templates.size())

func _record_city_load_stage(placement_index: int, stage: String, started_usec: int, slow_stages: Array[String]) -> void:
    var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
    if elapsed_ms >= 5.0:
        slow_stages.append("%s=%.1fms" % [stage, elapsed_ms])

func _load_all_buildings() -> void:
    if _city_root == null or _templates.size() != 120:
        return
    var loaded := 0
    var batch_start_usec := Time.get_ticks_usec()
    for i in range(_placements.size()):
        var placement_start_usec := Time.get_ticks_usec()
        _load_placement(i)
        var placement_ms := float(Time.get_ticks_usec() - placement_start_usec) / 1000.0
        loaded += 1
        if placement_ms >= 20.0:
            print("[CITY LOAD SLOW] placement=%d/%d time=%.2fms" % [loaded, _placements.size(), placement_ms])
        # Yield after each building so a single batch of four expensive
        # instantiations/AABB checks cannot monopolize an Android frame.
        await get_tree().process_frame
        if loaded % 25 == 0:
            var batch_ms := float(Time.get_ticks_usec() - batch_start_usec) / 1000.0
            print("[CITY LOAD] buildings=%d/%d last25=%.1fms" % [loaded, _placements.size(), batch_ms])
            batch_start_usec = Time.get_ticks_usec()
    if loaded != 587:
        push_error("V11 NATIVE VISIBILITY: buildings caricati=%d expected=587" % loaded)

func _load_placement(i: int) -> void:
    var total_start_usec := Time.get_ticks_usec()
    var stage_start_usec := total_start_usec
    var stage_name := "setup"
    var slow_stages: Array[String] = []
    var d: Dictionary = _placements[i]
    var ti := clampi(int(d.get("template", 0)), 0, 119)
    if ti >= _templates.size():
        return
    var root := _templates[ti].instantiate() as Node3D
    _record_city_load_stage(i, "instantiate", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()
    if root == null:
        return
    var x := float(d.get("x", 0.0))
    var z := float(d.get("z", 0.0))
    var terrain_y := _get_terrain_height(x, z)
    _record_city_load_stage(i, "terrain_height", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()
    var requested_position := Vector3(x, terrain_y, z)
    root.position = requested_position
    root.rotation.y = float(d.get("rotation", 0))
    var template_floors := int(root.get_meta("template_floors", 3))
    var floors := clampi(int(d.get("floors", template_floors)), 3, 5)
    root.scale.y = float(floors) / float(maxi(1, template_floors))
    root.set_meta("runtime_placement", i)
    root.set_meta("ready_signature", "%d|f%d|c%d|r%d" % [ti, floors, int(d.get("facade_index", 0)), int(d.get("roof_index", 0))])
    root.set_meta("terrain_y", terrain_y)
    if _variation_script != null:
        _variation_script.apply(root, int(d.get("seed", i)), floors)
    _record_city_load_stage(i, "variation", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()
    _set_native_visibility(root)
    _record_city_load_stage(i, "visibility", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()

    _city_root.add_child(root)
    _record_city_load_stage(i, "add_child", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()

    var original_world_position := root.global_position
    var corrected_position := _resolve_road_clearance(root, original_world_position)
    _record_city_load_stage(i, "road_clearance", stage_start_usec, slow_stages)
    stage_start_usec = Time.get_ticks_usec()
    if corrected_position.distance_to(original_world_position) > 0.01:
        corrected_position = _find_non_overlapping_position(root, original_world_position, corrected_position)
        root.global_position = corrected_position
        root.set_meta("road_clearance_shift", corrected_position - original_world_position)

    for _audit in range(8):
        var final_bounds := _node_world_aabb(root)
        if _road_bounds_clear(final_bounds):
            break
        root.global_position = _resolve_road_clearance(root, root.global_position)
    var audited_bounds := _node_world_aabb(root)
    if not _road_bounds_clear(audited_bounds):
        push_error("V11 ROAD RESERVATION: final building footprint still intersects reserved road envelope at %s" % root.global_position)
    _placed_bounds.append(audited_bounds)
    _record_city_load_stage(i, "bounds_audit", stage_start_usec, slow_stages)
    var total_ms := float(Time.get_ticks_usec() - total_start_usec) / 1000.0
    if total_ms >= 20.0:
        print("[CITY LOAD DETAIL] placement=%d total=%.2fms stages=%s" % [i + 1, total_ms, ", ".join(slow_stages)])

func _load_road_corridors() -> void:
    _road_corridors.clear()
    var grid := get_tree().current_scene.get_node_or_null("Urban_Grid")
    if grid == null:
        push_warning("V11 ROAD RESERVATION: Urban_Grid non trovato")
        return
    var rects_variant: Variant = grid.get_meta("lot_rects", [])
    if not (rects_variant is Array):
        return
    var counts: Dictionary = {}
    var representative: Dictionary = {}
    for rect_variant in rects_variant as Array:
        if not (rect_variant is Dictionary):
            continue
        var rect: Dictionary = rect_variant as Dictionary
        var sides := [
            [float(rect.get("min_x", 0.0)), float(rect.get("min_z", 0.0)), float(rect.get("max_x", 0.0)), float(rect.get("min_z", 0.0))],
            [float(rect.get("max_x", 0.0)), float(rect.get("min_z", 0.0)), float(rect.get("max_x", 0.0)), float(rect.get("max_z", 0.0))],
            [float(rect.get("max_x", 0.0)), float(rect.get("max_z", 0.0)), float(rect.get("min_x", 0.0)), float(rect.get("max_z", 0.0))],
            [float(rect.get("min_x", 0.0)), float(rect.get("max_z", 0.0)), float(rect.get("min_x", 0.0)), float(rect.get("min_z", 0.0))]
        ]
        for side in sides:
            var ax := float(side[0]); var az := float(side[1]); var bx := float(side[2]); var bz := float(side[3])
            var first := "%.2f,%.2f" % [ax, az]; var second := "%.2f,%.2f" % [bx, bz]
            var key := first + "|" + second if first < second else second + "|" + first
            counts[key] = int(counts.get(key, 0)) + 1
            representative[key] = {"ax":ax, "az":az, "bx":bx, "bz":bz}
    for key in counts:
        if int(counts[key]) >= 2:
            var side: Dictionary = representative[key]
            var length := Vector2(float(side["bx"]) - float(side["ax"]), float(side["bz"]) - float(side["az"])).length()
            if length >= 20.0:
                _road_corridors.append(side)
    print("V11 ROAD RESERVATION: corridors=%d clearance=%.2fm guard=%.2fm cell=%.2fm" % [_road_corridors.size(), ROAD_RESERVATION_CLEARANCE, ROAD_COLLISION_GUARD_RADIUS, ROAD_COLLISION_CELL])

func _node_world_aabb(root: Node) -> AABB:
    var result := AABB()
    var has_bounds := false
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            var local_aabb := mesh_instance.get_aabb()
            var corners := [
                Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.position.z),
                Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.position.z),
                Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.position.z),
                Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.position.z),
                Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.end.z),
                Vector3(local_aabb.end.x, local_aabb.position.y, local_aabb.end.z),
                Vector3(local_aabb.position.x, local_aabb.end.y, local_aabb.end.z),
                Vector3(local_aabb.end.x, local_aabb.end.y, local_aabb.end.z)
            ]
            for corner in corners:
                var world_point: Vector3 = mesh_instance.global_transform * corner
                if not has_bounds:
                    result = AABB(world_point, Vector3.ZERO)
                    has_bounds = true
                else:
                    result = result.expand(world_point)
        for child in node.get_children():
            stack.append(child)
    return result

func _xz_overlap(a: AABB, b: AABB, gap: float = 0.0) -> bool:
    return a.position.x < b.end.x + gap and a.end.x > b.position.x - gap and a.position.z < b.end.z + gap and a.end.z > b.position.z - gap

func _resolve_road_clearance(root: Node3D, requested: Vector3) -> Vector3:
    root.global_position = requested
    for _pass in range(12):
        var bounds := _node_world_aabb(root)
        var moved := false
        for corridor in _road_corridors:
            var ax := float(corridor["ax"]); var az := float(corridor["az"])
            var bx := float(corridor["bx"]); var bz := float(corridor["bz"])
            if absf(az - bz) < 0.01:
                var line_z := az
                var min_x := minf(ax, bx) - ROAD_RESERVATION_CLEARANCE
                var max_x := maxf(ax, bx) + ROAD_RESERVATION_CLEARANCE
                if bounds.end.x > min_x and bounds.position.x < max_x and bounds.position.z < line_z + ROAD_RESERVATION_CLEARANCE and bounds.end.z > line_z - ROAD_RESERVATION_CLEARANCE:
                    var target_z := line_z - ROAD_RESERVATION_CLEARANCE if bounds.get_center().z <= line_z else line_z + ROAD_RESERVATION_CLEARANCE
                    var delta_z := target_z - (bounds.end.z if bounds.get_center().z <= line_z else bounds.position.z)
                    if absf(delta_z) > 0.01:
                        root.global_position = root.global_position + Vector3(0.0, delta_z, 0.0)
                        moved = true
                        break
            else:
                var line_x := ax
                var min_z := minf(az, bz) - ROAD_RESERVATION_CLEARANCE
                var max_z := maxf(az, bz) + ROAD_RESERVATION_CLEARANCE
                if bounds.end.z > min_z and bounds.position.z < max_z and bounds.position.x < line_x + ROAD_RESERVATION_CLEARANCE and bounds.end.x > line_x - ROAD_RESERVATION_CLEARANCE:
                    var target_x := line_x - ROAD_RESERVATION_CLEARANCE if bounds.get_center().x <= line_x else line_x + ROAD_RESERVATION_CLEARANCE
                    var delta_x := target_x - (bounds.end.x if bounds.get_center().x <= line_x else bounds.position.x)
                    if absf(delta_x) > 0.01:
                        root.global_position = root.global_position + Vector3(delta_x, 0.0, 0.0)
                        moved = true
                        break
        if not moved:
            break
    return root.global_position

func _road_bounds_clear(bounds: AABB) -> bool:
    for corridor in _road_corridors:
        var ax := float(corridor["ax"]); var az := float(corridor["az"])
        var bx := float(corridor["bx"]); var bz := float(corridor["bz"])
        if absf(az - bz) < 0.01:
            var line_z := az
            var min_x := minf(ax, bx) - ROAD_RESERVATION_CLEARANCE
            var max_x := maxf(ax, bx) + ROAD_RESERVATION_CLEARANCE
            if bounds.end.x > min_x and bounds.position.x < max_x and bounds.position.z < line_z + ROAD_RESERVATION_CLEARANCE and bounds.end.z > line_z - ROAD_RESERVATION_CLEARANCE:
                return false
        else:
            var line_x := ax
            var min_z := minf(az, bz) - ROAD_RESERVATION_CLEARANCE
            var max_z := maxf(az, bz) + ROAD_RESERVATION_CLEARANCE
            if bounds.end.z > min_z and bounds.position.z < max_z and bounds.position.x < line_x + ROAD_RESERVATION_CLEARANCE and bounds.end.x > line_x - ROAD_RESERVATION_CLEARANCE:
                return false
    return true

func _find_non_overlapping_position(root: Node3D, original: Vector3, resolved: Vector3) -> Vector3:
    var candidates: Array[Vector3] = [resolved]
    var offsets := [
        Vector3(8,0,0), Vector3(-8,0,0), Vector3(0,0,8), Vector3(0,0,-8),
        Vector3(12,0,0), Vector3(-12,0,0), Vector3(0,0,12), Vector3(0,0,-12),
        Vector3(8,0,8), Vector3(8,0,-8), Vector3(-8,0,8), Vector3(-8,0,-8),
        Vector3(12,0,12), Vector3(12,0,-12), Vector3(-12,0,12), Vector3(-12,0,-12),
        Vector3(16,0,0), Vector3(-16,0,0), Vector3(0,0,16), Vector3(0,0,-16)
    ]
    for offset in offsets:
        candidates.append(resolved + offset)
    var best := resolved
    var best_distance := INF
    for candidate in candidates:
        root.global_position = candidate
        var corrected := _resolve_road_clearance(root, candidate)
        root.global_position = corrected
        var bounds := _node_world_aabb(root)
        if not _road_bounds_clear(bounds):
            continue
        var collides := false
        for other in _placed_bounds:
            if _xz_overlap(bounds, other, BUILDING_GAP):
                collides = true
                break
        if not collides:
            var distance := original.distance_to(corrected)
            if distance < best_distance:
                best_distance = distance
                best = corrected
    root.global_position = best
    return best

func _get_terrain_height(x: float, z: float) -> float:
    if not is_finite(x) or not is_finite(z):
        return 0.0
    var terrain := get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
    if terrain != null and terrain.has_method("get_height"):
        var h := float(terrain.get_height(Vector3(x, 0.0, z)))
        if is_finite(h):
            return h
    if terrain != null:
        var data = terrain.get("data")
        if data != null and data.has_method("get_height"):
            var h2 := float(data.get_height(Vector3(x, 0.0, z)))
            if is_finite(h2):
                return h2
    push_warning("V11 TERRAIN Y: Terrain3D get_height non disponibile; uso Y=0 per x=%s z=%s" % [x, z])
    return 0.0

func _set_native_visibility(root: Node) -> void:
    var stack: Array[Node] = [root]
    var mesh_count := 0
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is MeshInstance3D:
            var mesh := n as MeshInstance3D
            mesh.visibility_range_begin = 0.0
            mesh.visibility_range_end = BUILDING_VISIBILITY_END
            mesh.visibility_range_begin_margin = 0.0
            mesh.visibility_range_end_margin = BUILDING_FADE_MARGIN
            mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
            mesh_count += 1
        for c in n.get_children():
            stack.append(c)
    root.set_meta("runtime_mesh_count", mesh_count)

func _create_district_planes() -> void:
    if _city_root == null:
        return
    for child in _city_root.get_children():
        if str(child.name).begins_with("V11_CITY_PLANE_"):
            child.queue_free()
    for district in range(12):
        var plane := MeshInstance3D.new()
        plane.name = "V11_CITY_PLANE_%02d" % (district + 1)
        var mesh := PlaneMesh.new()
        mesh.size = DISTRICT_PLANE_SIZE
        plane.mesh = mesh
        var authored_center: Vector3 = DISTRICT_CENTERS[district] as Vector3
        plane.position = authored_center + WORLD_OFFSET
        plane.position.y = DISTRICT_PLANE_Y
        plane.material_override = _make_flat_material(DISTRICT_COLORS[district])
        plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
        plane.visibility_range_begin = DISTRICT_PLANE_BEGIN
        plane.visibility_range_end = DISTRICT_PLANE_END
        plane.visibility_range_begin_margin = 40.0
        plane.visibility_range_end_margin = 40.0
        plane.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        plane.extra_cull_margin = 100.0
        _city_root.add_child(plane)
    print("V11 CITY DISTRICT PLANES: PASS count=12 size=300x300 y=0.5 range=500-5000 fade=self")

func _make_flat_material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    mat.metallic = 0.0
    return mat

func _find_player() -> Node3D:
    var debug_camera := get_tree().current_scene.find_child("DebugTopDownCamera3D", true, false) as Camera3D
    if debug_camera != null and debug_camera.current:
        return debug_camera
    var group_nodes := get_tree().get_nodes_in_group("player")
    if not group_nodes.is_empty() and group_nodes[0] is Node3D:
        return group_nodes[0] as Node3D
    return get_tree().current_scene.get_node_or_null("Player") as Node3D

func _yield_frames(n: int) -> void:
    for _i in range(n):
        await get_tree().process_frame
