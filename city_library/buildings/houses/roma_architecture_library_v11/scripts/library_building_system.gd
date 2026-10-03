extends RomaBuildingSystem
class_name RomaLibraryBuildingSystem

const LIB_ROOT := "res://city_library/buildings/houses/roma_architecture_library_v11/"
const TEX_ROOT := LIB_ROOT + "assets/textures/"

func setup_materials() -> void:
    super.setup_materials()
    mats["brick"] = _pbr(TEX_ROOT + "brick_weathered_albedo.jpg", TEX_ROOT + "brick_weathered_normal.jpg", 0.92, 4.0)
    mats["travertine"] = _weathered_pbr(TEX_ROOT + "travertine_weathered_albedo.jpg", TEX_ROOT + "travertine_weathered_normal.jpg", TEX_ROOT + "travertine_weathered_roughness.jpg", 0.86, 2.8)
    mats["weathered_plaster"] = _weathered_pbr(TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg", 0.94, 3.8)
    mats["facade_ochre"] = _weathered_facade(Color("#FFF0C9"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_yellow"] = _weathered_facade(Color("#FFF2B8"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_beige"] = _weathered_facade(Color("#FFF2DA"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_terracotta"] = _weathered_facade(Color("#FFD0B2"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["facade_rose"] = _weathered_facade(Color("#FFE0D4"), TEX_ROOT + "roman_plaster_weathered_albedo.jpg", TEX_ROOT + "roman_plaster_weathered_normal.jpg", TEX_ROOT + "roman_plaster_weathered_roughness.jpg")
    mats["roof"] = _warm_roof(Color("#E45B2F"), 3.5)
    mats["roof_terrace"] = _terracotta_terrace()
