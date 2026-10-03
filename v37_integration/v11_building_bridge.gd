extends Node3D
## PROMPT 3: validated placement of the first 40 V11 buildings.
## No roads or interiors are created here. Terrain3D remains authoritative.

const ADAPTER_SCRIPT = "res://city_library/buildings/house_library_adapter.gd"
const VARIATION_SCRIPT = "res://v37_integration/building_variation.gd"
const TEST_COUNT = 40
const MAX_SLOPE_DELTA = 2.0
const SUBSOIL_LIMIT = -5.0

var adapter = null
var variation_script = null
var built = false
var used_seeds = {}
var used_archetypes = {}
var rejection_counts = {}

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

    call_deferred("_wait_for_v37")

func _wait_for_v37() -> void:
    for _i in range(600):
        var v37 = get_parent().get_node_or_null("V37Integration")
        if v37 != null and v37.get("city_root") != null and not (v37.get("map_data") as Dictionary).is_empty():
            _build_library(v37)
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
        var data: Dictionary = buildings[i]
        var pos: Dictionary = data.get("position", {})
        var px = float(pos.get("x", NAN))
        var pz = float(pos.get("z", NAN))
        var size: Dictionary = data.get("size", {})
        var width = maxf(6.0, float(size.get("x", 10.0)))
        var depth = maxf(6.0, float(size.get("z", 10.0)))
        var seed_variation = variation_script.call("variation_for", i, int(i / 4))
        var seed = int(seed_variation["seed"])

        if not is_finite(px) or not is_finite(pz):
            _reject(i, "non_finite_position")
            continue
        if used_seeds.has(seed):
            _reject(i, "duplicate_seed")
            continue

        var center = Vector3(px, 0.0, pz)
        var half_w = width * 0.5
        var half_d = depth * 0.5
        var corners = [
            Vector3(px - half_w, 0.0, pz - half_d),
            Vector3(px + half_w, 0.0, pz - half_d),
            Vector3(px - half_w, 0.0, pz + half_d),
            Vector3(px + half_w, 0.0, pz + half_d)
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
        if not _inside_urban_grid(center, width, depth):
            _reject(i, "outside_urban_grid_or_on_road_line")
            continue

        var style = str(data.get("style", ""))
        var building = adapter.build_for_footprint(width, depth, Vector3(px, 0.0, pz), mean_h, style, i, 0.0)
        if building == null:
            building = adapter.build_for_footprint(width, depth, Vector3(px, 0.0, pz), mean_h, "", i, 0.0)
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
        building.position.y = mean_h
        building.rotation.y = _facade_rotation(center)
        city_root.add_child(building)
        used_seeds[seed] = true
        used_archetypes[int(seed_variation["archetype_index"])] = true
        placed += 1

    built = true
    print("V11 TEST 40 — piazzati: ", placed, " / ", limit)
    print("V11 TEST 40 — scartati: ", limit - placed)
    print("V11 TEST 40 — archetipi diversi: ", used_archetypes.size())
    print("V11 TEST 40 — motivi scarto: ", rejection_counts)

func _is_over_water(center: Vector3, mean_h: float) -> bool:
    var water = get_tree().current_scene.find_child("WaterPlane", true, false)
    var water_level = -INF
    if water != null:
        water_level = float(water.global_position.y)
    var space = get_world_3d().direct_space_state
    var from = Vector3(center.x, maxf(mean_h + 100.0, 100.0), center.z)
    var to = Vector3(center.x, minf(mean_h - 100.0, -100.0), center.z)
    var query = PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    query.collide_with_bodies = true
    var hit = space.intersect_ray(query)
    if hit.has("position"):
        var hit_y = float((hit["position"] as Vector3).y)
        if water_level > -INF and hit_y <= water_level:
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
    if grid != null:
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
    return 0.0

func _reject(index: int, reason: String) -> void:
    rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
    print("V11 TEST 40 — scarto #", index, " motivo=", reason)
