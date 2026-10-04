extends SceneTree
## Final deterministic V11 facade-style pass.
## Keeps the Roman plaster texture visible and assigns a warm Roman palette
## instead of replacing facade albedo with white/flat terracotta.

const MATERIAL_DIR := "res://baked_city/v11_shared_materials"
const TEXTURE_DIR := "res://city_library/buildings/houses/roma_architecture_library_v11/assets/textures"

const FACADE_COLORS := [
    Color("#B97845"), # ocra
    Color("#D3A63A"), # giallo romano
    Color("#B96F73"), # rosa antico
    Color("#C7AA83"), # beige
    Color("#A9573B"), # terracotta
    Color("#A99A7E")  # travertino
]

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var dir := DirAccess.open(MATERIAL_DIR)
    if dir == null:
        push_error("V11 FACADE STYLE FAIL: shared material directory missing")
        quit(1)
        return

    var albedo := load("%s/roman_plaster_weathered_albedo.jpg" % TEXTURE_DIR) as Texture2D
    var normal := load("%s/roman_plaster_weathered_normal.jpg" % TEXTURE_DIR) as Texture2D
    var roughness := load("%s/roman_plaster_weathered_roughness.jpg" % TEXTURE_DIR) as Texture2D
    if albedo == null or normal == null or roughness == null:
        push_error("V11 FACADE STYLE FAIL: required Roman weathered facade textures missing")
        quit(2)
        return

    var facade_count := 0
    var files := dir.get_files()
    files.sort()
    for file_name in files:
        if not file_name.ends_with(".tres"):
            continue
        var path := "%s/%s" % [MATERIAL_DIR, file_name]
        var material := load(path) as StandardMaterial3D
        if material == null:
            continue

        var current_path := ""
        if material.albedo_texture != null:
            current_path = material.albedo_texture.resource_path.to_lower()
        var is_facade := material.resource_name == "Muro_Romano" or current_path.contains("roman_plaster_")
        if not is_facade:
            continue

        var color: Color = FACADE_COLORS[facade_count % FACADE_COLORS.size()]
        material.resource_name = "Muro_Romano"
        material.albedo_color = color
        material.albedo_texture = albedo
        material.normal_enabled = true
        material.normal_scale = 0.58
        material.normal_texture = normal
        material.roughness = 0.90
        material.roughness_texture = roughness
        material.uv1_scale = Vector3(3.6, 3.6, 3.6)
        material.texture_repeat = true

        var err := ResourceSaver.save(material, path)
        if err != OK:
            push_error("V11 FACADE STYLE FAIL: cannot save %s" % path)
            quit(3)
            return
        facade_count += 1
        print("V11 ART FINAL: %s -> %s + weathered albedo + normal + roughness" % [path, color.to_html(false)])

    if facade_count == 0:
        push_error("V11 FACADE STYLE FAIL: no Roman facade material found")
        quit(4)
        return
    print("V11 ART FINAL PASS: facade_materials=%d palette=6 textures=weathered" % facade_count)
    quit(0)
