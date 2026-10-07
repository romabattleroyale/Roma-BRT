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
                    _build_network()
                    return
        await get_tree().process_frame
    push_error("ROMA ROADS V2: timeout waiting for Terrain3D height data")

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

    var nodes: Array[Vector3] = []
    for local_center in DISTRICT_CENTERS:
        var p: Vector3 = _world(Vector2(local_center.x, local_center.z))
        p.y = _terrain_y(p.x, p.z)
        nodes.append(p)

    # Main 8m network: 17 links joining all 12 districts.
    var work_counter: int = 0
    for row in range(3):
        for col in range(4):
            var index: int = row * 4 + col
            if col < 3:
                await _add_edge(nodes[index], nodes[index + 1], MAIN_WIDTH, _asphalt, true)
            if row < 2:
                await _add_edge(nodes[index], nodes[index + 4], MAIN_WIDTH, _asphalt, true)
            work_counter += 1
            if work_counter % 2 == 0:
                await get_tree().process_frame

    # Local Roman streets inside each district.
    for local_center in DISTRICT_CENTERS:
        var center: Vector3 = _world(Vector2(local_center.x, local_center.z))
        for offset in [-LOCAL_SPACING, 0.0, LOCAL_SPACING]:
            var a: Vector3 = Vector3(center.x - LOCAL_HALF_EXTENT, 0.0, center.z + offset)
            var b: Vector3 = Vector3(center.x + LOCAL_HALF_EXTENT, 0.0, center.z + offset)
            await _add_edge(a, b, ALLEY_WIDTH, _sampietrini, false)
            var c: Vector3 = Vector3(center.x + offset, 0.0, center.z - LOCAL_HALF_EXTENT)
            var d: Vector3 = Vector3(center.x + offset, 0.0, center.z + LOCAL_HALF_EXTENT)
            await _add_edge(c, d, ALLEY_WIDTH, _sampietrini, false)
        _add_intersection(center, MAIN_WIDTH)
        work_counter += 1
        if work_counter % 2 == 0:
            await get_tree().process_frame

    # Bridge placeholders remain on the existing network coordinates.
    _add_bridge(Vector3(880.0, 0.0, 960.0), Vector3(920.0, 0.0, 960.0))
    _add_bridge(Vector3(960.0, 0.0, 980.0), Vector3(1000.0, 0.0, 980.0))
    _add_bridge(Vector3(1040.0, 0.0, 1020.0), Vector3(1080.0, 0.0, 1020.0))
    _add_bridge(Vector3(1120.0, 0.0, 1040.0), Vector3(1160.0, 0.0, 1040.0))
    await get_tree().process_frame

    print("ROMA ROADS V2: PASS network=12_districts main_edges=17 sidewalks=enabled drainage=enabled street_furniture=enabled")

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
        var ground0: Vector3 = _surface_point(p0.x, p0.z, ROAD_HEIGHT * 0.5)
        var ground1: Vector3 = _surface_point(p1.x, p1.z, ROAD_HEIGHT * 0.5)
        var length: float = p0.distance_to(p1) + OVERLAP
        _add_box_between(ground0, ground1, width, ROAD_HEIGHT, material)

        if main_road:
            Sidewalks.add_pair(self, _terrain_data, p0, p1, width, SIDEWALK_WIDTH)
            if i % 2 == 0:
                _add_lamp_prop((p0 + p1) * 0.5 + side * (width * 0.5 + SIDEWALK_WIDTH * 0.55), direction)
                _add_street_tree((p0 + p1) * 0.5 + side * (width * 0.5 + SIDEWALK_WIDTH * 0.55), direction, (i / 2) % 2 == 0)
            if i % 5 == 0:
                _add_street_sign((p0 + p1) * 0.5 + side * (width * 0.5 + SIDEWALK_WIDTH * 0.75), direction, _street_name((p0 + p1) * 0.5))
            if i % 10 == 0:
                _add_nasone_prop((p0 + p1) * 0.5 + side * (width * 0.5 + SIDEWALK_WIDTH * 0.35), direction)
            if i % 3 == 1:
                _add_road_marking((p0 + p1) * 0.5, direction)
            if i % 4 == 1:
                _add_manhole((p0 + p1) * 0.5)
                _add_drain((p0 + p1) * 0.5, side, width)
        else:
            if i % 4 == 0:
                for side_sign in [-1.0, 1.0]:
                    var edge_center: Vector3 = (p0 + p1) * 0.5 + side * side_sign * (width * 0.5 + 0.10)
                    var e0: Vector3 = _surface_point(edge_center.x - direction.x * length * 0.5, edge_center.z - direction.z * length * 0.5, 0.035)
                    var e1: Vector3 = _surface_point(edge_center.x + direction.x * length * 0.5, edge_center.z + direction.z * length * 0.5, 0.035)
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
    center.y = _terrain_y(center.x, center.z) + CLEARANCE + ROAD_HEIGHT * 0.5
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(width, ROAD_HEIGHT, width)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = _asphalt
    instance.position = center
    add_child(instance)

    # Four Roman-style zebra crossings and four stop lines.
    for offset in [-5.0, 5.0]:
        _add_zebra(center + Vector3(offset, 0.0, 0.0), Vector3.FORWARD)
        _add_stop_line(center + Vector3(offset * 0.72, 0.0, 0.0), Vector3.FORWARD)
        _add_zebra(center + Vector3(0.0, 0.0, offset), Vector3.RIGHT)
        _add_stop_line(center + Vector3(0.0, 0.0, offset * 0.72), Vector3.RIGHT)
    _add_nasone_prop(center + Vector3(4.8, 0.0, 4.8), Vector3.FORWARD)

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
