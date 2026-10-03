extends RomaBuildingSystem
class_name RomaLibraryBuildingSystem

const ASSET_ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures/"

func setup_materials() -> void:
    mats.clear()
    mats["plaster_cream"] = _pbr(ASSET_ROOT + "roman_plaster_cream.jpg", ASSET_ROOT + "roman_plaster_cream_normal.jpg", 0.88, 3.2)
    mats["plaster_pale"] = _pbr(ASSET_ROOT + "roman_plaster_pale.jpg", ASSET_ROOT + "roman_plaster_pale_normal.jpg", 0.90, 3.2)
    mats["plaster_terracotta"] = _pbr(ASSET_ROOT + "roman_plaster_terracotta.jpg", ASSET_ROOT + "roman_plaster_terracotta_normal.jpg", 0.86, 3.0)
    mats["brick"] = _pbr(ASSET_ROOT + "brick_weathered_albedo.jpg", ASSET_ROOT + "brick_weathered_normal.jpg", 0.92, 4.0)
    var brick_rough := load(ASSET_ROOT + "brick_weathered_roughness.jpg") as Texture2D
    if brick_rough:
        (mats["brick"] as StandardMaterial3D).roughness_texture = brick_rough
        (mats["brick"] as StandardMaterial3D).roughness = 0.88
    mats["travertine"] = _weathered_pbr(ASSET_ROOT + "travertine_weathered_albedo.jpg", ASSET_ROOT + "travertine_weathered_normal.jpg", ASSET_ROOT + "travertine_weathered_roughness.jpg", 0.86, 2.8)
    mats["wood"] = _pbr(ASSET_ROOT + "dark_wood.jpg", ASSET_ROOT + "dark_wood_normal.jpg", 0.78, 2.0)
    mats["painted_wood"] = _pbr(ASSET_ROOT + "painted_wood.jpg", ASSET_ROOT + "painted_wood_normal.jpg", 0.80, 2.0)
    mats["roof"] = _warm_roof(Color("#E45B2F"), 3.5)
    mats["roof_terrace"] = _library_terracotta_terrace()
    mats["fabric_blue"] = _pbr(ASSET_ROOT + "fabric_blue.jpg", "", 0.84, 2.2)
    mats["shutter_green"] = _pbr(ASSET_ROOT + "painted_wood.jpg", ASSET_ROOT + "painted_wood_normal.jpg", 0.82, 2.0)
    mats["shutter_warm"] = _pbr(ASSET_ROOT + "painted_wood.jpg", ASSET_ROOT + "painted_wood_normal.jpg", 0.80, 2.0)

    mats["stucco"] = StandardMaterial3D.new()
    mats["stucco"].albedo_color = Color("#D9C3A1")
    mats["stucco"].roughness = 0.86

    mats["weathered_plaster"] = _weathered_pbr(ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg", 0.94, 3.8)

    for key in ["iron", "metal", "stone", "glass", "interior", "warm", "awning", "plant", "dark_stone"]:
        mats[key] = StandardMaterial3D.new()

    (mats["iron"] as StandardMaterial3D).albedo_color = Color("#252522")
    (mats["iron"] as StandardMaterial3D).metallic = 0.78
    (mats["iron"] as StandardMaterial3D).roughness = 0.42
    (mats["metal"] as StandardMaterial3D).albedo_color = Color("#30363A")
    (mats["metal"] as StandardMaterial3D).metallic = 0.72
    (mats["metal"] as StandardMaterial3D).roughness = 0.36
    (mats["stone"] as StandardMaterial3D).albedo_color = Color("#D9C9AA")
    (mats["stone"] as StandardMaterial3D).roughness = 0.84
    (mats["glass"] as StandardMaterial3D).albedo_color = Color(0.82, 0.92, 0.90, 0.18)
    (mats["glass"] as StandardMaterial3D).roughness = 0.18
    (mats["glass"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    (mats["glass"] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
    (mats["interior"] as StandardMaterial3D).albedo_color = Color("#A37A5B")
    (mats["interior"] as StandardMaterial3D).roughness = 0.88
    (mats["warm"] as StandardMaterial3D).albedo_color = Color(1.0, 0.64, 0.28)
    (mats["warm"] as StandardMaterial3D).emission_enabled = true
    (mats["warm"] as StandardMaterial3D).emission = Color(1.0, 0.38, 0.10)
    (mats["warm"] as StandardMaterial3D).emission_energy_multiplier = 1.2
    (mats["awning"] as StandardMaterial3D).albedo_color = Color("#8A3E32")
    (mats["awning"] as StandardMaterial3D).roughness = 0.88
    (mats["plant"] as StandardMaterial3D).albedo_color = Color("#4D6D3F")
    (mats["plant"] as StandardMaterial3D).roughness = 0.96
    (mats["dark_stone"] as StandardMaterial3D).albedo_color = Color("#B8876D")
    (mats["dark_stone"] as StandardMaterial3D).roughness = 0.92

    mats["facade_ochre"] = _weathered_facade(Color("#FFF0C9"), ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_yellow"] = _weathered_facade(Color("#FFF2B8"), ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_beige"] = _weathered_facade(Color("#FFF2DA"), ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_terracotta"] = _weathered_facade(Color("#FFD0B2"), ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_rose"] = _weathered_facade(Color("#FFE0D4"), ASSET_ROOT + "roman_plaster_weathered_albedo.jpg", ASSET_ROOT + "roman_plaster_weathered_normal.jpg", ASSET_ROOT + "roman_plaster_weathered_roughness.jpg")

func _library_terracotta_terrace() -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    var albedo := load(ASSET_ROOT + "cotto_tiles.jpg") as Texture2D
    if albedo:
        m.albedo_texture = albedo
    var normal := load(ASSET_ROOT + "cotto_tiles_normal.jpg") as Texture2D
    if normal:
        m.normal_enabled = true
        m.normal_texture = normal
        m.normal_scale = 0.48
    m.albedo_color = Color("#F0B58A")
    m.roughness = 0.91
    m.uv1_scale = Vector3(2.2, 2.2, 2.2)
    m.texture_repeat = true
    return m
