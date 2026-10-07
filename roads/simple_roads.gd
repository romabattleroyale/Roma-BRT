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
const SEGMENT_LENGTH := 10.0
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
    print("ROMA ROADS V2: collision guard buildings=", _building_bounds.size())

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
        if not _road_segment_clear(a, b, MAIN_WIDTH):
            print("ROMA ROADS V2: blocked corridor skipped ", a, " -> ", b)
            continue
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

    print("ROMA ROADS V2: PASS network=Urban_Grid_corridors collision_safe buildings=%d corridors=%d sidewalks=enabled drainage=enabled street_furniture=enabled" % [_building_bounds.size(), corridors.size()])

func _build_corridors_between_lots(lot_rects: Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var seen: Dictionary = {}
    var max_gap: float = 22.0

    for i in range(lot_rects.size()):
        if not (lot_rects[i] is Dictionary):
            continue
        var a: Dictionary = lot_rects[i] as Dictionary
        var amin_x: float = float(a.get("min_x", 0.0))
        var amax_x: float = float(a.get("max_x", 0.0))
        var amin_z: float = float(a.get("min_z", 0.0))
        var amax_z: float = float(a.get("max_z", 0.0))

        for j in range(i + 1, lot_rects.size()):
            if not (lot_rects[j] is Dictionary):
                continue
            var b: Dictionary = lot_rects[j] as Dictionary
            var bmin_x: float = float(b.get("min_x", 0.0))
            var bmax_x: float = float(b.get("max_x", 0.0))
            var bmin_z: float = float(b.get("min_z", 0.0))
            var bmax_z: float = float(b.get("max_z", 0.0))

            var overlap_x: float = minf(amax_x, bmax_x) - maxf(amin_x, bmin_x)
            var overlap_z: float = minf(amax_z, bmax_z) - maxf(amin_z, bmin_z)

            if overlap_x >= 20.0:
                var gap_z: float = 0.0
                var center_z: float = 0.0
                if amax_z <= bmin_z:
                    gap_z = bmin_z - amax_z
                    center_z = (amax_z + bmin_z) * 0.5
                elif bmax_z <= amin_z:
                    gap_z = amin_z - bmax_z
                    center_z = (bmax_z + amin_z) * 0.5
                if gap_z > 7.0 and gap_z <= max_gap:
                    var ax: float = maxf(amin_x, bmin_x)
                    var bx: float = minf(amax_x, bmax_x)
                    if bx - ax >= 20.0:
                        var key: String = "H:%.1f:%.1f:%.1f" % [ax, bx, center_z]
                        if not seen.has(key):
                            seen[key] = true
                            result.append({"ax":ax, "az":center_z, "bx":bx, "bz":center_z})

            if overlap_z >= 20.0:
                var gap_x: float = 0.0
                var center_x: float = 0.0
                if amax_x <= bmin_x:
                    gap_x = bmin_x - amax_x
                    center_x = (amax_x + bmin_x) * 0.5
                elif bmax_x <= amin_x:
                    gap_x = amin_x - bmax_x
                    center_x = (bmax_x + amin_x) * 0.5
                if gap_x > 7.0 and gap_x <= max_gap:
                    var az: float = maxf(amin_z, bmin_z)
                    var bz: float = minf(amax_z, bmax_z)
                    if bz - az >= 20.0:
                        var key: String = "V:%.1f:%.1f:%.1f" % [az, bz, center_x]
                        if not seen.has(key):
                            seen[key] = true
                            result.append({"ax":center_x, "az":az, "bx":center_x, "bz":bz})

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

func _road_segment_clear(a: Vector3, b: Vector3, road_width: float, extra_clearance: float = 0.35) -> bool:
    var half_width: float = road_width * 0.5 + extra_clearance
    for building in _building_bounds:
        var min_x: float = building.position.x - half_width
        var max_x: float = building.end.x + half_width
        var min_z: float = building.position.z - half_width
        var max_z: float = building.end.z + half_width
        if _segment_intersects_rect(Vector2(a.x, a.z), Vector2(b.x, b.z), min_x, max_x, min_z, max_z):
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
            tz2 = temp_z
        t_min = maxf(t_min, tz1)
        t_max = minf(t_max, tz2)
        if t_min > t_max:
            return false

    return true

func _find_safe_side_offset(a: Vector3, b: Vector3, road_width: float) -> float:
    var direction: Vector3 = (b - a).normalized()
    var normal: Vector3 = Vector3(-direction.z, 0.0, direction.x)
    var candidates: Array[float] = [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, -5.0, 6.0, -6.0, 7.0, -7.0, 8.0, -8.0, 9.0, -9.0, 10.0, -10.0]
    for offset in candidates:
        var aa: Vector3 = a + normal * offset
        var bb: Vector3 = b + normal * offset
        if _road_segment_clear(aa, bb, road_width):
            return offset
    return NAN

func _area_clear(center: Vector3, width: float, depth: float, extra_clearance: float = 0.35) -> bool:
    var min_x: float = center.x - width * 0.5 - extra_clearance
    var max_x: float = center.x + width * 0.5 + extra_clearance
    var min_z: float = center.z - depth * 0.5 - extra_clearance
    var max_z: float = center.z + depth * 0.5 + extra_clearance
    for building in _building_bounds:
        if building.end.x + extra_clearance < min_x or building.position.x - extra_clearance > max_x:
            continue
        if building.end.z + extra_clearance < min_z or building.position.z - extra_clearance > max_z:
            continue
        return false
    return true

func _prop_position_clear(position: Vector3, clearance_m: float = 3.0) -> bool:
    for building in _building_bounds:
        var dx: float = maxf(maxf(building.position.x - position.x, 0.0), position.x - building.end.x)
        var dz: float = maxf(maxf(building.position.z - position.z, 0.0), position.z - building.end.z)
        if sqrt(dx * dx + dz * dz) < clearance_m:
            return false
    return true

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
            print("ROMA ROADS V2: blocked road segment skipped at ", p0, " -> ", p1)
            await get_tree().process_frame
            continue

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
            if i % 2 == 0 and _prop_position_clear(prop_base, 3.0):
                _add_lamp_prop(prop_base, direction)
                _add_street_tree(prop_base, direction, (i / 2) % 2 == 0)
            if i % 5 == 0:
                var sign_pos: Vector3 = (p0 + p1) * 0.5 + prop_side * (width * 0.5 + SIDEWALK_WIDTH * 0.75)
                if _prop_position_clear(sign_pos, 3.0):
                    _add_street_sign(sign_pos, direction, _street_name((p0 + p1) * 0.5))
            if i % 10 == 0:
                var nasone_pos: Vector3 = (p0 + p1) * 0.5 + prop_side * (width * 0.5 + SIDEWALK_WIDTH * 0.35)
                if _prop_position_clear(nasone_pos, 3.0):
                    _add_nasone_prop(nasone_pos, direction)
            if i % 3 == 1:
                _add_road_marking((p0 + p1) * 0.5, direction)
            if i % 4 == 1:
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
        print("ROMA ROADS V2: intersection skipped because it overlaps a building at ", center)
        return
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

func _add_stop_line(center: Vector3, direction: Vector3) -> void:
    var pos := _surface_point(center.x, center.z, ROAD_HEIGHT + 0.014)
    _add_box_between(pos - direction * 1.6, pos + direction * 1.6, 0.12, 0.025, _marking)

func _add_zebra(center: Vector3, direction: Vector3) -> void:
    var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
    for i in range(7):
        var offset := -2.4 + float(i) * 0.8
        var c := center + side * offset
        var p0 := _surface_point(c.x - direction.x * 2.5, c.z - direction.z * 2.5, ROAD_HEIGHT + 0.012)
        var p1 := _surface_point(c.x + direction.x * 2.5, c.z + direction.z * 2.5, ROAD_HEIGHT + 0.012)
        _add_box_between(p0, p1, 0.42, 0.025, _marking)

func _add_manhole(center: Vector3) -> void:
    var pos: Vector3 = _surface_point(center.x, center.z, ROAD_HEIGHT + 0.018)
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.34
    mesh.bottom_radius = 0.34
    mesh.height = 0.035
    mesh.radial_segments = 12
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = _metal
    instance.position = pos
    add_child(instance)

func _add_drain(center: Vector3, side: Vector3, width: float) -> void:
    for side_sign in [-1.0, 1.0]:
        var p: Vector3 = center + side * side_sign * (width * 0.5 - 0.18)
        var pos: Vector3 = _surface_point(p.x, p.z, ROAD_HEIGHT + 0.020)
        var base: MeshInstance3D = MeshInstance3D.new()
        var base_mesh: BoxMesh = BoxMesh.new()
        base_mesh.size = Vector3(0.48, 0.035, 0.30)
        base.mesh = base_mesh
        base.material_override = _metal
        base.position = pos
        add_child(base)
        for slot in range(4):
            var bar: MeshInstance3D = MeshInstance3D.new()
            var bar_mesh: BoxMesh = BoxMesh.new()
            bar_mesh.size = Vector3(0.055, 0.040, 0.24)
            bar.mesh = bar_mesh
            bar.material_override = _asphalt_dark
            bar.position = pos + side * (-0.13 + float(slot) * 0.087)
            add_child(bar)

func _add_lamp_prop(center: Vector3, direction: Vector3) -> void:
    var lamp := RomanLamp.new()
    lamp.rotation.y = atan2(direction.x, direction.z)
    lamp.position = _surface_point(center.x, center.z)
    add_child(lamp)

func _add_nasone_prop(center: Vector3, direction: Vector3) -> void:
    var nasone := Nasone.new()
    nasone.rotation.y = atan2(direction.x, direction.z)
    nasone.position = _surface_point(center.x, center.z)
    add_child(nasone)

func _add_street_sign(center: Vector3, direction: Vector3, street_name: String) -> void:
    var sign := StreetSign.new()
    sign.street_name = street_name
    sign.rotation.y = atan2(direction.x, direction.z)
    sign.position = _surface_point(center.x, center.z)
    add_child(sign)

func _add_street_tree(center: Vector3, direction: Vector3, alternate: bool) -> void:
    var tree := StreetTree.new()
    tree.rotation.y = atan2(direction.x, direction.z)
    tree.position = _surface_point(center.x, center.z)
    add_child(tree)

func _street_name(center: Vector3) -> String:
    var names := ["VIA CAVOUR", "VIA DEL CORSO", "LUNGOTEVERE", "VIA NAZIONALE", "VIA APPIA", "VIA VENETO"]
    var index: int = abs(int(round((center.x + center.z) / 50.0))) % names.size()
    return names[index]

func _add_bridge(a: Vector3, b: Vector3) -> void:
    var direction: Vector3 = (b - a).normalized()
    var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
    var distance: float = a.distance_to(b)
    var steps: int = maxi(1, ceili(distance / 10.0))

    # Sampietrini bridge deck, with 2m travertine sidewalks.
    _add_edge(a, b, MAIN_WIDTH, _sampietrini, false)
    Sidewalks.add_pair(self, _terrain_data, a, b, MAIN_WIDTH, 2.0)

    for i in range(steps + 1):
        var t: float = float(i) / float(steps)
        var p: Vector3 = a.lerp(b, t)
        if i < steps + 1:
            _add_bridge_lamp(p + side * 4.8, direction)
        for side_sign in [-1.0, 1.0]:
            var rail_center: Vector3 = p + side * side_sign * 5.0
            var rail := MeshInstance3D.new()
            var rail_mesh := BoxMesh.new()
            rail_mesh.size = Vector3(0.12, 1.35, 0.12)
            rail.mesh = rail_mesh
            rail.material_override = _lamp
            rail.position = _surface_point(rail_center.x, rail_center.z, 0.70)
            add_child(rail)
    for side_sign in [-1.0, 1.0]:
        var rail0: Vector3 = _surface_point(a.x + side.x * side_sign * 5.0, a.z + side.z * side_sign * 5.0, 1.35)
        var rail1: Vector3 = _surface_point(b.x + side.x * side_sign * 5.0, b.z + side.z * side_sign * 5.0, 1.35)
        _add_box_between(rail0, rail1, 0.10, 0.10, _lamp)

func _add_bridge_lamp(center: Vector3, direction: Vector3) -> void:
    var lamp := RomanLamp.new()
    lamp.rotation.y = atan2(direction.x, direction.z)
    lamp.position = _surface_point(center.x, center.z)
    add_child(lamp)
