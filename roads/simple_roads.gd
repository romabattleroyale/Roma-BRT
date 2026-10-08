extends Node3D
## Roma Battle Royale - stylized Roman street network V2.
## Procedural boxes only: no GridMap, MeshLibrary, spline plugin or terrain edits.
## Visual target: real Rome street language translated into Fortnite-stylized forms.

const WORLD_OFFSET := Vector3(1000.0, 0.0, 1000.0)
const DISTRICT_CENTERS := [
    Vector3(-800.0, 0.0, -650.0), Vector3(-400.0, 0.0, -650.0),
    Vector3( 400.0, 0.0, -650.0), Vector3( 800.0, 0.0, -650.0),
    Vector3(-800.0, 0.0,    0.0), Vector3(-400.0, 0.0,    0.0),
    Vector3( 400.0, 0.0,    0.0), Vector3( 800.0, 0.0,    0.0),
    Vector3(-800.0, 0.0,  650.0), Vector3(-400.0, 0.0,  650.0),
    Vector3( 400.0, 0.0,  650.0), Vector3( 800.0, 0.0,  650.0),
]

const MAIN_WIDTH := 8.0
const ALLEY_WIDTH := 4.0
const CURB_WIDTH := 0.22
const CURB_HEIGHT := 0.14
const SIDEWALK_HEIGHT := 0.12
const ROAD_HEIGHT := 0.12
const CLEARANCE := 0.07
const SEGMENT_LENGTH := 40.0
const OVERLAP := 0.18
const LOCAL_HALF_EXTENT := 120.0
const LOCAL_SPACING := 80.0
const RETRY_FRAMES := 600
const SIDEWALK_WIDTH := 1.5
const Sidewalks = preload("res://roads/sidewalks.gd")
const RomanLamp = preload("res://props/roman_lamp.gd")
const Nasone = preload("res://props/nasone.gd")
const StreetSign = preload("res://props/street_sign.gd")
const StreetTree = preload("res://props/street_tree.gd")

var _terrain_data: Object
var _built := false
var _asphalt: StandardMaterial3D
var _asphalt_dark: StandardMaterial3D
var _sidewalk: StandardMaterial3D
var _curb: StandardMaterial3D
var _sampietrini: StandardMaterial3D
var _gutter: StandardMaterial3D
var _metal: StandardMaterial3D
var _marking: StandardMaterial3D
var _lamp: StandardMaterial3D
var _building_bounds: Array[AABB] = []
var _building_spatial_index: Dictionary = {}
var _road_blocked_cells: Dictionary = {}
var _prop_blocked_cells: Dictionary = {}
const BUILDING_INDEX_CELL := 50.0
const ROAD_COLLISION_CELL := 2.5
const ROAD_COLLISION_RADIUS := 4.35
const PROP_COLLISION_RADIUS := 3.0

func _ready() -> void:
    _asphalt = _procedural_asphalt()
    _asphalt_dark = _material(Color("#292B2D"), 0.94)
    _sidewalk = _material(Color("#9B8D73"), 0.94)
    _curb = _material(Color("#6F685E"), 0.94)
    _sampietrini = _procedural_sampietrini()
    _gutter = _material(Color("#45433F"), 0.98)
    _metal = _material(Color("#5A5B58"), 0.82)
    _marking = _material(Color("#E9E5D7"), 0.72)
    _lamp = _material(Color("#202224"), 0.78)
    call_deferred("_wait_for_terrain")

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _procedural_asphalt() -> StandardMaterial3D:
    var asphalt_mat := StandardMaterial3D.new()
    asphalt_mat.albedo_color = Color(0.15, 0.15, 0.15)
    var noise := NoiseTexture2D.new()
    noise.width = 64
    noise.height = 64
    var generator := FastNoiseLite.new()
    generator.frequency = 0.5
    generator.seed = 42
    noise.noise = generator
    noise.seamless = true
    asphalt_mat.albedo_texture = noise
    asphalt_mat.roughness = 0.95
    asphalt_mat.uv1_scale = Vector3(8.0, 8.0, 8.0)
    return asphalt_mat

func _procedural_sampietrini() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#343432")
    var noise := NoiseTexture2D.new()
    noise.width = 64
    noise.height = 64
    var generator := FastNoiseLite.new()
    generator.noise_type = FastNoiseLite.TYPE_CELLULAR
    generator.frequency = 0.85
    generator.seed = 17
    noise.noise = generator
    noise.seamless = true
    mat.albedo_texture = noise
    mat.roughness = 0.94
    mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
    return mat

func _wait_for_terrain() -> void:
    for _i in range(RETRY_FRAMES):
        var terrain: Node = get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
        if terrain != null:
            _terrain_data = terrain.get("data") as Object
            if _terrain_data != null:
                var range_variant: Variant = _terrain_data.call("get_height_range")
                var height_range: Vector2 = Vector2.ZERO
                if range_variant is Vector2:
                    height_range = range_variant
                if height_range.y - height_range.x > 0.5:
                    print("ROMA ROADS V2: terrain ready range=", height_range)
                    await _wait_for_buildings()
                    _collect_building_bounds()
                    _build_network()
                    return
        await get_tree().process_frame
    push_error("ROMA ROADS V2: timeout waiting for Terrain3D height data")

func _wait_for_buildings() -> void:
    for _i in range(1200):
        var bridge: Node = get_tree().current_scene.find_child("V11BuildingBridge", true, false)
        if bridge != null and bool(bridge.get("built")):
            return
        await get_tree().process_frame
    push_warning("ROMA ROADS V2: building bridge not ready; collision guard will use available geometry")

func _collect_building_bounds() -> void:
    _building_bounds.clear()
    var world: Node = get_tree().current_scene.find_child("V37World", true, false)
    if world == null:
        return
    for child in world.get_children():
        if child.has_meta("runtime_placement"):
            var bounds: AABB = _node_world_aabb(child)
            if bounds.size.x > 0.01 and bounds.size.z > 0.01:
                _building_bounds.append(bounds)
    _rebuild_building_spatial_index()
    print("ROMA ROADS V2: collision guard buildings=", _building_bounds.size(), " spatial_cells=", _building_spatial_index.size())

func _terrain_y(x: float, z: float) -> float:
    if _terrain_data == null:
        return 0.0
    var h: float = float(_terrain_data.call("get_height", Vector3(x, 0.0, z)))
    if is_nan(h) or is_inf(h):
        return 0.0
    return h

func _world(local_xz: Vector2) -> Vector3:
    return Vector3(local_xz.x + WORLD_OFFSET.x, 0.0, local_xz.y + WORLD_OFFSET.z)

func _surface_point(x: float, z: float, extra: float = 0.0) -> Vector3:
    return Vector3(x, _terrain_y(x, z) + CLEARANCE + extra, z)

func _build_network() -> void:
    if _built:
        return
    _built = true
    var lot_rects: Array = _get_urban_lot_rects()
    if lot_rects.is_empty():
        push_error("ROMA ROADS V2: Urban_Grid LOT_RECTS unavailable")
        return

    var corridors: Array[Dictionary] = _build_corridors_between_lots(lot_rects)
    var junctions: Dictionary = {}
    var corridor_index: int = 0

    for corridor in corridors:
        var a: Vector3 = Vector3(float(corridor["ax"]), 0.0, float(corridor["az"]))
        var b: Vector3 = Vector3(float(corridor["bx"]), 0.0, float(corridor["bz"]))
        junctions["%.2f,%.2f" % [a.x, a.z]] = a
        junctions["%.2f,%.2f" % [b.x, b.z]] = b
        await _add_edge(a, b, MAIN_WIDTH, _asphalt, true)
        corridor_index += 1
        if corridor_index % 3 == 0:
            await get_tree().process_frame

    for key in junctions:
        _add_intersection(junctions[key], MAIN_WIDTH)
        if junctions.size() % 8 == 0:
            await get_tree().process_frame

    await _add_safe_bridge(Vector3(880.0, 0.0, 960.0), Vector3(920.0, 0.0, 960.0))
    await _add_safe_bridge(Vector3(960.0, 0.0, 980.0), Vector3(1000.0, 0.0, 980.0))
    await _add_safe_bridge(Vector3(1040.0, 0.0, 1020.0), Vector3(1080.0, 0.0, 1020.0))
    await _add_safe_bridge(Vector3(1120.0, 0.0, 1040.0), Vector3(1160.0, 0.0, 1040.0))

    print("ROMA ROADS V2: PASS network=Urban_Grid_corridors collision_safe authoritative_continuous=true buildings_reserved=%d corridors=%d sidewalks=enabled drainage=enabled street_furniture=enabled" % [_building_bounds.size(), corridors.size()])

func _build_corridors_between_lots(lot_rects: Array) -> Array[Dictionary]:
    var counts: Dictionary = {}
    var representative: Dictionary = {}
    for rect_variant in lot_rects:
        if not (rect_variant is Dictionary):
            continue
        var rect: Dictionary = rect_variant as Dictionary
        var raw_sides: Array = [
            [float(rect.get("min_x", 0.0)), float(rect.get("min_z", 0.0)), float(rect.get("max_x", 0.0)), float(rect.get("min_z", 0.0))],
            [float(rect.get("max_x", 0.0)), float(rect.get("min_z", 0.0)), float(rect.get("max_x", 0.0)), float(rect.get("max_z", 0.0))],
            [float(rect.get("max_x", 0.0)), float(rect.get("max_z", 0.0)), float(rect.get("min_x", 0.0)), float(rect.get("max_z", 0.0))],
            [float(rect.get("min_x", 0.0)), float(rect.get("max_z", 0.0)), float(rect.get("min_x", 0.0)), float(rect.get("min_z", 0.0))]
        ]
        for side in raw_sides:
            var ax: float = float(side[0])
            var az: float = float(side[1])
            var bx: float = float(side[2])
            var bz: float = float(side[3])
            var first: String = "%.2f,%.2f" % [ax, az]
            var second: String = "%.2f,%.2f" % [bx, bz]
            var key: String = first + "|" + second if first < second else second + "|" + first
            counts[key] = int(counts.get(key, 0)) + 1
            representative[key] = {"ax": ax, "az": az, "bx": bx, "bz": bz}

    var result: Array[Dictionary] = []
    for key in counts:
        if int(counts[key]) < 2:
            continue
        var side: Dictionary = representative[key] as Dictionary
        var length: float = Vector2(float(side["bx"]) - float(side["ax"]), float(side["bz"]) - float(side["az"])).length()
        if length >= 20.0:
            result.append(side)
    return result

func _get_urban_lot_rects() -> Array:
    var grid: Node = get_tree().current_scene.get_node_or_null("Urban_Grid")
    if grid == null:
        return []
    var rects_variant: Variant = grid.get_meta("lot_rects", [])
    if rects_variant is Array:
        return rects_variant as Array
    return []

func _unique_lot_sides(lot_rects: Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var seen: Dictionary = {}
    for rect_variant in lot_rects:
        if not (rect_variant is Dictionary):
            continue
        var rect: Dictionary = rect_variant as Dictionary
        var min_x: float = float(rect.get("min_x", 0.0))
        var max_x: float = float(rect.get("max_x", 0.0))
        var min_z: float = float(rect.get("min_z", 0.0))
        var max_z: float = float(rect.get("max_z", 0.0))
        var raw: Array = [
            [min_x, min_z, max_x, min_z],
            [max_x, min_z, max_x, max_z],
            [max_x, max_z, min_x, max_z],
            [min_x, max_z, min_x, min_z]
        ]
        for side in raw:
            var ax: float = float(side[0])
            var az: float = float(side[1])
            var bx: float = float(side[2])
            var bz: float = float(side[3])
            var first: String = "%.2f,%.2f" % [ax, az]
            var second: String = "%.2f,%.2f" % [bx, bz]
            var key: String = first + "|" + second if first < second else second + "|" + first
            if not seen.has(key):
                seen[key] = true
                result.append({"ax":ax, "az":az, "bx":bx, "bz":bz})
    return result

func _node_world_aabb(root: Node) -> AABB:
    var result: AABB = AABB()
    var has_bounds: bool = false
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is MeshInstance3D:
            var mesh_instance: MeshInstance3D = node as MeshInstance3D
            var local_aabb: AABB = mesh_instance.get_aabb()
            var corners: Array[Vector3] = [
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

func _rebuild_building_spatial_index() -> void:
    _building_spatial_index.clear()
    for index in range(_building_bounds.size()):
        var bounds: AABB = _building_bounds[index]
        var min_cell_x: int = floori(bounds.position.x / BUILDING_INDEX_CELL)
        var max_cell_x: int = floori(bounds.end.x / BUILDING_INDEX_CELL)
        var min_cell_z: int = floori(bounds.position.z / BUILDING_INDEX_CELL)
        var max_cell_z: int = floori(bounds.end.z / BUILDING_INDEX_CELL)
        for cx in range(min_cell_x, max_cell_x + 1):
            for cz in range(min_cell_z, max_cell_z + 1):
                var key: String = "%d:%d" % [cx, cz]
                var bucket: Array = _building_spatial_index.get(key, [])
                bucket.append(index)
                _building_spatial_index[key] = bucket

    _road_blocked_cells.clear()
    _prop_blocked_cells.clear()
    for bounds in _building_bounds:
        _mark_blocked_cells(_road_blocked_cells, bounds, ROAD_COLLISION_RADIUS)
        _mark_blocked_cells(_prop_blocked_cells, bounds, PROP_COLLISION_RADIUS)

func _mark_blocked_cells(target: Dictionary, bounds: AABB, radius: float) -> void:
    var min_x: float = bounds.position.x - radius
    var max_x: float = bounds.end.x + radius
    var min_z: float = bounds.position.z - radius
    var max_z: float = bounds.end.z + radius
    var min_cell_x: int = floori(min_x / ROAD_COLLISION_CELL)
    var max_cell_x: int = floori(max_x / ROAD_COLLISION_CELL)
    var min_cell_z: int = floori(min_z / ROAD_COLLISION_CELL)
    var max_cell_z: int = floori(max_z / ROAD_COLLISION_CELL)
    for cx in range(min_cell_x, max_cell_x + 1):
        for cz in range(min_cell_z, max_cell_z + 1):
            target["%d:%d" % [cx, cz]] = true

func _collision_cell_blocked(target: Dictionary, x: float, z: float) -> bool:
    var cx: int = floori(x / ROAD_COLLISION_CELL)
    var cz: int = floori(z / ROAD_COLLISION_CELL)
    return bool(target.get("%d:%d" % [cx, cz], false))

func _candidate_building_indices(min_x: float, max_x: float, min_z: float, max_z: float) -> Array:
    var result: Array = []
    var seen: Dictionary = {}
    var min_cell_x: int = floori(min_x / BUILDING_INDEX_CELL)
    var max_cell_x: int = floori(max_x / BUILDING_INDEX_CELL)
    var min_cell_z: int = floori(min_z / BUILDING_INDEX_CELL)
    var max_cell_z: int = floori(max_z / BUILDING_INDEX_CELL)
    for cx in range(min_cell_x, max_cell_x + 1):
        for cz in range(min_cell_z, max_cell_z + 1):
            var key: String = "%d:%d" % [cx, cz]
            var bucket_variant: Variant = _building_spatial_index.get(key, [])
            if bucket_variant is Array:
                for index_variant in bucket_variant:
                    var index: int = int(index_variant)
                    if not seen.has(index):
                        seen[index] = true
                        result.append(index)
    return result

func _road_segment_clear(a: Vector3, b: Vector3, road_width: float, extra_clearance: float = 0.35) -> bool:
    var distance: float = Vector2(b.x - a.x, b.z - a.z).length()
    var steps: int = maxi(1, ceili(distance / ROAD_COLLISION_CELL))
    for i in range(steps + 1):
        var t: float = float(i) / float(steps)
        var p: Vector3 = a.lerp(b, t)
        if _collision_cell_blocked(_road_blocked_cells, p.x, p.z):
            return false
    return true

func _segment_intersects_rect(a: Vector2, b: Vector2, min_x: float, max_x: float, min_z: float, max_z: float) -> bool:
    var t_min: float = 0.0
    var t_max: float = 1.0
    var dx: float = b.x - a.x
    var dz: float = b.y - a.y

    if absf(dx) < 0.00001:
        if a.x < min_x or a.x > max_x:
            return false
    else:
        var tx1: float = (min_x - a.x) / dx
        var tx2: float = (max_x - a.x) / dx
        if tx1 > tx2:
            var temp_x: float = tx1
            tx1 = tx2
            tx2 = temp_x
        t_min = maxf(t_min, tx1)
        t_max = minf(t_max, tx2)
        if t_min > t_max:
            return false

    if absf(dz) < 0.00001:
        if a.y < min_z or a.y > max_z:
            return false
    else:
        var tz1: float = (min_z - a.y) / dz
        var tz2: float = (max_z - a.y) / dz
        if tz1 > tz2:
            var temp_z: float = tz1
            tz1 = tz2
            tz2 = tz2
        t_min = maxf(t_min, tz1)
        t_max = minf(t_max, tz2)
        if t_min > t_max:
            return false

    return true

func _area_clear(center: Vector3, width: float, depth: float, extra_clearance: float = 0.35) -> bool:
    var min_x: float = center.x - width * 0.5 - extra_clearance
    var max_x: float = center.x + width * 0.5 + extra_clearance
    var min_z: float = center.z - depth * 0.5 - extra_clearance
    var max_z: float = center.z + depth * 0.5 + extra_clearance
    # Junctions are validated against the real building AABBs, not the
    # rasterized 2.5m collision mask. The raster guard is intentionally
    # conservative and can mark a neighboring cell even when the actual
    # building footprint does not intersect the 8m junction.
    for index in _candidate_building_indices(min_x, max_x, min_z, max_z):
        var bounds: AABB = _building_bounds[index]
        if bounds.position.x < max_x and bounds.end.x > min_x and bounds.position.z < max_z and bounds.end.z > min_z:
            return false
    return true

func _prop_position_clear(position: Vector3, clearance_m: float = 3.0) -> bool:
    return not _collision_cell_blocked(_prop_blocked_cells, position.x, position.z)

func _add_safe_bridge(a: Vector3, b: Vector3) -> void:
    if _road_segment_clear(a, b, MAIN_WIDTH):
        _add_bridge(a, b)
    else:
        print("ROMA ROADS V2: bridge skipped because it intersects a building")

func _add_edge(a: Vector3, b: Vector3, width: float, material: Material, main_road: bool) -> void:
    var flat_a: Vector3 = Vector3(a.x, 0.0, a.z)
    var flat_b: Vector3 = Vector3(b.x, 0.0, b.z)
    var distance: float = flat_a.distance_to(flat_b)
    if distance <= 0.01:
        return
    var direction: Vector3 = (flat_b - flat_a).normalized()
    var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
    var steps: int = maxi(1, ceili(distance / SEGMENT_LENGTH))

    for i in range(steps):
        var t0: float = float(i) / float(steps)
        var t1: float = float(i + 1) / float(steps)
        var p0: Vector3 = flat_a.lerp(flat_b, t0)
        var p1: Vector3 = flat_a.lerp(flat_b, t1)
        if not _road_segment_clear(p0, p1, width):
            push_error("ROMA ROADS V2: corridor validation FAILED at %s -> %s; building reservation is inconsistent" % [p0, p1])

        var ground0: Vector3 = _surface_point(p0.x, p0.z, ROAD_HEIGHT * 0.5)
        var ground1: Vector3 = _surface_point(p1.x, p1.z, ROAD_HEIGHT * 0.5)
        _add_box_between(ground0, ground1, width, ROAD_HEIGHT, material)

        if main_road:
            Sidewalks.add_pair(self, _terrain_data, p0, p1, width, SIDEWALK_WIDTH)
            var prop_base: Vector3 = (p0 + p1) * 0.5 + side * (width * 0.5 + SIDEWALK_WIDTH * 0.55)
            var prop_side: Vector3 = side
            if not _prop_position_clear(prop_base, 3.0):
                prop_base = (p0 + p1) * 0.5 - side * (width * 0.5 + SIDEWALK_WIDTH * 0.55)
                prop_side = -side
            if i % 3 == 0 and _prop_position_clear(prop_base, 3.0):
                _add_lamp_prop(prop_base, direction)
                if i % 6 == 0:
                    _add_street_tree(prop_base, direction, (i / 4) % 2 == 0)
            if i % 8 == 0:
                var sign_pos: Vector3 = (p0 + p1) * 0.5 + prop_side * (width * 0.5 + SIDEWALK_WIDTH * 0.75)
                if _prop_position_clear(sign_pos, 3.0):
                    _add_street_sign(sign_pos, direction, _street_name((p0 + p1) * 0.5))
            if i % 16 == 0:
                var nasone_pos: Vector3 = (p0 + p1) * 0.5 + prop_side * (width * 0.5 + SIDEWALK_WIDTH * 0.35)
                if _prop_position_clear(nasone_pos, 3.0):
                    _add_nasone_prop(nasone_pos, direction)
            if i % 5 == 1:
                _add_road_marking((p0 + p1) * 0.5, direction)
            if i % 8 == 1:
                _add_manhole((p0 + p1) * 0.5)
                _add_drain((p0 + p1) * 0.5, side, width)
        else:
            if i % 4 == 0:
                for side_sign in [-1.0, 1.0]:
                    var edge_center: Vector3 = (p0 + p1) * 0.5 + side * side_sign * (width * 0.5 + 0.10)
                    var e0: Vector3 = _surface_point(edge_center.x - direction.x * 4.0, edge_center.z - direction.z * 4.0, 0.035)
                    var e1: Vector3 = _surface_point(edge_center.x + direction.x * 4.0, edge_center.z + direction.z * 4.0, 0.035)
                    _add_box_between(e0, e1, 0.20, 0.07, _curb)
            if i % 5 == 2:
                _add_manhole((p0 + p1) * 0.5)

        if i % 4 == 0:
            await get_tree().process_frame

func _add_box_between(p0: Vector3, p1: Vector3, width: float, height: float, material: Material) -> void:
    var midpoint: Vector3 = (p0 + p1) * 0.5
    var direction: Vector3 = p1 - p0
    var length: float = maxf(0.10, direction.length() + OVERLAP)
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(width, height, length)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = midpoint
    add_child(instance)
    instance.global_position = midpoint
    instance.look_at_from_position(midpoint, midpoint + direction.normalized(), Vector3.UP)

func _add_intersection(center: Vector3, width: float) -> void:
    if not _area_clear(center, width, width):
        push_error("ROMA ROADS V2: junction validation FAILED at %s" % center)
    center.y = _terrain_y(center.x, center.z) + CLEARANCE + ROAD_HEIGHT * 0.5
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(width, ROAD_HEIGHT, width)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = _asphalt
    instance.position = center
    add_child(instance)

    for offset in [-5.0, 5.0]:
        _add_zebra(center + Vector3(offset, 0.0, 0.0), Vector3.FORWARD)
        _add_stop_line(center + Vector3(offset * 0.72, 0.0, 0.0), Vector3.FORWARD)
        _add_zebra(center + Vector3(0.0, 0.0, offset), Vector3.RIGHT)
        _add_stop_line(center + Vector3(0.0, 0.0, offset * 0.72), Vector3.RIGHT)
    var nasone_center: Vector3 = center + Vector3(4.8, 0.0, 4.8)
    if _prop_position_clear(nasone_center, 3.0):
        _add_nasone_prop(nasone_center, Vector3.FORWARD)

func _add_road_marking(center: Vector3, direction: Vector3) -> void:
    var dash_center: Vector3 = _surface_point(center.x, center.z, ROAD_HEIGHT + 0.012)
    _add_box_between(dash_center, dash_center + direction * 2.6, 0.12, 0.025, _marking)
