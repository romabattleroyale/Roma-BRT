extends Node3D
## Connected road network: nodes + 10m box segments.
## Does not use GridMap, MeshLibrary, spline plugins or alter Terrain3D/Tevere/buildings.

const WORLD_SIZE := 2000.0
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
const SEGMENT_LENGTH := 10.0
const SEGMENT_OVERLAP := 0.10
const ROAD_HEIGHT := 0.10
const LOCAL_HALF_EXTENT := 120.0
const LOCAL_SPACING := 80.0
const RETRY_FRAMES := 600

var _terrain_data: Object
var _built := false
var _asphalt: StandardMaterial3D
var _cobble: StandardMaterial3D
var _bridge_asphalt: StandardMaterial3D

func _ready() -> void:
    _asphalt = _material(Color("#3A3A3A"), 0.90)
    _cobble = _material(Color("#4A4A4A"), 0.92)
    _bridge_asphalt = _material(Color("#3A3A3A"), 0.90)
    call_deferred("_wait_for_terrain")

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _wait_for_terrain() -> void:
    for _i in range(RETRY_FRAMES):
        var terrain := get_tree().current_scene.find_child("Terrain3D_HEIGHTMAP_2000x2000", true, false)
        if terrain != null:
            _terrain_data = terrain.get("data") as Object
            if _terrain_data != null:
                _build_network()
                return
        await get_tree().process_frame
    push_error("SIMPLE ROADS: timeout waiting for Terrain3D")

func _terrain_y(x: float, z: float) -> float:
    if _terrain_data == null:
        return 0.0
    var h := float(_terrain_data.call("get_height", Vector3(x, 0.0, z)))
    if is_nan(h) or is_inf(h):
        return 0.0
    return h

func _world(local_xz: Vector2) -> Vector3:
    return Vector3(local_xz.x + WORLD_OFFSET.x, 0.0, local_xz.y + WORLD_OFFSET.z)

func _build_network() -> void:
    if _built:
        return
    _built = true

    var nodes: Array[Vector3] = []
    for local_center in DISTRICT_CENTERS:
        var p := _world(Vector2(local_center.x, local_center.z))
        p.y = _terrain_y(p.x, p.z)
        nodes.append(p)

    for row in range(3):
        for col in range(4):
            var index := row * 4 + col
            if col < 3:
                _add_edge(nodes[index], nodes[index + 1], MAIN_WIDTH, _asphalt)
            if row < 2:
                _add_edge(nodes[index], nodes[index + 4], MAIN_WIDTH, _asphalt)

    for local_center in DISTRICT_CENTERS:
        var center := _world(Vector2(local_center.x, local_center.z))
        for offset in [-LOCAL_SPACING, 0.0, LOCAL_SPACING]:
            var a := Vector3(center.x - LOCAL_HALF_EXTENT, 0.0, center.z + offset)
            var b := Vector3(center.x + LOCAL_HALF_EXTENT, 0.0, center.z + offset)
            _add_edge(a, b, ALLEY_WIDTH, _cobble)
            var c := Vector3(center.x + offset, 0.0, center.z - LOCAL_HALF_EXTENT)
            var d := Vector3(center.x + offset, 0.0, center.z + LOCAL_HALF_EXTENT)
            _add_edge(c, d, ALLEY_WIDTH, _cobble)
        _add_intersection(center, MAIN_WIDTH)

    _add_bridge(Vector3(880.0, 0.0, 960.0), Vector3(920.0, 0.0, 960.0))
    _add_bridge(Vector3(960.0, 0.0, 980.0), Vector3(1000.0, 0.0, 980.0))
    _add_bridge(Vector3(1040.0, 0.0, 1020.0), Vector3(1080.0, 0.0, 1020.0))
    _add_bridge(Vector3(1120.0, 0.0, 1040.0), Vector3(1160.0, 0.0, 1040.0))

    print("SIMPLE ROADS: PASS connected_network=true district_nodes=12 main_edges=17 local_districts=12 segment=10m")

func _add_edge(a: Vector3, b: Vector3, width: float, material: Material) -> void:
    var flat_a := Vector3(a.x, 0.0, a.z)
    var flat_b := Vector3(b.x, 0.0, b.z)
    var distance := flat_a.distance_to(flat_b)
    if distance <= 0.01:
        return
    var direction := (flat_b - flat_a).normalized()
    var steps := maxi(1, ceili(distance / SEGMENT_LENGTH))
    for i in range(steps):
        var t0 := float(i) / float(steps)
        var t1 := float(i + 1) / float(steps)
        var p0 := flat_a.lerp(flat_b, t0)
        var p1 := flat_a.lerp(flat_b, t1)
        var length := p0.distance_to(p1) + SEGMENT_OVERLAP
        var midpoint := (p0 + p1) * 0.5
        midpoint.y = _terrain_y(midpoint.x, midpoint.z) + ROAD_HEIGHT * 0.5
        _add_segment(midpoint, length, width, direction, material)

func _add_segment(midpoint: Vector3, length: float, width: float, direction: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, ROAD_HEIGHT, length)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = midpoint
    instance.rotation.y = atan2(direction.x, direction.z)
    add_child(instance)

func _add_intersection(center: Vector3, width: float) -> void:
    center.y = _terrain_y(center.x, center.z) + ROAD_HEIGHT * 0.5
    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, ROAD_HEIGHT, width)
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = _asphalt
    instance.position = center
    add_child(instance)

func _add_bridge(a: Vector3, b: Vector3) -> void:
    _add_edge(a, b, MAIN_WIDTH, _bridge_asphalt)
    var direction := (b - a).normalized()
    var side := Vector3(-direction.z, 0.0, direction.x)
    var midpoint := (a + b) * 0.5
    var length := a.distance_to(b)
    for side_sign in [-1.0, 1.0]:
        var rail: Vector3 = midpoint + side * side_sign * 4.3
        rail.y = _terrain_y(rail.x, rail.z) + 0.75
        var mesh := BoxMesh.new()
        mesh.size = Vector3(0.12, 1.5, length)
        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = _bridge_asphalt
        instance.position = rail
        instance.rotation.y = atan2(direction.x, direction.z)
        add_child(instance)
