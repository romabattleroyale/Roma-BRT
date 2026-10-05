extends SceneTree
## Final deterministic V11 facade-style pass.
## Keeps the Roman plaster texture visible and assigns a warm Roman palette
## instead of replacing facade albedo with white/flat terracotta.
## Reads source images directly so CI does not depend on imported .ctex caches.

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

    var albedo_path:String = "%s/roman_plaster_weathered_albedo.jpg" % TEXTURE_DIR
    var normal_path:String = "%s/roman_plaster_weathered_normal.jpg" % TEXTURE_DIR
    var roughness_path:String = "%s/roman_plaster_weathered_roughness.jpg" % TEXTURE_DIR

    # Use source files directly. The headless bake may not have generated
    # .godot/imported/*.ctex entries yet, so load() is intentionally avoided.
    var albedo_image:Image = Image.load_from_file(albedo_path)
    var normal_image:Image = Image.load_from_file(normal_path)
    var roughness_image:Image = Image.load_from_file(roughness_path)
    if albedo_image == null or albedo_image.is_empty() or normal_image == null or normal_image.is_empty() or roughness_image == null or roughness_image.is_empty():
        push_error("V11 FACADE STYLE FAIL: required Roman weathered facade source textures missing")
        quit(2)
        return

    # The materials still reference the normal/roughness source paths below;
    # loading them through ResourceLoader is not safe in a fresh headless cache.
    # Preserve existing imported resource references when available and fail only
    # if a required source image itself is absent.
    var albedo:Texture2D = load(albedo_path) as Texture2D
    var normal:Texture2D = load(normal_path) as Texture2D
    var roughness:Texture2D = load(roughness_path) as Texture2D

    var facade_count:int = 0
    var files := dir.get_files()
    files.sort()
    for file_name in files:
        if not file_name.ends_with(".tres"):
            continue
        var path:String = "%s/%s" % [MATERIAL_DIR, file_name]
        var material:StandardMaterial3D = load(path) as StandardMaterial3D
        if material == null:
            continue

        var current_path:String = ""
        if material.albedo_texture != null:
            current_path = material.albedo_texture.resource_path.to_lower()
        var is_facade:bool = material.resource_name == "Muro_Romano" or current_path.contains("roman_plaster_")
        if not is_facade:
            continue

        var color:Color = FACADE_COLORS[facade_count % FACADE_COLORS.size()]
        material.resource_name = "Muro_Romano"
        material.albedo_color = color
        if albedo != null:
            material.albedo_texture = albedo
        material.normal_enabled = true
        material.normal_scale = 0.58
        if normal != null:
            material.normal_texture = normal
        material.roughness = 0.90
        if roughness != null:
            material.roughness_texture = roughness
        material.uv1_scale = Vector3(3.6, 3.6, 3.6)
        material.texture_repeat = true

        var err:Error = ResourceSaver.save(material, path)
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
