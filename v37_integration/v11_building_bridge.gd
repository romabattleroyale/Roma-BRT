extends Node3D
## PROMPT 3: actually instantiate the first 40 V11 buildings.
## Validation happens before instantiation. No roads, interiors or terrain edits.
## Generation is intentionally staggered across frames to avoid blocking the runtime.

const ADAPTER_SCRIPT = "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT = "res://v37_integration/building_variation.gd"
const TEST_COUNT = 40
const MAX_SLOPE_DELTA = 2.0
const SUBSOIL_LIMIT = -5.0
const LOT_MARGIN = 15.0

var adapter = null
var variation_script = null
var built = false
var used_seeds = {}
var used_archetypes = {}
var rejection_counts = {}
var placed_centers = []
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
    var placed = 0

    for i in range(limit):
        await get_tree().process_frame
        var data: Dictionary = buildings[i]
        var size: Dictionary = data.get("size", {})
        var width = maxf(6.0, float(size.get("x", 10.0)))
        var depth = maxf(6.0, float(size.get("z", 10.0)))
        var seed_variation = variation_script.call("variation_for", i, int(i / 4))
        var seed = int(seed_variation["seed"])

        if used_seeds.has(seed):
            _reject(i, "duplicate_seed")
            continue

        var center = _grid_test_position(i, width, depth)
        if not center.is_finite():
            _reject(i, "non_finite_position")
            continue
        if not _inside_urban_grid(center, width, depth):
            _reject(i, "outside_urban_grid_or_on_road_line")
            continue

        var half_w = width * 0.5
        var half_d = depth * 0.5
        var corners = [
            Vector3(center.x - half_w, 0.0, center.z - half_d),
            Vector3(center.x + half_w, 0.0, center.z - half_d),
            Vector3(center.x - half_w, 0.0, center.z + half_d),
            Vector3(center.x + half_w, 0.0, center.z + half_d)
        ]
        var heights = []
        var valid_corners = true
        for corner in corners:
            var h = float(v37.sample_height(corner.x, corner.z)) if v37.has_method("sample_height") else NAN
            if not is_finite(h):
                valid_corners = false
                break
            heights.append(h)
        if not valid_corners:
            _reject(i, "non_finite_terrain_height")
            continue

        var min_h = heights.min()
        var max_h = heights.max()
        var mean_h = (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25

        if _is_over_water(center, mean_h):
            _reject(i, "water")
            continue
        if max_h - min_h > MAX_SLOPE_DELTA:
            _reject(i, "slope_gt_2m")
            continue
        if mean_h < SUBSOIL_LIMIT:
            _reject(i, "subsoil_below_-5m")
            continue
        if _overlaps_existing(center, width, depth):
            _reject(i, "footprint_overlap")
            continue

        var rotation_y = _facade_rotation(center)
        var style = str(data.get("style", ""))
        var building = adapter.build_for_footprint(width, depth, Vector3(center.x, 0.0, center.z), mean_h, style, i, rotation_y)
        if building == null:
            building = adapter.build_for_footprint(width, depth, Vector3(center.x, 0.0, center.z), mean_h, "", i, rotation_y)
        if building == null:
            _reject(i, "library_build_failed")
            continue

        if not building.position.is_finite():
            building.queue_free()
            _reject(i, "non_finite_building_transform")
            continue

        building.name = str(data.get("id", "V11Building_%03d" % i))
        building.set_meta("v11_seed", seed)
        building.set_meta("v11_variation", seed_variation)
        building.set_meta("v11_source_position", data.get("position", {}))
        building.set_meta("v11_source_id", data.get("id", ""))
        building.position.y = mean_h
        building.rotation.y = rotation_y
        city_root.add_child(building)
        placed_centers.append(center)
        used_seeds[seed] = true
        used_archetypes[int(seed_variation["archetype_index"])] = true
        placed += 1
        print("V11 TEST 40 — piazzato #", i + 1, " id=", building.name, " seed=", seed, " archetype=", seed_variation["archetype_index"], " pos=", center)
        await get_tree().process_frame

    built = true
    print("V11 TEST 40 — PIAZZATI: ", placed, " / ", limit)
    print("V11 TEST 40 — SCARTATI: ", limit - placed)
    print("V11 TEST 40 — ARCHETIPI DIVERSI: ", used_archetypes.size())
    print("V11 TEST 40 — MOTIVI SCARTO: ", rejection_counts)

func _grid_test_position(index: int, width: float, depth: float) -> Vector3:
    var block_index = 0 if index < 20 else 1
    var slot = index if index < 20 else index - 20
    var row = int(slot / 10)
    var col = slot % 10
    var x_min = 520.0 if block_index == 0 else 900.0
    var x_max = 900.0 if block_index == 0 else 1390.0
    var z_min = 420.0
    var z_max = 760.0
    var usable_x_min = x_min + LOT_MARGIN + width * 0.5
    var usable_x_max = x_max - LOT_MARGIN - width * 0.5
    var usable_z_min = z_min + LOT_MARGIN + depth * 0.5
    var usable_z_max = z_max - LOT_MARGIN - depth * 0.5
    if usable_x_max < usable_x_min or usable_z_max < usable_z_min:
        return Vector3(NAN, NAN, NAN)
    var x = lerpf(usable_x_min, usable_x_max, float(col) / 9.0)
    var z = lerpf(usable_z_min, usable_z_max, float(row))
    return Vector3(x, 0.0, z)

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

func _inside_urban_grid(center: Vector3, width: float, depth: float) -> bool:
    var grid = get_parent().get_node_or_null("Urban_Grid")
    if grid == null:
        return false
    var rects: Array = grid.get_meta("lot_rects", [])
    if rects.is_empty():
        return false
    for rect_variant in rects:
        if not (rect_variant is Dictionary):
            continue
        var rect: Dictionary = rect_variant
        var min_x = float(rect.get("min_x", INF))
        var max_x = float(rect.get("max_x", -INF))
        var min_z = float(rect.get("min_z", INF))
        var max_z = float(rect.get("max_z", -INF))
        if center.x - width * 0.5 > min_x + 0.5 and center.x + width * 0.5 < max_x - 0.5 and center.z - depth * 0.5 > min_z + 0.5 and center.z + depth * 0.5 < max_z - 0.5:
            return true
    return false

func _facade_rotation(center: Vector3) -> float:
    var grid = get_parent().get_node_or_null("Urban_Grid")
    if grid == null:
        return 0.0
    var sides: Array = grid.get_meta("lot_sides", [])
    var best_distance = INF
    var best_angle = 0.0
    for side_variant in sides:
        if not (side_variant is Dictionary):
            continue
        var side: Dictionary = side_variant
        var a = Vector3(float(side.get("ax", 0.0)), 0.0, float(side.get("az", 0.0)))
        var b = Vector3(float(side.get("bx", 0.0)), 0.0, float(side.get("bz", 0.0)))
        var ab = b - a
        var len_sq = ab.length_squared()
        if len_sq <= 0.0001:
            continue
        var t = clampf((center - a).dot(ab) / len_sq, 0.0, 1.0)
        var closest = a + ab * t
        var distance = center.distance_to(closest)
        if distance < best_distance:
            best_distance = distance
            best_angle = atan2(ab.x, ab.z)
    return best_angle

func _overlaps_existing(center: Vector3, width: float, depth: float) -> bool:
    for other in placed_centers:
        if absf(center.x - other.x) < width + 1.0 and absf(center.z - other.z) < depth + 1.0:
            return true
    return false

func _reject(index: int, reason: String) -> void:
    rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
    print("V11 TEST 40 — scarto #", index, " motivo=", reason)
