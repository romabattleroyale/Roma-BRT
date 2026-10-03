extends Node3D
## PROMPT 4: compact Roman-style urban blocks from the first 40 V11 candidates.
## Validation remains mandatory before instantiation. No roads, interiors or terrain edits.
## Buildings form perimeter U-blocks with outward-facing doors and an open courtyard.
## Android optimization: deterministic anchors and frame-yielded construction avoid startup spikes.

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
var built = false
var used_seeds = {}
var used_archetypes = {}
var rejection_counts = {}
var placed_rects = []
var water_ray: RayCast3D

func _ready() -> void:
    var adapter_resource = load(ADAPTER_SCRIPT)
    if adapter_resource == null:
        push_error("V11 Building Bridge: impossibile caricare house_library_adapter.gd")
        return
    adapter = adapter_resource.new()

    variation_script = load(VARIATION_SCRIPT)
    if variation_script == null:
        push_error("V11 Building Bridge: impossibile caricare building_variation.gd")
        return

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
    if built or adapter == null or variation_script == null:
        return
    if not adapter.initialize():
        push_warning("V11 Building Bridge: City Library V11 non inizializzabile")
        return

    var city_root = v37.get("city_root") as Node3D
    var map_data = v37.get("map_data") as Dictionary
    var buildings: Array = map_data.get("city", {}).get("buildings", [])
    var limit = min(TEST_COUNT, buildings.size())

    var candidates: Array = []
    for i in range(limit):
        var data: Dictionary = buildings[i]
        var size: Dictionary = data.get("size", {})
        candidates.append({
            "index": i,
            "data": data,
            "width": maxf(6.0, float(size.get("x", 10.0))),
            "depth": maxf(6.0, float(size.get("z", 10.0))),
            "variation": variation_script.call("variation_for", i, int(i / 4))
        })

    var placed = 0
    var blocks = _urban_lot_rects()
    var block_count = min(blocks.size(), int(ceil(float(limit) / 5.0)))

    for block_index in range(block_count):
        var group: Array = []
        var first = block_index * 5
        var last = min(first + 5, candidates.size())
        for i in range(first, last):
            group.append(candidates[i])
        if group.is_empty():
            continue

        var rect: Dictionary = blocks[block_index]
        var layout = _make_compact_layout(group)
        var anchor = _direct_anchor(rect, layout, block_index)
        var valid_group = 0

        for item in layout:
            await _android_yield()

            var candidate: Dictionary = item["candidate"]
            var index: int = int(candidate["index"])
            var data: Dictionary = candidate["data"]
            var width: float = float(candidate["width"])
            var depth: float = float(candidate["depth"])
            var variation: Dictionary = candidate["variation"]
            var seed: int = int(variation["seed"])
            var center: Vector3 = anchor + item["offset"]
            center.y = 0.0
            var rotation_y: float = float(item["rotation"])

            if used_seeds.has(seed):
                _reject(index, "duplicate_seed")
                continue
            if not center.is_finite():
                _reject(index, "non_finite_position")
                continue
            if not _inside_urban_grid(center, width, depth, rotation_y):
                _reject(index, "outside_urban_grid_or_on_road_line")
                continue

            var validation = _validate_prompt4_candidate(v37, center, width, depth, rotation_y, rect)
            if not validation["valid"]:
                _reject(index, str(validation["reason"]))
                continue

            # Use the highest footprint corner as the base plane. This prevents the
            # lower side of a building from being buried when the terrain slopes.
            var base_h: float = float(validation["base_h"])
            var style = str(data.get("style", ""))
            var building = adapter.build_for_footprint(width, depth, Vector3(center.x, 0.0, center.z), base_h, style, index, rotation_y)
            if building == null:
                building = adapter.build_for_footprint(width, depth, Vector3(center.x, 0.0, center.z), base_h, "", index, rotation_y)
            if building == null:
                _reject(index, "library_build_failed")
                continue

            if not building.position.is_finite():
                building.queue_free()
                _reject(index, "non_finite_building_transform")
                continue

            building.name = str(data.get("id", "V11Building_%03d" % index))
            building.set_meta("v11_seed", seed)
            building.set_meta("v11_variation", variation)
            building.set_meta("v11_source_position", data.get("position", {}))
            building.set_meta("v11_source_id", data.get("id", ""))
            building.set_meta("prompt4_block", str(rect.get("id", "BLOCK_%02d" % block_index)))
            building.set_meta("prompt4_slot", int(item["slot"]))
            building.set_meta("prompt4_compact", true)
            building.set_meta("prompt4_safety_corridor_m", SAFETY_CORRIDOR)
            building.set_meta("prompt4_courtyard", true)
            building.set_meta("prompt4_terrain_base_h", base_h)
            building.position.y = base_h
            building.rotation.y = rotation_y
            city_root.add_child(building)

            placed_rects.append({
                "center": center,
                "width": width,
                "depth": depth,
                "rotation": rotation_y,
                "block": block_index
            })
            used_seeds[seed] = true
            used_archetypes[int(variation["archetype_index"])] = true
            valid_group += 1
            placed += 1
            print("PROMPT 4 — piazzato #", index + 1, " id=", building.name, " block=", rect.get("id", ""), " slot=", item["slot"], " seed=", seed, " archetype=", variation["archetype_index"], " pos=", center, " base_y=", base_h)
            await _android_yield()

        print("PROMPT 4 — ", rect.get("id", "BLOCK_%02d" % block_index), " edifici compatti: ", valid_group, " / ", group.size())

    built = true
    print("PROMPT 4 — PIAZZATI: ", placed, " / ", limit)
    print("PROMPT 4 — SCARTATI: ", limit - placed)
    print("PROMPT 4 — ARCHETIPI DIVERSI: ", used_archetypes.size())
    print("PROMPT 4 — ISOLATI TARGET: ", block_count)
    print("PROMPT 4 — SAFETY CORRIDOR: ", SAFETY_CORRIDOR, "m")
    print("PROMPT 4 — ROAD SETBACK: ", ROAD_SETBACK, "m")
    print("PROMPT 4 — BATCH PAUSE FRAMES: ", BATCH_PAUSE_FRAMES)
    print("PROMPT 4 — TERRAIN CLEARANCE: ", TERRAIN_CLEARANCE, "m")
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
    return [
        {"id":"BLOCK_NW", "min_x":520.0, "max_x":900.0, "min_z":420.0, "max_z":760.0},
        {"id":"BLOCK_NE", "min_x":900.0, "max_x":1390.0, "min_z":420.0, "max_z":760.0},
        {"id":"BLOCK_W1", "min_x":520.0, "max_x":900.0, "min_z":760.0, "max_z":1080.0},
        {"id":"BLOCK_E1", "min_x":900.0, "max_x":1390.0, "min_z":760.0, "max_z":1080.0},
        {"id":"BLOCK_W2", "min_x":520.0, "max_x":900.0, "min_z":1080.0, "max_z":1400.0},
        {"id":"BLOCK_E2", "min_x":900.0, "max_x":1390.0, "min_z":1080.0, "max_z":1400.0},
        {"id":"BLOCK_W3", "min_x":520.0, "max_x":900.0, "min_z":1400.0, "max_z":1660.0},
        {"id":"BLOCK_E3", "min_x":900.0, "max_x":1390.0, "min_z":1400.0, "max_z":1660.0}
    ]

func _make_compact_layout(group: Array) -> Array:
    # Five buildings form a perimeter U: three continuous on the rear edge,
    # one on each side. Side doors face outward; the courtyard remains open.
    var layout: Array = []
    if group.size() < 5:
        return layout

    var w0 = float(group[0]["width"])
    var w1 = float(group[1]["width"])
    var w2 = float(group[2]["width"])
    var d0 = float(group[0]["depth"])
    var d1 = float(group[1]["depth"])
    var d2 = float(group[2]["depth"])
    var outer_depth = maxf(d0, maxf(d1, d2))

    var x0 = -(w0 + w1 + w2) * 0.5 + w0 * 0.5
    var x1 = x0 + w0 * 0.5 + w1 * 0.5
    var x2 = x1 + w1 * 0.5 + w2 * 0.5
    var top_z = -outer_depth * 0.5

    layout.append({"candidate":group[0], "offset":Vector3(x0, 0.0, top_z + (outer_depth - d0) * 0.5), "rotation":0.0, "slot":0})
    layout.append({"candidate":group[1], "offset":Vector3(x1, 0.0, top_z + (outer_depth - d1) * 0.5), "rotation":0.0, "slot":1})
    layout.append({"candidate":group[2], "offset":Vector3(x2, 0.0, top_z + (outer_depth - d2) * 0.5), "rotation":0.0, "slot":2})

    # At 90 degrees the source width/depth swap in world space.
    var left_world_w = float(group[3]["depth"])
    var left_world_d = float(group[3]["width"])
    var right_world_w = float(group[4]["depth"])
    var right_world_d = float(group[4]["width"])
    var left_x = x0 - w0 * 0.5 - left_world_w * 0.5
    var right_x = x2 + w2 * 0.5 + right_world_w * 0.5
    var side_z = top_z + outer_depth * 0.5 + maxf(left_world_d, right_world_d) * 0.5

    layout.append({"candidate":group[3], "offset":Vector3(left_x, 0.0, side_z), "rotation":PI * 0.5, "slot":3})
    layout.append({"candidate":group[4], "offset":Vector3(right_x, 0.0, side_z), "rotation":-PI * 0.5, "slot":4})
    return layout

func _world_half_extents(width: float, depth: float, rotation_y: float) -> Vector2:
    var quarter = fmod(absf(rotation_y), PI)
    if absf(quarter - PI * 0.5) < 0.01:
        return Vector2(depth * 0.5, width * 0.5)
    return Vector2(width * 0.5, depth * 0.5)

func _direct_anchor(rect: Dictionary, layout: Array, block_index: int) -> Vector3:
    var min_x = float(rect.get("min_x", 0.0))
    var max_x = float(rect.get("max_x", 0.0))
    var min_z = float(rect.get("min_z", 0.0))
    var max_z = float(rect.get("max_z", 0.0))

    var local_min_x = INF
    var local_max_x = -INF
    var local_min_z = INF
    var local_max_z = -INF
    for item in layout:
        var c: Dictionary = item["candidate"]
        var p: Vector3 = item["offset"]
        var ext = _world_half_extents(float(c["width"]), float(c["depth"]), float(item["rotation"]))
        local_min_x = minf(local_min_x, p.x - ext.x)
        local_max_x = maxf(local_max_x, p.x + ext.x)
        local_min_z = minf(local_min_z, p.y - ext.y)
        local_max_z = maxf(local_max_z, p.y + ext.y)

    var anchor_min_x = min_x + ROAD_SETBACK - local_min_x
    var anchor_max_x = max_x - ROAD_SETBACK - local_max_x
    var anchor_min_z = min_z + ROAD_SETBACK - local_min_z
    var anchor_max_z = max_z - ROAD_SETBACK - local_max_z
    if anchor_max_x < anchor_min_x or anchor_max_z < anchor_min_z:
        return Vector3(NAN, 0.0, NAN)

    var target_x = anchor_max_x if block_index % 2 == 0 else anchor_min_x
    var target_z = (anchor_min_z + anchor_max_z) * 0.5
    return Vector3(target_x, 0.0, target_z)

func _validate_prompt4_candidate(v37: Node, center: Vector3, width: float, depth: float, rotation_y: float, rect: Dictionary, check_overlap: bool = true) -> Dictionary:
    if not center.is_finite():
        return {"valid":false, "reason":"non_finite_position"}
    if not _inside_urban_grid(center, width, depth, rotation_y):
        return {"valid":false, "reason":"outside_urban_grid_or_on_road_line"}
    if check_overlap and _overlaps_existing(center, width, depth, rotation_y):
        return {"valid":false, "reason":"footprint_overlap"}

    var half_w = width * 0.5
    var half_d = depth * 0.5
    var corners = []
    var local_corners = [Vector2(-half_w, -half_d), Vector2(half_w, -half_d), Vector2(-half_w, half_d), Vector2(half_w, half_d)]
    var sin_r = sin(rotation_y)
    var cos_r = cos(rotation_y)
    for local in local_corners:
        var rx = local.x * cos_r - local.y * sin_r
        var rz = local.x * sin_r + local.y * cos_r
        corners.append(Vector3(center.x + rx, 0.0, center.z + rz))

    var heights = []
    for corner in corners:
        var h = float(v37.sample_height(corner.x, corner.z)) if v37.has_method("sample_height") else NAN
        if not is_finite(h):
            return {"valid":false, "reason":"non_finite_terrain_height"}
        heights.append(h)

    var min_h = heights.min()
    var max_h = heights.max()
    var mean_h = (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25
    if _is_over_water(center, mean_h):
        return {"valid":false, "reason":"water"}
    if max_h - min_h > MAX_SLOPE_DELTA:
        return {"valid":false, "reason":"slope_gt_2m"}
    if mean_h < SUBSOIL_LIMIT:
        return {"valid":false, "reason":"subsoil_below_-5m"}

    # Critical fix: the whole building footprint starts at the highest terrain
    # corner, so no facade/door/floor can be buried by a sloping Terrain3D cell.
    var base_h = max_h + TERRAIN_CLEARANCE
    return {"valid":true, "reason":"", "mean_h":mean_h, "base_h":base_h, "min_h":min_h, "max_h":max_h}

func _is_over_water(center: Vector3, mean_h: float) -> bool:
    var water = get_tree().current_scene.find_child("WaterPlane", true, false)
    var water_level = -INF
    if water != null:
        water_level = float(water.global_position.y)

    water_ray.global_position = Vector3(center.x, maxf(mean_h + 100.0, 100.0), center.z)
    water_ray.target_position = Vector3(0.0, minf(mean_h - 100.0, -100.0) - water_ray.global_position.y, 0.0)
    water_ray.force_raycast_update()
    if water_ray.is_colliding():
        var collider = water_ray.get_collider()
        var hit_position = water_ray.get_collision_point()
        if water_level > -INF and hit_position.y <= water_level:
            return true
        if collider != null:
            var collider_name = str(collider.name).to_lower()
            if collider_name.contains("water") or collider_name.contains("tevere") or collider_name.contains("river"):
                return true
    return water_level > -INF and mean_h <= water_level

func _inside_urban_grid(center: Vector3, width: float, depth: float, rotation_y: float = 0.0) -> bool:
    var grid = get_parent().get_node_or_null("Urban_Grid")
    if grid == null:
        return false
    var rects: Array = grid.get_meta("lot_rects", [])
    if rects.is_empty():
        return false
    var ext = _world_half_extents(width, depth, rotation_y)
    for rect_variant in rects:
        if not (rect_variant is Dictionary):
            continue
        var rect: Dictionary = rect_variant
        var min_x = float(rect.get("min_x", INF))
        var max_x = float(rect.get("max_x", -INF))
        var min_z = float(rect.get("min_z", INF))
        var max_z = float(rect.get("max_z", -INF))
        if center.x - ext.x > min_x + 0.5 and center.x + ext.x < max_x - 0.5 and center.z - ext.y > min_z + 0.5 and center.z + ext.y < max_z - 0.5:
            return true
    return false

func _overlaps_existing(center: Vector3, width: float, depth: float, rotation_y: float = 0.0) -> bool:
    var ext = _world_half_extents(width, depth, rotation_y)
    for other in placed_rects:
        var oc: Vector3 = other["center"]
        var oext = _world_half_extents(float(other["width"]), float(other["depth"]), float(other.get("rotation", 0.0)))
        if absf(center.x - oc.x) < (ext.x + oext.x) - 0.01 and absf(center.z - oc.z) < (ext.y + oext.y) - 0.01:
            return true
    return false

func _reject(index: int, reason: String) -> void:
    rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
    print("PROMPT 4 — scarto #", index + 1, " motivo=", reason)
