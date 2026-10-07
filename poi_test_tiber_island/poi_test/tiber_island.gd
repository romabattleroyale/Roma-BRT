extends Node3D
## ITERATION 2 — Trastevere / Isola Tiberina isolated POI refinement.
## Godot 4.7.2. No dependency on Roma-BRT.
## No GridMap, MeshLibrary or spline. Low-poly procedural construction.

const ISLAND_L: float = 270.0
const ISLAND_W: float = 110.0
const ISLAND_RISE: float = 4.0
const ISLAND_TOP: float = 4.0
const WALL_H: float = 3.0
const BRIDGE_DECK_Y: float = 5.0
const BRIDGE_DECK_THICK: float = 1.2
const MAX_RADIAL: int = 12
var mats: Dictionary = {}

func _ready() -> void:
    _build_materials()
    _build_island()
    _build_fabricio()
    _build_cestio()
    _build_basilica()
    _build_caetani()
    _build_residential()
    _build_paths()
    _build_vegetation()
    _build_props()

func _noise_mat(base: Color, frequency: float, roughness: float) -> StandardMaterial3D:
    var noise: FastNoiseLite = FastNoiseLite.new()
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = frequency
    noise.fractal_octaves = 3
    noise.fractal_gain = 0.55
    var tex: NoiseTexture2D = NoiseTexture2D.new()
    tex.noise = noise
    tex.width = 128
    tex.height = 128
    tex.seamless = true
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_texture = tex
    mat.albedo_color = base
    mat.roughness = roughness
    mat.metallic = 0.0
    return mat

func _flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.metallic = 0.0
    return mat

func _build_materials() -> void:
    mats["travertine"] = _noise_mat(Color("#D6C29B"), 0.3, 0.85)
    mats["tuff"] = _noise_mat(Color("#9B8265"), 0.3, 0.85)
    mats["brick"] = _noise_mat(Color("#9A4936"), 0.8, 0.85)
    mats["roof"] = _noise_mat(Color("#C24A2A"), 0.5, 0.85)
    mats["ochre"] = _noise_mat(Color("#D7A34D"), 0.2, 0.85)
    mats["rose"] = _noise_mat(Color("#C78370"), 0.2, 0.85)
    mats["cream"] = _noise_mat(Color("#DDD2B8"), 0.2, 0.85)
    mats["cobble"] = _noise_mat(Color("#8B8171"), 0.5, 0.85)
    mats["peperino"] = _noise_mat(Color("#6A5A4A"), 0.45, 0.85)
    mats["wood"] = _noise_mat(Color("#4A2E1B"), 0.45, 0.85)
    mats["leaf"] = _noise_mat(Color("#4F7B38"), 0.25, 0.85)
    mats["ivy"] = _noise_mat(Color("#315D32"), 0.35, 0.85)
    mats["iron"] = _flat_mat(Color("#24282A"), 0.85)
    mats["marble"] = _noise_mat(Color("#E8E1D0"), 0.3, 0.85)

func _box(parent: Node, name: String, size: Vector3, pos: Vector3, key: String) -> MeshInstance3D:
    var n: MeshInstance3D = MeshInstance3D.new()
    n.name = name
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    n.mesh = mesh
    n.position = pos
    n.material_override = mats[key] as Material
    parent.add_child(n)
    return n

func _cyl(parent: Node, name: String, radius: float, height: float, pos: Vector3, key: String, sides: int = 10) -> MeshInstance3D:
    var n: MeshInstance3D = MeshInstance3D.new()
    n.name = name
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = min(sides, MAX_RADIAL)
    n.mesh = mesh
    n.position = pos
    n.material_override = mats[key] as Material
    parent.add_child(n)
    return n

func _sphere(parent: Node, name: String, radius: float, pos: Vector3, key: String) -> MeshInstance3D:
    var n: MeshInstance3D = MeshInstance3D.new()
    n.name = name
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 10
    mesh.rings = 5
    n.mesh = mesh
    n.position = pos
    n.material_override = mats[key] as Material
    parent.add_child(n)
    return n

func _roof(parent: Node, name: String, w: float, d: float, y: float) -> void:
    var a: MeshInstance3D = _box(parent, name + "_A", Vector3(w * 0.56, 0.30, d + 0.8), Vector3(-w * 0.23, y, 0), "roof")
    a.rotation_degrees.z = -20.0
    var b: MeshInstance3D = _box(parent, name + "_B", Vector3(w * 0.56, 0.30, d + 0.8), Vector3(w * 0.23, y, 0), "roof")
    b.rotation_degrees.z = 20.0

func _build_island() -> void:
    var g: Node3D = Node3D.new()
    g.name = "01_Isola"
    add_child(g)
    var island: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = 1.0
    mesh.bottom_radius = 1.0
    mesh.height = ISLAND_RISE
    mesh.radial_segments = 48
    island.mesh = mesh
    island.scale = Vector3(ISLAND_L * 0.5, 1.0, ISLAND_W * 0.5)
    island.position.y = ISLAND_RISE * 0.5
    island.material_override = mats["tuff"] as Material
    g.add_child(island)
    var blocks: int = 120
    for i in range(blocks):
        var a: float = TAU * float(i) / float(blocks)
        var taper: float = 0.74 + 0.26 * abs(cos(a))
        var x: float = cos(a) * (ISLAND_L * 0.5 - 1.2)
        var z: float = sin(a) * (ISLAND_W * 0.5 - 1.2) * taper
        var b: MeshInstance3D = _box(g, "TravertineBlock_%03d" % i, Vector3(1.5, WALL_H, 0.8), Vector3(x, WALL_H * 0.5, z), "travertine")
        b.rotation.y = -a
    _box(g, "CentralSurface", Vector3(215.0, 0.25, 48.0), Vector3(0, ISLAND_TOP + 0.12, 0), "tuff")

func _torus_arch(parent: Node, name: String, center: Vector3, radius: float, key: String) -> void:
    var n: MeshInstance3D = MeshInstance3D.new()
    n.name = name
    var mesh: TorusMesh = TorusMesh.new()
    mesh.inner_radius = radius - 1.25
    mesh.outer_radius = radius
    mesh.rings = 12
    mesh.ring_segments = 8
    n.mesh = mesh
    n.rotation_degrees.x = 90.0
    n.position = center
    n.material_override = mats[key] as Material
    parent.add_child(n)

func _build_bridge(parent: Node, name: String, length: float, width: float, arches: int, center: Vector3, key: String, peperino: bool) -> void:
    var g: Node3D = Node3D.new()
    g.name = name
    parent.add_child(g)
    g.position = center
    _box(g, "Deck", Vector3(length, BRIDGE_DECK_THICK, width), Vector3(0, BRIDGE_DECK_Y, 0), key)
    _box(g, "RailLeft", Vector3(length, 0.8, 0.55), Vector3(0, BRIDGE_DECK_Y + 0.8, -width * 0.5 + 0.28), "travertine")
    _box(g, "RailRight", Vector3(length, 0.8, 0.55), Vector3(0, BRIDGE_DECK_Y + 0.8, width * 0.5 - 0.28), "travertine")
    var span: float = length / float(arches)
    for i in range(arches):
        var cx: float = -length * 0.5 + span * (float(i) + 0.5)
        _torus_arch(g, "Arch_%02d" % i, Vector3(cx, -3.0, 0), span * 0.46, key)
        _box(g, "Pier_%02d" % i, Vector3(2.8, 8.0, width - 0.8), Vector3(-length * 0.5 + span * float(i), 0.8, 0), "travertine")
        if peperino:
            _box(g, "PeperinoBand_%02d" % i, Vector3(span * 0.72, 0.45, 0.5), Vector3(cx, 1.4, 0), "peperino")

func _lamp(parent: Node, name: String, pos: Vector3) -> void:
    _cyl(parent, name + "_Post", 0.09, 3.4, pos + Vector3(0, 1.7, 0), "iron", 8)
    _sphere(parent, name + "_Cap", 0.28, pos + Vector3(0, 3.55, 0), "marble")

func _build_fabricio() -> void:
    var g: Node3D = Node3D.new()
    g.name = "02_Ponte_Fabricio"
    add_child(g)
    _build_bridge(g, "PonteFabricio", 62.0, 5.0, 2, Vector3(112, 0, 0), "travertine", false)
    _lamp(g, "FabricioLamp1", Vector3(96, BRIDGE_DECK_Y + 0.8, -2))
    _lamp(g, "FabricioLamp2", Vector3(112, BRIDGE_DECK_Y + 0.8, 2))
    _lamp(g, "FabricioLamp3", Vector3(128, BRIDGE_DECK_Y + 0.8, -2))

func _build_cestio() -> void:
    var g: Node3D = Node3D.new()
    g.name = "03_Ponte_Cestio"
    add_child(g)
    _build_bridge(g, "PonteCestio", 70.0, 8.0, 3, Vector3(-112, 0, 0), "travertine", true)
    _lamp(g, "CestioLamp1", Vector3(-136, BRIDGE_DECK_Y + 0.8, -3))
    _lamp(g, "CestioLamp2", Vector3(-120, BRIDGE_DECK_Y + 0.8, 3))
    _lamp(g, "CestioLamp3", Vector3(-104, BRIDGE_DECK_Y + 0.8, -3))
    _lamp(g, "CestioLamp4", Vector3(-88, BRIDGE_DECK_Y + 0.8, 3))

func _build_basilica() -> void:
    var g: Node3D = Node3D.new()
    g.name = "04_San_Bartolomeo"
    add_child(g)
    var p: Vector3 = Vector3(18, ISLAND_TOP, -2)
    _box(g, "Nave", Vector3(30, 10, 18), p + Vector3(0, 5, 0), "cream")
    _roof(g, "TettoCoppi", 30, 18, p.y + 10.2)
    _box(g, "PronaoCornice", Vector3(30, 0.7, 2), p + Vector3(0, 9, -10), "marble")
    for x in [-9.0, -3.0, 3.0, 9.0]:
        _cyl(g, "Colonna", 0.6, 8.0, p + Vector3(x, 4, -10.5), "marble", 10)
    _box(g, "Portone", Vector3(3.4, 4.8, 0.35), p + Vector3(0, 2.4, -10.7), "wood")
    _box(g, "Campanile", Vector3(4, 18, 4), p + Vector3(11, 9, 7), "brick")
    _box(g, "CampanaArcoA", Vector3(2.6, 2.4, 0.35), p + Vector3(11, 14, 4.8), "iron")
    _box(g, "CampanaArcoB", Vector3(2.6, 2.4, 0.35), p + Vector3(11, 14, 9.2), "iron")
    _cyl(g, "Croce", 0.16, 2.5, p + Vector3(11, 19.3, 7), "iron", 8)
    _box(g, "CroceBar", Vector3(1.2, 0.16, 0.16), p + Vector3(11, 19.8, 7), "iron")

func _build_caetani() -> void:
    var g: Node3D = Node3D.new()
    g.name = "05_Torre_Caetani"
    add_child(g)
    var p: Vector3 = Vector3(-28, ISLAND_TOP, 19)
    _box(g, "Tower", Vector3(10, 25, 10), p + Vector3(0, 12.5, 0), "brick")
    for i in range(10):
        var a: float = TAU * float(i) / 10.0
        _box(g, "Merlon_%02d" % i, Vector3(0.8, 1.5, 0.8), p + Vector3(cos(a) * 4.8, 26, sin(a) * 4.8), "brick")
    _box(g, "StoneCornice", Vector3(10.8, 0.8, 10.8), p + Vector3(0, 13, 0), "travertine")
    for level in [7.0, 19.0]:
        _box(g, "Window_%s" % str(level), Vector3(1.2, 2.0, 0.35), p + Vector3(0, level, -5.15), "wood")

func _house(parent: Node, name: String, pos: Vector3, w: float, d: float, h: float, key: String) -> void:
    var g: Node3D = Node3D.new()
    g.name = name
    parent.add_child(g)
    g.position = pos
    _box(g, "Body", Vector3(w, h, d), Vector3(0, h * 0.5, 0), key)
    _roof(g, "Roof", w, d, h + 0.4)
    var floors: int = 2 if h < 10.5 else 3
    for floor in range(floors):
        var y: float = 2.0 + float(floor) * 2.7
        for col in range(3):
            var x: float = -w * 0.3 + float(col) * w * 0.3
            _box(g, "Window_%02d_%02d" % [floor, col], Vector3(1.2, 1.5, 0.16), Vector3(x, y, -d * 0.51), "wood")
            _box(g, "Frame_%02d_%02d" % [floor, col], Vector3(1.45, 0.12, 0.20), Vector3(x, y - 0.82, -d * 0.57), "marble")
    _box(g, "Door", Vector3(1.7, 3.2, 0.20), Vector3(0, 1.6, -d * 0.53), "wood")

func _build_residential() -> void:
    var g: Node3D = Node3D.new()
    g.name = "06_Case"
    add_child(g)
    _house(g, "Casa_Ocra", Vector3(52, ISLAND_TOP, -14), 22, 15, 10, "ochre")
    _house(g, "Casa_Rosa", Vector3(74, ISLAND_TOP, -2), 18, 14, 8.5, "rose")
    _house(g, "Casa_Crema", Vector3(42, ISLAND_TOP, 14), 18, 14, 9.5, "cream")
    _house(g, "Casa_Gialla", Vector3(10, ISLAND_TOP, 23), 20, 14, 8.5, "ochre")
    _house(g, "Casa_Rosa2", Vector3(-2, ISLAND_TOP, -22), 19, 14, 9, "rose")
    _house(g, "Casa_Crema2", Vector3(-54, ISLAND_TOP, -10), 21, 15, 10.5, "cream")

func _build_paths() -> void:
    var g: Node3D = Node3D.new()
    g.name = "07_Percorsi"
    add_child(g)
    _box(g, "PathMain", Vector3(210, 0.22, 5), Vector3(0, ISLAND_TOP + 0.25, 0), "cobble")
    _box(g, "PathNorth", Vector3(100, 0.22, 4), Vector3(25, ISLAND_TOP + 0.27, 21), "cobble")
    _box(g, "PathSouth", Vector3(110, 0.22, 4), Vector3(-20, ISLAND_TOP + 0.27, -23), "cobble")
    _box(g, "SidewalkNorth", Vector3(100, 0.28, 1), Vector3(25, ISLAND_TOP + 0.5, 24), "travertine")
    _box(g, "SidewalkSouth", Vector3(110, 0.28, 1), Vector3(-20, ISLAND_TOP + 0.5, -26), "travertine")

func _tree(parent: Node, name: String, pos: Vector3, pine: bool) -> void:
    _cyl(parent, name + "_Trunk", 0.42 if pine else 0.55, 4, pos + Vector3(0, 2, 0), "wood", 8)
    if pine:
        for i in range(3):
            _cyl(parent, name + "_Crown_%02d" % i, 1.9 - float(i) * 0.35, 2.8, pos + Vector3(0, 4.5 + float(i) * 1.5, 0), "leaf", 8)
    else:
        _sphere(parent, name + "_CrownA", 2.5, pos + Vector3(-0.9, 5.2, 0), "leaf")
        _sphere(parent, name + "_CrownB", 2.6, pos + Vector3(0.9, 5.5, 0.1), "leaf")
        _sphere(parent, name + "_CrownC", 2.2, pos + Vector3(0, 6.2, -0.4), "leaf")

func _build_vegetation() -> void:
    var g: Node3D = Node3D.new()
    g.name = "08_Vegetazione"
    add_child(g)
    var pts: Array[Vector3] = [Vector3(-86,4,17),Vector3(-70,4,30),Vector3(-48,4,26),Vector3(-15,4,17),Vector3(18,4,30),Vector3(39,4,28),Vector3(66,4,18),Vector3(87,4,5),Vector3(66,4,-23),Vector3(42,4,-29),Vector3(10,4,-30),Vector3(-24,4,-29),Vector3(-56,4,-25),Vector3(-82,4,-14),Vector3(-32,4,4),Vector3(83,4,-8),Vector3(-5,4,4),Vector3(25,4,-7)]
    for i in range(pts.size()):
        _tree(g, "Tree_%02d" % i, pts[i], i % 4 == 0)
    for i in range(12):
        _box(g, "Hedge_%02d" % i, Vector3(3,1.6,0.8), Vector3(-65 + float(i)*11,4.8,25), "ivy")
    for i in range(6):
        _box(g, "IvyPanel_%02d" % i, Vector3(2,4,0.1), Vector3(-35 + float(i)*12,7,-27), "ivy")

func _bench(parent: Node, name: String, pos: Vector3) -> void:
    _box(parent, name + "_Seat", Vector3(2.4,0.18,0.55), pos + Vector3(0,0.9,0), "wood")
    _box(parent, name + "_Back", Vector3(2.4,0.65,0.16), pos + Vector3(0,1.35,0.25), "wood")
    _box(parent, name + "_LegA", Vector3(0.14,0.9,0.14), pos + Vector3(-0.8,0.45,0), "iron")
    _box(parent, name + "_LegB", Vector3(0.14,0.9,0.14), pos + Vector3(0.8,0.45,0), "iron")

func _build_props() -> void:
    var g: Node3D = Node3D.new()
    g.name = "09_Props"
    add_child(g)
    for i in range(8):
        _lamp(g, "Lamp_%02d" % i, Vector3(-70 + float(i)*20,4.3,4))
    for i in range(4):
        _bench(g, "Bench_%02d" % i, Vector3(-42 + float(i)*28,4,9))
    for i in range(3):
        var x: float = -38 + float(i)*38
        _cyl(g, "Nasone_%02d" % i, 0.22, 1, Vector3(x,4.5,-8), "iron", 8)
        _cyl(g, "NasoneSpout_%02d" % i, 0.10, 0.5, Vector3(x,4.85,-8.35), "iron", 8)
    _box(g, "Sign_IsolaTiberina", Vector3(2.8,1.2,0.12), Vector3(-72,5.8,4), "travertine")
    _box(g, "Sign_PonteFabricio", Vector3(2.8,1.2,0.12), Vector3(88,5.8,4), "travertine")
    _box(g, "Sign_PonteCestio", Vector3(2.8,1.2,0.12), Vector3(-88,5.8,4), "travertine")
    _box(g, "Sign_SanBartolomeo", Vector3(2.8,1.2,0.12), Vector3(18,5.8,-15), "travertine")
