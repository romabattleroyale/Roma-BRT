extends Node3D
## ITERATION 3 — Isola Tiberina, exactly 9 approved GLB assets.
## No other model is loaded by this scene. The island body remains procedural.

const ASSET_ROOT := "res://poi_test/assets/models/"
const ISLAND_L := 270.0
const ISLAND_W := 110.0
const ISLAND_RISE := 4.0

const FABRICIO := ASSET_ROOT + "ponte_fabricio.glb"
const CESTIO := ASSET_ROOT + "ponte_cestio.glb"
const BASILICA := ASSET_ROOT + "basilica_san_bartolomeo.glb"
const TORRE := ASSET_ROOT + "torre_caetani.glb"
const CASA := ASSET_ROOT + "casa_01.glb"
const PAVIMENTO := ASSET_ROOT + "pavimento.glb"
const FONTANA := ASSET_ROOT + "fontana.glb"
const LAMPIONE := ASSET_ROOT + "lampione.glb"
const ALBERO := ASSET_ROOT + "albero.glb"

var _asset_cache: Dictionary = {}

func _ready() -> void:
    _build_island()
    _spawn_required(FABRICIO, "PonteFabricio", Vector3(112, 4, 0), Vector3(31, 1, 1), 0.0)
    _spawn_required(CESTIO, "PonteCestio", Vector3(-112, 4, 0), Vector3(35, 1, 1), 0.0)
    _spawn_required(BASILICA, "SanBartolomeo", Vector3(18, 4, -2), Vector3(4.2, 4.2, 4.2), 0.0)
    _spawn_required(TORRE, "TorreCaetani", Vector3(-28, 4, 19), Vector3(1.9, 1.9, 1.9), 0.0)
    _spawn_repeated(CASA, [
        Vector3(52,4,-14), Vector3(74,4,-2), Vector3(42,4,14),
        Vector3(10,4,23), Vector3(-2,4,-22), Vector3(-54,4,-10)
    ], "Casa")
    _spawn_repeated(PAVIMENTO, [
        Vector3(0,4.2,0), Vector3(25,4.2,21), Vector3(-20,4.2,-23)
    ], "Pavimento")
    _spawn_repeated(FONTANA, [
        Vector3(-38,4,-8), Vector3(0,4,-8), Vector3(38,4,-8)
    ], "Nasone")
    _spawn_repeated(LAMPIONE, [
        Vector3(-70,4,4),Vector3(-45,4,4),Vector3(-20,4,4),Vector3(5,4,4),
        Vector3(30,4,4),Vector3(55,4,4),Vector3(80,4,4),Vector3(0,4,-12)
    ], "Lampione")
    _spawn_repeated(ALBERO, [
        Vector3(-86,4,17),Vector3(-70,4,30),Vector3(-48,4,26),Vector3(-15,4,17),
        Vector3(18,4,30),Vector3(39,4,28),Vector3(66,4,18),Vector3(87,4,5),
        Vector3(66,4,-23),Vector3(42,4,-29),Vector3(10,4,-30),Vector3(-24,4,-29),
        Vector3(-56,4,-25),Vector3(-82,4,-14),Vector3(-32,4,4),Vector3(83,4,-8),
        Vector3(-5,4,4),Vector3(25,4,-7)
    ], "Albero")

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
    island.material_override = mat
    add_child(island)

func _load_asset(path: String) -> PackedScene:
    if _asset_cache.has(path):
        return _asset_cache[path]
    if not ResourceLoader.exists(path):
        push_error("Required POI GLB missing: " + path)
        return null
    var packed := load(path) as PackedScene
    if packed == null:
        push_error("Required POI GLB failed to load: " + path)
        return null
    _asset_cache[path] = packed
    return packed

func _spawn_required(path: String, node_name: String, pos: Vector3, scale: Vector3, yaw: float) -> void:
    var packed := _load_asset(path)
    if packed == null:
        return
    var node := packed.instantiate() as Node3D
    node.name = node_name
    node.position = pos
    node.scale = scale
    node.rotation.y = yaw
    add_child(node)

func _spawn_repeated(path: String, positions: Array[Vector3], prefix: String) -> void:
    var packed := _load_asset(path)
    if packed == null:
        return
    for i in range(positions.size()):
        var node := packed.instantiate() as Node3D
        node.name = "%s_%02d" % [prefix, i]
        node.position = positions[i]
        add_child(node)
