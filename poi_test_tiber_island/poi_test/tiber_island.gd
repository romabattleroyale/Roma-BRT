extends Node3D
## ITERATION 3 — Asset-based Isola Tiberina.
## Main island body is procedural; principal POI elements are imported GLB assets.

const ISLAND_L := 270.0
const ISLAND_W := 110.0
const ISLAND_RISE := 4.0
const WATER_Y := 0.0
const ASSET_ROOT := "res://poi_test/assets/models/"
var mats: Dictionary = {}

func _ready() -> void:
    _build_island()
    _spawn_asset("roman_bridge", "PonteFabricio", Vector3(112, 0, 0), Vector3(31.0, 1.0, 1.0), 0.0)
    _spawn_asset("roman_bridge", "PonteCestio", Vector3(-112, 0, 0), Vector3(35.0, 1.0, 1.6), 0.0)
    _spawn_asset("low_poly_church", "SanBartolomeo", Vector3(18, 4, -2), Vector3(4.2, 4.2, 4.2), 0.0)
    _spawn_asset("medieval_tower", "TorreCaetani", Vector3(-28, 4, 19), Vector3(1.9, 1.9, 1.9), 0.0)
    _spawn_houses()
    _spawn_paths()
    _spawn_props()
    _spawn_trees()

func _asset_scene(name: String) -> PackedScene:
    var path := ASSET_ROOT + name + "/" + name + ".glb"
    if not ResourceLoader.exists(path):
        push_warning("Missing Sketchfab GLB: " + path)
        return null
    return load(path) as PackedScene

func _spawn_asset(asset_name: String, node_name: String, pos: Vector3, scale: Vector3, yaw: float) -> Node3D:
    var packed := _asset_scene(asset_name)
    if packed == null:
        return null
    var node := packed.instantiate() as Node3D
    node.name = node_name
    node.position = pos
    node.scale = scale
    node.rotation.y = yaw
    add_child(node)
    return node

func _build_island() -> void:
    var island := MeshInstance3D.new()
    island.name = "ProceduralIslandBody"
    var mesh := CylinderMesh.new()
    mesh.top_radius = 1.0
    mesh.bottom_radius = 1.0
    mesh.height = ISLAND_RISE
    mesh.radial_segments = 48
    island.mesh = mesh
    island.scale = Vector3(ISLAND_L * 0.5, 1.0, ISLAND_W * 0.5)
    island.position.y = ISLAND_RISE * 0.5
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#9B8265")
    mat.roughness = 0.85
    mat.metallic = 0.0
    island.material_override = mat
    add_child(island)

func _spawn_houses() -> void:
    var positions := [
        Vector3(52,4,-14), Vector3(74,4,-2), Vector3(42,4,14),
        Vector3(10,4,23), Vector3(-2,4,-22), Vector3(-54,4,-10)
    ]
    var scales := [Vector3(1.8,1.8,1.8),Vector3(1.5,1.5,1.5),Vector3(1.7,1.7,1.7),Vector3(1.6,1.6,1.6),Vector3(1.5,1.5,1.5),Vector3(1.8,1.8,1.8)]
    for i in range(positions.size()):
        _spawn_asset("medieval_house", "Casa_%02d" % i, positions[i], scales[i], 0.0 if i % 2 == 0 else 0.35)

func _spawn_paths() -> void:
    _spawn_asset("cobblestone_ground", "PathMain", Vector3(0,4.2,0), Vector3(2.5,1.0,0.45), 0.0)
    _spawn_asset("cobblestone_ground", "PathNorth", Vector3(25,4.2,21), Vector3(1.25,1.0,0.5), 0.0)
    _spawn_asset("cobblestone_ground", "PathSouth", Vector3(-20,4.2,-23), Vector3(1.4,1.0,0.5), 0.0)

func _spawn_props() -> void:
    var lamp_positions := [Vector3(-70,4,4),Vector3(-45,4,4),Vector3(-20,4,4),Vector3(5,4,4),Vector3(30,4,4),Vector3(55,4,4),Vector3(80,4,4),Vector3(0,4,-12)]
    for i in range(lamp_positions.size()):
        _spawn_asset("street_lamp", "Lamp_%02d" % i, lamp_positions[i], Vector3(1.4,1.4,1.4), 0.0)
    for i in range(4):
        _spawn_asset("bench", "Bench_%02d" % i, Vector3(-42 + float(i) * 28.0, 4, 9), Vector3(1.3,1.3,1.3), 0.0)
    for i in range(3):
        _spawn_asset("italian_fountain", "Nasone_%02d" % i, Vector3(-38 + float(i) * 38.0, 4, -8), Vector3(0.7,0.7,0.7), 0.0)

func _spawn_trees() -> void:
    var pts := [
        Vector3(-86,4,17),Vector3(-70,4,30),Vector3(-48,4,26),Vector3(-15,4,17),
        Vector3(18,4,30),Vector3(39,4,28),Vector3(66,4,18),Vector3(87,4,5),
        Vector3(66,4,-23),Vector3(42,4,-29),Vector3(10,4,-30),Vector3(-24,4,-29),
        Vector3(-56,4,-25),Vector3(-82,4,-14),Vector3(-32,4,4),Vector3(83,4,-8),
        Vector3(-5,4,4),Vector3(25,4,-7)
    ]
    for i in range(pts.size()):
        _spawn_asset("low_poly_tree", "Tree_%02d" % i, pts[i], Vector3(2.5,2.5,2.5), float(i % 4) * 0.35)
