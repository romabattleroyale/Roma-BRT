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
