extends RomaBuildingSystem
class_name RomaLibraryBuildingSystem

const LIB_ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const TEX_ROOT := LIB_ROOT + "assets/textures/"

func setup_materials() -> void:
    mats["plaster_cream"] = _pbr(TEX_ROOT + "roman_plaster_cream.jpg", TEX_ROOT + "roman_plaster_cream_normal.jpg", 0.88, 3.2)
    mats["plaster_pale"] = _pbr(TEX_ROOT + "roman_plaster_pale.jpg", TEX_ROOT + "roman_plaster_pale_normal.jpg", 0.90, 3.2)
    mats["plaster_terracotta"] = _pbr(TEX_ROOT + "roman_plaster_terracotta.jpg", TEX_ROOT + "roman_plaster_terracotta_normal.jpg", 0.86, 3.0)
    mats["brick"] = _pbr(TEX_ROOT + "brick_weathered_albedo.jpg", TEX_ROOT + "brick_weathered_normal.jpg", 0.92, 4.0)
    var brick_rough: Texture2D = load(TEX_ROOT + "brick_weathered_roughness.jpg") as Texture2D
    var brick_mat: StandardMaterial3D = mats["brick"] as StandardMaterial3D
    if brick_rough:
        brick_mat.roughness_texture = brick_rough
        brick_mat.roughness = 0.88
    mats["travertine"] = _weathered_pbr(TEX_ROOT + "travertine_weathered_albedo.jpg", TEX_ROOT + "travertine_weathered_normal.jpg", TEX_ROOT + "travertine_weathered_roughness.jpg", 0.86, 2.8)
    mats["wood"] = _pbr(TEX_ROOT + "dark_wood.jpg", TEX_ROOT + "dark_wood_normal.jpg", 0.78, 2.0)
    mats["painted_wood"] = _pbr(TEX_ROOT + "painted_wood.jpg", TEX_ROOT + "painted_wood_normal.jpg", 0.80, 2.0)
    mats["roof"] = _warm_roof(Color("#E45B2F"), 3.5)
    mats["roof_terrace"] = _terracotta_terrace()
    mats["fabric_blue"] = _pbr(TEX_ROOT + "fabric_blue.jpg", "", 0.84, 2.2)
    mats["shutter_green"] = _pbr(TEX_ROOT + "painted_wood.jpg", TEX_ROOT + "painted_wood_normal.jpg", 0.82, 2.0)
    mats["shutter_warm"] = _pbr(TEX_ROOT + "painted_wood.jpg", TEX_ROOT + "painted_wood_normal.jpg", 0.80, 2.0)
    mats["stucco"] = StandardMaterial3D.new()
    (mats["stucco"] as StandardMaterial3D).albedo_color = Color("#D9C3A1")
    (mats["stucco"] as StandardMaterial3D).roughness = 0.86
    mats["weathered_plaster"] = _weathered_pbr(TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg", 0.94, 3.8)
    mats["iron"] = StandardMaterial3D.new()
    (mats["iron"] as StandardMaterial3D).albedo_color = Color("#252522")
    (mats["iron"] as StandardMaterial3D).metallic = 0.78
    (mats["iron"] as StandardMaterial3D).roughness = 0.42
    mats["dark_stone"] = StandardMaterial3D.new()
    (mats["dark_stone"] as StandardMaterial3D).albedo_color = Color("#B8876D")
    (mats["dark_stone"] as StandardMaterial3D).roughness = 0.92
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color("#30363A")
    metal.metallic = 0.72
    metal.roughness = 0.36
    mats["metal"] = metal
    var stone := StandardMaterial3D.new()
    stone.albedo_color = Color("#D9C9AA")
    stone.roughness = 0.84
    mats["stone"] = stone
    var glass := StandardMaterial3D.new()
    glass.albedo_color = Color(0.82, 0.92, 0.90, 0.18)
    glass.metallic = 0.05
    glass.roughness = 0.18
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.cull_mode = BaseMaterial3D.CULL_DISABLED
    mats["glass"] = glass
    var interior := StandardMaterial3D.new()
    interior.albedo_color = Color("#A37A5B")
    interior.roughness = 0.88
    mats["interior"] = interior
    var warm := StandardMaterial3D.new()
    warm.albedo_color = Color(1.0, 0.64, 0.28)
    warm.emission_enabled = true
    warm.emission = Color(1.0, 0.38, 0.10)
    warm.emission_energy_multiplier = 1.2
    mats["warm"] = warm
    var awning := StandardMaterial3D.new()
    awning.albedo_color = Color("#8A3E32")
    awning.roughness = 0.88
    mats["awning"] = awning
    var plant := StandardMaterial3D.new()
    plant.albedo_color = Color("#4D6D3F")
    plant.roughness = 0.96
    mats["plant"] = plant
    mats["facade_ochre"] = _weathered_facade(Color("#FFF0C9"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_yellow"] = _weathered_facade(Color("#FFF2B8"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_beige"] = _weathered_facade(Color("#FFF2DA"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_terracotta"] = _weathered_facade(Color("#FFD0B2"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_rose"] = _weathered_facade(Color("#FFE0D4"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")

func _terracotta_terrace() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    var albedo: Texture2D = load(TEX_ROOT + "cotto_tiles.jpg") as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal: Texture2D = load(TEX_ROOT + "cotto_tiles_normal.jpg") as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.48
    m.albedo_color = Color("#F0B58A")
    m.roughness = 0.91
    m.uv1_scale = Vector3(2.2, 2.2, 2.2)
    m.texture_repeat = true
    return m

func _warm_roof(color: Color, uv_scale: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    var albedo: Texture2D = load(TEX_ROOT + "coppi_romani_albedo.jpg") as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal: Texture2D = load(TEX_ROOT + "coppi_romani_normal.jpg") as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.72
    var rough: Texture2D = load(TEX_ROOT + "coppi_romani_roughness.jpg") as Texture2D
    if rough:
        m.roughness_texture = rough
    m.roughness = 0.88
    m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
    m.texture_repeat = true
    return m

func _pbr(color_path: String, normal_path: String, rough: float, uv_scale: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    if not color_path.is_empty():
        var color: Texture2D = load(color_path) as Texture2D
        if color:
            m.albedo_texture = color
    if not normal_path.is_empty():
        var normal: Texture2D = load(normal_path) as Texture2D
        if normal:
            m.normal_enabled = true
            m.normal_texture = normal
            m.normal_scale = 0.55
    m.roughness = rough
    m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
    m.texture_repeat = true
    return m

## Lightweight construction path for Android block-generation tests.
## Keeps the visible shell, windows, roof and door while skipping the expensive
## interior/stair/detail passes. Full build() remains unchanged for final POIs.
func build_mobile(data: Dictionary, variant: int) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = str(data["id"])
    var w: float = float(data["w"])
    var d: float = float(data["d"])
    var floors: int = int(data["floors"])
    var style: String = str(data["style"])
    var style_mat: Material = mats["facade_beige"] as Material
    if style == "plaster_cream" or style == "brick":
        style_mat = mats["facade_ochre"] as Material
    elif style == "plaster_pale" or style == "travertine":
        style_mat = mats["facade_beige"] as Material
    elif style == "plaster_terracotta":
        style_mat = mats["facade_terracotta"] as Material
    if root.name == "palazzetto" or root.name == "palazzo_nobile":
        style_mat = mats["facade_yellow"] as Material
    elif root.name == "casa_mercante":
        style_mat = mats["facade_rose"] as Material
    var ground_function: String = str(data["function"])
    if root.name == "casa_mercante":
        ground_function += " / BOTTEGA"
    elif root.name == "palazzetto":
        ground_function += " / BAR / NEGOZI"
    _build_shell(root, w, d, floors, style_mat, variant, ground_function)
    _build_windows_and_shutters(root, w, d, floors, ground_function, variant)
    _build_roof(root, w, d, floors, style, variant)
    _build_door_anchor(root, w, d, ground_function)
    if bool(data.get("v12", false)):
        _build_v12_signature(root, root.name, w, d, floors, variant, style_mat)
    return root

func _build_v12_signature(root: Node3D, archetype_id: String, w: float, d: float, floors: int, variant: int, facade: Material) -> void:
    if archetype_id == "v12_casa_romana_stretta":
        _v12_narrow_house(root, w, d, floors, facade)
    elif archetype_id == "v12_palazzina_residenziale":
        _v12_residential_palazzina(root, w, d, floors)
    elif archetype_id == "v12_palazzo_angolare":
        _v12_corner_palazzo(root, w, d, floors)

func _v12_narrow_house(root: Node3D, w: float, d: float, floors: int, facade: Material) -> void:
    var top_y: float = float(floors) * FLOOR_H
    _box(root, Vector3(0, top_y + 0.26, -d * 0.5 - 0.22), Vector3(w + 0.55, 0.34, 0.55), mats["travertine"], false)
    _box(root, Vector3(0, top_y + 0.48, -d * 0.5 - 0.22), Vector3(w + 0.34, 0.12, 0.62), facade, false)
    if floors >= 4:
        var balcony_y: float = FLOOR_H * 2.0 + 2.90
        var balcony_width: float = min(w * 0.72, 4.4)
        _box(root, Vector3(0, balcony_y, -d * 0.5 - 0.52), Vector3(balcony_width, 0.16, 0.78), mats["travertine"], false)
        _v12_rail_front(root, balcony_y + 0.55, balcony_width, -d * 0.5 - 0.88)

func _v12_residential_palazzina(root: Node3D, w: float, d: float, floors: int) -> void:
    var balcony_w: float = min(w * 0.72, 8.6)
    var balcony_d: float = 1.05
    for floor_index in range(1, floors):
        if floor_index % 2 == 0 or floor_index == floors - 1:
            var y: float = float(floor_index) * FLOOR_H - 0.18
            _box(root, Vector3(0, y, -d * 0.5 - balcony_d * 0.48), Vector3(balcony_w, 0.18, balcony_d), mats["travertine"], false)
            _v12_rail_front(root, y + 0.55, balcony_w, -d * 0.5 - balcony_d)
    var top_y: float = float(floors) * FLOOR_H
    _box(root, Vector3(0, top_y + 0.22, -d * 0.5 - 0.18), Vector3(w + 0.70, 0.32, 0.44), mats["travertine"], false)

func _v12_corner_palazzo(root: Node3D, w: float, d: float, floors: int) -> void:
    var corner_h: float = float(floors) * FLOOR_H + 0.40
    var corner_x: float = w * 0.5 - 0.18
    var corner_z: float = -d * 0.5 - 0.18
    _box(root, Vector3(corner_x, corner_h * 0.5, corner_z), Vector3(0.52, corner_h, 0.52), mats["travertine"], false)
    _box(root, Vector3(-corner_x, corner_h * 0.5, corner_z), Vector3(0.52, corner_h, 0.52), mats["travertine"], false)
    var y: float = FLOOR_H * 2.0 - 0.12
    var balcony_w: float = min(w * 0.58, 8.2)
    _box(root, Vector3(0, y, -d * 0.5 - 0.54), Vector3(balcony_w, 0.18, 0.86), mats["travertine"], false)
    _v12_rail_front(root, y + 0.55, balcony_w, -d * 0.5 - 0.98)
    _box(root, Vector3(w * 0.5 + 0.54, y, 0), Vector3(0.86, 0.18, balcony_w), mats["travertine"], false)
    _v12_rail_side(root, y + 0.55, balcony_w, w * 0.5 + 0.98)
    _box(root, Vector3(0, float(floors) * FLOOR_H + 0.20, -d * 0.5 - 0.20), Vector3(w + 0.78, 0.34, 0.50), mats["travertine"], false)

func _v12_rail_front(root: Node3D, top_y: float, width: float, z: float) -> void:
    var rail_base: float = top_y - 0.55
    var rail_height: float = 0.55
    _box(root, Vector3(0, top_y, z), Vector3(width, 0.08, 0.08), mats["iron"], false)
    var count: int = max(3, int(floor(width / 0.75)))
    for i in range(count):
        var x: float = -width * 0.5 + width * float(i) / float(max(1, count - 1))
        _box(root, Vector3(x, rail_base + rail_height * 0.5, z), Vector3(0.055, rail_height, 0.055), mats["iron"], false)

func _v12_rail_side(root: Node3D, top_y: float, depth: float, x: float) -> void:
    var rail_base: float = top_y - 0.55
    var rail_height: float = 0.55
    _box(root, Vector3(x, top_y, 0), Vector3(0.08, 0.08, depth), mats["iron"], false)
    var count: int = max(3, int(floor(depth / 0.75)))
    for i in range(count):
        var z: float = -depth * 0.5 + depth * float(i) / float(max(1, count - 1))
        _box(root, Vector3(x, rail_base + rail_height * 0.5, z), Vector3(0.055, rail_height, 0.055), mats["iron"], false)
